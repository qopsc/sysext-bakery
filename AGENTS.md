# AI Agent Fork Maintenance Guide

## Purpose

Instructions for AI agents (Claude, Copilot, Cursor, Aider, etc.) working on this repository. This is a **fork** of `flatcar/sysext-bakery` carrying a small, deliberate patch stack that must be preserved across upstream syncs.

---

## Repository Context

- **Fork**: `qopsc/sysext-bakery` (git remote: `origin`)
- **Upstream**: `flatcar/sysext-bakery` (git remote: `flatcar`)
- **Fork hub**: `extensions.quantumops.consulting`
- **Legacy fork** (retired): `darkspadez/sysext-bakery` / `sysext.darkspadez.me` — kept only until nodes deployed from it are re-provisioned.

The fork's entire divergence from upstream is **four commits** on top of `flatcar/main`:

1. **docker-only default** — `docker.sysext/create.sh`: the `without` parameter defaults to `containerd` instead of empty.
2. **EROFS default** — `lib/generate.sh`: the `format` parameter defaults to `erofs` instead of `squashfs`.
3. **Fork identity** — `.gitignore` no longer ignores `.env`; `.env` is committed with the qopsc values.
4. **These docs** — `AGENTS.md` and `CLAUDE.md`.

Nothing else may diverge. If you find other differences from `flatcar/main`, they are drift — investigate and remove them.

---

## Protected Patches

### 1. Docker-only default

**File**: `docker.sysext/create.sh`, in `populate_sysext_root()`:

```bash
local without="$(get_optional_param "without" "containerd" "$@")"
```

Upstream defaults `without` to `""` (ship docker + containerd/runc bundled). This fork defaults to `containerd`, so upstream's own `--without containerd` code path strips containerd, runc, and the bundled containerd unit/config files from every default build — including release builds, which pass no options (`release.sh`).

**Rules**:
- Preserve only this one-line default change. Do NOT delete upstream's conditional logic or the `docker.sysext/files/**/containerd*` files — upstream's code removes them from the built image at bake time.
- A combined docker+containerd image can still be built with `--without ''`.
- If upstream renames or refactors the `without` parameter, re-apply the same intent: default release builds must ship docker-only.

### 2. EROFS default format

**File**: `lib/generate.sh`, in `generate_sysext()`:

```bash
local format="$(get_optional_param "format" "erofs" "${@}")"
```

Upstream default is `squashfs`. All qopsc release images are EROFS. Squashfs remains available via `--format squashfs`.

### 3. Fork identity (.env)

**File**: `.env` (committed; upstream gitignores it — this fork removed that ignore line):

```bash
bakery="qopsc/sysext-bakery"
bakery_hub="extensions.quantumops.consulting"
```

- `bakery` drives release-existence checks and publishing (`release_dispatcher.sh`, `release_meta.sh`).
- `bakery_hub` is baked into the sysupdate `.conf` shipped inside every released sysext (`lib/generate.sh` → `lib/sysupdate.conf.tmpl`) — deployed nodes poll `https://<bakery_hub>/extensions/...` for updates. Changing it silently orphans already-deployed nodes; never change it casually.

### 4. Intentionally NOT customized

- `release_build_versions.txt` — tracks upstream verbatim. Take upstream's version in any conflict.
- Everything else in the repo — tracks upstream verbatim.

Historical customizations that were dropped because they converged upstream: docker-buildx sysext, wasmedge fixes, erofs <1.8.5 workaround, workflow tweaks, and the old six-file docker.sysext hard fork.

---

## Upstream Sync Procedure

The patch stack is rebased onto upstream; history on `origin/main` is linear upstream history + 4 fork commits.

```bash
git fetch flatcar
git rebase flatcar/main main
# resolve conflicts per the rules above (fork patches win only within their one-line scope)
git push --force-with-lease origin main
```

After every sync, verify the divergence is exactly the expected files:

```bash
git diff flatcar/main main --stat
# expected: .env, .gitignore, AGENTS.md, CLAUDE.md,
#           docker.sysext/create.sh (1 line), lib/generate.sh (1 line)
```

And sanity-check the scripts:

```bash
bash -n docker.sysext/create.sh lib/generate.sh
./bakery.sh list docker | head
```

---

## Release Verification

After a release workflow run on qopsc, spot-check a docker asset:

- contains **no** `usr/bin/containerd` / `usr/bin/runc`;
- `file docker-*.raw` reports EROFS;
- its `docker.conf` sysupdate `Path` points at `extensions.quantumops.consulting`.
