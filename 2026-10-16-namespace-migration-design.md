# Namespace migration — spike findings and plan (fork patch #23, proposed)

Status: **SPIKE COMPLETE, PLAN AMENDED** — spike green on both arches (runs
38888125159, 38888336108, 38888465328); throwaway probe on branch
`spike/namespace-runner-test`, PR #22 (do not merge). Decision amended
2026-10-16 after the quota investigation: **GitHub Releases stay** (see
decision 3). Ready for Phase 1 (pilot) on approval.

## Locked decisions (from grilling, as amended)

1. All four workflows move to Namespace runners.
2. Native per-arch builds (amd64 + arm64 jobs), no QEMU; a third publish job joins both.
3. **Split by meter, not by logo.** Everything GitHub *meters* leaves GitHub:
   runner minutes, Actions artifacts (intra-run staging via
   `namespace-actions/*`), and OCI images (`nscr.io`, if/when any) move to
   Namespace. Everything GitHub gives this public repo *free and unmetered*
   stays: the code, and **GitHub Releases as the public `.raw` distribution**
   (free storage/egress, anonymous node downloads, unaffected by Actions
   disablement). Source of truth stays GitHub Releases:
   `github_release_exists`, `release_meta.sh`, the hub's Caddy redirects,
   dispatcher, docs links and `sysupdate.conf.tmpl` are all **unchanged**.
   *(Supersedes the original decisions 3–5: no Namespace distribution store,
   no 1:1 mirror, no deletion of releases or git tags — the 2000/2000 quota
   fire never involved Releases, so moving them bought only risk: hub
   signed-URL minting, metered fleet egress, a 110 GiB transfer.)*
4. `4c-8g` profiles everywhere (`linux-amd64-4c-8g-u24`, `linux-arm64-4c-8g-u24`);
   upsize individual extensions only on proven OOM/disk failure.
5. Full Namespace feature set in scope, staged: runners → staging artifacts → caching.
6. Pilot: one small extension (`dust` or `eza`) via `rebuild.yaml` before
   `release.yaml` depends on any of this.
7. Registered as permanent fork patch #23 (AGENTS.md/CLAUDE.md) in one change;
   scope is now mostly workflow files + the `release.sh` arch split.

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

### Artifact store — only the staging tier is used (as amended)

| | Staging (intra-run) — **used** | Distribution — **not used** |
|---|---|---|
| Tool | `namespace-actions/upload-artifact@v1` / `download-artifact@v2` | `nsc artifact upload/download/describe/expire` |
| Semantics | GitHub-artifact-compatible, per-run | Path-addressed objects in a workspace namespace (`main`) |
| Default expiry | **30 days** (set `retention-days: 1` for build staging) | None |
| Addressing | name within a run | path, e.g. `docker-v28.0.0/docker-v28.0.0-x86-64.raw` |

- The probe also verified the distribution tier end-to-end (path upload,
  `describe`, download, expire, silent-overwrite re-upload, `cache-url`),
  so the shelved full-exit design remains executable if ever wanted.
- **Why distribution stays on GitHub**: artifacts have **no public access**
  (pre-signed 30-min URLs, workspace-scoped only; the probe's anonymous
  fetch returned the dashboard login shell). Moving `.raw` would have
  forced the hub to become an authenticated URL-minting proxy and made
  every node download metered Namespace egress — cost and complexity to
  escape a quota that never applied to Releases. GH Releases stay the
  origin; the hub keeps 302-redirecting to GitHub exactly as designed in
  patch 9; no hub token, no sidecar, no back-catalogue transfer (321
  releases / 110.8 GiB stay put, free).

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
   HTML login shell to unauthenticated clients. (Key input to the amended
   decision 3: distribution stays on GitHub Releases.)
8. Publish-join pattern verified end-to-end:
   `namespace-actions/upload-artifact@v1` per arch →
   `download-artifact@v2` (pattern+merge) → joined SHA256SUMS.

### Still open

1. Largest-bake resource fit on 55 GiB disk / 7.8 GiB RAM (docker, ollama,
   coder) — answered by real builds in Phases 1–2, per-extension upsize is
   the escape hatch (decision 4).
