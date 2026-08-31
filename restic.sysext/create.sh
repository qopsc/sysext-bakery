#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# restic sysext.
#
# Ships the restic backup binary from upstream GitHub release assets.
#

RELOAD_SERVICES_ON_MERGE="false"

# Fetch and print a list of available restic releases from GitHub.
# Called by 'bakery.sh list restic'.
function list_available_versions() {
  list_github_releases "restic" "restic"
}
# --

# Download the restic binary for the requested version and architecture,
# verify it against SHA256SUMS, install it into the sysext root, and
# verify the installed version.
# Called by 'bakery.sh create restic' with sysextroot, arch, and version.
function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local rel_arch="$(arch_transform "x86-64" "amd64" "$arch")"
  local relver="${version#v}"
  local asset="restic_${relver}_linux_${rel_arch}.bz2"
  local checksums="SHA256SUMS"
  local base_url="https://github.com/restic/restic/releases/download/${version}"

  curl --parallel --fail --silent --show-error --location \
    --remote-name "${base_url}/${asset}" \
    --remote-name "${base_url}/${checksums}"

  grep -F "${asset}" "${checksums}" | sha256sum --check -

  mkdir -p "${sysextroot}/usr/bin"
  bzip2 -dc "${asset}" > restic
  install -m 0755 restic "${sysextroot}/usr/bin/restic"

  # qemu-user can run static Go binaries, but skip the runtime check on a
  # foreign arch anyway so a future dynamically-linked restic cannot abort
  # the arm64 image. release.sh builds x86-64 first, so the version
  # assertion still runs on the native arch.
  case "$(uname -m)" in
    x86_64) [[ "${arch}" == "x86-64" ]] || return 0 ;;
    aarch64|arm64) [[ "${arch}" == "arm64" ]] || return 0 ;;
  esac

  local installed_version
  installed_version="$("${sysextroot}/usr/bin/restic" version | awk '{print $2; exit}')"
  if [[ "${installed_version}" != "${relver}" ]] ; then
    echo "ERROR: installed restic version '${installed_version}' != requested '${relver}'." >&2
    return 1
  fi
}
# --
