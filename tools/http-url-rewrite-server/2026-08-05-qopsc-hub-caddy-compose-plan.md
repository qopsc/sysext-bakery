# qopsc sysext hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `extensions.quantumops.consulting` by repointing the upstream flatcar hub Caddy config at the qopsc fork, adding a docker compose deployment, and shipping a one-line installer.

**Architecture:** Caddy runs as a single container that rewrites `systemd-sysupdate` requests into GitHub release URLs. Compose replaces the old Flatcar systemd unit; bind mounts keep ACME certificates on disk. An installer script fetches both files over HTTPS into the working directory and starts the stack.

**Tech Stack:** Caddy 2 (alpine image), Docker Compose v2, bash.

**Spec:** `tools/http-url-rewrite-server/2026-08-05-qopsc-hub-caddy-compose-design.md`

## Global Constraints

- **Hardcode all values.** No `.env` parameterisation, no Caddy `{$VAR}` placeholders. This was decided explicitly.
- **Hostname:** `extensions.quantumops.consulting`
- **GitHub org/repo:** `qopsc/sysext-bakery`
- **ACME contact:** `hello@quantumops.consulting`
- **Catch-all target:** `https://qopsc.github.io/sysext-bakery{uri}`
- **Do not modify:** `caddy.service`, `extensions.flatcar.org.yaml`, `.env`, root `README.md`, anything under `docs/`. These track upstream.
- **The Caddyfile site block is indented with TABs.** Preserve them; do not reformat.
- **Do not touch any of the five `path_regexp` matchers or their `redir` templates.** Only the hostname, `base_dest_url`, and the final catch-all change.
- **Script conventions** (match `bakery.sh`): `#!/usr/bin/env bash`, `# vim: et ts=2 syn=bash`, Apache 2.0 header, `set -euo pipefail`, `# --` after each function.
- Target host is Fedora with Docker + Compose v2 preinstalled. Local dev/testing is macOS.

---

### Task 1: Repoint the Caddyfile at the qopsc fork

**Files:**
- Modify: `tools/http-url-rewrite-server/Caddyfile`

**Interfaces:**
- Consumes: nothing.
- Produces: a Caddyfile whose site block is `extensions.quantumops.consulting`, redirecting to `https://github.com/qopsc/sysext-bakery/releases/download`. Task 2's compose file mounts this at `/etc/caddy/Caddyfile`.

- [ ] **Step 1: Establish the failing baseline**

Prove the current config redirects to *flatcar* before changing it. The `:80` test block ships commented out, so build a scratch copy with it enabled and the domain line disabled. The second `sed` matches any `extensions.` line, so this same command works before and after the edit.

```bash
cd tools/http-url-rewrite-server
sed -e 's/^#:80 {/:80 {/' -e 's/^extensions\./#extensions./' Caddyfile > /tmp/Caddyfile.test
docker run --rm -d --name caddy-test \
  -v /tmp/Caddyfile.test:/etc/caddy/Caddyfile:ro \
  -p 8080:80 caddy:2-alpine
sleep 2
curl -sI http://localhost:8080/extensions/docker-28.5.2-x86-64.raw | grep -i '^location:'
docker stop caddy-test
```

Expected output — note `flatcar`, which is what we are about to change:

```
location: https://github.com/flatcar/sysext-bakery/releases/download/docker-28.5.2/docker-28.5.2-x86-64.raw
```

- [ ] **Step 2: Add the global options block**

Caddy requires global options to be the **first block** in the file. Comments may precede it. Insert this after the header comment block (after the line ending `...which pattern matches the request.` and its following blank line, i.e. after current line 17) and **before** the `# For testing locally,` comment:

```
{
	email hello@quantumops.consulting
}

```

- [ ] **Step 3: Repoint the three endpoints**

Make exactly these three replacements.

Line 18–20 comment, so the documented local-test path matches the new tooling:

```
# For testing locally, uncomment the below and comment 'extensions.quantumops.consulting {',
#  then run
# docker run --rm -ti -v ${PWD}/Caddyfile:/etc/caddy/Caddyfile -p 8080:80 caddy:2-alpine
```

Site block opener:

```
extensions.quantumops.consulting {
```

`base_dest_url` (leading indentation is a TAB):

```
	vars base_dest_url "https://github.com/qopsc/sysext-bakery/releases/download"
```

