# AI Agent Fork Maintenance Guide

## Purpose

Instructions for AI agents (Claude, Copilot, Cursor, Aider, etc.) working on this repository. This is a **fork** of `flatcar/sysext-bakery` carrying a small, deliberate patch stack that must be preserved across upstream syncs.

---

## Repository Context

- **Fork**: `qopsc/sysext-bakery` (git remote: `origin`)
- **Upstream**: `flatcar/sysext-bakery` (git remote: `flatcar`)
- **Fork hub**: `extensions.quantumops.consulting` — **not yet stood up**, see Known Issues.
- **Legacy fork** (retired): `darkspadez/sysext-bakery` / `sysext.darkspadez.me` — kept only until nodes deployed from it are re-provisioned.

The fork's divergence from `flatcar/main` is **nineteen permanent patches** plus any temporary divergences listed below. Anything not covered by either list is drift — investigate and remove it.

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
| 9 | qopsc hub deployment | `tools/http-url-rewrite-server/**` | policy |
| 10 | sqlite extension | `sqlite.sysext/**`, `docs/sqlite.md`, `docs/index.md`, `release_build_versions.txt` sqlite lines | policy |
| 11 | btop rebuilt from source for GPU support | `btop.sysext/**`, `docs/btop.md`, `docs/index.md` btop row | policy |
| 12 | nvidia-runtime official debs | `nvidia-runtime.sysext/create.sh`, `nvidia-runtime.sysext/extract.sh` | upstream bugfix |
| 13 | arcane extension | `arcane.sysext/**`, `docs/arcane.md`, `docs/index.md` arcane row, `release_build_versions.txt` arcane lines | policy |
| 14 | dust extension | `dust.sysext/**`, `docs/dust.md`, `docs/index.md` dust row, `release_build_versions.txt` dust lines | policy |
| 15 | iperf3 extension | `iperf3.sysext/**`, `docs/iperf3.md`, `docs/index.md` iperf3 row, `release_build_versions.txt` iperf3 lines | policy |
| 16 | neovim extension | `neovim.sysext/**`, `docs/neovim.md`, `docs/index.md` neovim row, `release_build_versions.txt` neovim lines | policy |
| 17 | eza extension | `eza.sysext/**`, `docs/eza.md`, `docs/index.md` eza row, `release_build_versions.txt` eza lines | policy |
| 18 | Rebuild published releases | `.github/workflows/rebuild.yaml`, `rebuild_dispatcher.sh` | policy |
| 19 | List-builds listing resilience | `lib/helpers.sh`, `release_dispatcher.sh`, `bird.sysext/create.sh` | upstream bugfix |

Patches marked **upstream bugfix** (2, 7, 8, 12, 19) fix defects that also exist in `flatcar/main`. They are carried fork-locally by choice. If they are ever upstreamed, drop them here on the next rebase and move them to the temporary-divergence list in the meantime.

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

This fork builds a **subset** of upstream's extensions. Every other line tracks upstream verbatim **except** the two `sqlite` entries (patch 10), the two `arcane` entries (patch 13), the two `dust` entries (patch 14), the two `iperf3` entries (patch 15), the two `neovim` entries (patch 16), and the two `eza` entries (patch 17), which are fork-added; take upstream's version in any conflict, then re-apply the kata-containers comment, the sqlite lines, the arcane lines, the dust lines, the iperf3 lines, the neovim lines, and the eza lines.

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

### 9. qopsc hub deployment

**Files**: `tools/http-url-rewrite-server/` — `Caddyfile` (modified), plus `docker-compose.yml`, `install.sh`, `README.md` and the design/plan docs (added).

Upstream ships this directory configured for `extensions.flatcar.org` with a Flatcar/Ignition systemd unit as its only run definition. This fork repoints the `Caddyfile` at `extensions.quantumops.consulting` and `github.com/qopsc/sysext-bakery`, and adds a compose deployment for a non-Flatcar (Fedora) host.

