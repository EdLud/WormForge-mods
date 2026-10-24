#!/usr/bin/env python3
"""Build the online mod catalogue the WormForge loader reads (Check online).

The packs selected by catalogue.toml, staged
without their diagnostic components by `tools/prepare-public-packs.py`, go
into <site>/downloads/packs/:

  <folder>.zip   one per mod, deterministic (sorted entries, a fixed time),
                 so an unchanged mod keeps its sha256 and installed copies
                 stay "up to date";
  index.toml     schema 3 (`weapons::INDEX_SCHEMA`, mods in the current
                 format): id / folder / version / author / file / sha256 / size,
                 the store's address and its list's hash;
  index.toml.sig the index's Ed25519 signature, hex, by the catalogue key
                 (`weapons::CATALOGUE_KEYS`): the loader uses nothing from an
                 index without it;

and the public store, <site>/downloads/blobs/ (every published file by
hash) with each version's file list in <site>/downloads/packs/versions/.
Of the profiles the mods carry, only those selected in catalogue.toml go out.
A zip for a mod no longer published is removed, and so is the old
downloads/mods.zip (every mod at once; the loader installs from the zips).

The signing key's private half (an Ed25519 seed, hex) stays with whoever
publishes, outside the repo: --key, by default KEY_FILE. Each publisher has
their own; --new-key makes one and prints its public half, which goes into
`weapons::CATALOGUE_KEYS` for the next DLL (the private half never leaves
its machine).

    python3 tools/publish-packs.py --new-key

    python3 tools/publish-packs.py --site ../WormForge-site
"""
import argparse
import datetime
import hashlib
import importlib.util
import io
import shutil
import re
import subprocess
import tarfile
import tempfile
import tomllib
import urllib.parse
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# The catalogue the DLL reads (weapons::PUBLIC_INDEX_URL): ropahektic/WormForge,
# the only one.
BASE_URL = "https://ropahektic.github.io/WormForge/downloads/packs/"
INDEX_SCHEMA = 3
SOURCE_URL = "https://github.com/EdLud/WormForge-mods"
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
        if path.is_symlink():
            raise ValueError(f"source symlinks are not supported: {path}")
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


def catalogue():
    """Explicit source selection, shared by validation and publication."""
    config = tomllib.loads((REPO / "catalogue.toml").read_text(encoding="utf-8"))
    if config.get("schema") != 1 or set(config) != {"schema", "packs", "profiles"}:
        raise ValueError("catalogue.toml needs schema=1, packs and profiles")
    packs, profiles = config["packs"], config["profiles"]
    if not isinstance(packs, list) or not packs or not isinstance(profiles, list):
        raise ValueError("catalogue packs must be a nonempty list; profiles must be a list")
    for value in packs + profiles:
        if not isinstance(value, str):
            raise ValueError("catalogue paths must be strings")
        path = Path(value)
        if path.is_absolute() or ".." in path.parts or "\\" in value or str(path) != value:
            raise ValueError(f"unsafe catalogue path: {value!r}")
        if not (REPO / path).resolve().is_relative_to(REPO.resolve()):
            raise ValueError(f"catalogue path escapes repository: {value}")
    if len({Path(p).name.casefold() for p in packs}) != len(packs):
        raise ValueError("catalogue pack folder names must be unique")
    if len(set(profiles)) != len(profiles):
        raise ValueError("catalogue profiles must be unique")
    for profile in profiles:
        if not any(Path(profile).parent == Path(pack) / "profiles" for pack in packs):
            raise ValueError(f"profile is not in a selected pack: {profile}")
        if Path(profile).suffix != ".toml":
            raise ValueError(f"profile is not TOML: {profile}")
    return packs, profiles


def stage_public(tmp):
    """Stage exactly the selected packs/profiles, excluding diagnostics."""
    public, profiles = catalogue()
    gathered, staged = Path(tmp) / "source", Path(tmp) / "public"
    gathered.mkdir()
    ids, components = set(), set()
    for rel in public:
        src = REPO / rel
        manifest = src / "mod.toml"
        if not manifest.is_file():
            raise ValueError(f"{rel}: no mod.toml")
        data = tomllib.loads(manifest.read_text(encoding="utf-8"))
        if data.get("format_version") != 2 or data.get("api_version") != 4:
            raise ValueError(f"{rel}: expected bundle format 2 / API 4")
        for key in ("id", "version"):
            value = data.get(key, "")
            if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.+-]*", value):
                raise ValueError(f"{rel}: unsafe or missing {key}")
        if data["id"] in ids:
            raise ValueError(f"duplicate pack id: {data['id']}")
        ids.add(data["id"])
        for component in data.get("components", []):
            if component["id"] in components:
                raise ValueError(f"duplicate component id: {component['id']}")
            components.add(component["id"])
        # Reject symlinks before copytree could follow one outside the source.
        files_of(src)
        shutil.copytree(src, gathered / src.name, ignore=shutil.ignore_patterns(*SKIP))
    prepare.stage(gathered, staged)
    validate_libraries(staged)
    selected = {Path(Path(p).parent.parent.name) / "profiles" / Path(p).name for p in profiles}
    found = set()
    for profile in staged.glob("*/profiles/*.toml"):
        rel = profile.relative_to(staged)
        if rel in selected:
            tomllib.loads(profile.read_text(encoding="utf-8"))
            found.add(rel)
        else:
            profile.unlink()
    if found != selected:
        raise ValueError(f"public profiles missing or diagnostic: {sorted(str(p) for p in selected - found)}")
    for folder in staged.glob("*/profiles"):
        if not any(folder.iterdir()):
            folder.rmdir()
    return staged