Final catch-all (leading indentation is a TAB):

```
	redir https://qopsc.github.io/sysext-bakery{uri}
```

- [ ] **Step 4: Verify the config parses**

```bash
cd tools/http-url-rewrite-server
docker run --rm -v "${PWD}/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine \
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

Expected: `Valid configuration`. If it reports that global options must come first, the block from Step 2 was placed after the site block.

- [ ] **Step 5: Verify the redirect now points at qopsc**

Same command as Step 1:

```bash
cd tools/http-url-rewrite-server
sed -e 's/^#:80 {/:80 {/' -e 's/^extensions\./#extensions./' Caddyfile > /tmp/Caddyfile.test
docker run --rm -d --name caddy-test \
  -v /tmp/Caddyfile.test:/etc/caddy/Caddyfile:ro \
  -p 8080:80 caddy:2-alpine
sleep 2
curl -sI http://localhost:8080/extensions/docker-28.5.2-x86-64.raw | grep -i '^location:'
```

Expected — `qopsc` where `flatcar` used to be:

```
location: https://github.com/qopsc/sysext-bakery/releases/download/docker-28.5.2/docker-28.5.2-x86-64.raw
```

- [ ] **Step 6: Verify the other matchers still work**

These prove the untouched regexes survived the edit. With the container still running:

```bash
curl -sI http://localhost:8080/extensions/docker.conf              | grep -i '^location:'
curl -sI http://localhost:8080/extensions/kubernetes/kubernetes-v1.32.conf | grep -i '^location:'
curl -sI http://localhost:8080/extensions/SHA256SUMS               | grep -i '^location:'
curl -sI http://localhost:8080/nonsense                            | grep -i '^location:'
docker stop caddy-test
```

Expected, in order:

```
location: https://github.com/qopsc/sysext-bakery/releases/download/docker/docker.conf
location: https://github.com/qopsc/sysext-bakery/releases/download/kubernetes/kubernetes-v1.32.conf
location: https://github.com/qopsc/sysext-bakery/releases/download/SHA256SUMS/SHA256SUMS
location: https://qopsc.github.io/sysext-bakery/nonsense
```

- [ ] **Step 7: Commit**

```bash
rm -f /tmp/Caddyfile.test
git add tools/http-url-rewrite-server/Caddyfile
git commit -m "hub: repoint Caddyfile at the qopsc fork

Redirect sysupdate requests to qopsc/sysext-bakery releases and serve
extensions.quantumops.consulting. Adds an ACME contact address and points
the catch-all at the fork's Pages site. Redirect matchers are unchanged."
```

---

### Task 2: Add the compose deployment

**Files:**
- Create: `tools/http-url-rewrite-server/docker-compose.yml`

**Interfaces:**
- Consumes: `./Caddyfile` from Task 1.
- Produces: a compose project named `sysext-hub` with service `caddy`, expecting `./data` and `./config` to exist beside it. Task 3's installer creates those directories and runs `docker compose up -d` against this file.

- [ ] **Step 1: Write the compose file**

Create `tools/http-url-rewrite-server/docker-compose.yml`:

```yaml
# Deployment for the qopsc sysext hub (extensions.quantumops.consulting).
#
# Caddy rewrites systemd-sysupdate requests into qopsc/sysext-bakery release
# URLs. See Caddyfile for the redirect patterns.
#
# Requires ./Caddyfile beside this file, and ./data + ./config directories.
# Certificates live in ./data - back that directory up, losing it means
# re-issuing against Let's Encrypt rate limits.

name: sysext-hub

services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy-webserver
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      # ':z' relabels for SELinux, required on Fedora.
      - ./Caddyfile:/etc/caddy/Caddyfile:ro,z
      - ./data:/data:z
      - ./config:/config:z
