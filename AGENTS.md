# AI Agent Fork Maintenance Guide

## Purpose

Instructions for AI agents (Claude, Copilot, Cursor, Aider, etc.) working on this repository. This is a **fork** of `flatcar/sysext-bakery` carrying a small, deliberate patch stack that must be preserved across upstream syncs.

---

## Repository Context

- **Fork**: `qopsc/sysext-bakery` (git remote: `origin`)
- **Upstream**: `flatcar/sysext-bakery` (git remote: `flatcar`)
- **Fork hub**: `extensions.quantumops.consulting` — **not yet stood up**, see Known Issues.
- **Legacy fork** (retired): `darkspadez/sysext-bakery` / `sysext.darkspadez.me` — kept only until nodes deployed from it are re-provisioned.

The fork's divergence from `flatcar/main` is **eight permanent patches** plus any temporary divergences listed below. Anything not covered by either list is drift — investigate and remove it.

| # | Patch | File(s) | Kind |
|---|-------|---------|------|
| 1 | Docker-only default | `docker.sysext/create.sh` | policy |
| 2 | Docker-only `rm` filename fix | `docker.sysext/create.sh` | upstream bugfix |
| 3 | EROFS default format | `lib/generate.sh` | policy |
| 4 | Fork identity | `.env`, `.gitignore` | policy |
| 5 | Fork docs | `AGENTS.md`, `CLAUDE.md` | docs |
| 6 | Build-list subset (no kata-containers) | `release_build_versions.txt` | policy |
| 7 | Metadata resilience | `release_meta.sh` | upstream bugfix |
| 8 | CI resilience | `.github/workflows/release.yaml` | upstream bugfix |

Patches marked **upstream bugfix** (2, 7, 8) fix defects that also exist in `flatcar/main`. They are carried fork-locally by choice. If they are ever upstreamed, drop them here on the next rebase and move them to the temporary-divergence list in the meantime.

---

## Temporary Divergences (pending upstream merge)

These commits ride on the fork only until the corresponding upstream PR merges; the next rebase then drops or converges them and they leave this list.

- **netbird extension** (`netbird.sysext/`, `docs/netbird.md`, `docs/index.md` row, `release_build_versions.txt` netbird lines) — upstream PR: https://github.com/flatcar/sysext-bakery/pull/243. The commit is upstream-clean (flatcar URLs in docs); do not add qopsc-specific content to it.

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

### 2. Docker-only `rm` filename fix

**File**: `docker.sysext/create.sh`, same function, in the `--without containerd` branch:

```bash
       "${sysextroot}/usr/share/containerd/config-cgroupfs.toml"
```

Upstream says `config-cgroups.toml`; the file that actually exists is `config-cgroupfs.toml`. The typo dates to upstream commit `e144c64`, the same commit that renamed the file. It is **dead code upstream** because upstream's `without` default is `""`, so that branch never runs — but patch 1 makes it the always-taken path here, and `rm` fails, aborting the build.

This bug cost the fork every docker release between 2026-07-24 and its discovery: not one `docker-<version>` sysext was ever published.

**Rules**:
- Patches 1 and 2 live in the same function and will present as a **single rebase conflict**. Resolve them together.
- Do not soften `rm` to `rm -f`. The strict failure is what surfaced this bug, and it guards against upstream renaming a bundled file again.
- If upstream fixes the typo, this patch disappears on rebase. That is the desired outcome.

### 3. EROFS default format

**File**: `lib/generate.sh`, in `generate_sysext()`:

```bash
local format="$(get_optional_param "format" "erofs" "${@}")"
```

Upstream default is `squashfs`. All qopsc release images are EROFS. Squashfs remains available via `--format squashfs`.

Measured cost: EROFS (`-zlz4hc,12`) produces images **4–8% larger** than squashfs for the same content (ollama-v0.32.5 +4.24%, coder-v2.35.3 +8.19%, qopsc vs flatcar assets of identical versions). This is a real but accepted trade for EROFS's read performance. It matters when an image approaches GitHub's 2 GiB release-asset limit — see patch 6.

### 4. Fork identity (.env)

**File**: `.env` (committed; upstream gitignores it — this fork removed that ignore line):

```bash
bakery="qopsc/sysext-bakery"
bakery_hub="extensions.quantumops.consulting"
```

- `bakery` drives release-existence checks and publishing (`release_dispatcher.sh`, `release_meta.sh`).
- `bakery_hub` is baked into the sysupdate `.conf` shipped inside every released sysext (`lib/generate.sh` → `lib/sysupdate.conf.tmpl`) — deployed nodes poll `https://<bakery_hub>/extensions/...` for updates. Changing it silently orphans already-deployed nodes; never change it casually. **It does not currently resolve** — see Known Issues.

### 5. Fork docs

`AGENTS.md` and `CLAUDE.md`. Keep the patch table above in sync with reality; it is the only thing standing between this fork and a rebase that silently deletes patches 2, 6, 7 and 8 as "drift".

### 6. Build-list subset

**File**: `release_build_versions.txt` — the `kata-containers latest` entry is commented out.

This fork builds a **subset** of upstream's extensions. Every other line tracks upstream verbatim; take upstream's version in any conflict, then re-apply the kata-containers comment.