def validate_libraries(staged):
    """Check dependencies and exported files in the actual public payload."""
    packs, exports, namespaces = {}, {}, {}
    for folder in staged.iterdir():
        data = tomllib.loads((folder / "mod.toml").read_text(encoding="utf-8"))
        packs[data["id"]] = data
        deps = data.get("dependencies", [])
        if not isinstance(deps, list) or any(not isinstance(d, str) for d in deps) or len(set(deps)) != len(deps):
            raise ValueError(f"{data['id']}: invalid dependencies")
        namespace = data.get("asset_namespace")
        if namespace is not None:
            if not isinstance(namespace, str) or not re.fullmatch(r"wf-lib/[A-Za-z0-9_-]+", namespace):
                raise ValueError(f"{data['id']}: invalid asset namespace")
            if namespace in namespaces:
                raise ValueError(f"duplicate asset namespace: {namespace}")
            namespaces[namespace] = data["id"]
        for name, entry in data.get("exports", {}).items():
            if not re.fullmatch(r"wf-lib/[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*", name):
                raise ValueError(f"{data['id']}: invalid export {name}")
            if name in exports:
                raise ValueError(f"duplicate library export: {name}")
            exports[name] = data["id"]
            if (not isinstance(entry, str) or not re.fullmatch(r"[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\.lua", entry)
                    or not (folder / entry).is_file()):
                raise ValueError(f"{data['id']}: missing or invalid public export file {entry}")
    done = set()

    def visit(mod_id, active):
        if mod_id in active:
            raise ValueError(f"library dependency cycle: {' -> '.join(active + [mod_id])}")
        if mod_id not in packs:
            raise ValueError(f"missing published library dependency: {mod_id}")
        if mod_id in done:
            return
        for dependency in packs[mod_id].get("dependencies", []):
            visit(dependency, active + [mod_id])
        done.add(mod_id)

    for mod_id in packs:
        visit(mod_id, [])


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


def checked_versions(staged, site):
    """Reject all reused versions before any download file is written."""
    versions, refused = {}, []
    for folder in sorted(p for p in staged.iterdir() if p.is_dir()):
        manifest = tomllib.loads((folder / "mod.toml").read_text(encoding="utf-8"))
        mod_id, version = manifest["id"], manifest["version"]
        files = file_hashes(folder)
        known = version_file(site, mod_id, version) if site is not None else None
        if known is not None and known.is_file() and read_version(known) != files:
            refused.append(f"{mod_id} v{version} ({folder.name})")
        versions[folder.name] = (mod_id, version, files)
    if refused:
        raise ValueError("changed since published under the same version; bump mod.toml:\n  "
                         + "\n  ".join(refused))
    return versions


def check_source(site=None):
    if site is not None and not (site / "downloads/packs").is_dir():
        raise ValueError(f"site has no downloads/packs history: {site}")
    with tempfile.TemporaryDirectory() as tmp:
        staged = stage_public(tmp)
        versions = checked_versions(staged, site)
        for mod_id, version, files in versions.values():
            print(f"{mod_id} {version}: {len(files)} files")
        return versions


def verify_site(site, public_key):
    """Check the complete local download snapshot, including its signature."""
    packs, blobs = site / "downloads/packs", site / "downloads/blobs"
    raw = (packs / "index.toml").read_bytes()
    signature = "".join(line.strip() for line in (packs / "index.toml.sig").read_text().splitlines()
                        if line.strip() and not line.startswith("#"))
    public_key.verify(bytes.fromhex(signature), raw)
    index = tomllib.loads(raw.decode("utf-8"))
    if index["schema"] != INDEX_SCHEMA:
        raise ValueError("unsupported catalogue schema")
    hashes = (blobs / "hashes.txt").read_bytes()
    if hashlib.sha256(hashes).hexdigest() != index["hashes"]:
        raise ValueError("blob list does not match signed index")
    names = hashes.decode("ascii").splitlines()
    if names != sorted(set(names)):
        raise ValueError("blob list must be sorted and unique")
    for sha in names:
        if not re.fullmatch(r"[0-9a-f]{64}", sha):
            raise ValueError("invalid blob hash")
        if hashlib.sha256((blobs / sha[:2] / sha).read_bytes()).hexdigest() != sha:
            raise ValueError(f"corrupt blob: {sha}")
    available = set(names)
    # Historical versions must remain reconstructible after every build.
    for path in (packs / "versions").glob("*/*.toml"):
        if not set(read_version(path).values()) <= available:
            raise ValueError(f"historical version references missing blobs: {path}")
    seen = set()
    for pack in index["packs"]:
        if pack["id"] in seen:
            raise ValueError(f"duplicate pack id: {pack['id']}")
        seen.add(pack["id"])
        for field in ("id", "version", "folder", "file"):
            value = pack[field]
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.+-]*", value):
                raise ValueError(f"unsafe pack {field}: {value}")
        data = (packs / pack["file"]).read_bytes()
        if len(data) != pack["size"] or hashlib.sha256(data).hexdigest() != pack["sha256"]:
            raise ValueError(f"archive mismatch: {pack['id']}")
        expected = read_version(version_file(site, pack["id"], pack["version"]))
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            actual = {name: hashlib.sha256(archive.read(name)).hexdigest() for name in archive.namelist()}
            if len(actual) != len(archive.namelist()):
                raise ValueError(f"duplicate archive entries: {pack['id']}")
        if actual != {f"{pack['folder']}/{path}": sha for path, sha in expected.items()}:
            raise ValueError(f"archive does not match version manifest: {pack['id']}")
    print(f"Verified signed catalogue: {len(seen)} packs, {len(names)} blobs")


