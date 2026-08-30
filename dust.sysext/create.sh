#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# dust sysext.
#
# Ships the dust disk-usage utility from upstream GitHub release assets.
#

RELOAD_SERVICES_ON_MERGE="false"

# Fetch and print a list of available dust releases from GitHub.
# Called by 'bakery.sh list dust'.
function list_available_versions() {
  list_github_releases "bootandy" "dust"
}
# --

# Download the dust binary for the requested version and architecture,
# install it into the sysext root, and verify the installed version.
# Called by 'bakery.sh create dust' with sysextroot, arch, and version.
function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local rust_arch
  case "${arch}" in
    x86-64) rust_arch="x86_64-unknown-linux-gnu" ;;
    arm64)  rust_arch="aarch64-unknown-linux-gnu" ;;
    *)
      echo "ERROR: unsupported architecture '${arch}' for dust." >&2
      return 1
      ;;
  esac

  local relver="${version#v}"
  local tarball="dust-${version}-${rust_arch}.tar.gz"
  local base_url="https://github.com/bootandy/dust/releases/download/${version}"

  curl --fail --silent --show-error --location \
    --remote-name "${base_url}/${tarball}"

  mkdir -p "${sysextroot}/usr/bin" extract
  tar --force-local -xf "${tarball}" -C extract \
    "dust-${version}-${rust_arch}/dust"
  install -m 0755 "extract/dust-${version}-${rust_arch}/dust" \
    "${sysextroot}/usr/bin/dust"

  # qemu-user on an x86-64 builder cannot run the aarch64-gnu binary
  # (host has no /lib/ld-linux-aarch64.so.1). release.sh builds x86-64
  # first, so the version assertion still runs on the native arch.
  case "$(uname -m)" in
    x86_64) [[ "${arch}" == "x86-64" ]] || return 0 ;;
    aarch64|arm64) [[ "${arch}" == "arm64" ]] || return 0 ;;
  esac

  local installed_version
  installed_version="$("${sysextroot}/usr/bin/dust" --version | awk '{print $2}')"
  if [[ "${installed_version}" != "${relver}" ]] ; then
    echo "ERROR: installed dust version '${installed_version}' != requested '${relver}'." >&2
    return 1
  fi
}
# --
