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
curl -fsSL https://raw.githubusercontent.com/qopsc/sysext-bakery/main/tools/http-url-rewrite-server/install.sh | bash -s -- --dir /opt/sysext-hub --no-up
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
