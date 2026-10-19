#!/usr/bin/env python3
"""Build the online mod catalogue the WormForge loader reads (Check online).

The published mods (PUBLIC: `mods/px` and the public examples), staged
without their diagnostic components by `tools/prepare-public-packs.py`, go
into <site>/downloads/packs/:

  <folder>.zip   one per mod, deterministic (sorted entries, a fixed time),
                 so an unchanged mod keeps its sha256 and installed copies
                 stay "up to date";
  index.toml     schema 2 (`weapons::INDEX_SCHEMA`, mods in the current
                 format): id / folder / version / author / file / sha256 / size,
                 the store's address and its list's hash;
  index.toml.sig the index's Ed25519 signature, hex, by the catalogue key
                 (`weapons::CATALOGUE_KEYS`): the loader uses nothing from an
                 index without it;

and the public store, <site>/downloads/blobs/ (every published file by
hash) with each version's file list in <site>/downloads/packs/versions/.
Of the profiles the mods carry, only PUBLIC_PROFILES go out.
A zip for a mod no longer published is removed, and so is the old
downloads/mods.zip (every mod at once; the loader installs from the zips).

The signing key's private half (an Ed25519 seed, hex) stays with whoever
publishes, outside the repo: --key, by default KEY_FILE. Each publisher has
their own; --new-key makes one and prints its public half, which goes into
`weapons::CATALOGUE_KEYS` for the next DLL (the private half never leaves
its machine).

    python3 tools/publish-packs.py --new-key

    python3 tools/publish-packs.py --site ../WormForge-site
    # ropa's copy of the site:
    python3 tools/publish-packs.py --site ../WormForge-site --base-url https://ropahektic.github.io/WormForge/downloads/packs/
"""
import argparse
import datetime
import hashlib
import importlib.util
import io
import shutil
import tempfile
import tomllib
import urllib.parse
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# The catalogue the DLL reads by default (weapons::PUBLIC_INDEX_URL): our
# site. Another copy of it (ropa's) takes --base-url.
BASE_URL = "https://edlud.github.io/WormForge/downloads/packs/"
INDEX_SCHEMA = 2
# The mods players get: Highlander and its ports, the add-ons, the examples.
# The audits and test weapons (`tools`, `labs`) stay in the repo, and so do
# `gravler_strike` and `turret`, which Highlander's px.ports now covers.
PUBLIC = [
    "mods/px",
    "mods/examples/utilities",
    "mods/examples/fog_demo",
    "mods/examples/cursor_light",
    "mods/examples/component_demo",
    "mods/examples/gif_donkey",
    "mods/examples/pooz",
    "mods/examples/wormcraft",
    "mods/examples/KillTheKing",
]
# The saved profiles players get, from the mods' `profiles/`. Any other a
# mod carries (Growth Hormones, Highlander weapons) stays in the repo.
PUBLIC_PROFILES = {"Demo", "Funny", "Highlander", "Full Wormforage", "Fog of war", "Cursor Light"}
# Never in a zip: the OS's and Python's leftovers.
SKIP = {".DS_Store", "__pycache__", "Thumbs.db"}
FIXED_TIME = (2020, 1, 1, 0, 0, 0)
# The catalogue key's private half: never in the repo.
KEY_FILE = Path.home() / ".config" / "wormforge" / "catalogue-signing.key"

_spec = importlib.util.spec_from_file_location("prepare_public_packs", REPO / "tools" / "prepare-public-packs.py")
prepare = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(prepare)


def files_of(folder):
    out = []
    for path in folder.rglob("*"):
        rel = path.relative_to(folder)
        if path.is_file() and not any(part in SKIP for part in rel.parts):
            out.append(rel)
    return sorted(out, key=lambda r: r.as_posix().lower())


