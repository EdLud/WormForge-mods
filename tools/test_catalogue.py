#!/usr/bin/env python3
"""Regression tests for source selection, immutable versions and safe builds."""
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest
from unittest.mock import patch
import zipfile

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


spec = importlib.util.spec_from_file_location("publisher", Path(__file__).with_name("publish-packs.py"))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


def hashes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file()}


class Catalogue(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo, self.site = self.root / "mods", self.root / "site"
        self.repo.mkdir()
        self.site.mkdir()
        self.write(".gitignore", "ignored.lua\n.DS_Store\n")
        self.write("catalogue.toml", 'schema = 1\npacks = ["pack"]\nprofiles = ["pack/profiles/Published.toml"]\n')
        self.write("pack/mod.toml", '''id = "example.test"
version = "1.0.0"
api_version = 4
format_version = 2
debug_input = true
[[components]]
id = "test.public"
type = "weapon"
entry = "weapon.lua"
[[components]]
id = "test.audit"
type = "feature"
entry = "audit/run.lua"
diagnostics = true
''')
        self.write("pack/weapon.lua", "return {}\n")
        self.write("pack/audit/run.lua", "-- diagnostic only\n")
        self.write("pack/profiles/Published.toml", 'features = []\n')
        self.write("pack/profiles/Private.toml", 'features = []\n')
        self.write("pack/profiles/Audit.toml", 'features = ["test.audit"]\n')
        self.git("init", "-b", "main")
        self.commit()
        self.key = Ed25519PrivateKey.generate()
        self.source = patch.object(publisher, "REPO", self.repo)
        self.source.start()
        self.addCleanup(self.source.stop)

    def write(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], stderr=subprocess.STDOUT, text=True).strip()

    def commit(self):
        self.git("add", ".")
        self.git("-c", "user.name=Catalogue test", "-c", "user.email=test@example.invalid",
                 "commit", "-m", "Test source")

    def build(self):
        with contextlib.redirect_stdout(io.StringIO()):
            publisher.build_site(self.site, publisher.BASE_URL, self.key)

    def index(self):
        return tomllib.loads((self.site / "downloads/packs/index.toml").read_text())

    def test_only_selected_profiles_and_public_components_are_staged(self):
        with tempfile.TemporaryDirectory() as temp:
            staged = publisher.stage_public(temp) / "pack"
            manifest = tomllib.loads((staged / "mod.toml").read_text())
            self.assertEqual([c["id"] for c in manifest["components"]], ["test.public"])
            self.assertNotIn("debug_input", manifest)
            self.assertFalse((staged / "audit").exists())
            self.assertEqual([p.name for p in (staged / "profiles").iterdir()], ["Published.toml"])
            self.assertEqual(publisher.mod_zip(staged), publisher.mod_zip(staged))

    def test_missing_or_diagnostic_selected_profile_is_rejected(self):
        for name in ("Missing", "Audit"):
            self.write("catalogue.toml", f'schema = 1\npacks = ["pack"]\nprofiles = ["pack/profiles/{name}.toml"]\n')
            with tempfile.TemporaryDirectory() as temp, self.assertRaisesRegex(ValueError, "missing or diagnostic"):
                publisher.stage_public(temp)

    def test_path_traversal_and_duplicate_folder_names_are_rejected(self):
        for selection in ('["../elsewhere"]', '["pack", "other/pack"]', '["/tmp/pack"]'):
            self.write("catalogue.toml", f'schema = 1\npacks = {selection}\nprofiles = []\n')
            with self.assertRaises(ValueError):
                publisher.catalogue()

    def test_source_symlinks_are_rejected(self):
        (self.repo / "pack/escape").symlink_to(self.root)
        with tempfile.TemporaryDirectory() as temp, self.assertRaisesRegex(ValueError, "symlinks"):
            publisher.stage_public(temp)

    def test_committed_build_is_reproducible_signed_and_records_source(self):
        self.build()
        first = hashes(self.site / "downloads")
        self.build()
        self.assertEqual(first, hashes(self.site / "downloads"))
        self.assertEqual(self.index()["source_commit"], self.git("rev-parse", "HEAD"))
        self.assertEqual(self.index()["source_repository"], publisher.SOURCE_URL)
        with contextlib.redirect_stdout(io.StringIO()):
            publisher.verify_site(self.site, self.key.public_key())

    def test_dirty_and_untracked_source_never_changes_downloads(self):
        self.build()
        before = hashes(self.site / "downloads")
        for name in ("pack/weapon.lua", "pack/untracked.lua"):
            self.write(name, "-- uncommitted\n")
            with self.assertRaisesRegex(ValueError, "commit mods repository"):
                self.build()
            self.assertEqual(before, hashes(self.site / "downloads"))
            self.git("reset", "--hard", "HEAD")
            if (self.repo / "pack/untracked.lua").exists():
                (self.repo / "pack/untracked.lua").unlink()

    def test_ignored_working_files_cannot_enter_a_published_archive(self):
        self.write("pack/ignored.lua", "-- not in source commit\n")
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.build()
        with zipfile.ZipFile(self.site / "downloads/packs/pack.zip") as archive:
            self.assertNotIn("pack/ignored.lua", archive.namelist())

    def test_changed_published_version_fails_without_touching_downloads(self):
        self.build()
        before = hashes(self.site / "downloads")
        self.write("pack/weapon.lua", "return { changed = true }\n")
        self.commit()
        with self.assertRaisesRegex(ValueError, "bump mod.toml"):
            self.build()
        self.assertEqual(before, hashes(self.site / "downloads"))
        self.assertFalse(list(self.site.glob(".catalogue-build-*")))

    def test_version_bump_retains_old_blobs_manifests_and_other_downloads(self):
        self.build()
        old = hashes(self.site / "downloads")
        (self.site / "downloads/wkLua.zip").write_bytes(b"existing engine release")
        self.write("pack/weapon.lua", "return { changed = true }\n")
        manifest = self.repo / "pack/mod.toml"
        manifest.write_text(manifest.read_text().replace('"1.0.0"', '"1.0.1"'))
        self.commit()
        self.build()
        new = hashes(self.site / "downloads")
        for path, sha in old.items():
            if path.startswith("blobs/") and path != "blobs/hashes.txt" or path.startswith("packs/versions/"):
                self.assertEqual(new[path], sha)
        self.assertEqual((self.site / "downloads/wkLua.zip").read_bytes(), b"existing engine release")
        self.assertEqual(self.index()["packs"][0]["version"], "1.0.1")

    def test_invalid_signature_archive_and_blob_are_detected(self):
        self.build()
        with self.assertRaises(InvalidSignature):
            publisher.verify_site(self.site, Ed25519PrivateKey.generate().public_key())
        archive = self.site / "downloads/packs/pack.zip"
        original = archive.read_bytes()
        archive.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "archive mismatch"):
            publisher.verify_site(self.site, self.key.public_key())
        archive.write_bytes(original)
        blob = next((self.site / "downloads/blobs").glob("??/*"))
        blob.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "corrupt blob"):
            publisher.verify_site(self.site, self.key.public_key())

    def test_failed_final_verification_preserves_previous_downloads(self):
        self.build()
        before = hashes(self.site / "downloads")
        with patch.object(publisher, "verify_site", side_effect=ValueError("verification failed")):
            with self.assertRaisesRegex(ValueError, "verification failed"):
                self.build()
        self.assertEqual(before, hashes(self.site / "downloads"))


if __name__ == "__main__":
    unittest.main()
