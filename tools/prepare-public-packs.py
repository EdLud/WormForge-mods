#!/usr/bin/env python3
"""Stage public packs without diagnostic components, their entries or profiles."""
import argparse
from pathlib import Path
import re
import shutil
import tomllib


def references(value, ids):
    if isinstance(value, dict):
        return any(k in ids or references(v, ids) for k, v in value.items())
    if isinstance(value, list):
        return any(references(v, ids) for v in value)
    return isinstance(value, str) and value in ids


def stage(source, output):
    source, output = Path(source).resolve(), Path(output).resolve()
    if source == output or source in output.parents or output in source.parents:
        raise ValueError("source and staging directories must be separate")
    if output.exists() and any(output.iterdir()):
        raise ValueError("staging directory must be empty")
    output.mkdir(parents=True, exist_ok=True)
    manifests = {}
    diagnostic_ids = set()
    for bundle in sorted(source.iterdir()):
        manifest = bundle / "mod.toml"
        if not manifest.is_file():
            continue
        text = manifest.read_text(encoding="utf-8")
        data = tomllib.loads(text)
        diagnostic = [c for c in data.get("components", []) if c.get("diagnostics", False)]
        diagnostic_ids.update(c["id"] for c in diagnostic)
        manifests[bundle] = (text, diagnostic)
    for bundle, (text, diagnostic) in manifests.items():
        declared_exports = tomllib.loads(text).get("exports", {})
        excluded = set()
        for c in diagnostic:
            entry = Path(c["entry"])
            if entry.is_absolute() or ".." in entry.parts:
                raise ValueError(f"unsafe entry path: {entry}")
            # Entries in a subdirectory own that diagnostic tool's supporting files.
            excluded.add(entry if entry.parent == Path(".") else Path(entry.parts[0]))
        # Exports are a root table even when written after a diagnostic
        # component. Preserve them before filtering component blocks. Keep
        # existing bundles byte-identical when they have no exports.
        exports = []
        def keep_exports(match):
            exports.append(match.group(0))
            return ""
        text = re.sub(r"(?ms)^[ \t]*\[exports\][ \t]*(?:\#[^\n]*)?\n.*?(?=^[ \t]*\[|\Z)", keep_exports, text)
        pieces = re.split(r"(?m)^\s*\[\[components\]\]\s*$", text)
        header = re.sub(r"(?m)^\s*debug_(?:input|worm_state)\s*=.*\n?", "", pieces[0])
        kept = [piece for piece in pieces[1:]
                if not tomllib.loads("[[components]]\n" + piece)["components"][0].get("diagnostics", False)]
        public_manifest = header + "".join(exports) + "".join("[[components]]\n" + piece for piece in kept)
        if tomllib.loads(public_manifest).get("exports", {}) != declared_exports:
            raise ValueError(f"{bundle.name}: public exports were removed with diagnostic components")
        public_components = tomllib.loads(public_manifest).get("components", [])
        for c in public_components:
            if set(c.get("requires", [])) & diagnostic_ids:
                raise ValueError(f"{c['id']}: a public component requires a diagnostic component")
        target = output / bundle.name
        target.mkdir()
        for file in sorted(bundle.rglob("*")):
            if not file.is_file():
                continue
            rel = file.relative_to(bundle)
            if rel == Path("mod.toml") or any(rel == e or e in rel.parents for e in excluded):
                continue
            if file.suffix == ".toml" and "profiles" in rel.parts:
                if references(tomllib.loads(file.read_text(encoding="utf-8")), diagnostic_ids):
                    continue
            dest = target / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, dest)
        for c in public_components:
            if not (target / c["entry"]).is_file():
                raise ValueError(f"{c['id']}: diagnostic files overlap the public entry {c['entry']}")
        (target / "mod.toml").write_text(public_manifest, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    stage(args.source, args.output)


if __name__ == "__main__":
    main()