def add(zf, name, data):
    info = zipfile.ZipInfo(name, FIXED_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    zf.writestr(info, data, compresslevel=9)


def mod_zip(folder):
    """One mod's zip: its folder's files under `<folder>/`."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        for rel in files_of(folder):
            add(zf, f"{folder.name}/{rel.as_posix()}", (folder / rel).read_bytes())
    return buf.getvalue()


def stage_public(tmp):
    """The public mods as players get them, staged under `tmp`: diagnostic
    components dropped (`tools/prepare-public-packs.py`), and of the
    profiles only PUBLIC_PROFILES. Returns the staged folder, one
    subfolder per mod."""
    gathered, staged = Path(tmp) / "source", Path(tmp) / "public"
    gathered.mkdir()
    for rel in PUBLIC:
        src = REPO / rel
        if not (src / "mod.toml").is_file():
            raise SystemExit(f"{rel}: no mod.toml")
        shutil.copytree(src, gathered / src.name, ignore=shutil.ignore_patterns(*SKIP))
    prepare.stage(gathered, staged)
    found = set()
    for profile in staged.glob("*/profiles/*.toml"):
        if profile.stem in PUBLIC_PROFILES:
            found.add(profile.stem)
        else:
            profile.unlink()
    for folder in staged.glob("*/profiles"):
        if not any(folder.iterdir()):
            folder.rmdir()
    if found != PUBLIC_PROFILES:
        raise SystemExit(f"public profiles not found: {sorted(PUBLIC_PROFILES - found)}")
    return staged


def toml_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def file_hashes(folder):
    """A staged mod's files: published path -> SHA-256, as the store keeps them."""
    return {rel.as_posix(): hashlib.sha256((folder / rel).read_bytes()).hexdigest() for rel in files_of(folder)}


def version_file(site, mod_id, version):
    return site / "downloads" / "packs" / "versions" / mod_id / f"{version}.toml"


def read_version(path):
    return tomllib.loads(path.read_text(encoding="utf-8")).get("files", {})


def write_version(path, mod_id, version, files):
    lines = [
        "# One published version of a mod: its files by hash, in downloads/blobs/.",
        "# Generated by tools/publish-packs.py; never changed once written.",
        f"id = {toml_string(mod_id)}",
        f"version = {toml_string(version)}",
        "",
        "[files]",
    ] + [f"{toml_string(rel)} = {toml_string(sha)}" for rel, sha in sorted(files.items())]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def store_blobs(site, staged):
    """Every published file into downloads/blobs/<aa>/<sha>, never removed
    or rewritten, and downloads/blobs/hashes.txt: every hash the store holds,
    one per line, sorted. Returns how many blobs are new."""
    blobs = site / "downloads" / "blobs"
    new = 0
    for folder in sorted(p for p in staged.iterdir() if p.is_dir()):
        for rel in files_of(folder):
            data = (folder / rel).read_bytes()
            sha = hashlib.sha256(data).hexdigest()
            blob = blobs / sha[:2] / sha
            if not blob.is_file():
                blob.parent.mkdir(parents=True, exist_ok=True)
                blob.write_bytes(data)
                new += 1
    hashes = sorted(b.name for b in blobs.glob("??/*") if b.is_file() and len(b.name) == 64)
    (blobs / "hashes.txt").write_text("".join(h + "\n" for h in hashes), encoding="utf-8")
    return new, len(hashes)


def load_key(path):
    """The catalogue key from its file: the seed's hex, `#` lines aside."""
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    try:
        lines = [l.strip() for l in path.read_text(encoding="utf-8").splitlines()]
    except FileNotFoundError:
        raise SystemExit(f"no catalogue key at {path}: make one with --new-key, and have its public "
                         "half added to weapons::CATALOGUE_KEYS")
    except OSError as e:
        raise SystemExit(f"catalogue key {path}: {e}")
    seed = next((l for l in lines if l and not l.startswith("#")), "")
    try:
        return Ed25519PrivateKey.from_private_bytes(bytes.fromhex(seed))
    except ValueError:
        raise SystemExit(f"catalogue key {path}: not a 32-byte Ed25519 seed in hex")


def new_key(path):
    """Make a catalogue key at `path` (never over an existing one) and print
    its public half."""
    import os
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    key = Ed25519PrivateKey.generate()
    seed = key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                             serialization.NoEncryption())
    public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise SystemExit(f"{path} exists already: a key is never replaced")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("# WormForge catalogue signing key (Ed25519 seed). Keep it secret and back it up.\n")
        f.write(seed.hex() + "\n")
    print(f"Catalogue key written to {path}: keep it secret, and back it up.")
    print("Its public half, for weapons::CATALOGUE_KEYS (safe to share):")
    print(public.hex())


def sign(key, data):
    return ("# Ed25519 signature of index.toml by the WormForge catalogue key.\n"
            + key.sign(data).hex() + "\n")