```

Deliberate differences from the `caddy.service` this replaces, all recorded in the design doc — do not "restore" them:
- Bind mounts instead of named volumes, so certificates are visible and backup-able.
- No `user: 1001:1001`; bind-mount paths are root-owned and the official image expects root.
- No `/logs` mount; the Caddyfile has no `log` directive so nothing was ever written there.
- `443/udp` published for HTTP/3.

- [ ] **Step 2: Verify the file is valid**

```bash
cd tools/http-url-rewrite-server
docker compose config >/dev/null && echo "compose OK"
```

Expected: `compose OK`. A schema error prints the offending key and line.

- [ ] **Step 3: Verify the stack starts and serves**

`docker compose up` on the real file binds :80 and :443 and will attempt ACME for a hostname that does not yet resolve. Test in a throwaway copy on high ports instead:

```bash
cd tools/http-url-rewrite-server
testdir="$(mktemp -d)"
sed -e 's/^#:80 {/:80 {/' -e 's/^extensions\./#extensions./' Caddyfile > "${testdir}/Caddyfile"
# Rename the project and container too, so this cannot collide with a real
# deployment on the same host.
sed -e 's/"80:80"/"8080:80"/' \
    -e '/"443:443/d' \
    -e 's/^name: sysext-hub/name: sysext-hub-test/' \
    -e 's/container_name: caddy-webserver/container_name: caddy-webserver-test/' \
    docker-compose.yml > "${testdir}/docker-compose.yml"
mkdir -p "${testdir}/data" "${testdir}/config"
( cd "${testdir}" && docker compose up -d )
sleep 3
curl -sI http://localhost:8080/extensions/docker-28.5.2-x86-64.raw | grep -i '^location:'
```

Expected:

```
location: https://github.com/qopsc/sysext-bakery/releases/download/docker-28.5.2/docker-28.5.2-x86-64.raw
```

- [ ] **Step 4: Verify restart policy and cert directory wiring**

```bash
( cd "${testdir}" && docker compose ps )
docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$(cd "${testdir}" && docker compose ps -q caddy)"
```

Expected: the service shows as `running`, and the restart policy prints `unless-stopped` — that is what replaces the old systemd unit.

- [ ] **Step 5: Tear down the test**

```bash
( cd "${testdir}" && docker compose down )
rm -rf "${testdir}"
```

- [ ] **Step 6: Commit**

```bash
git add tools/http-url-rewrite-server/docker-compose.yml
git commit -m "hub: add docker compose deployment

Replaces the Flatcar systemd unit for non-Flatcar hosts. Bind-mounts ./data
so ACME certificates are visible and backup-able, publishes 443/udp for
HTTP/3, and relies on restart: unless-stopped instead of a unit file."
```

---

### Task 3: Add the one-line installer

**Files:**
- Create: `tools/http-url-rewrite-server/install.sh`

**Interfaces:**
- Consumes: `Caddyfile` and `docker-compose.yml` from Tasks 1 and 2, fetched over HTTPS from `raw.githubusercontent.com` rather than read locally.
- Produces: a script invoked as `curl -fsSL <raw-url>/install.sh | bash`, optionally with `bash -s -- --dir <path> --ref <ref> --force --no-up`.

- [ ] **Step 1: Write the installer**

Create `tools/http-url-rewrite-server/install.sh`. Note the structure: everything is a function and `main "$@"` is the **final line**, so a truncated download defines functions and exits without running anything.

```bash
#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Installer for the qopsc sysext hub (Caddy URL-rewrite server).
#
# Fetches the Caddy config and compose file into the current directory,
# creates the certificate/config directories, and starts the stack.
#
#   curl -fsSL https://raw.githubusercontent.com/qopsc/sysext-bakery/main/tools/http-url-rewrite-server/install.sh | bash
#
# Copyright (c) 2025 the Flatcar Maintainers.
# Use of this source code is governed by the Apache 2.0 license.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/qopsc/sysext-bakery"
SRC_DIR="tools/http-url-rewrite-server"
HUB_HOST="extensions.quantumops.consulting"
FILES=(Caddyfile docker-compose.yml)

target_dir="$(pwd)"
ref="main"
force="false"
start="true"
tmpdir=""

function usage() {
  cat <<EOF

install.sh - install and start the qopsc sysext hub (Caddy URL-rewrite server).

Options:
  --dir <path>   Install into <path> instead of the current directory.
  --ref <ref>    Fetch from this git ref (branch or tag). Default: main.
  --force        Overwrite existing files (${FILES[*]}).
  --no-up        Stage files only; do not run 'docker compose up -d'.
  --help         Print this help.

EOF
}
# --

function fatal() {
  echo "ERROR: $*" >&2
  exit 1
}
# --

function warn() {
  echo "WARNING: $*" >&2
}
# --

