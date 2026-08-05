# sqlite sysext Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `sqlite` system extension shipping `sqlite3` and `sqldiff` for x86-64 and arm64, built from Alpine `latest-stable` packages, and record it as fork patch 10.

**Architecture:** `create.sh` runs an architecture-matched Alpine container, installs `sqlite` and `sqlite-tools`, asserts the installed version matches the requested one, and uses `tools/flix.sh` to extract the two binaries with their musl/readline dependency closure into a self-contained `/usr` tree. Version discovery scrapes the Alpine package index directory listing.

**Tech Stack:** bash, Docker (with binfmt for the emulated arm64 build), Alpine `latest-stable` `main`, `tools/flix.sh` + patchelf.

**Spec:** `sqlite.sysext/2026-08-05-sqlite-sysext-design.md`

## Global Constraints

- **Ship exactly two binaries:** `/usr/bin/sqlite3` and `/usr/bin/sqldiff`. No `sqlite3_rsync`, no `sqlite3_analyzer`, no `show*` tools, no `libsqlite3.so`, no headers.
- **Alpine mirror:** `https://dl-cdn.alpinelinux.org/alpine/latest-stable/main` — repo `main`, not `community`.
- **Pinned release version:** `3.53.2` (current Alpine `latest-stable`).
- **Hub hostname in docs:** `extensions.quantumops.consulting`. Release-tag links point at `qopsc/sysext-bakery`, not flatcar — this extension does not exist upstream.
- **Script conventions** (match `btop.sysext/create.sh`): `#!/usr/bin/env bash`, `# vim: et ts=2 syn=bash`, `# --` after each function.
- **Never ship `/usr/sbin`.** On Flatcar it is a symlink to `/usr/bin`; a sysext containing it destroys `/usr/bin` on merge. `flix.sh` only writes `/usr/bin` and `/usr/local/<name>/` for these inputs, so this is a review check, not a code change.
- **Do not modify:** `.env`, `lib/**`, `bakery.sh`, `release.sh`, `release_meta.sh`, `release_dispatcher.sh`, `.github/**`, root `README.md`, or any other `*.sysext/`. This extension uses existing interfaces unchanged.
- Local host is macOS with Docker but no `mkfs.erofs`, `mksquashfs` or `qemu`. `./bakery.sh create` and `./bakery.sh boot` **cannot run here** — image generation is proven by CI.

---

### Task 1: The extension build script

**Files:**
- Create: `sqlite.sysext/create.sh`
- Create: `sqlite.sysext/test.sh` (empty)

**Interfaces:**
- Consumes: `arch_transform` and `scriptroot` from `lib/`, sourced by `bakery.sh` before `create.sh` runs. `tools/flix.sh`, invoked inside the container as `/tools/flix.sh`.
- Produces: `list_available_versions()` printing one version per line, newest first (e.g. `3.53.2`), and `populate_sysext_root(sysextroot, arch, version)` leaving a populated `usr/` under `${sysextroot}`. Task 3's `release_build_versions.txt` entries depend on the version string format having no `v` prefix and no `-rN` Alpine suffix.

- [ ] **Step 1: Establish the failing baseline — show why the obvious regex is wrong**

`btop.sysext/create.sh` discovers versions with `grep -m1 -o "btop-.*apk"`. Run that idiom against this package name before writing anything, so the reason for the deviation is on the record:

```bash
curl -sSfL https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64/ \
  | grep -oE 'sqlite-3[a-z0-9._-]*apk' | sed 's/^sqlite-//;s/-r[0-9]*\.apk$//' | sort -Vr | head
```

Expected: **more than one version**, including values that are not sqlite releases at all. The unanchored pattern matches the `sqlite-…` substring inside *other* packages' filenames (`lua5.4-sqlite-0.9.6-r0.apk`, and similar for `php84-sqlite3-…`). Anything other than a single `3.53.2` here confirms the trap this task must avoid.

