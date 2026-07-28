# CLAUDE.md

This repository is the **qopsc fork** of `flatcar/sysext-bakery`. Read `AGENTS.md` for the full fork-maintenance contract before changing anything — it defines the eight protected fork patches and the upstream sync procedure.

## Quick facts

- Remotes: `origin` = `qopsc/sysext-bakery` (this fork), `flatcar` = upstream.
- Divergence from `flatcar/main` is **eight permanent patches**, plus temporary divergences listed in AGENTS.md (currently: the netbird extension, pending flatcar/sysext-bakery#243). Anything else is drift.

  | # | Patch | File(s) |
  |---|-------|---------|
  | 1 | Docker-only default | `docker.sysext/create.sh` |
  | 2 | Docker-only `rm` filename fix | `docker.sysext/create.sh` |
  | 3 | EROFS default format | `lib/generate.sh` |
  | 4 | Fork identity | `.env`, `.gitignore` |
  | 5 | Fork docs | `AGENTS.md`, `CLAUDE.md` |
  | 6 | Build-list subset (no kata-containers) | `release_build_versions.txt` |
  | 7 | Metadata resilience | `release_meta.sh` |
  | 8 | CI resilience | `.github/workflows/release.yaml` |

- Patches 1 and 2 are in the same function — they rebase as **one conflict**, resolve together.
- Patches 2, 7 and 8 fix bugs that also exist upstream; they are carried fork-locally by choice and should disappear if upstream ever fixes them.
- `.env` values (`bakery`, `bakery_hub`) are load-bearing: `bakery_hub` is baked into sysupdate configs shipped inside released images. Do not change without a node-migration plan.
- `release_build_versions.txt` tracks upstream **except** the commented-out `kata-containers` line (patch 6): its x86-64 image is 2.286 GiB against GitHub's hard 2 GiB asset limit, and squashfs does not fix it.
- Every other file tracks upstream verbatim — in conflicts, upstream wins outside the eight patches.

## Known issue

`bakery_hub` (`extensions.quantumops.consulting`) **has no DNS record**. Released images ship a sysupdate `.conf` pointing at it, so node-side sysupdate does not work yet. Builds and releases are unaffected. Do not "fix" this by editing `.env`.

## Upstream sync

```bash
git fetch flatcar
git rebase flatcar/main main
git push --force-with-lease origin main
git diff flatcar/main main --stat   # must show only the expected fork files
```

## Building

```bash
./bakery.sh list <extension>                 # list available versions
./bakery.sh create <extension> <version>     # bake a sysext (defaults: erofs, docker-only)
```
