#!/usr/bin/env bash
#
# Build script helper for the btop sysext.
# This script runs inside an ephemeral Debian container.
#
# It builds btop from source rather than repackaging an upstream release,
# because every published btop release asset is a static musl build, and the
# Makefile disables GPU support for static builds (Makefile:96). A static musl
# btop therefore cannot monitor NVIDIA GPUs no matter how it is packaged.
#
set -euo pipefail

version="$1"
export_user_group="$2"
gpu_support="$3"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  git \
  ca-certificates \
  make \
  g++ \
  binutils

cd /opt
git clone -q --depth 1 --branch "v${version}" --single-branch \
  https://github.com/aristocratos/btop.git
cd btop

# -static-libstdc++ / -static-libgcc leave only libc and libm as dynamic
# dependencies, so the sysext does not have to ship a C++ runtime or care
# which one Flatcar has. Note we deliberately do NOT link fully static: that
# would turn off GPU support and break the dlopen described below.
make STATIC=false GPU_SUPPORT="${gpu_support}" \
     ADDFLAGS="-static-libstdc++ -static-libgcc"

# btop finds GPUs by dlopen'ing libnvidia-ml.so.1 and librocm_smi64.so by
# soname (src/linux/btop_collect.cpp:1234). Those libraries belong to the
# driver and are supplied by a separate sysext, so they can only be resolved
# through the loader's default search path. Anything that sets RPATH/RUNPATH
# or the DF_1_NODEFLIB flag would break GPU detection, which is why this
# extension cannot be packaged with tools/flix.sh.
if readelf -d bin/btop | grep -qiE 'RPATH|RUNPATH|NODEFLIB'; then
  echo "ERROR: btop was linked with RPATH/RUNPATH/NODEFLIB set." >&2
  echo "       GPU libraries are resolved via the default search path and" >&2
  echo "       would no longer be found. Refusing to publish this build." >&2
  readelf -d bin/btop >&2
  exit 1
fi

# The binary must start on the oldest Flatcar we support. Symbol versions,
# not the build host's glibc, decide that: this is built against a newer
# glibc but only references symbols up to the version asserted here.
#
# The floor is Flatcar stable's glibc. LTS (2.38) is deliberately not a
# target for this fork. Raising the floor further would only be meaningful
# alongside a newer build base, since the base's own glibc caps what the
# binary can possibly reference.
glibc_floor="2.41"
max_glibc="$(objdump -T bin/btop \
  | grep -o 'GLIBC_[0-9.]*' \
  | sed 's/GLIBC_//' \
  | sort -V \
  | tail -1)"
if [ "$(printf '%s\n%s\n' "${max_glibc}" "${glibc_floor}" | sort -V | tail -1)" != "${glibc_floor}" ]; then
  echo "ERROR: btop requires glibc ${max_glibc}, newer than the ${glibc_floor} floor." >&2
  echo "       It would fail to start on Flatcar stable. Refusing to publish." >&2
  exit 1
fi
echo "btop requires at most glibc ${max_glibc} (floor is ${glibc_floor})"

make install PREFIX=/install_root/usr

# Ships /usr only. The desktop entry and icons are meaningless on Flatcar;
# the themes are what make btop usable, so those stay.
rm -rf /install_root/usr/share/applications \
       /install_root/usr/share/icons

chown -R "${export_user_group}" /install_root/usr
