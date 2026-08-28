# Arcane sysext

This sysext ships [Arcane](https://github.com/getarcaneapp/arcane), a modern Docker
management platform:

- `arcane-agent` at `/usr/bin/arcane-agent` — connects a Docker host to an Arcane manager
- `arcane-cli` at `/usr/bin/arcane-cli` — command-line client for the Arcane API

The extension includes `arcane-agent.service`, which starts the agent on port 3553 once
`/etc/arcane.d/arcane-agent.env` is populated. The unit carries `ConditionFileNotEmpty` on
that file, so the agent stays stopped until you configure it.

Populate the env file with at least:

- `AGENT_TOKEN` — agent API token from your Arcane manager
- `MANAGER_API_URL` — base URL of the manager (for example `http://10.1.1.4:3552`)

Optional settings such as `EDGE_TRANSPORT`, `PUID`, and `PGID` are documented in the
[upstream `.env.example`](https://github.com/getarcaneapp/arcane/blob/main/.env.example).

The agent needs access to the Docker API. Merge the [docker sysext](docker.md) (or another
runtime that exposes `/var/run/docker.sock`) alongside this one.

## Usage

The snippet below includes automated updates via systemd-sysupdate.
Sysupdate will stage updates, refresh the merged sysext, and restart `arcane-agent.service`
— no reboot is required.
You can deactivate updates by changing `enabled: true` to `enabled: false` in
`systemd-sysupdate.timer`.

Note that the snippet is for the x86-64 version of Arcane v2.9.0.

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
        source: https://extensions.quantumops.consulting/extensions/arcane-v2.9.0-x86-64.raw
    - path: /etc/sysupdate.arcane.d/arcane.conf
      contents:
        source: https://extensions.quantumops.consulting/extensions/arcane.conf
    - path: /etc/arcane.d/arcane-agent.env
      mode: 0600
      contents:
        inline: |
          AGENT_TOKEN=arc_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
          MANAGER_API_URL=http://10.1.1.4:3552
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
