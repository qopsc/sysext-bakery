#!/bin/bash
#
# Update bakery release metadata
#
# If a sysext name is provided in "$1" we download
#  - all sysupdate configurations
#  - all SHA256SUMS
# and create a new extension metadata release from that.
#
# If $1 is empty, we update the global SHA256SUMS covering all releases.

set -euo pipefail
cd "$(dirname "$0")"
source "lib/libbakery.sh"

rm -f *.raw SHA256SUMS.* SHA256SUMS *.conf Release.md

extension="$(extension_name "${@:-}")"
tag="${extension:-SHA256SUMS}"

function out() {
  echo "${@:-}" | tee -a Release.md
}
# --

function fetch_artefacts() {
  local release="$1"

  { curl_api_wrapper \
         "https://api.github.com/repos/${bakery}/releases/tags/${release}" \
  | jq -r '.assets[] | "\(.name)\t\(.browser_download_url)"' | grep -E '(\bSHA256SUMS|\.conf)$' || true; } \
  > downloads.txt

  local rc=0
  while IFS=$'\t' read -r name url; do
    echo "  Fetching ${name} <-- ${url}"
    if ! curl \
      -o "${name}" -fsSL --retry-delay 1 --retry 60 --retry-connrefused --retry-max-time 60 \
       --connect-timeout 20  "${url}" ; then
      echo "  WARNING: could not fetch ${name} from ${url}"
      rc=1
    fi
  done <downloads.txt

  rm -f downloads.txt
  return "${rc}"
}
# --

function fetch_extension_metadata() {
  local extension="$1"
  local versions="$(./bakery.sh list-bakery "${extension}")"

  if [[ -z "${versions}" ]] ; then
    out "* SKIPPED ${extension} as no releases are available"
    return
  fi

  for version in $(./bakery.sh list-bakery "${extension}"); do
    release="${extension}-${version}"

    # Clear per iteration: a failed fetch would otherwise leave the previous
    # version's SHA256SUMS on disk and append it a second time.
    rm -f SHA256SUMS

    # A draft or half-uploaded release is listed by the API but its assets are
    # not downloadable. Skip it instead of failing the whole metadata job.
    if ! fetch_artefacts "${release}" || [[ ! -f SHA256SUMS ]] ; then
      out "* SKIPPED ${release} (no downloadable SHA256SUMS -- draft or incomplete release)"
      continue
    fi

    out "* ${release}"
    cat SHA256SUMS >> SHA256SUMS.all
  done

  if [[ -f SHA256SUMS.all ]] ; then
    mv SHA256SUMS.all SHA256SUMS
  else
    rm -f SHA256SUMS
  fi
}
# --

if [[ -n $extension ]] ; then

  out "# Extension ${extension} metadata release."
  out ""
  out "Updated $(date --rfc-3339 seconds)"

  fetch_extension_metadata "$extension"
  if [[ ! -f SHA256SUMS ]] ; then
    out "No releases available at this time."
  else
    out ""
    out "## Sysupdate confs:"
    out '```'
    ls -1 *.conf | tee -a Release.md
    out '```'
  fi

else

  out "# Global SHA256SUMS metadata release."
  out ""
  out "Updated $(date --rfc-3339 seconds)"

  for extension in $(./bakery.sh list --plain true); do
    echo
    rm -f SHA256SUMS
    if ! fetch_artefacts "$extension" || [[ ! -f SHA256SUMS ]] ; then
      out "* SKIPPED ${extension} as no SHA256SUMS is available"
      continue
    fi
    cat SHA256SUMS >> SHA256SUMS.global
    out "* ${extension}:"
    sed 's:.*\s:  * :' SHA256SUMS | tee -a Release.md
    rm SHA256SUMS
  done

  if [[ ! -f SHA256SUMS.global ]] ; then
    out "No releases available at this time."
  else
    mv SHA256SUMS.global SHA256SUMS
  fi
fi
# --

git tag -f "${tag}" --force
git push origin "${tag}" --force
