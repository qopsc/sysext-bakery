# btop sysext

This sysext ships [btop++](https://github.com/aristocratos/btop), a resource monitor for
CPU, memory, disks, network and processes.

On x86-64 the extension also monitors GPUs: NVIDIA (via NVML), AMD (via ROCm SMI) and
Intel. On arm64 GPU support is not available, because btop only offers it on x86-64.

btop is built from source for this extension instead of repackaging an upstream release.
Every published btop release asset is a fully static musl build, and btop's Makefile turns
GPU support off for static builds, so an upstream asset can never report GPU stats. The
build here links against glibc dynamically and links the C++ runtime statically, so the
image ships only the binary and its themes.

No services are installed and no state is created — merging the extension adds `btop` to
`/usr/bin`.

## GPU monitoring

btop does not link against the NVIDIA or AMD libraries. It looks them up at runtime by
name (`libnvidia-ml.so.1`, `librocm_smi64.so`) using the loader's normal search path. It
degrades gracefully: if a library is absent, btop logs the fact and simply shows no GPU
panel.

For NVIDIA GPUs this means the driver libraries must be present on the host. Merge the
[NVIDIA drivers sysext](https://www.flatcar.org/docs/latest/setup/customization/using-nvidia-gpus/)
alongside this one — it installs the driver userspace into `/usr`, where the loader finds
it without further configuration. No drop-in, no `LD_LIBRARY_PATH`, and nothing to set in
this extension.

To confirm detection on a node:

```
btop --debug        # then quit with q
grep -iE 'nvidia|nvml|gpu' ~/.local/state/btop.log
```

A working setup logs no NVML failure and shows a GPU panel. `Failed to load
libnvidia-ml.so` means the driver sysext is missing or not merged.

btop needs a UTF-8 locale and an interactive terminal. If it exits with `No UTF-8 locale
detected`, start it as `btop --force-utf`.

## Usage

The snippet below includes automated updates via systemd-sysupdate.
Sysupdate will stage updates and refresh the merged sysext — no reboot is required.
You can deactivate updates by changing `enabled: true` to `enabled: false` in `systemd-sysupdate.timer`.

Note that the snippet is for the x86-64 version of btop 1.4.7.

Check out the metadata release at https://github.com/qopsc/sysext-bakery/releases/tag/btop for a list of all versions available in the bakery.

```yaml
variant: flatcar
version: 1.0.0

storage:
  files:
    - path: /opt/extensions/btop/btop-1.4.7-x86-64.raw
      mode: 0644
      contents:
        source: https://extensions.quantumops.consulting/extensions/btop-1.4.7-x86-64.raw
    - path: /etc/sysupdate.btop.d/btop.conf
      contents:
        source: https://extensions.quantumops.consulting/extensions/btop.conf
  links:
    - target: /opt/extensions/btop/btop-1.4.7-x86-64.raw
      path: /etc/extensions/btop.raw
      hard: false
systemd:
  units:
    - name: systemd-sysupdate.timer
      enabled: true
    - name: systemd-sysupdate.service
      dropins:
        - name: btop.conf
          contents: |
            [Service]
            ExecStartPre=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/btop.raw > /tmp/btop"
            ExecStartPre=/usr/lib/systemd/systemd-sysupdate -C btop update
            ExecStartPost=/usr/bin/sh -c "readlink --canonicalize /etc/extensions/btop.raw > /tmp/btop-new"
            ExecStartPost=/usr/bin/sh -c "if ! cmp --silent /tmp/btop /tmp/btop-new; then systemd-sysext refresh; fi"
```

## Versions

Versions follow btop's GitHub releases, with the leading `v` of the upstream tag dropped.
Any release can be rebuilt, since the source for old tags remains available.

## Building locally

```
./bakery.sh list btop
./bakery.sh create btop 1.4.7 --arch x86-64
```

The build runs in a Debian trixie container and takes about a minute per architecture;
arm64 is built under emulation and is slower.