2. Whether staging artifacts need `compression-level: 0` tuning for
   multi-hundred-MB `.raw` files (probe used 1 MiB payloads; the pilot
   measures real upload/download timings on a real image).

## Repo touchpoint inventory (what patch #23 must change)

- `.github/workflows/{release,rebuild,update-all-metadata,report-missing-extension-docs}.yaml`
  — every `runs-on: ubuntu-24.04` (12 sites) → profile labels; drop
  `docker/setup-qemu-action` from build jobs.
- `release.sh` — builds both arches in one job today (`for arch in x86-64 arm64`);
  split to one arch per invocation (per-arch matrix leg writes a partial
  `SHA256SUMS.<arch>` + build log), and move the git tag push out of the
  per-arch path so only the publish job tags, once, after the join.
- Publish-join job (new, in `release.yaml`/`rebuild.yaml`): runs on the
  amd64 Namespace profile; downloads both arch staging artifacts
  (`namespace-actions/download-artifact@v2`), joins `SHA256SUMS`, assembles
  `.conf` set + `Release.md`, pushes the git tag, and creates the GitHub
  release. Absorbs the 8 `softprops/action-gh-release` sites (metadata
  jobs keep theirs — they only run `release_meta.sh`, which is unchanged).
  For `rebuild.yaml`, its existing delete-release-after-build step stays,
  now in the publish job immediately before re-creating the release.
- **Unchanged by design**: `release_dispatcher.sh`, `release_meta.sh`,
  `lib/helpers.sh` (`github_release_exists`, `list-bakery`),
  `lib/sysupdate.conf.tmpl`, `.env`, `tools/http-url-rewrite-server/**`
  (hub still redirects to GitHub Releases), `docs/**` release links.
- `AGENTS.md`/`CLAUDE.md` — patch #23 row (workflows + `release.sh` split),
  expected-diff list narrowed to `.github/workflows/*` + `release.sh`,
  sanity checks extended with a Namespace run spot-check; Release
  Verification section unchanged (assets still land on GitHub).

## Plan (gated)

- **Phase 0 — unblock + live spike. ✅ DONE** (fork auto-disable re-enabled;
  probe green on both arches; findings above).
- **Phase 1 — pilot. ✅ DONE** (run 39071157202, branch
  `namespace/pilot-rebuild`). `rebuild.yaml` native split + publish-join
  rebuilt `dust:v1.2.6` end-to-end: list 10s, builds 9s (x86-64) / 18s
  (arm64, includes apt), publish 14s, both metadata jobs green; ~90s
  total vs 3m30s for the old QEMU flow. **Gate passed**: release asset
  list and sizes identical to the pre-pilot release, `.conf` identical,
  and `SHA256SUMS` **byte-identical** — EROFS images are reproducible
  (zero UUID), so `sha256sum -c` verifies against the sums published
  before the rebuild. Delete-then-recreate worked from the publish job;
  per-extension and global metadata releases updated. `release.sh`
  gained `--arch`/`--join` modes; the legacy no-arg path is untouched,
  so `release.yaml` keeps working until Phase 2.
- **Phase 2 — all workflows. ✅ DONE** (branch `namespace/pilot-rebuild`).
  `release.yaml` split/join ran the real backlog (run 39071604340):
  9 releases × 2 arches, **18/18 build legs, 9/9 publishes, 10/10
  metadata jobs green, zero drafts**. docker 29.9.1 legs: 0.3/0.6 min;
  ollama 3.5/6.3 min; slowest leg scx arm64 at 38.9 min (x86-64 11.8) —
  native arm compilation, no OOM/disk failure anywhere, so no per-
  extension upsizes. docker `.raw` sha256-verified post-download.
  `update-all-metadata` (run 39074968695, 45 jobs) and
  `report-missing-extension-docs` (run 39074970633) green on Namespace
  labels. Known cosmetic regression: publish legs wait for the whole
  build matrix, so the slowest leg (scx) delays every release in the
  run (old flow published per-release as each finished). Metadata jobs
  waited for the whole matrix before too; if time-to-first-release ever
  matters, restructure as a reusable per-release workflow — not needed
  for a daily cadence.
