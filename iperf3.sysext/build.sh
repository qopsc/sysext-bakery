#!/bin/ash
#
# Build script helper for iperf3 sysext.
# This script runs inside an ephemeral Alpine container.
#
set -euo pipefail

version="$1"
export_user_group="$2"

apk --no-cache add \
  build-base \
  make \
  openssl-dev \
  bash \
  coreutils \
  grep \
  patchelf

cd /opt
tar xf "/install_root/iperf-${version}.tar.gz"
cd "iperf-${version}"

./configure --prefix=/usr
make -j"$(nproc)"
make install

# Assert against the just-installed binary, before flix.sh rewrites its
# interpreter to /usr/local/iperf3/ld-musl-*.so.1. That path only exists
# inside the sysext tree, so executing the flixed binary in this container
# reports "not found" even though the file is there (same as sqlite:
# version-check, then flix).
# --version is multi-line ("iperf 3.21 ...", hostname, "Optional features
# available: ..."). awk '{print $2}' on every line concatenates
# "3.21\\n<hostname>\\nfeatures" and fails the equality check.
installed="$(/usr/bin/iperf3 --version | awk 'NR==1 {print $2; exit}')"
if [ "${installed}" != "${version}" ]; then
  echo "ERROR: installed iperf3 version '${installed}' != requested '${version}'." >&2
  exit 1
fi

# flix.sh resolves the musl loader relative to FOLDER. Installing into
# DESTDIR=/staging leaves /lib/ld-musl-*.so.1 in the Alpine root, so
# FOLDER must be / (same pattern as sqlite).
cd /install_root
/tools/flix.sh / iperf3 /usr/bin/iperf3

mv /install_root/iperf3/usr /install_root/usr
rmdir /install_root/iperf3

chown -R "${export_user_group}" /install_root/usr
