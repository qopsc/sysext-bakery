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
# authenticate SHA256SUMS with the pinned restic release key, install the
# binary into the sysext root, and verify the installed version.
# Called by 'bakery.sh create restic' with sysextroot, arch, and version.
function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local rel_arch="$(arch_transform "x86-64" "amd64" "$arch")"
  local relver="${version#v}"
  local asset="restic_${relver}_linux_${rel_arch}.bz2"
  local checksums="SHA256SUMS"
  local checksums_sig="SHA256SUMS.asc"
  # Official restic release signing key (Alexander Neumann).
  # https://restic.net/gpg-key-alex.asc
  local restic_fpr="CF8F18F2844575973F79D4E191A6868BD3F7A907"
  local restic_key="${scriptroot}/restic.sysext/gpg-key-alex.asc"
  local base_url="https://github.com/restic/restic/releases/download/${version}"

  curl --parallel --fail --silent --show-error --location \
    --remote-name "${base_url}/${asset}" \
    --remote-name "${base_url}/${checksums}" \
    --remote-name "${base_url}/${checksums_sig}"

  if ! command -v gpg >/dev/null; then
    echo "ERROR: gpg is required to authenticate restic SHA256SUMS." >&2
    return 1
  fi

  local gnupghome
  gnupghome="$(pwd)/gnupg"
  mkdir -m 700 "${gnupghome}"

  if ! GNUPGHOME="${gnupghome}" gpg --batch --quiet \
        --no-default-keyring --keyring "${gnupghome}/restic.gpg" \
        --import "${restic_key}"; then
    echo "ERROR: failed to import restic release signing key." >&2
    return 1
  fi

  local imported
  imported="$(GNUPGHOME="${gnupghome}" gpg --batch --quiet --with-colons \
        --no-default-keyring --keyring "${gnupghome}/restic.gpg" \
        --fingerprint)"
  if ! awk -F: -v pin="${restic_fpr}" \
        '$1=="fpr" && $10==pin {found=1} END{exit !found}' <<< "${imported}"; then
    echo "ERROR: pinned restic signing key ${restic_fpr} not in ${restic_key}." >&2
    return 1
  fi

  local verify_status
  if ! verify_status="$(GNUPGHOME="${gnupghome}" gpg --batch \
        --no-default-keyring --keyring "${gnupghome}/restic.gpg" \
        --status-fd 1 --verify "${checksums_sig}" "${checksums}")"; then
    echo "ERROR: restic SHA256SUMS signature verification failed." >&2
    return 1
  fi
  if ! grep -q "^\[GNUPG:\] VALIDSIG ${restic_fpr} " <<< "${verify_status}"; then
    echo "ERROR: SHA256SUMS is not signed by the pinned restic key ${restic_fpr}." >&2
    return 1
  fi

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
