# Namespace migration — spike findings and plan (fork patch #23, proposed)

Status: **SPIKE COMPLETE** — decisions grilled and locked 2026-10-16; live
probe green on both arches (runs 38888125159, 38888336108, 38888465328).
Throwaway probe: branch `spike/namespace-runner-test`, PR #22 (do not merge).
Ready for Phase 1 (pilot) on approval.

## Locked decisions (from grilling)

1. All four workflows move to Namespace runners.
2. Native per-arch builds (amd64 + arm64 jobs), no QEMU; a third publish job joins both.
3. GitHub keeps the code; **artifacts leave GitHub**. Namespace artifact store is the
   source of truth (replaces `github_release_exists`, `release_meta.sh` GitHub API use).
4. Store layout mirrors GitHub Releases 1:1 (`<ext>-<version>/` with both `.raw`,
   `.conf`, `SHA256SUMS`, build logs; per-extension + global `SHA256SUMS`), no expiry.
5. GH releases **and their git tags** are deleted on workflow success.
6. `4c-8g` profiles everywhere (`linux-amd64-4c-8g-u24`, `linux-arm64-4c-8g-u24`);
   upsize individual extensions only on proven OOM/disk failure.
7. Full Namespace feature set in scope, staged: runners → artifacts → caching.
8. Pilot: one small extension (`dust` or `eza`) via `rebuild.yaml` before
   `release.yaml` depends on any of this.
9. Registered as permanent fork patch #23 (AGENTS.md/CLAUDE.md, docs, hub) in one change.

## RESOLVED BLOCKER — GitHub Actions was disabled for this repository

Every trigger type was tested on 2026-10-16 (push, PR, dispatch, trivial
`ubuntu-24.04` echo workflow): **no run is ever created**, and dispatch returns
`HTTP 422: Actions has been disabled for this repository`. Repo- and org-level
API permissions both report enabled/all-allowed (token has `admin:org`), yet
the public Actions page states the real cause verbatim: *"Workflows are not
currently being run on this fork due to the scale of GitHub Actions usage. A
repository maintainer can choose to re-enable these."* GitHub auto-disabled
this fork's workflows (~2026-10-14, when scheduled runs stop); the flag is
only clearable by a signed-in maintainer clicking re-enable on the repo
Actions page — the REST API cannot clear it (PUT permissions/enable all
succeed and change nothing).

Namespace runners are a *runner backend for GitHub Actions* — with Actions off,
no Namespace job can ever start. Re-enabled by a maintainer 2026-10-16;
verified by a successful `report-missing-extension-docs` dispatch and the
green probe runs. Note the daily/weekly schedules were collateral of this
flag from ~Oct 14 until re-enablement.

## Spike findings (Namespace docs, 2026-10-16)

Sources: namespace.so/docs — artifact-storage, runner-configuration (label
grammar), upload/download-artifact references, `nsc artifact *` CLI references,
cache-volumes, federation/github-actions, billing-and-limits, pricing page.

### Runners

- Two selection mechanisms: **profiles** (`runs-on: namespace-profile-<name>`,
  name from the dashboard — so our labels are almost certainly
  `namespace-profile-linux-amd64-4c-8g-u24` / `...-arm64-...`) and the raw label
  grammar (`nscloud-ubuntu-24.04-amd64-4x8`). The probe workflow uses the profile
  form; if jobs queue forever, fall back to the `nscloud-` form. *Verify live.*
- Jobs on Namespace runners carry a short-lived workload-identity token: `nsc`
  artifact/CLI access needs **no secrets** in-workflow. From non-Namespace
  runners, OIDC federation (`id-token: write` + `namespacelabs/nscloud-setup`)
  does the same.
- Concurrency is plan-capped per platform (e.g. Team Linux: 64 vCPU/128 GB →
  sixteen concurrent 4c-8g jobs). The daily matrix (dozens of extensions × 2
  arches + joins) will queue against this cap; per-profile concurrency limits
  exist if list/metadata jobs must not starve builds. *Confirm plan tier.*

### Artifact store — the two tiers must not be conflated

| | Staging (intra-run) | Distribution (replaces GH Releases) |
|---|---|---|
| Tool | `namespace-actions/upload-artifact@v1` / `download-artifact@v2` | `nsc artifact upload/download/describe/expire` |
| Semantics | GitHub-artifact-compatible, per-run | Path-addressed objects in a workspace namespace (`main`) |
| Default expiry | **30 days** | **None** |
| Addressing | name within a run | path, e.g. `docker-v28.0.0/docker-v28.0.0-x86-64.raw` (`describe` example confirms path-style) |
| Existence check | n/a | `nsc artifact describe <path> -o json` → `Status: AVAILABLE` |

- `nsc artifact upload` is **single-file** (or `--pack` zip glob). Our layout is
  per-file uploads — fine, and it makes the 1:1 GH mirror literal.
- Versioning: re-upload to an existing path fails unless a new version is
  requested at the API level; CLI behaviour on re-upload of our rebuild path
  must be confirmed live (rebuild.yaml overwrites published versions by design).