function cleanup() {
  if [[ -n "${tmpdir}" && -d "${tmpdir}" ]] ; then
    rm -rf "${tmpdir}"
  fi
}
# --

function parse_args() {
  while [[ $# -gt 0 ]] ; do
    case "$1" in
      --dir)     target_dir="${2:?--dir requires a path}"; shift 2;;
      --ref)     ref="${2:?--ref requires a git ref}"; shift 2;;
      --force)   force="true"; shift;;
      --no-up)   start="false"; shift;;
      --help|-h) usage; exit 0;;
      *)         echo "ERROR: unknown option '$1'" >&2; usage; exit 1;;
    esac
  done
}
# --

function preflight() {
  command -v docker >/dev/null 2>&1 \
    || fatal "docker not found in PATH."

  docker info >/dev/null 2>&1 \
    || fatal "cannot reach the docker daemon. Is it running, and is your user in the 'docker' group?"

  docker compose version >/dev/null 2>&1 \
    || fatal "'docker compose' (Compose v2) not available. The legacy 'docker-compose' binary is not supported."

  mkdir -p "${target_dir}" \
    || fatal "cannot create '${target_dir}'."
  [[ -w "${target_dir}" ]] \
    || fatal "'${target_dir}' is not writable."

  local f
  for f in "${FILES[@]}" ; do
    if [[ -e "${target_dir}/${f}" && "${force}" != "true" ]] ; then
      fatal "'${target_dir}/${f}' already exists. Re-run with --force to overwrite."
    fi
  done
}
# --

function check_environment() {
  local port
  for port in 80 443 ; do
    if command -v ss >/dev/null 2>&1 \
       && ss -lnt "sport = :${port}" 2>/dev/null | grep -q LISTEN ; then
      warn "port ${port} is already in use; startup will fail unless that service is stopped."
    fi
  done

  local resolved=""
  if command -v getent >/dev/null 2>&1 ; then
    resolved="$(getent ahostsv4 "${HUB_HOST}" 2>/dev/null | awk 'NR==1 {print $1}')" || true
  elif command -v dig >/dev/null 2>&1 ; then
    resolved="$(dig +short A "${HUB_HOST}" 2>/dev/null | head -n1)" || true
  fi

  if [[ -z "${resolved}" ]] ; then
    warn "${HUB_HOST} does not resolve."
    warn "  Caddy will start, but the Let's Encrypt HTTP-01 challenge cannot succeed"
    warn "  until an A record for it points at this host."
  else
    echo "${HUB_HOST} resolves to ${resolved} - confirm that is this host, or certificate issuance will fail."
  fi
}
# --

function fetch_files() {
  tmpdir="$(mktemp -d)"

  local f
  for f in "${FILES[@]}" ; do
    echo "Fetching ${f} (ref '${ref}') ..."
    curl -fsSL --proto '=https' --tlsv1.2 \
      -o "${tmpdir}/${f}" \
      "${REPO_RAW}/${ref}/${SRC_DIR}/${f}" \
      || fatal "failed to download ${f} from ref '${ref}'."
    [[ -s "${tmpdir}/${f}" ]] \
      || fatal "downloaded ${f} is empty."
  done

  # Only move into place once every file arrived intact, so a mid-transfer
  # failure cannot leave a truncated config where a working one used to be.
  for f in "${FILES[@]}" ; do
    mv "${tmpdir}/${f}" "${target_dir}/${f}"
  done
}
# --

function main() {
  trap cleanup EXIT

  parse_args "$@"

  echo "Installing the qopsc sysext hub into '${target_dir}'."

  preflight
  check_environment
  fetch_files

  mkdir -p "${target_dir}/data" "${target_dir}/config"

  if [[ "${start}" != "true" ]] ; then
    echo
    echo "Files staged. Start the hub with:"
    echo "  cd '${target_dir}' && docker compose up -d"
    return
  fi

  echo "Starting caddy ..."
  ( cd "${target_dir}" && docker compose up -d )
  echo
  ( cd "${target_dir}" && docker compose ps )
  echo
  echo "Serving ${HUB_HOST}."
  echo "Certificates are stored in '${target_dir}/data' - back that directory up."
  echo "Logs: cd '${target_dir}' && docker compose logs -f"
}
# --

