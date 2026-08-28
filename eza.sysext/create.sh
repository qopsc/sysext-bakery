#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# eza sysext.
#
# Ships the eza directory listing utility from upstream GitHub release assets.
#

RELOAD_SERVICES_ON_MERGE="false"

# Fetch and print a list of available eza releases from GitHub.
# Called by 'bakery.sh list eza'.
function list_available_versions() {
  list_github_releases "eza-community" "eza"
}
# --

# Download the eza binary for the requested version and architecture,
# install it into the sysext root, and verify the installed version.
# Called by 'bakery.sh create eza' with sysextroot, arch, and version.
function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local rust_arch
  case "${arch}" in
    x86-64) rust_arch="x86_64-unknown-linux-gnu" ;;
    arm64)  rust_arch="aarch64-unknown-linux-gnu" ;;
    *)
      echo "ERROR: unsupported architecture '${arch}' for eza." >&2
      return 1
      ;;
  esac

  local tarball="eza_${rust_arch}.tar.gz"
  local base_url="https://github.com/eza-community/eza/releases/download/${version}"

  curl --fail --silent --show-error --location \
    --remote-name "${base_url}/${tarball}"

  mkdir -p "${sysextroot}/usr/bin" extract
  tar --force-local -xf "${tarball}" -C extract ./eza
  install -m 0755 "extract/eza" "${sysextroot}/usr/bin/eza"

  local installed_version
  installed_version="$("${sysextroot}/usr/bin/eza" --version \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' \
    | head -1)"
  if [[ "${installed_version}" != "${version}" ]] ; then
    echo "ERROR: installed eza version '${installed_version}' != requested '${version}'." >&2
    return 1
  fi
}
# --