- [ ] **Step 2: Write `create.sh`**

Create `sqlite.sysext/create.sh`:

```bash
#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# sqlite sysext.
#

RELOAD_SERVICES_ON_MERGE="false"

alpine_mirror="https://dl-cdn.alpinelinux.org/alpine/latest-stable/main"

function list_available_versions() {
  # The index is an HTML directory listing, so anchor the match on the href
  # quotes. An unanchored 'sqlite-...apk' also matches inside other packages'
  # filenames (lua5.4-sqlite-0.9.6-r0.apk, php84-sqlite3-...) and reports
  # their versions as sqlite's.
  # Alpine's latest-stable branch only ever carries one version; sort anyway
  # so a mirror listing in arbitrary order cannot change the answer.
  curl -sSfL "${alpine_mirror}/x86_64/" \
    | grep -oE '"sqlite-3[^"]*\.apk"' \
    | tr -d '"' \
    | sed -e 's/^sqlite-//' -e 's/-r[0-9]*\.apk$//' \
    | sort -Vr \
    | uniq
}
# --

function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local img_arch="$(arch_transform 'x86-64' 'amd64' "$arch")"
  img_arch="$(arch_transform 'arm64' 'arm64/v8' "$img_arch")"

  # 'apk add' installs whatever latest-stable currently carries and ignores
  # the version we were asked for, so check afterwards. Without this, the day
  # Alpine moves on we would publish a sysext labelled with one version that
  # contains another, and sysupdate would hand it to nodes as that version.
  local sysextname=sqlite
  docker run --rm \
              -i \
              -v "${scriptroot}/tools/":/tools \
              -v "${sysextroot}":/install_root \
              --platform "linux/${img_arch}" \
              --pull always \
              --network host \
              docker.io/alpine:latest \
                  sh -c "apk add -U sqlite sqlite-tools patchelf && installed=\$(sqlite3 --version | cut -d ' ' -f 1) && if [ \"\$installed\" != \"${version}\" ]; then echo \"ERROR: Alpine latest-stable ships sqlite \$installed, but ${version} was requested.\" >&2; exit 1; fi && cd /install_root && /tools/flix.sh / $sysextname /usr/bin/sqlite3 /usr/bin/sqldiff && OWNER=\$(stat -c '%u:%g' /install_root) && if [ \"\$OWNER\" != \"\$(id -u):\$(id -g)\" ]; then chown -R \"\$OWNER\" /install_root/$sysextname; fi"
  # flix.sh resolves the musl loader, libc and libreadline into the tree.
  # We rely on the host's /usr/share/terminfo for readline's terminal
  # handling; a sysext may only ship /usr and /opt, so Alpine's /etc/terminfo
  # cannot be carried at its original path anyway.
  mv "${sysextroot}"/sqlite/usr "${sysextroot}"/usr
  rmdir "${sysextroot}"/sqlite
}
# --
```

- [ ] **Step 3: Create the empty test hook**

`btop.sysext/test.sh`, `tilde.sysext/test.sh` and `lib/test.sh` are all zero-byte. Match them:

```bash
touch sqlite.sysext/test.sh
```

- [ ] **Step 4: Syntax-check**

This is the same check the fork's upstream-sync procedure runs on its scripts.

```bash
bash -n sqlite.sysext/create.sh && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 5: Verify version discovery returns exactly one clean version**

```bash
./bakery.sh list sqlite
```

Expected: exactly `3.53.2` and nothing else. Specifically **not** `15.0.3`, `6.0.6`, `2.4.4`, `1.78` or `0.9.6` — those are the phantom matches from Step 1 and their presence means the quote anchoring was dropped.

- [ ] **Step 6: Verify the latest-version path and extension discovery**

`release_dispatcher.sh` uses the first of these to resolve a `latest` line into a concrete version, and the second is how `list` advertises the extension.

```bash
./bakery.sh list sqlite --latest true
./bakery.sh list --plain true | grep '^sqlite$'
./bakery.sh list | grep sqlite
```

Expected: `3.53.2`; then `sqlite`; then a table row reading `sqlite | No | Yes | No` — static files No, build script Yes, test hook No.

- [ ] **Step 7: Commit**

```bash
git add sqlite.sysext/create.sh sqlite.sysext/test.sh
git commit -m "sqlite: add sysext shipping sqlite3 and sqldiff