def build_site(site, base_url, key):
    """Build a committed source snapshot; verify before replacing downloads."""
    global REPO
    status = subprocess.check_output(["git", "-C", str(REPO), "status", "--porcelain",
                                      "--untracked-files=normal"], text=True)
    if status:
        raise ValueError("commit mods repository changes before building; use --check for a working-tree preview")
    commit = subprocess.check_output(["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True).strip()
    epoch = int(subprocess.check_output(["git", "-C", str(REPO), "show", "-s", "--format=%ct", "HEAD"]))
    snapshot = subprocess.check_output(["git", "-C", str(REPO), "archive", "--format=tar", commit])
    if not site.is_dir():
        raise ValueError(f"site checkout does not exist: {site}")
    with tempfile.TemporaryDirectory(prefix=".catalogue-build-", dir=site) as temp:
        root = Path(temp)
        source, candidate = root / "source", root / "site"
        source.mkdir()
        candidate.mkdir()
        with tarfile.open(fileobj=io.BytesIO(snapshot)) as archive:
            archive.extractall(source, filter="data")
        downloads = site / "downloads"
        if downloads.exists():
            shutil.copytree(downloads, candidate / "downloads")
        # The archive is the only input: ignored files never enter a pack.
        previous = REPO
        try:
            REPO = source
            publish(candidate, base_url, key, commit, epoch)
            verify_site(candidate, key.public_key())
        finally:
            REPO = previous
        if downloads.exists():
            downloads.rename(root / "previous-downloads")
        try:
            (candidate / "downloads").rename(downloads)
        except BaseException:
            if (root / "previous-downloads").exists():
                (root / "previous-downloads").rename(downloads)
            raise
    print(f"Built from {SOURCE_URL}@{commit}; review and commit the website changes")


def publish(site, base_url=BASE_URL, key=None, source_commit=None, source_time=None):
    out_dir = site / "downloads" / "packs"
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        staged = stage_public(tmp)
        # A published version never changes: content that differs from what
        # a version was published with needs a new version. Checked for every
        # mod before anything is written.
        versions = checked_versions(staged, site)
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
        generated = (datetime.datetime.fromtimestamp(source_time, datetime.timezone.utc)
                     if source_time is not None else datetime.datetime.now(datetime.timezone.utc))
        lines = [
            "# WormForge mod index. Generated by tools/publish-packs.py; do not edit by hand.",
            f"schema = {INDEX_SCHEMA}",
            f"generated = {toml_string(generated.strftime('%Y-%m-%dT%H:%M:%SZ'))}",
            f"base = {toml_string(base_url)}",
            # The public store: every published file by hash (blobs/<aa>/<sha>,
            # blobs/hashes.txt), and each version's file list (versions/).
            f"blobs = {toml_string(urllib.parse.urljoin(base_url, '../blobs/'))}",
            f"hashes = {toml_string(hashes_sha)}",
        ]
        if source_commit is not None:
            lines += [f"source_repository = {toml_string(SOURCE_URL)}",
                      f"source_commit = {toml_string(source_commit)}"]
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
    parser.add_argument("--key", type=Path, default=KEY_FILE,
                        help=f"the catalogue key's private half (default {KEY_FILE})")
    parser.add_argument("--new-key", action="store_true",
                        help="make a catalogue key at --key and print its public half; publish nothing")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true",
                      help="validate working sources and optional --site version history; write nothing")
    mode.add_argument("--verify", action="store_true",
                      help="verify an existing site's signed downloads using --key; write nothing")
    args = parser.parse_args()
    if args.new_key:
        new_key(args.key)
        return
    if args.check:
        check_source(args.site.resolve() if args.site is not None else None)
        return
    if args.site is None:
        parser.error("--site is required")
    base_url = BASE_URL
    # Before anything is written: no key, no publish.
    key = load_key(args.key)
    if args.verify:
        verify_site(args.site.resolve(), key.public_key())
    else:
        build_site(args.site.resolve(), base_url, key)


if __name__ == "__main__":
    main()