**Rules**:
- Values are hardcoded by choice, not read from `.env`. Do not "improve" this into `{$bakery_hub}` placeholders without deciding to; the deployment host does not have the repo checked out.
- The three endpoints in the `Caddyfile` are the hostname, `base_dest_url`, and the final catch-all. The five `path_regexp` matchers track upstream verbatim — take upstream's version in any conflict, then re-apply the three endpoints.
- `caddy.service` and `extensions.flatcar.org.yaml` are deliberately **left on upstream's values**. They are the Flatcar deployment path and this fork does not use them.
- Certificates live in the deployment host's `./data` bind mount, not in this repo.

See `tools/http-url-rewrite-server/2026-08-05-qopsc-hub-caddy-compose-design.md` for the decisions and their rationale.

### 10. sqlite extension

**Files**: `sqlite.sysext/` (create.sh, test.sh, design and plan docs), `docs/sqlite.md`, the `sqlite` row in `docs/index.md`, and the two `sqlite` lines in `release_build_versions.txt`.

A fork-local extension shipping `sqlite3` and `sqldiff`. It does not exist upstream, so there is no upstream version to reconcile against — in any conflict take upstream's file and re-add the sqlite parts.

**Rules**:
- Ships exactly two binaries. Adding `sqlite3_rsync`, `sqlite3_analyzer` or the `show*` tools is a scope decision, not a fix; see the design doc.
- The version-discovery regex anchors on the href quotes (`'"sqlite-3[^"]*\.apk"'`). Do not "simplify" it to `btop`'s unanchored idiom: an unanchored match fires inside other packages' filenames (`lua5.4-sqlite-…`) and reports their versions as sqlite's.
- The build asserts the installed version matches the requested one. `btop` and `tilde` lack this check and can silently publish mislabelled images; do not remove it to make a pinned build pass. When Alpine moves past a pinned version, bump or drop the pinned line instead.
- `docs/index.md` and `docs/sqlite.md` link the **qopsc** release tag, not flatcar's. There is no flatcar release for this extension.

See `sqlite.sysext/2026-08-05-sqlite-sysext-design.md` for the decisions and their rationale.

### 12. nvidia-runtime official debs

**Files**: `nvidia-runtime.sysext/create.sh`, `nvidia-runtime.sysext/extract.sh` (and the removed v1.18.1 source-build patches).

