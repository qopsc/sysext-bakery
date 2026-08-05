# btop: rebuild from source for GPU monitoring

Date: 2026-08-05

## Problem

The `btop` extension repackaged Alpine's `btop` package with `tools/flatwrap.sh`. The
resulting extension cannot monitor GPUs, and could not be made to no matter how it was
configured. Three separate reasons stack up:

1. **Static builds have GPU support compiled out.** btop's `Makefile:96` only sets
   `-DGPU_SUPPORT` for Linux on x86_64 *when `STATIC != true`*. Every btop release asset
   upstream publishes is `btop-x86_64-unknown-linux-musl.tar.gz`, a static musl build, so
   the GPU code is absent from the shipped binaries.
2. **musl cannot load the NVIDIA driver.** `libnvidia-ml.so.1` is a glibc library. Even a
   non-static musl build (as Alpine produces) cannot dlopen it.
3. **flatwrap hides the host.** `flatwrap.sh` runs the program in a namespace where only
   `/dev /proc /sys /run /tmp /var/tmp` are bound. The driver libraries live outside that
   list.

## Decision

Build btop from source against glibc, and ship the binary directly.

| Question | Choice | Why |
|---|---|---|
| Packaging | Plain `/usr` tree, no helper | `flix.sh` sets `DF_1_NODEFLIB`, which breaks the NVML lookup (below). `flatwrap.sh` hides the driver. Neither can be used. |
| Build base | `debian:trixie-slim` | Needs GCC 14: btop 1.4.7 uses C++23 that GCC 12 (bookworm) rejects. AlmaLinux 9 (glibc 2.34) was tried for a lower floor, but btop's vendored Intel GPU code fails to compile there. |
| Linking | `STATIC=false`, `-static-libstdc++ -static-libgcc` | Static linking disables GPU support, so it is out. Statically linking just the C++ runtime leaves `libc`/`libm` as the only dynamic dependencies, so the image ships no C++ runtime and cannot conflict with the host's. |
| GPU support | `true` on x86-64, `false` on arm64 | btop only offers it on x86_64; asking for it on arm64 fails the build. |
| NVIDIA libraries | Not shipped | They belong to the driver. The official Flatcar drivers sysext merges them into `/usr`, where the default loader path finds them. |
| Version listing | `list_github_releases`, `v` stripped | Upstream tags are `v1.4.7`; published assets are `btop-1.4.7-…`. Unlike the Alpine source, old versions stay buildable. |
| Desktop files | Removed | `make install` writes a `.desktop` entry and icons, meaningless on Flatcar. Themes are kept. |

## The property this depends on

btop resolves GPU libraries at runtime by soname
(`src/linux/btop_collect.cpp:1234`), not at link time:

```cpp
//? Try possible library names for libnvidia-ml.so
"libnvidia-ml.so",
"libnvidia-ml.so.1",
```

A dlopen by soname is resolved through the loader's default search path. Two ELF
properties would defeat it, and neither may be introduced:

- `RPATH`/`RUNPATH` redirects the search away from the system directories.
- `DF_1_NODEFLIB` removes the default directories from the search entirely. This is what
  `patchelf --no-default-lib` sets, and it is why `tools/flix.sh` — otherwise the obvious
  choice, and what the `sqlite` extension uses — is unusable here.

`build.sh` asserts none of the three appear in the linked binary, so a future change that
reintroduces them fails the build rather than silently shipping a btop that never sees a
GPU.

## glibc floor

Building against a newer glibc than the target is safe up to a point: what matters is the
symbol *versions* the binary references, not the build host's glibc. The trixie build
references at most `GLIBC_2.38`, entirely from the `__isoc23_strtol` family that glibc's
headers redirect to when compiling in C23/C++23 mode.

Flatcar's channels, checked from `*.release.flatcar-linux.net`:

| Channel | Version | glibc |
|---|---|---|
| stable | 4593.2.4 | 2.41 |
| beta | 4722.1.0 | 2.42 |
| alpha | 4757.0.0 | 2.42 |
| lts | 4081.3.9 | 2.38 |

The binary starts on every current channel. `build.sh` nonetheless asserts a ceiling, so
that a toolchain bump cannot quietly produce an image that will not start on the oldest
target.

**The ceiling is 2.41, Flatcar stable's glibc. LTS is deliberately not a target.** This
fork deploys alpha, so LTS compatibility would be unused strictness: pinning the ceiling at
LTS's 2.38 would eventually fail a build over a target nobody here runs. Supporting LTS
again means lowering the ceiling to 2.38 and finding a build base with an older glibc and a
new enough GCC — which is not trivial, as the AlmaLinux 9 attempt above shows.

Note the assertion cannot fire while the build base is trixie, whose glibc 2.41 already
caps what the binary can reference. That is intended: it is a tripwire for the day the
build base moves ahead of the deployed fleet, which is exactly when a silent breakage
would otherwise slip through.

## Verification

Static properties of the x86-64 build:

```
$ readelf -d bin/btop | grep NEEDED
  libm.so.6      libc.so.6      ld-linux-x86-64.so.2
$ readelf -d bin/btop | grep -iE 'RPATH|RUNPATH|NODEFLIB'
  (none)
$ btop --version
  Configured with: make STATIC=false GPU_SUPPORT=true
```

That the NVML lookup actually reaches the default search path was confirmed rather than
argued. A stub `libnvidia-ml.so.1` was installed into the normal library directory of a
container that had never had btop or a driver, and btop was driven under a pty:

```
ERROR: NVML: Couldn't find function nvmlErrorString:
       /lib/x86_64-linux-gnu/libnvidia-ml.so.1: undefined symbol: nvmlErrorString
INFO:  Failed to load librocm_smi64.so, AMD GPUs will not be detected:
       librocm_smi64.so.6: cannot open shared object file: No such file or directory
DEBUG: Shared::init() : Initialized.
```

btop found and loaded the stub by soname from the default path, getting as far as
resolving symbols inside it — the stub exports none, hence the error. The AMD line in the
same log shows what a genuine *not found* looks like, which is what the NVIDIA line would
have said had the search path been restricted. With the real driver present, this is the
code path that populates the GPU panel.

The arm64 build was checked separately: it compiles under emulation, needs only `libc.so.6`
and the loader, and lands on the same `GLIBC_2.38` floor.

Remaining verification belongs on a real node with the drivers sysext merged, per the
procedure in `docs/btop.md`. It cannot be done here: no GPU, and no way to run a Flatcar
image on this host.

## Out of scope

Shipping the NVIDIA driver, ROCm, or terminfo. The host provides `/usr/share/terminfo`,
which is what btop's previous packaging relied on too. `.env`, `lib/`, `bakery.sh` and the
release scripts are untouched.
