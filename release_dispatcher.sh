#!/bin/bash
#
# Ensure parity of Bakery releases and all extensions / release versions in release_build_versions.txt.
#
# Note that only new releases will be published; existing ones removed from release_build_versions.txt
#   will not be un-published.

set -euo pipefail
cd "$(dirname "$0")"
source "lib/libbakery.sh"

output="${GITHUB_OUTPUT:-releases_to_build.txt}"

echo
echo "Checking for new extension images to be built"
echo "============================================="
echo

mapfile -t images < <( sed -e 's:\s*#.*::' -e 's/[[:space:]]*$//' -e '/^$/d' release_build_versions.txt )

builds=()
extensions=()

for image in "${images[@]}"; do
  extension="${image% *}"
  version="${image#* }"

  if [ "${version}" = "latest" ] ; then
    unset version
    # Process substitution hides bakery.sh's exit status, so capture stdout
    # and fail this entry loudly instead of silently skipping it (bird latest
    # was dropped on a gitlab.nic.cz 403 in run 33328132566).
    latest_out=""
    if ! latest_out="$(./bakery.sh list "${extension}" --latest true)"; then
      echo "*  ${extension} latest: ERROR listing upstream versions; skipping." >&2
      continue
    fi
    mapfile -t version <<< "${latest_out}"
    if [[ ${#version[@]} -eq 0 || -z "${version[0]}" ]]; then
      echo "*  ${extension} latest: ERROR no versions returned; skipping." >&2
      continue
    fi
  fi

  build_required="false"
  for v in "${version[@]}"; do
    echo -n "*  ${extension} ${v}: "

    if github_release_exists "${bakery%/*}" "${bakery#*/}" "${extension}-${v}"; then
      echo "Bakery release exists."
      continue
    fi

    if [[ " ${builds[@]} " != *" ${extension}:${v} "* ]] ; then
      echo "Build required. "
      build_required="true"
      builds+=( "${extension}:${v}" )
    else
      echo "Build already scheduled. "
    fi
  done

  if [[ $build_required == true && " ${extensions[@]} " != *" ${extension} "* ]] ; then
    extensions+=( "${extension}" )
  fi
  unset version
done

cat >> "${output}" <<EOF
builds=$(jq -r -c -n --args '$ARGS.positional' "${builds[@]}")
extensions=$(jq -r -c -n --args '$ARGS.positional' "${extensions[@]}")
EOF
