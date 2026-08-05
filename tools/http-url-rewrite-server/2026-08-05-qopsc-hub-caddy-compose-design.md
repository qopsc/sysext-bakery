# qopsc sysext hub: Caddy + docker compose + one-line installer

**Date:** 2026-08-05
**Status:** Approved, pending implementation

## Problem

`tools/http-url-rewrite-server/` carries upstream's deployment config for
`extensions.flatcar.org`. It is hardcoded to flatcar's hostname and GitHub org, and
its only run definition is a Flatcar/Ignition systemd unit wrapping `docker run`.

This fork publishes to `qopsc/sysext-bakery` and bakes
`https://extensions.quantumops.consulting/extensions/...` into the sysupdate `.conf`
inside every released sysext (`lib/sysupdate.conf.tmpl`). That hostname has never been
stood up, so node-side `systemd-sysupdate` does not work — recorded in AGENTS.md under
Known Issues.

Standing the hub up requires two things this repo does not have: a Caddy config pointing
at the qopsc fork, and a way to run it on the intended host.

## Target environment

A Fedora-based server with Docker and Compose v2 already installed. **Not** Flatcar, and
not provisioned by Ignition. This rules out the sysext/Ignition provisioning path and
makes `restart: unless-stopped` the replacement for the systemd unit.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| URL configuration | Hardcode qopsc values | Chosen over parameterising from `.env`. Directly readable; accepted cost is a permanent fork patch. |
| Flatcar files | Leave untouched | `caddy.service` and `extensions.flatcar.org.yaml` stay as upstream reference for a Flatcar deployment. |
| TLS | Caddy handles ACME | Let's Encrypt, contact `hello@quantumops.consulting`. |
| Catch-all target | `qopsc.github.io/sysext-bakery` | Verified live (HTTP 200); Pages is enabled on the fork. |
| Cert storage | Bind mounts | Certs visible on disk and backup-able by rsync. Matters because Let's Encrypt rate limits punish cert loss. |
| Installer | `curl \| bash`, stages then starts | One-command bring-up on a fresh host. |
| Spec location | Alongside the deployment files | Kept in `tools/http-url-rewrite-server/` with the config it describes. Not `docs/` — that is the Jekyll source for the live Pages site, so a spec there would be published and would require editing upstream's `_config.yml`. |

`.env` is **not** modified. `bakery_hub` is load-bearing — it is baked into already-released
images — and AGENTS.md patch 4 forbids casual changes. This work makes the existing value
resolve rather than changing it.

## Design

### Caddyfile

Three endpoint changes plus a global options block. All five `path_regexp` matchers and
their `redir` templates stay byte-identical; only the hostname and the redirect
destinations move.

- New first block (Caddy requires global options to precede all site blocks):
  ```
  {
      email hello@quantumops.consulting
  }
  ```
- Site block `extensions.flatcar.org` → `extensions.quantumops.consulting`
- `vars base_dest_url` → `https://github.com/qopsc/sysext-bakery/releases/download`
- Catch-all `redir` → `https://qopsc.github.io/sysext-bakery{uri}`
- Header comment's local-test snippet repointed from `docker run` to compose

### docker-compose.yml

```yaml
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy-webserver
    restart: unless-stopped
    ports: ["80:80", "443:443", "443:443/udp"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro,z
      - ./data:/data:z
      - ./config:/config:z
```

Four deliberate departures from the `caddy.service` it supersedes:

- **Bind mounts over named volumes.** `/data` holds ACME certificates. On disk they are
  visible and trivially backed up; losing them means re-issuing against Let's Encrypt rate
  limits.
- **No `user: 1001:1001`.** The old unit set it. Named-volume and bind-mount paths are
  root-owned, so a uid override needs a manual chown to work. The official image expects
  root and its binary carries `cap_net_bind_service`. Accepted tradeoff: the container runs
  as root.
- **No `/logs` mount.** The old unit mounted one, but the Caddyfile has no `log` directive,
  so nothing was ever written there. Logs go to Docker's driver, read via `docker compose logs`.
- **`443/udp` published** for HTTP/3, which the old unit omitted.

`:z` (shared SELinux relabel) is required on Fedora — without it the container cannot read
the Caddyfile or write to `./data`.

Image is pinned to the `2-alpine` tag rather than the old unit's bare `caddy` (`:latest`).

### install.sh

Invocation:

```sh
curl -fsSL https://raw.githubusercontent.com/qopsc/sysext-bakery/main/tools/http-url-rewrite-server/install.sh | bash
```

