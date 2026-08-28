# dust sysext

This sysext ships [dust](https://github.com/bootandy/dust), a more intuitive alternative
to `du` for inspecting disk usage. The binary is installed at `/usr/bin/dust`.

No services are installed and no state is created — merging the extension only adds the
`dust` command.

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
Sysupdate will stage updates and refresh the merged sysext — no reboot is required.
You can deactivate updates by changing `enabled: true` to `enabled: false` in
`systemd-sysupdate.timer`.

Note that the snippet is for the x86-64 version of dust v1.2.5.

Check out the metadata release at
https://github.com/qopsc/sysext-bakery/releases/tag/dust for a list of all versions
available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/dust/dust-v1.2.5-x86-64.raw
      mode: 0644
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/dust-v1.2.5/dust-v1.2.5-x86-64.raw
    - path: /etc/sysupdate.dust.d/dust.conf
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/dust-v1.2.5/dust.conf
  links:
    - target: /opt/extensions/dust/dust-v1.2.5-x86-64.raw
      path: /etc/extensions/dust.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: dust.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/dust.raw > /tmp/dust"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C dust update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/dust.raw > /tmp/dust-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/dust /tmp/dust-new; then systemd-sysext refresh; fi"
```

## Building locally

```bash
./bakery.sh list dust
./bakery.sh create dust v1.2.5 --arch x86-64
```