main "$@"
```

- [ ] **Step 2: Make it executable and syntax-check it**

`bash -n` is the same check the fork's own upstream-sync procedure runs on its scripts.

```bash
chmod +x tools/http-url-rewrite-server/install.sh
bash -n tools/http-url-rewrite-server/install.sh && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 3: Lint if shellcheck is available**

```bash
command -v shellcheck >/dev/null 2>&1 \
  && shellcheck tools/http-url-rewrite-server/install.sh \
  || echo "shellcheck not installed, skipping"
```

Expected: no output from shellcheck, or the skip message.

- [ ] **Step 4: Verify `--help` works and starts nothing**

```bash
bash tools/http-url-rewrite-server/install.sh --help
```

Expected: the usage text, exit 0, no files written.

- [ ] **Step 5: Verify staging into a temp directory**

This exercises the real network fetch. It only works once Task 1 and Task 2 are pushed to `origin/main`; until then pass `--ref` for the branch that has them, or expect a 404 from Step 5 and run it after pushing.

```bash
testdir="$(mktemp -d)"
bash tools/http-url-rewrite-server/install.sh --dir "${testdir}" --no-up
ls -la "${testdir}"
grep -c 'quantumops' "${testdir}/Caddyfile"
```

Expected: `Caddyfile`, `docker-compose.yml`, `data/` and `config/` present; the `grep -c` returns a non-zero count, proving the fetched Caddyfile is the qopsc one.

- [ ] **Step 6: Verify it refuses to clobber**

```bash
bash tools/http-url-rewrite-server/install.sh --dir "${testdir}" --no-up ; echo "exit=$?"
```

Expected: `ERROR: '<testdir>/Caddyfile' already exists. Re-run with --force to overwrite.` and `exit=1`. Re-running with `--force` appended should succeed.

- [ ] **Step 7: Clean up and commit**

```bash
rm -rf "${testdir}"
git add tools/http-url-rewrite-server/install.sh
git commit -m "hub: add one-line installer

Fetches the Caddyfile and compose file into the working directory, creates
the cert/config directories and starts the stack. Body is wrapped in main()
invoked on the last line so a truncated 'curl | bash' cannot half-execute,
and downloads land in a tempdir before being moved into place."
```

---

### Task 4: Document the deployment

**Files:**
- Create: `tools/http-url-rewrite-server/README.md`

**Interfaces:**
- Consumes: the installer invocation and flags from Task 3.
- Produces: nothing consumed by later tasks.

This is a new file rather than an edit to the root `README.md`, which tracks upstream — adding qopsc hosting content there would create a rebase conflict for no benefit.

- [ ] **Step 1: Write the README**

Create `tools/http-url-rewrite-server/README.md`:

````markdown
# qopsc sysext hub

Caddy configuration and deployment for `extensions.quantumops.consulting`, the
URL-rewrite server that turns `systemd-sysupdate` requests into
`qopsc/sysext-bakery` GitHub release URLs.

Clients see a single flat directory of sysext images; Caddy rewrites each
request to the matching release asset. `Caddyfile` documents every redirect
pattern.

## Requirements

- Docker with Compose v2 (`docker compose`, not the legacy `docker-compose`).
- Ports 80 and 443 reachable from the internet.
- A DNS **A record** for `extensions.quantumops.consulting` pointing at the host.
  Without it Caddy starts but the Let's Encrypt HTTP-01 challenge cannot
  complete, so no certificate is issued.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/qopsc/sysext-bakery/main/tools/http-url-rewrite-server/install.sh | bash
```

This fetches `Caddyfile` and `docker-compose.yml` into the current directory,
creates `data/` and `config/`, and runs `docker compose up -d`.

Options are passed through `bash -s --`:

```sh
curl -fsSL .../install.sh | bash -s -- --dir /opt/sysext-hub --no-up
```

| Flag | Default | Effect |
|---|---|---|
| `--dir <path>` | current directory | Install target |
| `--ref <ref>` | `main` | Git ref to fetch from |
| `--force` | off | Overwrite an existing `Caddyfile` / `docker-compose.yml` |
| `--no-up` | off | Stage files only, do not start |

To read the script before running it:

```sh
curl -fsSLO https://raw.githubusercontent.com/qopsc/sysext-bakery/main/tools/http-url-rewrite-server/install.sh
less install.sh && bash install.sh
```

## Operating

```sh
docker compose logs -f      # follow logs
docker compose restart      # after editing the Caddyfile
docker compose down         # stop
```

## Backups

Let's Encrypt certificates and account keys live in `./data`. Back that
directory up. Losing it forces re-issuance, which counts against Let's
Encrypt rate limits.

```sh
tar czf sysext-hub-data-$(date +%F).tar.gz data
```

## Verifying

```sh
curl -sI https://extensions.quantumops.consulting/extensions/docker-28.5.2-x86-64.raw
```

Should return `302` with a `Location` pointing at
`https://github.com/qopsc/sysext-bakery/releases/download/...`.