Follows repo script conventions: `#!/usr/bin/env bash`, `# vim: et ts=2 syn=bash`, Apache 2.0
header, `set -euo pipefail`, `# --` function separators.

**Truncation safety.** The entire body lives in functions, with `main "$@"` as the final line.
A partially-downloaded script defines functions and then ends without invoking anything, so an
interrupted transfer cannot execute a half-configured install.

**Flags**, usable under a pipe via `bash -s -- <flags>`:

| Flag | Default | Effect |
|---|---|---|
| `--dir <path>` | `$PWD` | Install target |
| `--ref <ref>` | `main` | Git ref to fetch from |
| `--force` | off | Overwrite existing `Caddyfile` / `docker-compose.yml` |
| `--no-up` | off | Stage only; skip `docker compose up -d` |

**Preflight — fatal:** `docker info` reachable (covers both "not installed" and "no permission"),
`docker compose version` reports v2, target directory writable.

**Preflight — warning only:**

- Ports 80 or 443 already bound.
- `extensions.quantumops.consulting` does not resolve, or does not resolve to this host.
  This warning is a primary feature, not a nicety: as of writing the A record does not exist,
  and ACME HTTP-01 will fail without it. Warning up front stops the operator burning Let's
  Encrypt failure attempts on a misconfigured DNS zone.

These warn rather than fail because both are legitimate mid-migration states.

**Fetch:** `curl -fsSL --proto '=https' --tlsv1.2` into `mktemp -d`, verify each file is
non-empty, then move into place. Downloading to temp first means a network failure cannot
leave a truncated `Caddyfile` where a valid one used to be. Refuses to overwrite an existing
`Caddyfile` or `docker-compose.yml` without `--force`, so re-running the one-liner cannot
silently discard local edits.

**Then:** `mkdir -p ./data ./config`, `docker compose up -d`, print `docker compose ps` and
next steps.

### tools/http-url-rewrite-server/README.md

Documents the one-liner, the DNS and port prerequisites, and how to back up `./data`.

A new file rather than an edit to the root `README.md`: that file is upstream-tracked and
currently diverges only for the temporary netbird work. Adding qopsc hosting content there
would create a rebase conflict for no benefit.

### AGENTS.md

The fork's sync procedure treats any file outside its documented divergence list as drift to
be removed. Left unrecorded, this entire change is deleted by the next rebase. So:

- Patch table row 9: `qopsc hub deployment | tools/http-url-rewrite-server/{Caddyfile,docker-compose.yml,install.sh,README.md} + the design and plan docs in that directory | policy`
- Same paths appended to the expected-divergence list under Upstream Sync Procedure
- Known Issues DNS entry annotated: hub config now exists and is deployable; only the A record is outstanding

## Out of scope

`caddy.service`, `extensions.flatcar.org.yaml`, `.env`, root `README.md`, `docs/`, and every
`docs/*.md` reference to `extensions.flatcar.org` — those track upstream and stay clean.

## Verification

1. `bash -n` on `install.sh` — matches the repo's own sync sanity-check
2. `docker compose config` — schema valid
3. `caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile` in-container — parses, and the global options block is accepted in first position
4. Redirect correctness. The Caddyfile's `:80` test block is commented out by default, so this
   runs against a scratch copy with `:80 {` uncommented and the domain line commented, per the
   Caddyfile's own header instructions. Testing the domain block directly does not work — Caddy
   answers a domain site on port 80 with a 308 to HTTPS before any matcher runs.
   `curl -sI http://localhost/extensions/docker-28.5.2-x86-64.raw` →
   `302`, `Location: https://github.com/qopsc/sysext-bakery/releases/download/docker-28.5.2/docker-28.5.2-x86-64.raw`
   Confirms all three endpoint edits at once: org, path construction, and that the matchers survived.
5. Installer run into a temp dir with `--no-up`: files land, `./data` and `./config` created,
   re-run without `--force` refuses to clobber
6. `git diff flatcar/main main --stat` — divergence matches the updated AGENTS.md list exactly

## Prerequisites outside this repo

- **DNS A record** `extensions.quantumops.consulting` → Fedora host IP. Until it exists, ACME
  fails and no certificate is issued. The installer warns.
- Ports 80/443 reachable. Docker normally bypasses firewalld for published ports.

## Follow-up

Once DNS resolves and a cert issues, verify a released sysext's baked-in sysupdate source end
to end, and close the AGENTS.md Known Issues entry.