- **Public access: there is none for artifacts.** Downloads resolve to
  **pre-signed URLs valid 30 minutes**, workspace/RBAC-scoped. Anonymous
  `systemd-sysupdate` cannot fetch from Namespace directly. (Contrast: the
  *container registry* has `nsc registry share` → `public.nscr.io`; artifact
  storage has no equivalent in the docs.)
- Therefore the hub design is forced: `extensions.quantumops.consulting` stops
  302-redirecting to GitHub and becomes an **authenticated minting proxy**:
  per request it resolves the artifact path (scoped revocable token,
  `nsc token create --grant '{"resource_type":"artifact","actions":["resolve","list",...]}'`,
  consumed via `NSC_TOKEN_FILE`) and 302s to a fresh pre-signed URL, or streams
  the object. Caddy alone cannot call the ResolveArtifact API — this means a
  small sidecar service next to Caddy in the existing compose deployment, or
  Caddy calling an API endpoint; to be prototyped on the hub host. Each
  sysupdate request (SHA256SUMS, each `.raw`) is minted independently, so the
  30-minute validity is not a problem *if* sysupdate follows 302s (it does for
  `url-file` transfers; *verify with a real node in the pilot*).
- Cost inversion vs GitHub: GH release egress is free; Namespace bills
  **artifact storage GB-month + artifact reads per GB**. Every node update
  fleet-wide becomes metered egress. Storage pricing seen: $0.20/GB-month
  (GitHub Artifacts line); read pricing to confirm on the workspace plan.
  Indefinite 1:1 retention of the whole back-catalogue is a recurring,
  growing line item, not a one-off.

### Caching ("full feature set", staged last)

- **Cache Volumes** (`-with-cache` profile/label option, `/cache`, tags shared
  per profile, last-write-wins generations, 20 GB min): candidate for the
  toolchain/Alpine package caches inside bakes. Our builds are `docker run`
  based (`lib/helpers.sh`), not `docker build`, so Remote Builders / BuildKit
  layer caching — Namespace's headline Docker feature — **mostly does not
  apply**; `docker/setup-qemu-action` disappears with native arches anyway.
- **`nsc artifact cache-url`**: pull-through cache that assumes the URL content
  is **immutable**. Correct for version-pinned upstream release tarballs (most
  `*.sysext/create.sh` downloads); must not be used for `latest`-style moving
  URLs without `--max_age`. Retrofitting every create.sh is the largest,
  least-valuable diff — stage it after the migration is proven, extension by
  extension, and only where download time actually shows in build logs.
- Transparent profile-level caching (container images, toolchains, checkout
  mirrors via `namespacelabs/nscloud-checkout-action`) is configuration on the
  two existing profiles, no workflow diff beyond optionally swapping
  `actions/checkout`. Note `nscloud-cache-action` has **no cache keys** —
  caches are shared across branches for a profile; branch-commit restrictions
  (`nscloud-cache-allow-commit-from-main`) should be set so PR/spike branches
  cannot poison main's cache.

### Live-probe answers (runs 38888125159 / 38888336108, 2026-10-16)

1. **`runs-on` confirmed**: `namespace-profile-linux-{amd64,arm64}-4c-8g-u24`
   schedule instantly; jobs complete in seconds (probe: ~5 s/job).
2. **Disk**: root overlay 63 GiB total / **55 GiB free**; a separate 100 GiB
   cache volume is mounted (`/cache`, `/gitmirror`, hosted tool/action
   caches). Largest bakes must fit source+image in ~55 GiB — plausible, but
   docker/ollama/coder are Phase 1/2 watch items.
3. **Shape truth**: 4 vCPU, **7.8 GiB RAM + 8 GiB swap** (GitHub was 16 GiB,
   no guaranteed swap). Caches were already enabled on both profiles
   (container, git-mirror, runner-tools, Actions cache, 100 GiB bundled).
4. **Docker works natively**: Docker 29.3.0 with a live daemon
   (`29.3.0-namespace`, overlayfs) on both arches — `lib/helpers.sh`
   `docker run` bakes need no buildx/qemu rework. No podman (unused by CI).
   `mkfs.erofs`/`mksquashfs` are NOT preinstalled; the existing
   `apt install` prerequisite step stays.
