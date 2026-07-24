# CLAUDE.md

This repository is the **qopsc fork** of `flatcar/sysext-bakery`. Read `AGENTS.md` for the full fork-maintenance contract before changing anything — it defines the four protected fork patches and the upstream sync procedure.

## Quick facts

- Remotes: `origin` = `qopsc/sysext-bakery` (this fork), `flatcar` = upstream.
- Divergence from `flatcar/main` is four permanent commits: docker-only default (`docker.sysext/create.sh`), EROFS default (`lib/generate.sh`), committed `.env` fork identity, and these docs — plus temporary divergences listed in AGENTS.md (currently: the netbird extension, pending flatcar/sysext-bakery#243). Anything else is drift.
- `.env` values (`bakery`, `bakery_hub`) are load-bearing: `bakery_hub` is baked into sysupdate configs shipped inside released images. Do not change without a node-migration plan.
- `release_build_versions.txt` and all other files track upstream verbatim — in conflicts, upstream wins outside the four patches.

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
