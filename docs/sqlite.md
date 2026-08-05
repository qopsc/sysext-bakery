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
