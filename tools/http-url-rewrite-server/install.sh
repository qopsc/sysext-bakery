#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# Installer for the qopsc sysext hub (Caddy URL-rewrite server).
#
# Fetches the Caddy config and compose file into the current directory,
# creates the certificate/config directories, and starts the stack.
#
#   curl -fsSL https://raw.githubusercontent.com/qopsc/sysext-bakery/main/tools/http-url-rewrite-server/install.sh | bash
#
# Copyright (c) 2025 the Flatcar Maintainers.
# Use of this source code is governed by the Apache 2.0 license.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/qopsc/sysext-bakery"
SRC_DIR="tools/http-url-rewrite-server"
HUB_HOST="extensions.quantumops.consulting"
FILES=(Caddyfile docker-compose.yml)

target_dir="$(pwd)"
ref="main"
force="false"
start="true"
tmpdir=""

function usage() {
  cat <<EOF

install.sh - install and start the qopsc sysext hub (Caddy URL-rewrite server).

Options:
  --dir <path>   Install into <path> instead of the current directory.
  --ref <ref>    Fetch from this git ref (branch or tag). Default: main.
  --force        Overwrite existing files (${FILES[*]}).
  --no-up        Stage files only; do not run 'docker compose up -d'.
  --help         Print this help.

EOF
}
# --

function fatal() {
  echo "ERROR: $*" >&2
  exit 1
}
# --

function warn() {
  echo "WARNING: $*" >&2
}
# --

function cleanup() {
  if [[ -n "${tmpdir}" && -d "${tmpdir}" ]] ; then
    rm -rf "${tmpdir}"
  fi
}
# --

function parse_args() {
  while [[ $# -gt 0 ]] ; do
    case "$1" in
      --dir)     target_dir="${2:?--dir requires a path}"; shift 2;;
      --ref)     ref="${2:?--ref requires a git ref}"; shift 2;;
      --force)   force="true"; shift;;
      --no-up)   start="false"; shift;;
      --help|-h) usage; exit 0;;
      *)         echo "ERROR: unknown option '$1'" >&2; usage; exit 1;;
    esac
  done
}
# --

function preflight() {
  command -v docker >/dev/null 2>&1 \
    || fatal "docker not found in PATH."

  docker info >/dev/null 2>&1 \
    || fatal "cannot reach the docker daemon. Is it running, and is your user in the 'docker' group?"

  docker compose version >/dev/null 2>&1 \
    || fatal "'docker compose' (Compose v2) not available. The legacy 'docker-compose' binary is not supported."

  mkdir -p "${target_dir}" \
    || fatal "cannot create '${target_dir}'."
  [[ -w "${target_dir}" ]] \
    || fatal "'${target_dir}' is not writable."

  local f
  for f in "${FILES[@]}" ; do
    if [[ -e "${target_dir}/${f}" && "${force}" != "true" ]] ; then
      fatal "'${target_dir}/${f}' already exists. Re-run with --force to overwrite."
    fi
  done
}
# --

function check_environment() {
  local port
  for port in 80 443 ; do
    if command -v ss >/dev/null 2>&1 \
       && ss -lnt "sport = :${port}" 2>/dev/null | grep -q LISTEN ; then
      warn "port ${port} is already in use; startup will fail unless that service is stopped."
    fi
  done

  local resolved=""
  if command -v getent >/dev/null 2>&1 ; then
    resolved="$(getent ahostsv4 "${HUB_HOST}" 2>/dev/null | awk 'NR==1 {print $1}')" || true
  elif command -v dig >/dev/null 2>&1 ; then
    resolved="$(dig +short A "${HUB_HOST}" 2>/dev/null | head -n1)" || true
  fi

  if [[ -z "${resolved}" ]] ; then
    warn "${HUB_HOST} does not resolve."
    warn "  Caddy will start, but the Let's Encrypt HTTP-01 challenge cannot succeed"
    warn "  until an A record for it points at this host."
  else
    echo "${HUB_HOST} resolves to ${resolved} - confirm that is this host, or certificate issuance will fail."
  fi
}
# --

function fetch_files() {
  tmpdir="$(mktemp -d)"

  local f
  for f in "${FILES[@]}" ; do
    echo "Fetching ${f} (ref '${ref}') ..."
    curl -fsSL --proto '=https' --tlsv1.2 \
      -o "${tmpdir}/${f}" \
      "${REPO_RAW}/${ref}/${SRC_DIR}/${f}" \
      || fatal "failed to download ${f} from ref '${ref}'."
    [[ -s "${tmpdir}/${f}" ]] \
      || fatal "downloaded ${f} is empty."
  done

  # Only move into place once every file arrived intact, so a mid-transfer
  # failure cannot leave a truncated config where a working one used to be.
  for f in "${FILES[@]}" ; do
    mv "${tmpdir}/${f}" "${target_dir}/${f}"
  done
}
# --

function main() {
  trap cleanup EXIT

  parse_args "$@"

  echo "Installing the qopsc sysext hub into '${target_dir}'."

  preflight
  check_environment
  fetch_files

  mkdir -p "${target_dir}/data" "${target_dir}/config"

  if [[ "${start}" != "true" ]] ; then
    echo
    echo "Files staged. Start the hub with:"
    echo "  cd '${target_dir}' && docker compose up -d"
    return
  fi

  echo "Starting caddy ..."
  ( cd "${target_dir}" && docker compose up -d )
  echo
  ( cd "${target_dir}" && docker compose ps )
  echo
  echo "Serving ${HUB_HOST}."
  echo "Certificates are stored in '${target_dir}/data' - back that directory up."
  echo "Logs: cd '${target_dir}' && docker compose logs -f"
}
# --

main "$@"
