#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# NVIDIA runtime (userspace tools) extension.
#

RELOAD_SERVICES_ON_MERGE="false"

function list_available_versions() {
  list_github_releases "NVIDIA" "nvidia-container-toolkit"
}
# --

# NVIDIA's v1.20.0 packaging fix (PR #1827) moved nvidia-cdi-refresh units from
# /etc/systemd to /lib/systemd. The previous bakery recipe compiled ubuntu18.04
# packages from source and then copied out/etc/systemd/, so the v1.20.0 "latest"
# GitHub Actions build died on that cp under set -e. Official release tarballs
# already ship the same ubuntu18.04 debs the source build produced — consume
# those instead of compiling (and of applying the v1.18.1-only go.dev / submodule
# patches that the source path needed).
function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local rel_arch="$(arch_transform "x86-64" "amd64" "$arch")"
  local rel_version="${version#v}"
  local tarball="nvidia-container-toolkit_${rel_version}_deb_${rel_arch}.tar.gz"
  local checksums="nvidia-container-toolkit_${rel_version}_checksums.txt"
  local base_url="https://github.com/NVIDIA/nvidia-container-toolkit/releases/download/${version}"

  announce "Downloading NVIDIA container toolkit ${version} packages."

  curl --parallel --fail --silent --show-error --location \
    --remote-name "${base_url}/${tarball}" \
    --remote-name "${base_url}/${checksums}"

  local expected
  expected="$(awk -v t="${tarball}" '
    {
      n = $2
      sub(".*/", "", n)
      if (n == t) { print $1; exit }
    }' "${checksums}")"
  if [[ -z "${expected}" ]]; then
    echo "ERROR: ${tarball} not listed in upstream checksums file." >&2
    return 1
  fi
  echo "${expected}  ${tarball}" | sha256sum -c -

  tar --force-local -xf "${tarball}"

  local pkgdir
  pkgdir="$(find . -type d -path "*/packages/ubuntu18.04/${rel_arch}" -print -quit)"
  if [[ -z "${pkgdir}" ]]; then
    echo "ERROR: ubuntu18.04/${rel_arch} packages not found in ${tarball}." >&2
    return 1
  fi

  mkdir -p out
  announce "Extracting NVIDIA user space tools from DEB packages."
  _extract_nvidia_debs "${pkgdir}" "$(pwd)/out"

  rm -rf out/usr/share

  mkdir -p "${sysextroot}/usr/bin/"
  mkdir -p "${sysextroot}/usr/lib64/"
  mkdir -p "${sysextroot}/usr/local/"
  mkdir -p "${sysextroot}/usr/lib/systemd/"
  mkdir -p "${sysextroot}/usr/share/flatcar/etc/"

  # v1.19.x and earlier installed units under /etc/systemd; v1.20.0+ uses /lib/systemd.
  if [[ -d out/etc/systemd ]]; then
    cp -aR out/etc/systemd/. "${sysextroot}/usr/lib/systemd/"
  fi
  if [[ -d out/lib/systemd ]]; then
    cp -aR out/lib/systemd/. "${sysextroot}/usr/lib/systemd/"
  fi
  if [[ -d out/etc/nvidia-container-toolkit ]]; then
    cp -aR out/etc/nvidia-container-toolkit "${sysextroot}/usr/share/flatcar/etc/"
  fi
  cp -aR out/usr/bin/* "${sysextroot}/usr/bin/"
  cp -aR out/usr/lib/*-linux-gnu/* "${sysextroot}/usr/lib64/"

  ln -s /opt/nvidia "${sysextroot}/usr/local/nvidia"
}
# --

function _extract_nvidia_debs() {
  local pkgdir="$1"
  local outdir="$2"

  if command -v dpkg-deb >/dev/null 2>&1; then
    "${scriptroot}/nvidia-runtime.sysext/extract.sh" "${pkgdir}" "${outdir}"
    return
  fi

  # Hosts without dpkg (e.g. Fedora) extract inside an ephemeral Alpine container,
  # matching the previous bakery helper.
  local export_user_group="$(id -u):$(id -g)"
  mkdir -p in/pkgs
  cp -a "${pkgdir}"/*.deb in/pkgs/
  cp "${scriptroot}/nvidia-runtime.sysext/extract.sh" in/extract.sh
  docker run -i --rm \
             -v "$(pwd)/in":/in \
             -v "${outdir}":/out \
             alpine \
             /in/extract.sh /in/pkgs /out "${export_user_group}"
}
# --
