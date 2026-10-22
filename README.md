# WormForge mods

The source repository for WormForge's Lua packs, artwork, sounds, profiles and
pack tests. Mod changes belong here. The engine lives in
[EdLud/WormForgeNew](https://github.com/EdLud/WormForgeNew); the production
catalogue is served by [ropahektic/WormForge](https://github.com/ropahektic/WormForge).

`px/` contains the Project X ports and Highlander. `examples/` contains the
other bundles, including developer and diagnostic examples. `catalogue.toml`
selects exactly which packs and profiles players receive. Diagnostic components
and their support files are removed during public staging.

## Working locally

In the game installation, create your own bundle directly under
`WormForge/Mods/<my-mod>/`. Catalogue downloads go under `Mods/wf-lib/`, which
contains a warning explaining ownership. Update All skips locally edited packs.
**Replace (backup)** explicitly installs the catalogue copy while retaining the
complete previous folder under `WormForge/Backups/Packs/`; saved profiles stay
under `WormForge/Profiles/`.

The public [SDK helpers](sdk/README.md) expose the PX sprite builder, postures
and hands through `require("wf-lib/px_sprite_builder")` with
`dependencies = ["wf.sdk"]` in your manifest. See
[`examples/shared_library_demo`](examples/shared_library_demo) for a separate
weapon using these helpers. Library state stays private to each consuming
bundle. Selected dependencies and assets are frozen for online games and replays.

The engine checks this repository out at `mods/`; the website checks it out at
`catalogue/`. Both are Git submodules pinned to a particular commit. Initialize
them with `git submodule update --init --recursive` after cloning a parent.

The usual catalogue workspace is:

```text
WormForge-site/
  catalogue/             this repository; edit and commit mods here
  downloads/             generated, signed catalogue and retained content store
```

Before editing a submodule, switch it to a branch, for example
`git switch -c update-health-zone`. Commit and push changes in that repository
first; then commit the new submodule pointer in the engine or website. Updating
one parent does not automatically update the other. Never pin an unpublished
mods commit in a parent that other people need to clone.

Run engine integration tests from an engine checkout using the same mods
commit. Existing `mods/px` and `mods/examples` paths remain valid there.

## Catalogue checks and builds

Requires Python 3.11+ and `python3 -m pip install -r requirements.txt`.

From `WormForge-site/`:

```sh
python3 catalogue/tools/test_catalogue.py
# Preview sources and compare versions against the website's retained history.
python3 catalogue/tools/publish-packs.py --check --site .
```

Change the version in each affected pack's `mod.toml` before republishing changed
files, including changed bundled profiles. A published `(pack id, version)` is
immutable. Unchanged packs keep their archive hashes. Removing a bundled profile
does not remove a player's locally saved profile.

Commit the mods changes before building. The builder reads a Git archive of
that exact commit, excluding ignored or untracked files. The signed index records
the source repository and commit. With the same retained store and base URL,
building the same commit produces the same catalogue bytes.

Build for the staging fork:

```sh
python3 catalogue/tools/publish-packs.py --site . --channel staging
```

The signing seed stays outside Git, by default at
`~/.config/wormforge/catalogue-signing.key`. Both catalogues need a key trusted by
the DLL. The public key is safe to share; the seed must not enter source, logs,
release archives or website files. Building locally uses the existing key.

The builder prepares a complete candidate, checks its signature, archives,
version manifests and retained blobs, then replaces the local `downloads/`.
A failure preserves the previous downloads. Review and commit the website's
submodule pointer and generated files together, then deploy that snapshot.
Building does not commit, push or deploy anything.

For loader testing, point the test installation's `WormForge/online.toml` at:

```toml
index_url = "https://edlud.github.io/WormForge/downloads/packs/index.toml"
```

The DLL's default remains the production catalogue. Test staging with a separate
installation or backed-up settings; leave ordinary players on production.

## Promoting to production

Shared-library catalogues use schema 3. Publish a compatible engine DLL before
promoting them; older DLLs refuse schema 3 without installing any packs. Current
DLLs continue to accept older schema 2 catalogues.

1. Test the staging catalogue through the loader and in game.
2. Pin the **same mods commit** in the production website checkout.
3. Rebuild there with `--channel production`.
4. Verify and review the complete generated downloads, then commit and deploy.

Staging and production indexes differ because they name different hosting URLs;
the mod archives come from the same committed source. Retain historical version
manifests and blobs so old replays remain reconstructible. Roll back by restoring
a previously tested mods pointer and rebuilding against the retained store.

## History

The initial history preserves 279 commits affecting mods and catalogue tooling
from engine commit `4af1ba763933b00a71b29e13f682015f88901208`. Paths under the old
`mods/` directory are now rooted here. Commit hashes changed during extraction;
authors, dates and messages are preserved. Engine source and local notes were
excluded. The original engine history remains intact.

Source examples may include diagnostic tools; their public availability does
not enable diagnostic verbs in a public DLL. Player downloads continue to pass
through the public-component filter.
