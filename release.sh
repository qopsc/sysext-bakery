#!/bin/bash
#
# Ensure parity of Bakery releases and all extensions / release versions in release_build_versions.txt.
#
# Note that only new releases will be published; existing ones removed from release_build_versions.txt
#   will not be un-published.
#
# Usage:
#   release.sh <extension>:<version>              build both arches, tag (legacy)
#   release.sh <extension>:<version> --arch <arch> build one arch, no tag;
#                                                  writes SHA256SUMS.<arch> partial
#   release.sh <extension>:<version> --join       join both arches' artefacts in
#                                                  the current directory into
#                                                  SHA256SUMS + Release.md, tag

set -euo pipefail
cd "$(dirname "$0")"
source "lib/libbakery.sh"

output="${GITHUB_OUTPUT:-release-tag.txt}"

extension="${1%:*}"
version="${1#*:}"

mode="all"
arch=""
case "${2:-}" in
  --arch)
    mode="arch"
    arch="${3:?--arch requires an architecture (x86-64 or arm64)}"
    ;;
  --join)
    mode="join"
    ;;
  "")
    ;;
  *)
    echo "ERROR: unknown argument '${2}'." >&2
    exit 1
    ;;
esac

function out() {
  echo "${@:-}" | tee -a Release.md
}
# --

function build_arch() {
  local arch="$1"
  local sums_file="$2"
  local target="${extension}-${version}-${arch}"
  out "## \`${target}.raw\`"
  ./bakery.sh create "${extension}" "${version}" --arch "${arch}" --sysupdate true --output-file "${target}" 2>&1 \
    | tee "${extension}-${version}-${arch}-build.log"
  cat SHA256SUMS."${extension}" >> "${sums_file}"
}
# --

if [[ "${mode}" == "join" ]] ; then
  # Artefacts for both arches must already be in the current directory
  # (placed there by the caller, e.g. a publish job downloading staging
  # artefacts). Join them, regenerate Release.md, and tag.
  for arch in x86-64 arm64; do
    for f in "${extension}-${version}-${arch}.raw" \
             "${extension}-${version}-${arch}-build.log" \
             "SHA256SUMS.${arch}"; do
      if [[ ! -f "${f}" ]] ; then
        echo "ERROR: --join requires '${f}' in the current directory." >&2
        exit 1
      fi
    done
  done
  if [[ ! -f "${extension}.conf" ]] ; then
    echo "ERROR: --join requires '${extension}.conf' in the current directory." >&2
    exit 1
  fi

  rm -f SHA256SUMS Release.md

  out ""
  out "New ${extension} extension release ${version}"
  out ""
  out "Built $(date --rfc-3339 seconds)"

  for arch in x86-64 arm64; do
    out "## \`${extension}-${version}-${arch}.raw\`"
    cat "SHA256SUMS.${arch}" >> SHA256SUMS
  done
else
  rm -f *.raw SHA256SUMS.* SHA256SUMS *.conf Release.md

  out ""
  out "New ${extension} extension release ${version}"
  out ""
  out "Built $(date --rfc-3339 seconds)"

  if [[ "${mode}" == "arch" ]] ; then
    # Per-arch build leg: emit a partial sums file for the publish job to
    # join. No final Release.md content and no git tag happen here; the
    # Release.md fragment written by 'out' is discarded by the caller.
    build_arch "${arch}" "SHA256SUMS.${arch}"
    exit 0
  fi

  for arch in x86-64 arm64; do
    build_arch "${arch}" "SHA256SUMS"
  done
fi

out "## SHA256SUMS"
out '```'
cat SHA256SUMS >> Release.md
out '```'

echo "tag=${extension}-${version}" >> "${output}"

git tag "${extension}-${version}" --force
git push origin "${extension}-${version}" --force
