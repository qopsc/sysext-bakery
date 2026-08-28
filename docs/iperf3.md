# iperf3 sysext

This sysext ships [iperf3](https://github.com/esnet/iperf), a tool for measuring
network throughput using TCP, UDP, and SCTP. The binary is installed at
`/usr/bin/iperf3`.

No services are installed and no state is created — merging the extension only
adds the `iperf3` command.

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

Note that the snippet is for the x86-64 version of iperf3 3.21.

Check out the metadata release at
https://github.com/qopsc/sysext-bakery/releases/tag/iperf3 for a list of all versions
available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/iperf3/iperf3-3.21-x86-64.raw
      mode: 0644
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/iperf3-3.21/iperf3-3.21-x86-64.raw
    - path: /etc/sysupdate.iperf3.d/iperf3.conf
      contents:
        source: https://github.com/qopsc/sysext-bakery/releases/download/iperf3-3.21/iperf3.conf
  links:
    - target: /opt/extensions/iperf3/iperf3-3.21-x86-64.raw
      path: /etc/extensions/iperf3.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: iperf3.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/iperf3.raw > /tmp/iperf3"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C iperf3 update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/iperf3.raw > /tmp/iperf3-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/iperf3 /tmp/iperf3-new; then systemd-sysext refresh; fi"
```

## Building locally

```bash
./bakery.sh list iperf3
./bakery.sh create iperf3 3.21 --arch x86-64
```