Upstream compiles `nvidia-container-toolkit` from source via `./scripts/build-packages.sh ubuntu18.04-${arch}` and then `cp -aR out/etc/systemd/.` into the sysext. That broke on toolkit **v1.20.0** (the current `latest`): NVIDIA PR [#1827](https://github.com/NVIDIA/nvidia-container-toolkit/pull/1827) moved `nvidia-cdi-refresh.{service,path}` from `/etc/systemd` to `/lib/systemd`, so the copy fails under `set -e` and the GitHub Actions `create-release (nvidia-runtime:v1.20.0)` job dies. The same failure is on `flatcar/sysext-bakery`.

NVIDIA has shipped the ubuntu18.04 debs as GitHub release assets since at least v1.16.2 (`nvidia-container-toolkit_${ver}_deb_{amd64,arm64}.tar.gz`). This patch consumes those packages instead of compiling, and copies systemd units from either `/etc/systemd` (v1.19.x and earlier) or `/lib/systemd` (v1.20.0+).

**Rules**:
- Do not restore the v1.18.1 `git am` patches or the `ubuntu18.04` source-build path. Those existed only because `storage.googleapis.com/golang` and a stale `libnvidia-container` submodule broke the compile; official debs do not need them.
- Keep extracting the ubuntu18.04 debs from the tarball (glibc 2.27) even if NVIDIA later also ships ubuntu20.04/22.04 trees. Flatcar LTS still needs the older glibc.
- Copy units from **both** `out/etc/systemd` and `out/lib/systemd` when present. A v1.19.1 rebuild must keep working.
- Do not soften the checksum check. The checksums file prefixes paths with `release-vX.Y.Z-stable/`; match on the basename.

### 13. arcane extension

**Files**: `arcane.sysext/` (create.sh, systemd units, tmpfiles), `docs/arcane.md`, the `arcane` row in `docs/index.md`, and the two `arcane` lines in `release_build_versions.txt`.

A fork-local extension shipping `arcane-agent` and `arcane-cli` from [getarcaneapp/arcane](https://github.com/getarcaneapp/arcane) GitHub release assets. It does not exist upstream — in any conflict take upstream's file and re-add the arcane parts.

**Rules**:
- Ships exactly two binaries: `arcane-agent` and `arcane-cli`. The upstream `arcane` manager binary is intentionally omitted; run the manager via the published container image or add it only with an explicit scope decision.
- Verify downloads against `arcane_<version>_checksums.txt` (basename match, like nvidia-runtime patch 12).
- The build asserts the installed `arcane-agent` version matches the requested one on the **native** architecture; do not remove that check to make a pinned build pass. Skip the runtime check on a foreign arch (qemu-user has no guest dynamic linker).
- `docs/index.md` and `docs/arcane.md` link the **qopsc** release tag and `extensions.quantumops.consulting` hub URLs, not flatcar's. There is no flatcar release for this extension.
- The bundled `arcane-agent.service` sets `PROJECTS_DIRECTORY`, `TEMPLATES_DIRECTORY`, and `DATABASE_URL` for a native (non-container) layout under `/var/lib/arcane-agent`; do not revert these to upstream container `/app` defaults.

### 14. dust extension

**Files**: `dust.sysext/` (create.sh), `docs/dust.md`, the `dust` row in `docs/index.md`, and the two `dust` lines in `release_build_versions.txt`.

A fork-local extension shipping the `dust` binary from [bootandy/dust](https://github.com/bootandy/dust) GitHub release assets. It does not exist upstream — in any conflict take upstream's file and re-add the dust parts.

**Rules**:
- Ships exactly one binary: `dust` at `/usr/bin/dust`.
- Upstream releases do not publish checksum files; do not add a checksum step unless upstream starts shipping one.
- The build asserts the installed version matches the requested one on the **native** architecture; do not remove that check to make a pinned build pass. Skip the runtime check on a foreign arch — `dust` is a dynamically-linked gnu binary, and qemu-user on the x86-64 builder has no `/lib/ld-linux-aarch64.so.1`.
- `docs/index.md` and `docs/dust.md` link the **qopsc** release tag, not flatcar's. There is no flatcar release for this extension.

### 15. iperf3 extension

**Files**: `iperf3.sysext/` (create.sh, build.sh), `docs/iperf3.md`, the `iperf3` row in `docs/index.md`, and the two `iperf3` lines in `release_build_versions.txt`.

A fork-local extension shipping the `iperf3` binary built from [esnet/iperf](https://github.com/esnet/iperf) GitHub release source tarballs. It does not exist upstream — in any conflict take upstream's file and re-add the iperf3 parts.

**Rules**:
- Ships exactly one binary: `iperf3` at `/usr/bin/iperf3`.
- Upstream publishes source tarballs, not prebuilt binaries; build inside Alpine with `build.sh` and bundle runtime libraries with `flix.sh`.
- `flix.sh` must be invoked with `FOLDER=/` after `make install` (not `DESTDIR=/staging`). The musl loader lives in the Alpine root, not in a DESTDIR tree; `FOLDER=/staging` fails with `cp: cannot stat '/staging/lib/ld-musl-*.so.1'`. Same pattern as sqlite.
- Verify downloads against `iperf-<version>.tar.gz.sha256` (basename match, like nvidia-runtime patch 12).
- Filter `list_available_versions` to numeric tags only; esnet/iperf publishes beta tags that are not marked GitHub prereleases.
- The build asserts the installed version matches the requested one; do not remove that check to make a pinned build pass. Run that check on `/usr/bin/iperf3` after `make install` and **before** `flix.sh`. The flixed binary's interpreter is `/usr/local/iperf3/ld-musl-*.so.1`, which is not on the container root, so executing it reports `not found`. Parse only the first line of `--version` (`awk 'NR==1 {print $2; exit}'`); later lines are the hostname and a features list, and taking `$2` from every line fails the equality check.
- `docs/index.md` and `docs/iperf3.md` link the **qopsc** release tag, not flatcar's. There is no flatcar release for this extension.

### 16. neovim extension

**Files**: `neovim.sysext/` (create.sh, test.sh), `docs/neovim.md`, the `neovim` row in `docs/index.md`, and the two `neovim` lines in `release_build_versions.txt`.

A fork-local extension shipping Neovim from the official Linux release tarballs, with `vim` and `vi` symlinks to `nvim`. It does not exist upstream — in any conflict take upstream's file and re-add the neovim parts.

**Rules**:
- Source the official `nvim-linux-{x86_64,arm64}.tar.gz` assets only (v0.11.0+). Do not use AppImage or `flix.sh`.
- Ship `/usr/bin/nvim` plus `vim` and `vi` symlinks. Runtime files live under `/usr/share/nvim`, parsers under `/usr/lib/nvim`.
- Verify tarball integrity via the GitHub release asset `digest` field. Assert the glibc symbol-version floor matches btop.
- The headless smoke test (`vim --headless '+qa'`) runs only on the native architecture. qemu-user on the x86-64 builder has no `/lib/ld-linux-aarch64.so.1`. Do not drop the digest or glibc-floor checks.
- `docs/index.md` and `docs/neovim.md` link the **qopsc** release tag, not flatcar's.

### 17. eza extension

**Files**: `eza.sysext/` (create.sh), `docs/eza.md`, the `eza` row in `docs/index.md`, and the two `eza` lines in `release_build_versions.txt`.

A fork-local extension shipping the `eza` binary from [eza-community/eza](https://github.com/eza-community/eza) GitHub release assets. It does not exist upstream — in any conflict take upstream's file and re-add the eza parts.

**Rules**:
- Ships exactly one binary: `eza` at `/usr/bin/eza`.
- Upstream releases do not publish checksum files; do not add a checksum step unless upstream starts shipping one.
- The build asserts the installed version matches the requested one on the **native** architecture; do not remove that check to make a pinned build pass. Skip the runtime check on a foreign arch — same qemu-user `/lib/ld-linux-aarch64.so.1` gap as dust.
- `docs/index.md` and `docs/eza.md` link the **qopsc** release tag, not flatcar's. There is no flatcar release for this extension.

### 18. Rebuild published releases

**Files**: `.github/workflows/rebuild.yaml`, `rebuild_dispatcher.sh`.

The daily `release.yaml` only builds versions that have **no** GitHub release yet (`github_release_exists`). After a bake-script or bundled-unit change, an already-published version (e.g. `arcane-v2.9.0`) would stay stale forever without a way to remake it.

**Rules**:
- `workflow_dispatch` only. Inputs are `extension` + `version` (or a comma-separated `releases` list of `extension:version`), plus optional `branch` (default `main`).
- `version` / a list entry may be `latest`; `rebuild_dispatcher.sh` resolves that the same way `release_dispatcher.sh` does.
- Reject any version that `./bakery.sh list <extension>` does not return, including a resolved `latest`. An unknown version must not reach `gh release delete`.
- Build both architectures first. Delete the existing GitHub **release** only after the build succeeds, immediately before upload (`gh release delete`). Do **not** pass `--cleanup-tag`; `release.sh` force-updates the git tag to the new build.
- After the rebuild, refresh that extension's metadata release and the global `SHA256SUMS`.
- Validate extension names against `*.sysext/` before building. Do not interpolate workflow inputs or `matrix.*` values into bash source — pass them as env vars (`RELEASE_SPEC`, `EXTENSION`).

### 19. List-builds listing resilience

**Files**: `lib/helpers.sh` (`list_latest_release`, `list_gitlab_tags`), `release_dispatcher.sh`, `bird.sysext/create.sh`.

`list-builds` in run 33328132566 succeeded but logged three listing defects that also exist upstream:

- `neovim.sysext/create.sh: echo: write error: Broken pipe` and `jq: error: writing output failed: Broken pipe` (vault) — `list_latest_release` piped to `head -n 1`, which closes the pipe after the first version.
- `curl: (22) The requested URL returned error: 403` while resolving `bird latest` — `gitlab.nic.cz` throttles unauthenticated GitHub Actions IPs. Process substitution hid `bakery.sh`'s non-zero exit, so bird latest was silently skipped.

**Rules**:
- `list_latest_release` must consume the full version list (e.g. `mapfile`) and print the first line. Do not restore `... | head -n 1`.
- `list_gitlab_tags` takes an optional third argument: a git clone URL. On API failure it falls back to `git ls-remote --tags --refs`. Bird must keep passing `https://gitlab.nic.cz/labs/bird.git`.
- `release_dispatcher.sh` must capture `./bakery.sh list … --latest true` so a failed listing prints `ERROR listing upstream versions; skipping` instead of dropping the line. Do not fail the whole dispatcher for one extension (same continue-on-error stance as patch 8).

---

## Rebuilding a published version

The scheduled release workflow only creates versions that are missing from GitHub. To remake an existing version after a patch (for example the arcane-agent unit env defaults):

1. Actions → **Rebuild a published sysext release** → Run workflow.
2. Set `extension` to `arcane` and `version` to `v2.9.0` (or `releases` to `arcane:v2.9.0,dust:v1.2.5` for a batch).
3. Leave `branch` as `main` unless you are testing a feature branch.

That rebuilds both architectures, then replaces the existing GitHub release and refreshes metadata. The old release stays published if the build fails.

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
.github/workflows/rebuild.yaml
rebuild_dispatcher.sh
docker.sysext/create.sh
lib/generate.sh
lib/helpers.sh
release_dispatcher.sh
bird.sysext/create.sh
release_build_versions.txt
release_meta.sh
tools/http-url-rewrite-server/**
docs/index.md  docs/sqlite.md  sqlite.sysext/**
docs/arcane.md  arcane.sysext/**
docs/dust.md  dust.sysext/**
docs/eza.md  eza.sysext/**
docs/iperf3.md  iperf3.sysext/**
docs/btop.md  btop.sysext/**
docs/neovim.md  neovim.sysext/**
nvidia-runtime.sysext/**
# plus, while the netbird divergence lasts:
README.md  docs/netbird.md  netbird.sysext/**
```

And sanity-check the scripts:

```bash
bash -n docker.sysext/create.sh lib/generate.sh lib/helpers.sh release_meta.sh release_dispatcher.sh rebuild_dispatcher.sh nvidia-runtime.sysext/create.sh arcane.sysext/create.sh dust.sysext/create.sh eza.sysext/create.sh iperf3.sysext/create.sh iperf3.sysext/build.sh neovim.sysext/create.sh bird.sysext/create.sh
./bakery.sh list docker | head
./bakery.sh list nvidia-runtime | head
./bakery.sh list arcane | head
./bakery.sh list dust | head
./bakery.sh list eza | head
./bakery.sh list iperf3 | head
./bakery.sh list neovim | head
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

  The hub's serving config now exists and is deployable — see patch 9 and `tools/http-url-rewrite-server/README.md`. The remaining work is external to this repo: create the A record pointing at the host, then run the installer. Until then Caddy starts but Let's Encrypt cannot issue a certificate.