**Why kata-containers is excluded**: `kata-containers-4.0.0-x86-64.raw` is **2,455,023,616 bytes (2.286 GiB)**, against GitHub's hard **2 GiB (2,147,483,648 B)** per-asset limit — over by 14.3%. Do not relitigate this with a format change: backing out the measured EROFS penalty from patch 3 puts squashfs at **~2.11–2.19 GiB, still over**. kata 4.0.0 ships ~26% more than 3.32.0 (TDX/SNP/NVIDIA/dragonball kernel, initrd and firmware variants) and will only grow.

`release_dispatcher.sh` derives both the build matrix and the metadata matrix from this file, so commenting the line out removes kata from both. `kata-containers.sysext/` and `docs/kata-containers.md` stay — they track upstream and still work for local `./bakery.sh create kata-containers …` builds.

Re-enabling kata would require trimming its payload in `kata-containers.sysext/create.sh` or hosting assets outside GitHub releases.

### 7. Metadata resilience

**File**: `release_meta.sh`.

Upstream aborts the whole metadata job when a single release's artefacts cannot be downloaded. This is reachable in normal operation: `release.sh` pushes the git tag *before* the upload step, so a failed upload leaves a **draft** release; `list_github_releases` queries `/releases` with `GH_TOKEN`, which **includes drafts**, so `list-bakery` reports the version — but `/releases/tags/<tag>` **404s for drafts**, `SHA256SUMS` is never written, and `cat SHA256SUMS` kills the job under `set -euo pipefail`. Once that happens it recurs on every subsequent run until the draft is deleted by hand.

The patch:
- `fetch_artefacts()` returns non-zero on a failed asset download instead of exiting.
- Both callers clear `SHA256SUMS` per iteration and `continue` past an unfetchable release with a `SKIPPED` line. The per-iteration clear also fixes a latent bug where a mid-loop failure caused the *previous* version's sums to be appended twice.
- `mv SHA256SUMS.all SHA256SUMS` is guarded for the all-skipped case.

### 8. CI resilience

**File**: `.github/workflows/release.yaml`. Three changes:

- `fail-fast: false` on the `create-release` matrix.
- `fail-fast: false` **and** `continue-on-error: true` on the `update-extension-metadata` matrix. Without the former, one failing extension cancels its siblings; without the latter, `update-global-metadata` (which `needs` it) is skipped and the global `SHA256SUMS` never publishes. This exactly matches upstream's own stated rationale for `create-release`.
- `update-global-metadata` gains `list-builds` in its `needs` array. Its `if:` reads `needs.list-builds.outputs.extensions`, but `list-builds` was not in `needs`, so the expression evaluated to null, `!= ''` was false, and **the job was skipped on every run**. This is not a qopsc regression — it is skipped on every upstream run too, and upstream's own global `SHA256SUMS` release has not been republished since 2025-03-20.

---

## Upstream Sync Procedure

The patch stack is rebased onto upstream; history on `origin/main` is linear upstream history + the fork commits.

```bash
git fetch flatcar
git rebase flatcar/main main
# resolve conflicts per the rules above (fork patches win only within their stated scope)
git push --force-with-lease origin main
```

After every sync, verify the divergence is exactly the expected files:

```bash
git diff flatcar/main main --stat
```

Expected, and nothing else:

```
.env  .gitignore  AGENTS.md  CLAUDE.md
.github/workflows/release.yaml
docker.sysext/create.sh
lib/generate.sh
release_build_versions.txt
release_meta.sh
# plus, while the netbird divergence lasts:
README.md  docs/index.md  docs/netbird.md  netbird.sysext/**
```

And sanity-check the scripts:

```bash
bash -n docker.sysext/create.sh lib/generate.sh release_meta.sh release_dispatcher.sh
./bakery.sh list docker | head
```

---

## Release Verification

After a release workflow run on qopsc, spot-check a docker asset:

- contains **no** `usr/bin/containerd` / `usr/bin/runc` / `usr/bin/ctr` / `usr/bin/containerd-shim-runc-v2`;
- contains `usr/bin/docker` and `usr/bin/dockerd`, and **no** `usr/share/containerd/`;
- `file docker-*.raw` reports EROFS;
- its `docker.conf` sysupdate `Path` points at `extensions.quantumops.consulting`.

Also confirm the pipeline itself is healthy — these were all broken before 2026-07-28:

```bash
gh run list --repo qopsc/sysext-bakery --workflow release.yaml --limit 1
gh release view docker-<version> --repo qopsc/sysext-bakery   # must have x86-64 + arm64 .raw
gh api repos/qopsc/sysext-bakery/releases/tags/SHA256SUMS     # must return 200
gh release list --repo qopsc/sysext-bakery | grep -i -- draft # must be empty
```

A leftover **draft** release is a red flag: it means an upload failed, and it will keep the metadata job skipping that version until deleted (`gh release delete <tag> --cleanup-tag`).

---

## Known Issues

- **`extensions.quantumops.consulting` does not resolve.** The `quantumops.consulting` zone exists (ClouDNS), but the `extensions` subdomain has no record. `lib/sysupdate.conf.tmpl` bakes `https://{BAKERY_HUB}/extensions/…` into the `.conf` inside every released image, so images published today ship an unusable sysupdate source. Builds and releases are unaffected; **node-side sysupdate is not usable until the hub is stood up**. Legacy `sysext.darkspadez.me` still resolves (152.53.243.195). Do not "fix" this by editing `.env` — see patch 4.
