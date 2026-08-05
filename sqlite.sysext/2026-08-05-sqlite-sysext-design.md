# sqlite sysext

**Date:** 2026-08-05
**Status:** Approved, pending implementation

## Problem

Flatcar ships no `sqlite3`. Inspecting or repairing a SQLite database on a node — the
storage format behind a large share of the software that ends up on these machines —
currently means copying the file off the host or running a throwaway container.

A sysext is the right shape for this: a handful of megabytes, no services, no state,
mergeable at provisioning time or on demand.

## Scope

Ships `/usr/bin/sqlite3` and `/usr/bin/sqldiff`, self-contained, for x86-64 and arm64.

Explicitly **not** shipped: `libsqlite3.so`, `sqlite3.h`, `pkg-config` files. No existing
extension in this repo ships dev files, and Flatcar has no compiler to use headers with.
Shared libraries appear in other extensions (`tilde` → libt3widget, `wasmedge` →
libwasmedge.so) only as runtime dependencies of the binary being shipped, which is
exactly how musl and readline are treated here.

## Upstream survey

The three plausible sources, and why Alpine wins:

**sqlite.org precompiled binaries.** `sqlite-tools-linux-x64-<VERNUM>.zip` contains
`sqlite3`, `sqldiff`, `sqlite3_analyzer` and `sqlite3_rsync` as dynamically-linked glibc
PIE executables. It is **x64-only** — there is no Linux arm64 build. `release.sh` loops
`for arch in x86-64 arm64`, so this cannot be the sole source, and pairing it with a
source build for arm64 means two code paths with different compile flags, i.e. feature
drift between architectures on the same version tag.

**sqlite.org source.** The `sqlite-autoconf-<VERNUM>.tar.gz` amalgamation contains only
`sqlite3.c` and `shell.c` — it builds the CLI and nothing else. Every companion tool
requires the canonical `sqlite-src-<VERNUM>.zip` tree, which requires TCL to build at all
and TCL *dev* headers for `sqlite3_analyzer`. Download URLs are also year-partitioned
(`https://sqlite.org/2026/…`), so a version list needs a version→year map scraped from
`changes.html`.

**Alpine `latest-stable`.** Packages the whole set for both `x86_64` and `aarch64`:
`sqlite` (the CLI), `sqlite-tools` (`sqldiff`, `sqlite3_rsync`, `showdb`, `showjournal`,
`showstat4`, `showwal`), `sqlite-analyzer`, plus `patchelf` in `main` for `flix.sh`.
Currently 3.53.2 against upstream's 3.53.4 — weeks of lag. Debian is not a candidate:
trixie carries 3.46.1.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Source | Alpine `latest-stable` `main` | Only source with both architectures and the companion tools, with no compiler in the loop. Same pattern as `btop` and `tilde`. |
| Binaries | `sqlite3`, `sqldiff` | `flix.sh` takes explicit paths. `sqlite3_rsync` (replication over ssh) and `sqlite3_analyzer` (space report) are niche; the `show*` tools are file-format forensics. Adding any of them later is a one-word change. |
| Self-containment | `flix.sh` | Alpine's `sqlite3` needs `/lib/ld-musl-x86_64.so.1`, `libc.musl-*.so.1` and `libreadline.so.8`. `flix.sh` copies the closure into `/usr/lib` and patchelfs interpreter and rpath. `tilde` does the same. |
| Version pinning | Assert, don't trust | See below. |
| Fork status | Permanent, patch 10 | Not upstreamed. Docs point at `extensions.quantumops.consulting`. |
| Release versions | `sqlite 3.53.2` + `sqlite latest` | Pinned known-good plus rolling, matching `chrony`/`consul`/`vault`. |
| Spec location | Alongside the extension | Same rule as patch 9's docs. Not `docs/` — that is Jekyll source for the live Pages site. |

## Design

### `sqlite.sysext/create.sh`

`RELOAD_SERVICES_ON_MERGE="false"` — no units, nothing for systemd to reload.

Alpine's version string is `3.53.2`, so the sysext tag is `sqlite-3.53.2` and the bakery's
default version-match pattern applies. No `EXTENSION_VERSION_MATCH_PATTERN` needed.

**`list_available_versions()`** scrapes the Alpine package index directory listing, as
`btop` does. `btop`'s idiom — `grep -m1 -o "btop-.*apk"` — is unsafe for this package name
and must not be copied verbatim: an unanchored `sqlite-…apk` match also fires inside
*other* packages' filenames (`lua5.4-sqlite-0.9.6-r0.apk`, `php84-sqlite3-…`), yielding
phantom versions like `0.9.6` and `15.0.3`. Anchor on the href quote instead:

```
curl -sSfL https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/ \
  | grep -oE '"sqlite-3[^"]*\.apk"'
```

then strip the quotes and the `-rN` Alpine release suffix, and `sort -Vr`. The listing is
served in whatever order the mirror produces, so sorting by version rather than taking the
first match is what makes this correct.

**`populate_sysext_root()`** follows `tilde` closely:

```
docker run --rm -i \
  -v "${scriptroot}/tools/":/tools \
  -v "${sysextroot}":/install_root \
  --platform "linux/${img_arch}" --pull always --network host \
  docker.io/alpine:latest \
  sh -c "apk add -U sqlite sqlite-tools patchelf && …"
```

with `arch_transform` mapping `x86-64`→`amd64` and `arm64`→`arm64/v8`, then
`/tools/flix.sh / sqlite /usr/bin/sqlite3 /usr/bin/sqldiff`, the `stat -c '%u:%g'`
ownership fixup every containerised extension carries, and finally
`mv "${sysextroot}"/sqlite/usr "${sysextroot}"/usr` + `rmdir`.