5. **`nsc` preinstalled** (`/nsc/bin/nsc` v0.0.576), workspace-authenticated
   with zero secrets. Full lifecycle verified: path upload
   (`spike/run-<id>/hello.txt`), `describe -o json` (note: status is
   `LIVE`, not the docs' `AVAILABLE`), download, expire, and
   `cache-url` (second call served from cache populated by a *different*
   run — cross-run sharing works).
6. **Re-upload to an existing path succeeds** (new version wins silently) —
   rebuild-overwrite semantics are free.
7. **Anonymous access disproved**: the `describe` `web_url`
   (`cloud.namespace.so/<ws>/artifacts/download/...`) returns the dashboard
   HTML login shell to unauthenticated clients. Nodes can never fetch
   artifacts directly; hub minting-proxy (above) is the only design.
8. Publish-join pattern verified end-to-end:
   `namespace-actions/upload-artifact@v1` per arch →
   `download-artifact@v2` (pattern+merge) → joined SHA256SUMS.

### Still open (Phase 1 / Namespace support)

1. Single-artifact size limit (must clear our largest `.raw`; kata excluded
   at 2.29 GiB, ollama/coder/docker need headroom proof — test by uploading
   the largest existing `.raw` early in Phase 1).
2. Pre-signed URL Range/redirect behaviour with a real systemd-sysupdate
   client (hub prototype, Phase 1 gate).
3. Artifact read (egress) unit price on the workspace's plan.

## Repo touchpoint inventory (what patch #23 must change)

- `.github/workflows/{release,rebuild,update-all-metadata,report-missing-extension-docs}.yaml`
  — every `runs-on: ubuntu-24.04` (12 sites) → profile labels; drop
  `docker/setup-qemu-action` from build jobs.
- `release.sh` — builds both arches in one job today (`for arch in x86-64 arm64`);
  split to one arch per invocation (matrix), keep tag/SHA256SUMS contract for
  the publish job to consume.
- Publish-join job (new, in `release.yaml`/`rebuild.yaml`): download both arch
  staging artifacts, join `SHA256SUMS`, generate `.conf` set + `Release.md`,
  `nsc artifact upload` the 1:1 layout, then (per decision 5) delete the GH
  release + tag if one exists. Replaces all 8 `softprops/action-gh-release`
  sites.
- `release_dispatcher.sh` + `lib/helpers.sh` — `github_release_exists` → an
  `nsc artifact describe`-based `bakery_artifact_exists`; `list-bakery`
  (GitHub releases listing) → artifact path listing.
- `release_meta.sh` — rewritten to aggregate `SHA256SUMS`/`.conf` from the
  artifact store instead of the GitHub API (patch 7's draft/skip resilience
  semantics carried over: skip missing artifacts, never fail the whole job).
- `tools/http-url-rewrite-server/` — Caddyfile `redir` rules → minting-proxy
  design (above); design doc + compose updated (patch 9 amended, not replaced).
- `docs/*.md` — ~10+ files link `github.com/qopsc/sysext-bakery/releases/...`;
  repoint to hub URLs. `lib/sysupdate.conf.tmpl` itself is unchanged (it
  already points at the hub) — **already-deployed nodes keep working iff the
  hub serves the same paths from Namespace.**
- `AGENTS.md`/`CLAUDE.md` — patch #23 row, expected-diff list
  (`.github/workflows/*`, the scripts above, hub, docs), new sanity checks
  (`nsc artifact describe` spot-check replacing the `gh release view` check).
- `.env` — unchanged. `bakery` still drives GitHub *code* operations; a new
  variable for artifact namespace/path prefix may be introduced in scripts,
  not `.env`, until the design settles.

## Plan (gated)

- **Phase 0 — unblock + live spike.** Re-enable Actions (org UI). Run PR #22's
  probe: confirm profile labels schedule on both arches, disk/RAM/docker/nsc
  facts, staging upload→join→download, `nsc artifact` lifecycle incl.
  re-upload and cache-url. Record answers to the 7 open questions above.
  *Gate: no Phase 1 until the probe is green on both arches.*
- **Phase 1 — pilot.** `rebuild.yaml` only: native split + publish-join for
  `dust`/`eza`, publishing to Namespace *and* GitHub (dual-publish despite
  decision 5, for exactly one pilot). Verify from a real node/box:
  sysupdate-style fetch of SHA256SUMS + `.raw` through the hub prototype.
  *Gate: byte-identical `.raw` vs the GH-published build (`sha256sum`).*
- **Phase 2 — distribution cutover.** `release.sh` split, dispatcher/meta
  rewrites, hub minting proxy deployed (needs the hub DNS record — known
  issue), docs repointed. New builds Namespace-only; on success delete the
  corresponding GH release + tag (decision 5/7).
- **Phase 3 — all workflows + back-catalogue.** Remaining workflows move;
  back-catalogue objects copied GH→Namespace (scripted `gh release download`
  → `nsc artifact upload`), verified against published SHA256SUMS, then GH
  releases + tags deleted in bulk.
- **Phase 4 — caching.** Profile cache options on; `cache-url` retrofits only
  where build logs prove download pain; cache-commit restricted to `main`.
- **Phase 5 — bookkeeping.** Patch #23 registered, expected-diff + release
  verification sections rewritten, spike branch/PR deleted.

## Risks recorded against the locked decisions

- Deletion-on-success (decision 5) before hub fetch is proven can orphan
  nodes; Phase 1's dual-publish is the deliberate exception that de-risks it.
- Fleet egress becomes metered (artifact reads). If the per-GB read price is
  material at fleet scale, the hub may need to cache `.raw` objects on its own
  disk instead of redirecting every node to Namespace — decide with Phase 0
  pricing answers.
- Halved RAM (16 GB → 8 GB) may OOM docker/ollama/coder bakes; Phase 1/2 must
  watch for it and invoke the per-extension upsize escape hatch (decision 6).
