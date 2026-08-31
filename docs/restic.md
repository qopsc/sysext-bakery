# restic sysext

This sysext ships [restic](https://github.com/restic/restic), a fast, secure,
and efficient backup program. The binary is installed at `/usr/bin/restic`.

No services are installed and no state is created — merging the extension only
adds the `restic` command. Repositories, passwords, and backup timers stay on
the host; configure those separately.

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

Note that the snippet is for the x86-64 version of restic v0.19.1.

Check out the metadata release at
https://github.com/qopsc/sysext-bakery/releases/tag/restic for a list of all versions
available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/restic/restic-v0.19.1-x86-64.raw
      mode: 0644
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/restic-v0.19.1/restic-v0.19.1-x86-64.raw
    - path: /etc/sysupdate.restic.d/restic.conf
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/restic-v0.19.1/restic.conf
  links:
    - target: /opt/extensions/restic/restic-v0.19.1-x86-64.raw
      path: /etc/extensions/restic.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: restic.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/restic.raw > /tmp/restic"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C restic update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/restic.raw > /tmp/restic-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/restic /tmp/restic-new; then systemd-sysext refresh; fi"
```

## Building locally

```bash
./bakery.sh list restic
./bakery.sh create restic v0.19.1 --arch x86-64
```
