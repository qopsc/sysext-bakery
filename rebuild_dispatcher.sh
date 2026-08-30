#!/bin/bash
#
# Resolve workflow_dispatch inputs for the rebuild workflow into a create-release
# matrix. Unlike release_dispatcher.sh this does not skip versions that already
# have a GitHub release — the point is to remake them.
#
# Usage (from the bakery root):
#   EXTENSION=arcane VERSION=v2.9.0 ./rebuild_dispatcher.sh
#   RELEASES='arcane:v2.9.0,dust:v1.2.5' ./rebuild_dispatcher.sh
#
# Inputs come from the environment so the workflow does not interpolate them
# into bash source. EXTENSION+VERSION or RELEASES (comma-separated
# extension:version) is required. VERSION / a list entry may be "latest".

set -euo pipefail
cd "$(dirname "$0")"
source "lib/libbakery.sh"

output="${GITHUB_OUTPUT:-rebuilds_to_build.txt}"

extension="${EXTENSION:-}"
version="${VERSION:-}"
releases_csv="${RELEASES:-}"

specs=()

if [[ -n "${releases_csv}" ]]; then
  IFS=',' read -ra raw_specs <<< "${releases_csv}"
  for spec in "${raw_specs[@]}"; do
    spec="${spec#"${spec%%[![:space:]]*}"}"
    spec="${spec%"${spec##*[![:space:]]}"}"
    [[ -z "${spec}" ]] && continue
    specs+=( "${spec}" )
  done
elif [[ -n "${extension}" && -n "${version}" ]]; then
  specs+=( "${extension}:${version}" )
else
  echo "ERROR: provide EXTENSION+VERSION or RELEASES (comma-separated extension:version)." >&2
  exit 1
fi

if [[ ${#specs[@]} -eq 0 ]]; then
  echo "ERROR: no rebuilds requested." >&2
  exit 1
fi

builds=()
extensions=()

for spec in "${specs[@]}"; do
  ext="${spec%%:*}"
  ver="${spec#*:}"

  if [[ "${ext}" == "${spec}" || -z "${ext}" || -z "${ver}" ]]; then
    echo "ERROR: '${spec}' is not extension:version." >&2
    exit 1
  fi
  if [[ ! "${ext}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]; then
    echo "ERROR: invalid extension name '${ext}'." >&2
    exit 1
  fi
  if [[ ! -d "${ext}.sysext" ]]; then
    echo "ERROR: unknown extension '${ext}' (no ${ext}.sysext/)." >&2
    exit 1
  fi

  if [[ "${ver}" == "latest" ]]; then
    ver="$(./bakery.sh list "${ext}" --latest true)"
    if [[ -z "${ver}" ]]; then
      echo "ERROR: could not resolve latest version for '${ext}'." >&2
      exit 1
    fi
  fi

  echo "*  rebuild ${ext} ${ver}"
  if [[ " ${builds[*]} " != *" ${ext}:${ver} "* ]]; then
    builds+=( "${ext}:${ver}" )
  fi
  if [[ " ${extensions[*]} " != *" ${ext} "* ]]; then
    extensions+=( "${ext}" )
  fi
done

cat >> "${output}" <<EOF
builds=$(jq -r -c -n --args '$ARGS.positional' "${builds[@]}")
extensions=$(jq -r -c -n --args '$ARGS.positional' "${extensions[@]}")
EOF