## Flatcar deployment

`caddy.service` and `extensions.flatcar.org.yaml` are upstream's
Flatcar/Ignition deployment path, kept here for reference. They still name
flatcar's hostname and are not used by the compose deployment above.
````

- [ ] **Step 2: Verify the install command in the README matches the script**

The one-liner is the primary interface; a typo makes it a 404.

```bash
grep -o 'https://raw.githubusercontent.com[^ ]*install.sh' tools/http-url-rewrite-server/README.md | sort -u
curl -sS -o /dev/null -w '%{http_code}\n' \
  "https://raw.githubusercontent.com/qopsc/sysext-bakery/main/tools/http-url-rewrite-server/install.sh"
```

Expected: one unique URL, and `200` once Task 3 is pushed (`404` before that is expected and not a README bug).

- [ ] **Step 3: Commit**

```bash
git add tools/http-url-rewrite-server/README.md
git commit -m "hub: document the deployment and installer"
```

---

### Task 5: Record the fork patch

**Files:**
- Modify: `AGENTS.md:16`, `AGENTS.md:18-29` (patch table), `AGENTS.md:153-164` (expected divergence), `AGENTS.md:197-199` (known issues)
- Modify: `CLAUDE.md:3`, `CLAUDE.md:8`, `CLAUDE.md:10-19` (patch table), `CLAUDE.md:27-29` (known issue)

**Interfaces:**
- Consumes: the file list produced by Tasks 1–4.
- Produces: nothing.

**Why this task is not optional:** `AGENTS.md` states that anything outside its documented divergence list is drift to be investigated and removed. Leaving Tasks 1–4 unrecorded means the next `git rebase flatcar/main` deletes all of it as drift. This is the same failure mode AGENTS.md already warns about for patches 2, 6, 7 and 8.

- [ ] **Step 1: Confirm the current divergence, pre-change**

```bash
git fetch flatcar
git diff flatcar/main main --stat | tail -20
```

Expected: the files listed in AGENTS.md, **plus** `tools/http-url-rewrite-server/**` from Tasks 1–4, which is exactly the drift this task documents.

- [ ] **Step 2: Update the AGENTS.md patch count and table**

`AGENTS.md:16` — change `**eight permanent patches**` to `**nine permanent patches**`.

Append this row to the patch table, after the row for patch 8:

```markdown
| 9 | qopsc hub deployment | `tools/http-url-rewrite-server/**` | policy |
```

- [ ] **Step 3: Add the AGENTS.md patch section**

Insert after the `### 8. CI resilience` section, before the `---` that precedes `## Upstream Sync Procedure`:

```markdown
### 9. qopsc hub deployment

**Files**: `tools/http-url-rewrite-server/` — `Caddyfile` (modified), plus `docker-compose.yml`, `install.sh`, `README.md` and the design/plan docs (added).

Upstream ships this directory configured for `extensions.flatcar.org` with a
Flatcar/Ignition systemd unit as its only run definition. This fork repoints the
`Caddyfile` at `extensions.quantumops.consulting` and
`github.com/qopsc/sysext-bakery`, and adds a compose deployment for a
non-Flatcar (Fedora) host.

**Rules**:
- Values are hardcoded by choice, not read from `.env`. Do not "improve" this into
  `{$bakery_hub}` placeholders without deciding to; the deployment host does not have
  the repo checked out.
- The three endpoints in the `Caddyfile` are the hostname, `base_dest_url`, and the
  final catch-all. The five `path_regexp` matchers track upstream verbatim — take
  upstream's version in any conflict, then re-apply the three endpoints.
- `caddy.service` and `extensions.flatcar.org.yaml` are deliberately **left on
  upstream's values**. They are the Flatcar deployment path and this fork does not
  use them.
- Certificates live in the deployment host's `./data` bind mount, not in this repo.

See `tools/http-url-rewrite-server/2026-08-05-qopsc-hub-caddy-compose-design.md`
for the decisions and their rationale.
```

- [ ] **Step 4: Update the AGENTS.md expected-divergence list**

In the code block under `## Upstream Sync Procedure`, add a line after `release_meta.sh`:

```
tools/http-url-rewrite-server/**
```

- [ ] **Step 5: Update the AGENTS.md known issue**

Replace the Known Issues bullet so it reflects that the config now exists and only DNS is outstanding. Keep the "do not fix by editing `.env`" instruction:

```markdown
- **`extensions.quantumops.consulting` does not resolve.** The `quantumops.consulting` zone exists (ClouDNS), but the `extensions` subdomain has no record. `lib/sysupdate.conf.tmpl` bakes `https://{BAKERY_HUB}/extensions/…` into the `.conf` inside every released image, so images published today ship an unusable sysupdate source. Builds and releases are unaffected; **node-side sysupdate is not usable until the hub is stood up**. Legacy `sysext.darkspadez.me` still resolves (152.53.243.195). Do not "fix" this by editing `.env` — see patch 4.

  The hub's serving config now exists and is deployable — see patch 9 and `tools/http-url-rewrite-server/README.md`. The remaining work is external to this repo: create the A record pointing at the host, then run the installer. Until then Caddy starts but Let's Encrypt cannot issue a certificate.
```

- [ ] **Step 6: Mirror the changes into CLAUDE.md**

`CLAUDE.md:3` — `eight protected fork patches` → `nine protected fork patches`.

`CLAUDE.md:8` — `**eight permanent patches**` → `**nine permanent patches**`.

Append to the patch table after the row for patch 8:

```markdown
  | 9 | qopsc hub deployment | `tools/http-url-rewrite-server/**` |
```

`CLAUDE.md:25` — `upstream wins outside the eight patches` → `upstream wins outside the nine patches`.

Append to the `## Known issue` section:

```markdown
The hub's Caddy config and compose deployment now exist (`tools/http-url-rewrite-server/`, patch 9). What is missing is the DNS A record, which lives outside this repo.
```

- [ ] **Step 7: Verify the divergence list matches reality**

This is the check the whole task exists to make pass.

```bash
git diff flatcar/main main --stat | awk '{print $1}' | grep -v '^$' | grep '/' | sed 's#/[^/]*$##' | sort -u
grep -n 'tools/http-url-rewrite-server' AGENTS.md CLAUDE.md
```

Expected: every directory shown in the diff is accounted for in AGENTS.md's expected list, and both files now reference `tools/http-url-rewrite-server`.

- [ ] **Step 8: Confirm nothing outside the intended scope changed**

```bash
git diff flatcar/main main --stat -- \
  tools/http-url-rewrite-server/caddy.service \
  tools/http-url-rewrite-server/extensions.flatcar.org.yaml \
  .env README.md docs/
```

Expected: **empty output**. Any output means an out-of-scope file was modified; revert it.

- [ ] **Step 9: Commit**

```bash
git add AGENTS.md CLAUDE.md
git commit -m "docs: record the qopsc hub deployment as fork patch 9

Without this the next rebase onto flatcar/main deletes tools/http-url-rewrite-server
changes as undocumented drift."
```

---

## Done criteria

- [ ] `curl -sI https://extensions.quantumops.consulting/extensions/docker-28.5.2-x86-64.raw` returns `302` to a `github.com/qopsc/...` URL *(requires the DNS A record — external to this repo)*
- [ ] `bash -n tools/http-url-rewrite-server/install.sh` passes
- [ ] `docker compose config` in `tools/http-url-rewrite-server/` passes
- [ ] `git diff flatcar/main main --stat` shows only files listed in AGENTS.md
- [ ] `caddy.service`, `extensions.flatcar.org.yaml`, `.env`, root `README.md` and `docs/` are untouched

## Known follow-up, outside this plan

Create the `extensions.quantumops.consulting` A record in the ClouDNS zone, pointing at the Fedora host. Then run the installer, confirm a certificate is issued, and verify a released sysext's baked-in sysupdate source end to end. Close the AGENTS.md Known Issues entry at that point.
