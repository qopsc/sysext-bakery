# Arcane sysext

This sysext ships [Arcane](https://github.com/getarcaneapp/arcane), a modern Docker
management platform:

- `arcane-agent` at `/usr/bin/arcane-agent` — connects a Docker host to an Arcane manager
- `arcane-cli` at `/usr/bin/arcane-cli` — command-line client for the Arcane API

The extension includes `arcane-agent.service`, which starts the agent on port 3553 once
`/etc/arcane.d/arcane-agent.env` is populated. The unit carries `ConditionFileNotEmpty` on
that file, so the agent stays stopped until you configure it.

The unit sets `PORT=3553` and `GIN_MODE=release` to match
`docker/Dockerfile-agent`. Those are image `ENV` values, not binary defaults —
`config.go` declares `PORT` as `"3552"`, and this sysext ships the bare binary —
so without the unit lines the agent would bind `:3552` while every published
example says 3553. `AGENT_MODE=true` stays in the unit (same as the official
agent image). For an edge agent, add `EDGE_AGENT=true` to the env file; Arcane
then keeps agent mode and selects the outbound tunnel. The env file overrides
unit `Environment=` values, so you do not need a systemd drop-in to change mode
or bind address.

Populate the env file with at least:

- `AGENT_TOKEN` — agent API token from your Arcane manager
- `MANAGER_API_URL` — base URL of the manager (for example `http://10.1.1.4:3552`)
- `LISTEN` — bind address. **Unset means every interface.** A host service has no
  network namespace, and this agent proxies the Docker API, so an unset `LISTEN`
  publishes root-equivalent access on every address the host has. Set
  `LISTEN=127.0.0.1` for an edge agent — the edge tunnel client dials its own
  listener over loopback, so nothing else needs to reach it — or the
  management-network address for a direct agent.

Optional settings such as `EDGE_AGENT`, `EDGE_TRANSPORT`, `PUID`, and `PGID` are
documented in the
[upstream `.env.example`](https://github.com/getarcaneapp/arcane/blob/main/.env.example).

The agent needs access to the Docker API. Merge the [docker sysext](docker.md) (or another
runtime that exposes `/var/run/docker.sock`) alongside this one.

## Installation sources

`extensions.quantumops.consulting` (the qopsc bakery hub) **does not resolve yet** — see
`AGENTS.md` Known Issues. Until the hub A record is deployed, fetch release assets directly
from GitHub. Automated sysupdate via the hub URLs baked into released images will not work
on nodes until the hub is live.

Once the hub is deployed, you can switch the example URLs below to
`https://extensions.quantumops.consulting/extensions/...` (that is also what the sysupdate
`.conf` shipped inside released images points at).

## Usage

The snippet below uses GitHub release URLs that work today. It also includes automated
updates via systemd-sysupdate.
Sysupdate will stage updates, refresh the merged sysext, and restart `arcane-agent.service`
— no reboot is required.
You can deactivate updates by changing `enabled: true` to `enabled: false` in
`systemd-sysupdate.timer`.

Note that the snippet is for the x86-64 version of Arcane v2.9.0. It is a
direct agent: `LISTEN` is the address the manager must be able to reach. For an
edge agent, add `EDGE_AGENT=true` and set `LISTEN=127.0.0.1` instead.

Check out the metadata release at
https://github.com/qopsc/sysext-bakery/releases/tag/arcane for a list of all versions
available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/arcane/arcane-v2.9.0-x86-64.raw
      mode: 0644
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/arcane-v2.9.0/arcane-v2.9.0-x86-64.raw
    - path: /etc/sysupdate.arcane.d/arcane.conf
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/arcane-v2.9.0/arcane.conf
    - path: /etc/arcane.d/arcane-agent.env
      mode: 0600
      contents:
        inline: |
          AGENT_TOKEN=arc_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
          MANAGER_API_URL=http://10.1.1.4:3552
          LISTEN=10.1.1.5
  links:
    - target: /opt/extensions/arcane/arcane-v2.9.0-x86-64.raw
      path: /etc/extensions/arcane.raw
      hard: false
systemd:
  units:
    - name: arcane-agent.service
      enabled: true
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: arcane.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/arcane.raw > /tmp/arcane"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C arcane update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/arcane.raw > /tmp/arcane-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/arcane /tmp/arcane-new; then systemd-sysext refresh && systemctl restart arcane-agent.service; fi"
```

## Building locally

```
./bakery.sh list arcane
./bakery.sh create arcane v2.9.0 --arch x86-64
```
