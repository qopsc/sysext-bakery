#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# neovim sysext.
#
# Ships the official Neovim Linux tarball with vim and vi symlinks.
#

RELOAD_SERVICES_ON_MERGE="false"

function list_available_versions() {
  local tag ver
  while read -r tag; do
    ver="${tag#v}"
    if semver_equals_or_higher "${ver}" "0.11.0"; then
      echo "${ver}"
    fi
  done < <(list_github_releases "neovim" "neovim" | grep -E '^v[0-9]')
}
# --

function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  if semver_lower "${version}" "0.11.0"; then
    echo "ERROR: neovim ${version} predates multi-arch Linux tarballs (need >= 0.11.0)." >&2
    return 1
  fi

  local rel_arch="$(arch_transform 'x86-64' 'x86_64' "$arch")"
  rel_arch="$(arch_transform 'arm64' 'arm64' "$rel_arch")"

  local tag="v${version}"
  local tarball="nvim-linux-${rel_arch}.tar.gz"
  local base_url="https://github.com/neovim/neovim/releases/download/${tag}"

  local expected
  expected="$(curl_api_wrapper \
    "https://api.github.com/repos/neovim/neovim/releases/tags/${tag}" \
    | jq -r --arg t "${tarball}" '.assets[] | select(.name == $t) | .digest')"
  if [[ -z "${expected}" || "${expected}" == "null" ]]; then
    echo "ERROR: ${tarball} not found in neovim release ${tag}." >&2
    return 1
  fi

  curl --fail --silent --show-error --location \
    --remote-name "${base_url}/${tarball}"

  echo "${expected#sha256:}  ${tarball}" | sha256sum -c -

  local topdir="nvim-linux-${rel_arch}"
  tar --force-local -xf "${tarball}"

  mkdir -p "${sysextroot}/usr/bin" \
           "${sysextroot}/usr/lib" \
           "${sysextroot}/usr/share"
  cp -a "${topdir}/bin/nvim" "${sysextroot}/usr/bin/"
  cp -a "${topdir}/lib/nvim" "${sysextroot}/usr/lib/"
  cp -a "${topdir}/share/nvim" "${sysextroot}/usr/share/"
  chmod 0755 "${sysextroot}/usr/bin/nvim"

  ln -sf nvim "${sysextroot}/usr/bin/vim"
  ln -sf nvim "${sysextroot}/usr/bin/vi"

  # Built against a newer glibc than Flatcar may ship, but only the symbol
  # versions referenced decide whether it starts. Same floor as btop.
  local glibc_floor="2.41"
  local max_glibc
  max_glibc="$(objdump -T "${sysextroot}/usr/bin/nvim" \
    | grep -o 'GLIBC_[0-9.]*' \
    | sed 's/GLIBC_//' \
    | sort -V \
    | tail -1)"
  if [ "$(printf '%s\n%s\n' "${max_glibc}" "${glibc_floor}" | sort -V | tail -1)" != "${glibc_floor}" ]; then
    echo "ERROR: neovim requires glibc ${max_glibc}, newer than the ${glibc_floor} floor." >&2
    echo "       It would fail to start on Flatcar stable. Refusing to publish." >&2
    return 1
  fi

  if ! "${sysextroot}/usr/bin/vim" --headless '+qa'; then
    echo "ERROR: neovim headless smoke test failed." >&2
    return 1
  fi
}
# --