Builds from Alpine latest-stable via flix.sh, which is the only source
covering both x86-64 and arm64 without a compiler: sqlite.org publishes no
Linux arm64 binaries and its amalgamation tarball builds only the CLI.

Version discovery anchors on the href quotes because an unanchored match
also fires inside other packages' filenames and reports their versions as
sqlite's. The build asserts the installed version matches the requested one,
since apk on a rolling branch silently ignores it."
```

---

### Task 2: Documentation

**Files:**
- Create: `docs/sqlite.md`
- Modify: `docs/index.md` (one table row, between the `scx` and `tailscale` rows)

**Interfaces:**
- Consumes: the version string `3.53.2` from Task 1 and the image naming `sqlite-<version>-<arch>.raw` produced by `release.sh`.
- Produces: nothing consumed by later tasks. Task 3 records both files as divergent.

- [ ] **Step 1: Write `docs/sqlite.md`**

Modelled on `docs/netbird.md`, minus the service-restart hook — this extension ships no units, so a sysupdate only needs `systemd-sysext refresh`. URLs point at the qopsc hub, per patch 4.

````markdown
# SQLite sysext

This sysext ships the [SQLite](https://sqlite.org/) command-line shell (`sqlite3`) and
`sqldiff`, for inspecting and diffing SQLite databases directly on a node.

The binaries come from Alpine's `latest-stable` packages and are self-contained: the musl
loader, C library and readline are bundled inside the image, so nothing is required from
the host beyond a terminfo database for line editing.

No services are installed and no state is created — merging the extension only adds the
two binaries to `/usr/bin`.

## Usage

The snippet below includes automated updates via systemd-sysupdate.
Sysupdate will stage updates and refresh the merged sysext — no reboot is required.
You can deactivate updates by changing `enabled: true` to `enabled: false` in `systemd-sysupdate.timer`.

Note that the snippet is for the x86-64 version of SQLite 3.53.2.

Check out the metadata release at https://github.com/qopsc/sysext-bakery/releases/tag/sqlite for a list of all versions available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/sqlite/sqlite-3.53.2-x86-64.raw
      mode: 0644
      contents:
        source: https://extensions.quantumops.consulting/extensions/sqlite-3.53.2-x86-64.raw
    - path: /etc/sysupdate.sqlite.d/sqlite.conf
      contents:
        source: https://extensions.quantumops.consulting/extensions/sqlite.conf
  links:
    - target: /opt/extensions/sqlite/sqlite-3.53.2-x86-64.raw
      path: /etc/extensions/sqlite.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: sqlite.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/sqlite.raw > /tmp/sqlite"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C sqlite update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/sqlite.raw > /tmp/sqlite-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/sqlite /tmp/sqlite-new; then systemd-sysext refresh; fi"
```

## Versions

Versions track Alpine's `latest-stable` branch, which carries one SQLite version at a time
and lags upstream by a few weeks. That branch does not retain older versions, so a bakery
release can only ever be built while Alpine still serves that version.

## Building locally

```
./bakery.sh list sqlite
./bakery.sh create sqlite 3.53.2 --arch x86-64
```
````

- [ ] **Step 2: Add the index row**

In `docs/index.md`, in the "What extensions are available?" table, insert between the `scx` and `tailscale` rows:

```markdown
| `sqlite`         |  released    | [sqlite versions](https://github.com/qopsc/sysext-bakery/releases/tag/sqlite) |
```

The link points at `qopsc`, unlike its neighbours — this extension is fork-local and has no upstream release tag.

