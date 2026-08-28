#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Arcane agent and CLI system extension.
#
# Ships arcane-agent (Docker host agent) and arcane-cli (management CLI)
# from upstream GitHub release assets.
#

RELOAD_SERVICES_ON_MERGE="true"

function list_available_versions() {
  list_github_releases "getarcaneapp" "arcane"
}
# --

function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local rel_arch="$(arch_transform "x86-64" "amd64" "$arch")"
  local relver="${version#v}"

  local agent_asset="arcane-agent_linux_${rel_arch}"
  local cli_tarball="arcane-cli_linux_${rel_arch}.tar.gz"
  local checksums="arcane_${relver}_checksums.txt"
  local base_url="https://github.com/getarcaneapp/arcane/releases/download/${version}"

  curl --parallel --fail --silent --show-error --location \
    --remote-name "${base_url}/${agent_asset}" \
    --remote-name "${base_url}/${cli_tarball}" \
    --remote-name "${base_url}/${checksums}"

  grep -F "${agent_asset}" "${checksums}" | sha256sum --check -
  grep -F "${cli_tarball}" "${checksums}" | sha256sum --check -

  mkdir -p "${sysextroot}/usr/bin" extract
  install -m 0755 "${agent_asset}" "${sysextroot}/usr/bin/arcane-agent"

  tar --force-local -xf "${cli_tarball}" -C extract arcane-cli
  install -m 0755 extract/arcane-cli "${sysextroot}/usr/bin/arcane-cli"

  local installed_version
  installed_version="$("${sysextroot}/usr/bin/arcane-agent" version | awk '/^Arcane version:/ {print $3}')"
  if [[ "${installed_version}" != "${relver}" ]] ; then
    echo "ERROR: installed arcane-agent version '${installed_version}' != requested '${relver}'." >&2
    return 1
  fi
}
# --
