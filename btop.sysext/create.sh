#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# btop sysext.
#

RELOAD_SERVICES_ON_MERGE="false"

function list_available_versions() {
  # Upstream tags are "v1.4.7"; published sysext assets are "btop-1.4.7-...",
  # so strip the leading v to stay consistent with what has already shipped.
  list_github_releases "aristocratos" "btop" \
    | sed -e 's/^v//'
}
# --

function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local img_arch="$(arch_transform 'x86-64' 'amd64' "$arch")"
  img_arch="$(arch_transform 'arm64' 'arm64/v8' "$img_arch")"

  # btop's Makefile only offers GPU support on x86_64 (Makefile:96), so asking
  # for it on arm64 would fail the build rather than be ignored.
  local gpu_support=false
  if [ "${arch}" = "x86-64" ]; then
    gpu_support=true
  fi

  # Debian trixie for GCC 14: btop 1.4.7 uses C++23 features that GCC 12 in
  # bookworm rejects. Building against trixie's newer glibc is safe because
  # build.sh asserts the resulting binary stays within the glibc version
  # Flatcar provides.
  local image="docker.io/debian:trixie-slim"

  announce "Building btop $version for $arch (GPU support: $gpu_support)"

  local user_group="$(id -u):$(id -g)"

  cp "${scriptroot}/btop.sysext/build.sh" .
  docker run --rm \
    -i \
    -v "$(pwd)":/install_root \
    --platform "linux/${img_arch}" \
    --network host \
    ${image} \
        /install_root/build.sh "${version}" "$user_group" "${gpu_support}"

  cp -aR usr "${sysextroot}"/
}
# --
