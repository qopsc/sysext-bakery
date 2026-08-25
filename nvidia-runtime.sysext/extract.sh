#!/bin/sh
#
# Extract NVIDIA userspace binaries from the official ubuntu18.04 DEB packages.
# Runs on the bakery host when dpkg-deb is available, otherwise inside an
# ephemeral Alpine container (which installs dpkg first).
#
# Official toolkit debs often omit a 0755 './' member, and dpkg-deb then chmods
# the destination to 0644. A second extract into the same directory fails with
# "failed to chdir to directory: Permission denied". Extract each deb into its
# own temp dir, restore u+rwx, then merge.
#
set -eu

pkgdir="$1"
outdir="$2"
export_user_group="${3:-}"

if ! command -v dpkg-deb >/dev/null 2>&1; then
  apk --no-cache add dpkg
fi

mkdir -p "${outdir}"
chmod u+rwx "${outdir}"

found=0
for deb in "${pkgdir}"/nvidia-container-toolkit*.deb \
        "${pkgdir}"/libnvidia-container1_*.deb \
        "${pkgdir}"/libnvidia-container-tools*.deb; do
  [ -f "${deb}" ] || continue
  work="$(mktemp -d)"
  dpkg-deb -x "${deb}" "${work}"
  chmod u+rwx "${work}"
  # Nested dirs from the archive can also lack +x when './' was 0644.
  chmod -R u+rwX "${work}"
  cp -a "${work}"/. "${outdir}"/
  rm -rf "${work}"
  found=1
done

if [ "${found}" -eq 0 ]; then
  echo "ERROR: no NVIDIA toolkit/libnvidia-container debs in ${pkgdir}" >&2
  exit 1
fi

chmod -R u+rwX "${outdir}"

if [ -n "${export_user_group}" ]; then
  chown -R "${export_user_group}" "${outdir}"
fi