- **Phase 3 — caching.** Profile cache options already on; optional
  `namespacelabs/nscloud-checkout-action` swap; `cache-url` retrofits only
  where build logs prove download pain (pinned URLs only); cache-commit
  restricted to `main` so feature branches cannot poison main's cache.
- **Phase 4 — bookkeeping.** Patch #23 registered in AGENTS.md/CLAUDE.md,
  expected-diff + sanity checks updated, spike branch/PR deleted.

## Budget check (2026-10-16)

- GitHub org `qopsc` Actions budget: **$5/mo, `prevent_further_usage: true`**
  (alerts: darkspadez, qopsc-admin). This budget does **not** fund Namespace:
  Namespace compute is billed by Namespace (unit minutes), never via GitHub.
- GitHub-side cost today is **net $0**: public repos are fully discounted.
  sysext-bakery used 1,888 GH Linux minutes in Aug 2026 (gross $11.33, net
  $0) and 869 in Oct (until the fork auto-disable). The $5 hard stop only
  bites if the org ever incurs *net* Actions charges (private-repo minutes,
  paid storage) — then it would disable Actions org-wide mid-migration.
  Raising it (e.g. $50, alerts on, hard stop off or higher) is safer.
- Estimated Namespace compute: ~2,000–3,500 runner wall-min/month across all
  workflows × 4 unit-min (4 vCPU/8 GiB shape) ≈ **10–15k unit minutes/mo**
  (≈$15–22 pay-as-you-go at $0.0015/unit-min; Team includes 100k for $100).
  Native arm64 removes QEMU overhead, so this should fall, not rise.
- Back-catalogue (context only, no longer moving): 321 GH releases,
  **110.8 GiB** of assets — stays on GitHub, free and unmetered.
- The 2000/2000 error was the org's **GitHub Free plan included minutes**
  (2,000/mo, consumed by *private* repos; qopsc plan = `free`). Public-repo
  minutes are fully discounted (net $0) but private repos (confetti,
  oarlock, interchange) drew ~594 min in Oct alone. With a
  `prevent_further_usage` budget, exhaustion blocks workflow execution —
  the failure that motivated this migration. Namespace-runner jobs bill
  **zero** GitHub minutes (self-hosted class), so after this migration
  sysext-bakery consumes no GitHub minutes, artifacts storage, or Packages
  storage at all. It never used GHCR: bake images come from docker.io/
  quay.io and, on Namespace, are served by the profile's container cache
  (nscr.io). Remaining GitHub contact is unmetered: orchestration/logs,
  git clones (code stays), the issues API in the docs workflow, GitHub
  Releases (unchanged), and GitHub Pages (docs site / hub fallback
  redirect). Org-level risk stays until the private repos also move or the
  org leaves the Free plan: their GH-hosted jobs keep eating the same
  2,000-min pool, and org Actions cache already totals 14.8 GiB
  (oarlock 11.8 GiB).
- Namespace-side TODO (dashboard, cannot be done via this repo): confirm
  plan tier + payment method; check Linux concurrency cap for the chosen
  plan (Developer 32 vCPU = 8 concurrent 4c-8g jobs — release matrices will
  queue; Team 64 / Business 160); set Namespace billing alerts. No artifact
  storage/reads budgeting needed (staging artifacts are short-lived;
  distribution never moved). Profiles, caches (100 GiB bundled), GitHub
  app install, and arm64 platform are already verified working live. No
  hub token to mint.

## Risks recorded against the locked decisions

- Halved RAM (16 GB → 8 GB, +8 GiB swap) and 55 GiB disk may squeeze
  docker/ollama/coder bakes; Phases 1–2 must watch for it and invoke the
  per-extension upsize escape hatch (decision 4).
- Native split changes `release.sh`'s contract (one arch per leg, tag once
  in publish): `rebuild.yaml`'s delete-then-recreate ordering must be
  preserved in the publish job, or a failed join could leave a published
  version deleted. Publish job deletes only after both arch artifacts are
  present and joined.
- Namespace concurrency caps can serialize the daily matrix on lower plan
  tiers; jobs queue rather than fail, but release latency grows.
