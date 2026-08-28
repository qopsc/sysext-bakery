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
make DESTDIR=/staging install

cd /install_root
/tools/flix.sh /staging iperf3 /usr/bin/iperf3

installed="$(/install_root/iperf3/usr/bin/iperf3 --version | awk '{print $2}')"
if [ "${installed}" != "${version}" ]; then
  echo "ERROR: installed iperf3 version '${installed}' != requested '${version}'." >&2
  exit 1
fi

mv /install_root/iperf3/usr /install_root/usr
rmdir /install_root/iperf3

chown -R "${export_user_group}" /install_root/usr
