# eza sysext

This sysext ships [eza](https://github.com/eza-community/eza), a modern, maintained
replacement for `ls` with colours, icons, git integration, and tree views. The binary is
installed at `/usr/bin/eza`.

No services are installed and no state is created — merging the extension only adds the
`eza` command.

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

Note that the snippet is for the x86-64 version of eza v0.23.5.

Check out the metadata release at
https://github.com/qopsc/sysext-bakery/releases/tag/eza for a list of all versions
available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/eza/eza-v0.23.5-x86-64.raw
      mode: 0644
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/eza-v0.23.5/eza-v0.23.5-x86-64.raw
    - path: /etc/sysupdate.eza.d/eza.conf
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/eza-v0.23.5/eza.conf
  links:
    - target: /opt/extensions/eza/eza-v0.23.5-x86-64.raw
      path: /etc/extensions/eza.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: eza.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/eza.raw > /tmp/eza"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C eza update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/eza.raw > /tmp/eza-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/eza /tmp/eza-new; then systemd-sysext refresh; fi"
```

## Building locally

```bash
./bakery.sh list eza
./bakery.sh create eza v0.23.5 --arch x86-64
```