def publish(site, base_url=BASE_URL, key=None):
    out_dir = site / "downloads" / "packs"
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        staged = stage_public(tmp)
        # A published version never changes: content that differs from what
        # a version was published with needs a new version. Checked for every
        # mod before anything is written.
        versions, refused = {}, []
        for folder in sorted(p for p in staged.iterdir() if p.is_dir()):
            manifest = tomllib.loads((folder / "mod.toml").read_text(encoding="utf-8"))
            mod_id, version = manifest["id"], manifest.get("version", "0.1.0")
            files = file_hashes(folder)
            known = version_file(site, mod_id, version)
            if known.is_file() and read_version(known) != files:
                refused.append(f"{mod_id} v{version} ({folder.name})")
            versions[folder.name] = (mod_id, version, files)
        if refused:
            raise SystemExit(
                "changed since published under the same version; bump their version in mod.toml:\n  "
                + "\n  ".join(refused))
        new_blobs, all_blobs = store_blobs(site, staged)
        hashes_sha = hashlib.sha256((site / "downloads" / "blobs" / "hashes.txt").read_bytes()).hexdigest()
        for mod_id, version, files in versions.values():
            path = version_file(site, mod_id, version)
            if not path.is_file():
                write_version(path, mod_id, version, files)
        mods = []
        for folder in sorted(p for p in staged.iterdir() if p.is_dir()):
            manifest = tomllib.loads((folder / "mod.toml").read_text(encoding="utf-8"))
            data = mod_zip(folder)
            zip_path = out_dir / f"{folder.name}.zip"
            state = "unchanged" if zip_path.is_file() and zip_path.read_bytes() == data else (
                "UPDATED" if zip_path.is_file() else "new")
            if state != "unchanged":
                zip_path.write_bytes(data)
            mods.append({
                "id": manifest["id"],
                "folder": folder.name,
                "version": manifest.get("version", "0.1.0"),
                "author": manifest.get("author", ""),
                "file": zip_path.name,
                "sha256": hashlib.sha256(data).hexdigest(),
                "size": len(data),
            })
            print(f"{folder.name:16} {manifest['id']:22} v{mods[-1]['version']:8} {len(data) // 1024:6} KB  {state}")
        known = {m["file"] for m in mods}
        for old in sorted(out_dir.glob("*.zip")):
            if old.name not in known:
                print(f"{old.name:16} removed (no longer published)")
                old.unlink()
        lines = [
            "# WormForge mod index. Generated by tools/publish-packs.py; do not edit by hand.",
            f"schema = {INDEX_SCHEMA}",
            f"generated = \"{datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\"",
            f"base = {toml_string(base_url)}",
            # The public store: every published file by hash (blobs/<aa>/<sha>,
            # blobs/hashes.txt), and each version's file list (versions/).
            f"blobs = {toml_string(urllib.parse.urljoin(base_url, '../blobs/'))}",
            f"hashes = {toml_string(hashes_sha)}",
        ]
        for m in mods:
            lines += ["", "[[packs]]"]
            lines += [f"{k} = {toml_string(m[k])}" for k in ("id", "folder", "version", "author", "file", "sha256")]
            lines.append(f"size = {m['size']}")
        index = ("\n".join(lines) + "\n").encode("utf-8")
        (out_dir / "index.toml").write_bytes(index)
        (out_dir / "index.toml.sig").write_text(sign(key, index), encoding="utf-8")
        # Every mod at once used to go out too: it grew the site's history by
        # its whole size on every publish, and the loader never used it.
        old_all = site / "downloads" / "mods.zip"
        if old_all.is_file():
            print("mods.zip         removed (no longer published)")
            old_all.unlink()
    print(f"{len(mods)} mods, index schema {INDEX_SCHEMA}, in {out_dir}; store: {new_blobs} new of {all_blobs} files")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--site", type=Path, help="the site repo's checkout (its downloads/ is written)")
    parser.add_argument("--base-url", default=BASE_URL,
                        help="where the site serves downloads/packs/ (default: the public front, ropa's site)")
    parser.add_argument("--key", type=Path, default=KEY_FILE,
                        help=f"the catalogue key's private half (default {KEY_FILE})")
    parser.add_argument("--new-key", action="store_true",
                        help="make a catalogue key at --key and print its public half; publish nothing")
    args = parser.parse_args()
    if args.new_key:
        new_key(args.key)
        return
    if args.site is None:
        parser.error("--site is required")
    if not args.base_url.startswith("https://") or not args.base_url.endswith("/"):
        raise SystemExit("--base-url must be an https address ending in /")
    # Before anything is written: no key, no publish.
    publish(args.site.resolve(), args.base_url, load_key(args.key))


if __name__ == "__main__":
    main()