The emulated arm64 run needs binfmt; the release workflow already sets it up via
`docker/setup-qemu-action@v3`, and `btop`/`tilde` prove the path works.

### Version assertion

One deliberate addition over `btop` and `tilde`: after `apk add`, run `sqlite3 --version`
inside the container and fail the build if it does not report `${version}`.

Alpine's `latest-stable` is a rolling branch that carries exactly one sqlite version.
`apk add sqlite` therefore installs whatever is current and ignores the `${version}` the
bakery was asked for. `btop` and `tilde` both have this hole. Left unchecked, the day
Alpine moves to 3.53.3 the pinned `sqlite 3.53.2` release-list entry silently publishes a
`sqlite-3.53.2-x86-64.raw` containing 3.53.3 — a mislabelled image, and one that
`systemd-sysupdate` would then serve to nodes under the wrong version. The assertion
converts that into a loud build failure.

The consequence is that pinned entries become unbuildable once Alpine moves on, and the
release job for that line fails. That is intended and visible; patch 8's `fail-fast: false`
already keeps one failing extension from taking down its siblings. The fix at that point is
to bump or drop the pinned line.

### Fork integration (patch 10)

The sync procedure treats anything outside the documented divergence list as drift to be
deleted. Unrecorded, the next rebase removes this extension entirely. So:

- `AGENTS.md`: new patch table row 10 — `sqlite extension | sqlite.sysext/**, docs/sqlite.md, docs/index.md row, release_build_versions.txt sqlite lines | policy`; same paths appended to the expected-divergence list under Upstream Sync Procedure.
- `AGENTS.md` patch 6 text: it currently says `release_build_versions.txt` tracks upstream verbatim except the commented-out kata line. That is no longer true once the `sqlite` lines land. Amend it to name the sqlite entries as the other exception, so a future rebase does not resolve them away as drift.
- `AGENTS.md` sync list: `docs/index.md` currently appears only under the *temporary* netbird divergence. It becomes permanently divergent here and must be listed as such — otherwise it disappears from the expected-divergence list when netbird converges upstream.
- `CLAUDE.md`: mirror the patch-10 row in its summary table.

### Files

| File | Status |
|---|---|
| `sqlite.sysext/create.sh` | new |
| `sqlite.sysext/test.sh` | new, empty — matches `btop`, `tilde`, and `lib/test.sh` |
| `docs/sqlite.md` | new — Butane snippet with `extensions.quantumops.consulting` URLs and a sysupdate drop-in, modelled on `docs/netbird.md` minus the service-restart hook |
| `docs/index.md` | one table row, linking the qopsc release tag |
| `release_build_versions.txt` | `sqlite 3.53.2`, `sqlite latest` |
| `AGENTS.md`, `CLAUDE.md` | patch 10, plus the patch 6 and `docs/index.md` corrections above |

## Known risks

**Version lag.** Alpine 3.53.2 vs upstream 3.53.4. Accepted as the price of a symmetric,
compiler-free build.

**Old versions vanish.** `latest-stable` keeps only the current version, so historical
builds are impossible. Same limitation as `btop` and `tilde`; the version assertion makes
it fail cleanly rather than silently.

**terminfo.** `libreadline` pulls `libncursesw`, which needs a terminfo database at
runtime. `btop`'s create.sh notes that Alpine keeps terminfo under `/etc/terminfo`, and
`tilde`'s that it relies on the host having `/usr/share/terminfo`. A sysext may only ship
`/usr` and `/opt`, so the Alpine copy cannot be carried at its original path regardless. If
lookup fails, readline degrades to dumb-terminal line editing and `sqlite3` otherwise works
— non-blocking. If it proves annoying, the fix is to pass Alpine's terminfo directory to
`flix.sh` as an extra resource path.

**Image size.** Roughly 5 MB of payload before compression; low single-digit MB as EROFS.
Nowhere near the 2 GiB asset limit that governs patch 6.

## Out of scope

`sqlite3_rsync`, `sqlite3_analyzer`, the `show*` tools, `libsqlite3.so`, headers, and any
static-linking or from-source build. `.env` is untouched. No changes to `lib/`,
`bakery.sh`, or the release scripts — this extension uses the existing interfaces as-is.

## Verification

Local tooling on the development host is macOS with Docker but no `mkfs.erofs`,
`mksquashfs` or `qemu`, so image generation and boot testing cannot run here. Verification
is therefore split:

1. `bash -n sqlite.sysext/create.sh` — the repo's own sync sanity-check.
2. `./bakery.sh list sqlite` — prints `3.53.2` and nothing else; specifically no `0.9.6`,
   `15.0.3` or other artefacts of unanchored matching.
3. `./bakery.sh list --plain true | grep sqlite` — the extension is discoverable.
4. `git diff flatcar/main main --stat` — divergence matches the updated AGENTS.md list exactly.
5. The release workflow proves the build: both `sqlite-3.53.2-x86-64.raw` and
   `sqlite-3.53.2-arm64.raw` published, `file` reports EROFS, and the image contains
   `usr/bin/sqlite3`, `usr/bin/sqldiff`, the bundled `usr/lib` closure, and no `usr/sbin`.

## Follow-up

Once `extensions.quantumops.consulting` resolves (AGENTS.md Known Issues), confirm the
baked-in sysupdate source fetches a `sqlite` update end to end on a real node.