- [ ] **Step 3: Verify the row landed in the right place and links to the fork**

```bash
grep -n -A1 -B1 '`sqlite`' docs/index.md
grep -c 'qopsc' docs/index.md
```

Expected: the `sqlite` row appears between `scx` and `tailscale`, and `qopsc` appears exactly once in the file — any other count means an unrelated row was edited.

- [ ] **Step 4: Verify the asset names in the snippet match what `release.sh` publishes**

`release.sh` names assets `${extension}-${version}-${arch}.raw`. A typo here is a 404 for
everyone who copies the snippet, and nothing else in the pipeline would catch it.

```bash
grep -o 'sqlite-[0-9.]*-x86-64\.raw' docs/sqlite.md | sort -u
grep -c 'extensions\.quantumops\.consulting' docs/sqlite.md
```

Expected: exactly one unique filename, `sqlite-3.53.2-x86-64.raw`, and `2` hub URLs — one
for the image, one for the sysupdate `.conf`. A count of `0` means the doc was written
against flatcar's hub by copy-paste.

- [ ] **Step 5: Commit**

```bash
git add docs/sqlite.md docs/index.md
git commit -m "sqlite: document the extension

Butane snippet with sysupdate, pointing at the qopsc hub. The sysupdate
drop-in only refreshes the sysext, since this extension ships no units."
```

---

### Task 3: Enable releases and record fork patch 10

**Files:**
- Modify: `release_build_versions.txt` (append at end, after the `vault` entries)
- Modify: `AGENTS.md` — line 16 (patch count), the patch table at lines 18–29, patch 6's section text at line 108, a new patch section after patch 9, and the expected-divergence block at lines 170–180
- Modify: `CLAUDE.md` — lines 3, 8, the patch table at lines 10–20, line 25 (patch 6 note), line 26 (patch count)

**Interfaces:**
- Consumes: the file list produced by Tasks 1 and 2, and the version string `3.53.2` from Task 1.
- Produces: nothing.

**Why this task is not optional:** `AGENTS.md` states that anything outside its documented divergence list is drift to be investigated and removed. Left unrecorded, the next `git rebase flatcar/main` deletes Tasks 1 and 2 wholesale. This is the failure mode AGENTS.md already warns about for patches 2, 6, 7 and 8.

- [ ] **Step 1: Add the release entries**

Append to the end of `release_build_versions.txt`, after the `vault` block:

```
sqlite 3.53.2
sqlite latest
```

- [ ] **Step 2: Verify the entries survive the dispatcher's parser**

`release_dispatcher.sh` derives both the build matrix and the metadata matrix from this
file, reading it through a comment-stripping filter. Run that exact filter rather than the
whole dispatcher — the dispatcher makes a GitHub API call per extension per version, which
is slow and rate-limited, and Task 1 Step 6 already proved `latest` resolves.

```bash
sed -e 's:\s*#.*::' -e 's/[[:space:]]*$//' -e '/^$/d' release_build_versions.txt | grep '^sqlite'
```

Expected: exactly `sqlite 3.53.2` and `sqlite latest`. The dispatcher splits each line on
the first space into extension and version, so a trailing comment or stray whitespace would
show up here as a malformed version.

- [ ] **Step 3: Verify the docs checker is satisfied**

`tools/report_missing_extension_docs.sh` only examines extensions listed in
`release_build_versions.txt`, so this check is meaningless until Step 1 lands — that is why
it runs here rather than in Task 2.

```bash
./tools/report_missing_extension_docs.sh | grep -i sqlite || echo "sqlite documented"
```

Expected: `sqlite documented`. A `Missing documentation detected for 'sqlite'` line means
Task 2's `docs/index.md` row or `docs/sqlite.md` did not land.

- [ ] **Step 4: Update the AGENTS.md patch count and table**

`AGENTS.md:16` — change `**nine permanent patches**` to `**ten permanent patches**`.

Append this row to the patch table, after the row for patch 9:

