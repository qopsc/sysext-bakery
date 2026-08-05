#!/usr/bin/env bash
# vim: et ts=2 syn=bash
#
# sqlite sysext.
#

RELOAD_SERVICES_ON_MERGE="false"

alpine_mirror="https://dl-cdn.alpinelinux.org/alpine/latest-stable/main"

function list_available_versions() {
  # The index is an HTML directory listing, so anchor the match on the href
  # quotes. An unanchored 'sqlite-...apk' also matches inside other packages'
  # filenames (lua5.4-sqlite-0.9.6-r0.apk, php84-sqlite3-...) and reports
  # their versions as sqlite's.
  # Alpine's latest-stable branch only ever carries one version; sort anyway
  # so a mirror listing in arbitrary order cannot change the answer.
  curl -sSfL "${alpine_mirror}/x86_64/" \
    | grep -oE '"sqlite-3[^"]*\.apk"' \
    | tr -d '"' \
    | sed -e 's/^sqlite-//' -e 's/-r[0-9]*\.apk$//' \
    | sort -Vr \
    | uniq
}
# --

function populate_sysext_root() {
  local sysextroot="$1"
  local arch="$2"
  local version="$3"

  local img_arch="$(arch_transform 'x86-64' 'amd64' "$arch")"
  img_arch="$(arch_transform 'arm64' 'arm64/v8' "$img_arch")"

  # 'apk add' installs whatever latest-stable currently carries and ignores
  # the version we were asked for, so check afterwards. Without this, the day
  # Alpine moves on we would publish a sysext labelled with one version that
  # contains another, and sysupdate would hand it to nodes as that version.
  local sysextname=sqlite
  # bash/coreutils/grep are for flix.sh itself, not for the payload: it is a
  # bash script and uses GNU 'realpath --relative-base' and 'grep -P', none of
  # which busybox provides.
  #
  # Alpine builds sqlite3 and libsqlite3.so.0 with RPATH=/usr/lib. flix.sh
  # copies each RPATH entry wholesale, so that one redundant entry drags the
  # build container's entire /usr/lib into the image: 19MB instead of 5.5MB,
  # and the contents change with whatever we happen to apk-install. The entry
  # is useless to us anyway, since flix.sh overwrites the RPATH with the
  # private lib dir it just populated. Drop it before flix.sh looks at it.
  docker run --rm \
              -i \
              -v "${scriptroot}/tools/":/tools \
              -v "${sysextroot}":/install_root \
              --platform "linux/${img_arch}" \
              --pull always \
              --network host \
              docker.io/alpine:latest \
                  sh -c "apk add -U sqlite sqlite-tools bash coreutils grep patchelf && installed=\$(sqlite3 --version | cut -d ' ' -f 1) && if [ \"\$installed\" != \"${version}\" ]; then echo \"ERROR: Alpine latest-stable ships sqlite \$installed, but ${version} was requested.\" >&2; exit 1; fi && patchelf --remove-rpath /usr/bin/sqlite3 && patchelf --remove-rpath /usr/lib/libsqlite3.so.0 && cd /install_root && /tools/flix.sh / $sysextname /usr/bin/sqlite3 /usr/bin/sqldiff && OWNER=\$(stat -c '%u:%g' /install_root) && if [ \"\$OWNER\" != \"\$(id -u):\$(id -g)\" ]; then chown -R \"\$OWNER\" /install_root/$sysextname; fi"
  # flix.sh resolves the musl loader, libc and libreadline into the tree.
  # We rely on the host's /usr/share/terminfo for readline's terminal
  # handling; a sysext may only ship /usr and /opt, so Alpine's /etc/terminfo
  # cannot be carried at its original path anyway.
  mv "${sysextroot}"/sqlite/usr "${sysextroot}"/usr
  rmdir "${sysextroot}"/sqlite
}
# --
