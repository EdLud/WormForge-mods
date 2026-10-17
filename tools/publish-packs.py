#!/usr/bin/env python3
"""Build the online mod catalogue the WormForge loader reads (Check online).

The published mods (PUBLIC: `mods/px` and the public examples), staged
without their diagnostic components by `tools/prepare-public-packs.py`, go
into <site>/downloads/packs/:

  <folder>.zip   one per mod, deterministic (sorted entries, a fixed time),
                 so an unchanged mod keeps its sha256 and installed copies
                 stay "up to date";
  index.toml     schema 2 (`weapons::INDEX_SCHEMA`, mods in the current
                 format): id / folder / version / author / file / sha256 / size;

and <site>/downloads/mods.zip, every mod at once, for installing by hand.
Of the profiles the mods carry, only PUBLIC_PROFILES go out.
A zip for a mod no longer published is removed.

    python3 tools/publish-packs.py --site ../WormForge-site
    # our staging copy of the site (the fork), to test before a PR:
    python3 tools/publish-packs.py --site ../WormForge-site --base-url https://edlud.github.io/WormForge/downloads/packs/
"""
import argparse
import datetime
import hashlib
import importlib.util
import io
import shutil
import tempfile
import tomllib
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# The public front: ropa's site. A staging copy of it (our fork, for testing
# before a PR, docs/content-store-plan.md) takes --base-url.
BASE_URL = "https://ropahektic.github.io/WormForge/downloads/packs/"
INDEX_SCHEMA = 2
# The mods players get: Highlander and its ports, the add-ons, the examples.
# The audits and test weapons (`tools`, `labs`) stay in the repo, and so do
# `gravler_strike` and `turret`, which Highlander's px.ports now covers.
PUBLIC = [
    "mods/px",
    "mods/examples/utilities",
    "mods/examples/component_demo",
    "mods/examples/gif_donkey",
    "mods/examples/pooz",
    "mods/examples/wormcraft",
    "mods/examples/KillTheKing",
]
# The saved profiles players get, from the mods' `profiles/`. Any other a
# mod carries (Growth Hormones, Highlander weapons) stays in the repo.
PUBLIC_PROFILES = {"Demo", "Funny", "Highlander", "Full Wormforage"}
# Never in a zip: the OS's and Python's leftovers.
SKIP = {".DS_Store", "__pycache__", "Thumbs.db"}
FIXED_TIME = (2020, 1, 1, 0, 0, 0)

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


def publish(site, base_url=BASE_URL):
    out_dir = site / "downloads" / "packs"
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        staged = stage_public(tmp)
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
        ]
        for m in mods:
            lines += ["", "[[packs]]"]
            lines += [f"{k} = {toml_string(m[k])}" for k in ("id", "folder", "version", "author", "file", "sha256")]
            lines.append(f"size = {m['size']}")
        (out_dir / "index.toml").write_text("\n".join(lines) + "\n", encoding="utf-8")
        # Every mod at once, for installing by hand (the loader uses the zips).
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zf:
            for folder in sorted(p for p in staged.iterdir() if p.is_dir()):
                for rel in files_of(folder):
                    add(zf, f"{folder.name}/{rel.as_posix()}", (folder / rel).read_bytes())
        (site / "downloads" / "mods.zip").write_bytes(buf.getvalue())
    print(f"{len(mods)} mods, index schema {INDEX_SCHEMA}, in {out_dir}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--site", type=Path, required=True, help="the site repo's checkout (its downloads/ is written)")
    parser.add_argument("--base-url", default=BASE_URL,
                        help="where the site serves downloads/packs/ (default: the public front, ropa's site)")
    args = parser.parse_args()
    if not args.base_url.startswith("https://") or not args.base_url.endswith("/"):
        raise SystemExit("--base-url must be an https address ending in /")
    publish(args.site.resolve(), args.base_url)


if __name__ == "__main__":
    main()
