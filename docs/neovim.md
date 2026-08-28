# neovim sysext

This sysext ships [Neovim](https://github.com/neovim/neovim) as `/usr/bin/nvim`, with
`/usr/bin/vim` and `/usr/bin/vi` as symlinks to the same binary. Scripts and tools that
invoke `vim` or `vi` — for example `kubectl edit` or `git commit` — therefore run Neovim.

Neovim is not bug-for-bug compatible with Vim. For interactive editing and most automation
it is close enough; plugin and scripting differences are documented upstream.

The binary comes from Neovim's official Linux release tarball and links dynamically against
the host glibc. Runtime files ship under `/usr/share/nvim` and tree-sitter parsers under
`/usr/lib/nvim`.

No services are installed and no state is created — merging the extension only adds the
editor binaries to `/usr/bin`.

## Usage

The snippet below includes automated updates via systemd-sysupdate.
Sysupdate will stage updates and refresh the merged sysext — no reboot is required.
You can deactivate updates by changing `enabled: true` to `enabled: false` in `systemd-sysupdate.timer`.

Note that the snippet is for the x86-64 version of Neovim 0.12.5.

Check out the metadata release at https://github.com/qopsc/sysext-bakery/releases/tag/neovim for a list of all versions available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/neovim/neovim-0.12.5-x86-64.raw
      mode: 0644
      contents:
        source: https://extensions.quantumops.consulting/extensions/neovim-0.12.5-x86-64.raw
    - path: /etc/sysupdate.neovim.d/neovim.conf
      contents:
        source: https://extensions.quantumops.consulting/extensions/neovim.conf
  links:
    - target: /opt/extensions/neovim/neovim-0.12.5-x86-64.raw
      path: /etc/extensions/neovim.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: neovim.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/neovim.raw > /tmp/neovim"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C neovim update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/neovim.raw > /tmp/neovim-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/neovim /tmp/neovim-new; then systemd-sysext refresh; fi"
```

## Versions

Versions track [Neovim GitHub releases](https://github.com/neovim/neovim/releases). Only
releases from v0.11.0 onward are supported — that is when upstream started publishing
`nvim-linux-x86_64` and `nvim-linux-arm64` tarballs.

## Building locally

```
./bakery.sh list neovim
./bakery.sh create neovim 0.12.5 --arch x86-64
```
