#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# iperf3 sysext.
#
# Ships the iperf3 network throughput benchmark built from upstream GitHub
# release source tarballs.
#

RELOAD_SERVICES_ON_MERGE="false"

# Fetch and print a list of available iperf3 releases from GitHub.
# Called by 'bakery.sh list iperf3'.
function list_available_versions() {
  # esnet/iperf tags stable releases as "3.21" but also publishes beta tags
  # like "3.16-beta1" that are not marked prerelease on GitHub.
  list_github_releases "esnet" "iperf" \
    | grep -E '^[0-9]+(\.[0-9]+)+$'
}
# --

# Download the iperf3 source tarball for the requested version, build the
# binary for the target architecture, and verify the installed version.
# Called by 'bakery.sh create iperf3' with sysextroot, arch, and version.
function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local img_arch="$(arch_transform 'x86-64' 'amd64' "$arch")"
  img_arch="$(arch_transform 'arm64' 'arm64/v8' "$img_arch")"

  local tarball="iperf-${version}.tar.gz"
  local base_url="https://github.com/esnet/iperf/releases/download/${version}"

  curl --parallel --fail --silent --show-error --location \
    --remote-name "${base_url}/${tarball}" \
    --remote-name "${base_url}/${tarball}.sha256"

  grep -F "${tarball}" "${tarball}.sha256" | sha256sum --check -

  announce "Building iperf3 ${version} for ${arch}"

  local user_group="$(id -u):$(id -g)"

  cp "${scriptroot}/iperf3.sysext/build.sh" .
  docker run --rm \
    -i \
    -v "${scriptroot}/tools/":/tools \
    -v "$(pwd)":/install_root \
    --platform "linux/${img_arch}" \
    --network host \
    docker.io/alpine:3.21 \
    /install_root/build.sh "${version}" "$user_group"

  cp -aR usr "${sysextroot}"/
}
# --
