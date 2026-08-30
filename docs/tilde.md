# tilde sysext

This sysext ships [Tilde](https://os.ghalkes.nl/tilde/), a console text editor with an
intuitive, GUI-like interface (menus, dialogs, and standard shortcut keys). The binary is
installed at `/usr/bin/tilde`.

The editor comes from Debian bookworm's `tilde` package. `flix.sh` bundles the binary
and its T3 libraries (libt3widget, transcript) into the image, so nothing is required
from the host beyond a terminfo database. Flatcar ships `/usr/share/terminfo`; the
extension does not duplicate it.

No services are installed and no state is created — merging the extension only adds the
`tilde` command.

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

Note that the snippet is for the x86-64 version of tilde 1.1.2.

Check out the metadata release at
https://github.com/qopsc/sysext-bakery/releases/tag/tilde for a list of all versions
available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/tilde/tilde-1.1.2-x86-64.raw
      mode: 0644
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/tilde-1.1.2/tilde-1.1.2-x86-64.raw
    - path: /etc/sysupdate.tilde.d/tilde.conf
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/tilde-1.1.2/tilde.conf
  links:
    - target: /opt/extensions/tilde/tilde-1.1.2-x86-64.raw
      path: /etc/extensions/tilde.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: tilde.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/tilde.raw > /tmp/tilde"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C tilde update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/tilde.raw > /tmp/tilde-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/tilde /tmp/tilde-new; then systemd-sysext refresh; fi"
```

## Versions

Versions track Debian bookworm's `tilde` package. Bookworm currently publishes 1.1.2; the
bakery's `latest` line resolves that same package page.

## Building locally

```bash
./bakery.sh list tilde
./bakery.sh create tilde 1.1.2 --arch x86-64
```
