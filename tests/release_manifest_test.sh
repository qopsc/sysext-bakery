#!/bin/bash
# Offline test of the version and arch logic in release_manifest.sh.
# Run: tests/release_manifest_test.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "${root}/release_manifest.sh"

fails=0
function assert() { # assert <name> <jq-expr> <expected>
  local got
  got="$(jq -c "$2" <<<"${manifest}")"
  if [[ ${got} != "$3" ]] ; then
    echo "FAIL $1: got ${got}, want $3"; fails=$((fails + 1))
  fi
}

manifest="$(build_manifest "${root}/tests/fixtures/gh-releases.json" "${root}" \
  docker docker-buildx tailscale k3s nvidia-runtime kata-containers)"
ext='.extensions[] | select(.name == "NAME")'

assert "generated is a timestamp" '.generated | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")' true
assert "sorted by name" '[.extensions[].name]' '["docker","docker-buildx","k3s","kata-containers","nvidia-runtime","tailscale"]'
assert "numeric, not lexical (1.10 > 1.9)" "${ext//NAME/tailscale} | .versions[-2:]" '["1.10.0","1.9.0"]'
assert "release beats its rc; draft ignored; v stripped" "${ext//NAME/tailscale} | .latest" '"1.11.0"'
assert "rc listed, below release" "${ext//NAME/tailscale} | .versions | index(\"1.11.0-rc1\") > index(\"1.11.0\")" true
assert "arches come from the latest version only" "${ext//NAME/tailscale} | .arches" '["arm64"]'
assert "docker does not swallow docker-buildx" "${ext//NAME/docker} | .versions" '["29.9.0"]'
assert "hyphenated name, two arches" "${ext//NAME/docker-buildx} | [.latest, .arches]" '["0.10.0",["arm64","x86-64"]]'
assert "build logs are not arches" "${ext//NAME/docker} | .arches" '["x86-64"]'
assert "plus-build suffix ordering" "${ext//NAME/k3s} | .versions" '["1.33.13+k3s2","1.33.13+k3s1"]'
assert "doc uses the docs/ filename (underscore)" "${ext//NAME/nvidia-runtime} | .doc" '"https://qopsc.github.io/sysext-bakery/nvidia_runtime/"'
assert "no releases yet" "${ext//NAME/kata-containers} | [.latest, .versions, .arches]" '[null,[],[]]'

if (( fails )) ; then echo "${fails} failure(s)"; exit 1; fi
echo "release_manifest_test: all passed"