```markdown
| 10 | sqlite extension | `sqlite.sysext/**`, `docs/sqlite.md`, `docs/index.md`, `release_build_versions.txt` sqlite lines | policy |
```

- [ ] **Step 5: Correct patch 6's claim about `release_build_versions.txt`**

Patch 6's section currently says every line other than the kata comment tracks upstream verbatim. Task 1's entries make that false, and a future rebase following it literally would delete them.

Replace the sentence at `AGENTS.md:108`:

```markdown
This fork builds a **subset** of upstream's extensions. Every other line tracks upstream verbatim **except** the two `sqlite` entries, which are fork-added and belong to patch 10; take upstream's version in any conflict, then re-apply the kata-containers comment and the sqlite lines.
```

- [ ] **Step 6: Add the AGENTS.md patch section**

Insert after the `### 9. qopsc hub deployment` section, before the `---` that precedes `## Upstream Sync Procedure`:

```markdown
### 10. sqlite extension

**Files**: `sqlite.sysext/` (create.sh, test.sh, design and plan docs), `docs/sqlite.md`, the `sqlite` row in `docs/index.md`, and the two `sqlite` lines in `release_build_versions.txt`.

A fork-local extension shipping `sqlite3` and `sqldiff`. It does not exist upstream, so there is no upstream version to reconcile against — in any conflict take upstream's file and re-add the sqlite parts.

**Rules**:
- Ships exactly two binaries. Adding `sqlite3_rsync`, `sqlite3_analyzer` or the `show*` tools is a scope decision, not a fix; see the design doc.
- The version-discovery regex anchors on the href quotes (`'"sqlite-3[^"]*\.apk"'`). Do not "simplify" it to `btop`'s unanchored idiom: an unanchored match fires inside other packages' filenames (`lua5.4-sqlite-…`) and reports their versions as sqlite's.
- The build asserts the installed version matches the requested one. `btop` and `tilde` lack this check and can silently publish mislabelled images; do not remove it to make a pinned build pass. When Alpine moves past a pinned version, bump or drop the pinned line instead.
- `docs/index.md` and `docs/sqlite.md` link the **qopsc** release tag, not flatcar's. There is no flatcar release for this extension.

See `sqlite.sysext/2026-08-05-sqlite-sysext-design.md` for the decisions and their rationale.
```

- [ ] **Step 7: Update the AGENTS.md expected-divergence list**

In the code block under `## Upstream Sync Procedure`, `docs/index.md` currently appears only on the temporary netbird line. It is permanently divergent from now on, so it must move up — otherwise it silently drops off the list when netbird converges upstream.

Replace the block with:

```
.env  .gitignore  AGENTS.md  CLAUDE.md
.github/workflows/release.yaml
docker.sysext/create.sh
lib/generate.sh
release_build_versions.txt
release_meta.sh
tools/http-url-rewrite-server/**
docs/index.md  docs/sqlite.md  sqlite.sysext/**
# plus, while the netbird divergence lasts:
README.md  docs/netbird.md  netbird.sysext/**
```

- [ ] **Step 8: Mirror the changes into CLAUDE.md**

`CLAUDE.md:3` — `nine protected fork patches` → `ten protected fork patches`.

`CLAUDE.md:8` — `**nine permanent patches**` → `**ten permanent patches**`.

Append to the patch table after the row for patch 9:

```markdown
  | 10 | sqlite extension | `sqlite.sysext/**`, `docs/sqlite.md`, `docs/index.md` |
```

`CLAUDE.md:25` — append to the `release_build_versions.txt` bullet so it reads:

```markdown
- `release_build_versions.txt` tracks upstream **except** the commented-out `kata-containers` line (patch 6): its x86-64 image is 2.286 GiB against GitHub's hard 2 GiB asset limit, and squashfs does not fix it. The two fork-added `sqlite` lines (patch 10) are the other exception.
```

`CLAUDE.md:26` — `upstream wins outside the nine patches` → `upstream wins outside the ten patches`.

- [ ] **Step 9: Verify the divergence list matches reality**

This is the check the whole task exists to make pass.

```bash
git fetch flatcar
git diff flatcar/main main --stat | cat
```

Expected: every file shown is named in the updated AGENTS.md block from Step 6 — `sqlite.sysext/**`, `docs/sqlite.md`, `docs/index.md`, `release_build_versions.txt`, `AGENTS.md`, `CLAUDE.md`, plus the pre-existing patches and the netbird divergence. Anything else is drift introduced by this work; revert it.

- [ ] **Step 10: Confirm nothing outside the intended scope changed**

Diff against the commit this work started from, **not** `flatcar/main` — comparing to upstream flags every pre-existing fork patch and drowns the signal.

```bash
# The plan doc's own commit is the last one before Task 1's work.
base="$(git log -1 --format=%H -- sqlite.sysext/2026-08-05-sqlite-sysext-plan.md)"
git diff "${base}" --stat -- \
  .env lib/ bakery.sh release.sh release_meta.sh release_dispatcher.sh \
  .github/ README.md docker.sysext/
```

Expected: **empty output**. Any output means an out-of-scope file was modified; revert it.

- [ ] **Step 11: Verify the patch count is internally consistent**

```bash
grep -c '^| [0-9]* |' AGENTS.md
grep -n 'permanent patches\|protected fork patches\|the ten patches' AGENTS.md CLAUDE.md
```

Expected: ten patch-table rows in AGENTS.md, and every prose reference saying "ten" — a leftover "nine" is the kind of drift that makes the next agent distrust the whole table.

- [ ] **Step 12: Commit**

```bash
git add release_build_versions.txt AGENTS.md CLAUDE.md
git commit -m "sqlite: enable releases and record as fork patch 10

Without this the next rebase onto flatcar/main deletes the extension as
undocumented drift.

Also corrects two now-false statements: patch 6 claimed every
release_build_versions.txt line but the kata comment tracks upstream, and
docs/index.md was listed only under the temporary netbird divergence, so it
would have dropped off the expected-divergence list once netbird converged."
```

---

## Done criteria

- [ ] `bash -n sqlite.sysext/create.sh` passes
- [ ] `./bakery.sh list sqlite` prints exactly `3.53.2`
- [ ] `./bakery.sh list --plain true` includes `sqlite`
- [ ] `git diff flatcar/main main --stat` shows only files named in AGENTS.md
- [ ] `.env`, `lib/`, `bakery.sh`, the release scripts, `.github/`, root `README.md` and other `*.sysext/` directories are untouched
- [ ] AGENTS.md and CLAUDE.md both say ten patches, and both describe patch 10

## Verified by CI, not locally

Image generation needs `mkfs.erofs` and an emulated arm64 container, neither available on the macOS dev host. After the release workflow runs:

- [ ] `sqlite-3.53.2-x86-64.raw` and `sqlite-3.53.2-arm64.raw` both published
- [ ] `file sqlite-3.53.2-x86-64.raw` reports EROFS
- [ ] The image contains `usr/bin/sqlite3`, `usr/bin/sqldiff`, a populated `usr/local/sqlite/` (musl loader + libs), and **no** `usr/sbin`. There will be no `usr/lib` — `flix.sh` keeps the closure private so it cannot shadow host libraries.
- [ ] The bundled `sqlite.conf` sysupdate `Path` points at `extensions.quantumops.consulting`
- [ ] No leftover **draft** release (`gh release list --repo qopsc/sysext-bakery | grep -i -- draft` is empty) — a draft means an upload failed and will keep the metadata job skipping this version until deleted

## Known follow-up, outside this plan

When Alpine's `latest-stable` moves past 3.53.2, the pinned release line stops building and fails loudly by design. Bump `release_build_versions.txt` to the new version at that point; `sqlite latest` continues unaffected.
