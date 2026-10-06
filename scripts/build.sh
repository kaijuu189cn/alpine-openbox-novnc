#!/usr/bin/env bash
#
# build.sh -- build the webtop noVNC image(s).
#
# China-network notes baked in:
#   * Alpine apk is served from a domestic mirror (default mirror.nju.edu.cn,
#     measured fastest from this network at ~1.5 MB/s vs ~0.8 MB/s for the
#     official CDN; mirrors.ustc.edu.cn and mirrors.tuna.tsinghua.edu.cn both
#     returned HTTP 403 here).
#   * The noVNC image's base is plain `alpine:3.22` from Docker Hub, which the
#     local dockerd already accelerates with its configured registry mirrors.
#     The older selkies builds had to fetch from ghcr.io, where blob downloads
#     stall -- see scripts/fetch-baseimage.sh and README.md.
#
# USAGE
#   ./scripts/build.sh                 # build webtop:alpine-openbox-novnc
#   ./scripts/build.sh legacy          # also rebuild the older selkies images
#
# ENV
#   APK_MIRROR   Alpine mirror host (default mirror.nju.edu.cn)
#   TAG          extra image tag to produce (default novnc-wine1); the image is
#                always also tagged webtop:alpine-openbox-novnc
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_MIRROR="${APK_MIRROR:-mirror.nju.edu.cn}"
TAG="${TAG:-novnc-wine1}"
TARGET="${1:-novnc}"

BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"

echo "=============================================="
echo " webtop rebuild (noVNC)"
echo "   apk mirror : $APK_MIRROR"
echo "   tag        : $TAG"
echo "=============================================="

build_one() {
  local name="$1" dir="$2" extra_tag="$3"
  echo
  echo "==> building webtop:${name}"
  docker build \
    --build-arg "BUILD_DATE=${BUILD_DATE}" \
    --build-arg "VERSION=${TAG}" \
    --build-arg "APK_MIRROR=${APK_MIRROR}" \
    -t "webtop:${name}" \
    -t "webtop:${extra_tag}" \
    "$ROOT/$dir"
  echo "==> built webtop:${name}"
  docker image inspect "webtop:${name}" --format '    id={{.Id}} size={{.Size}}'
}

case "$TARGET" in
  novnc|"")
    build_one alpine-openbox-novnc novnc/alpine-openbox "alpine-openbox-${TAG}"
    ;;
  legacy)
    # Older selkies-based builds. These need the ghcr.io base image, so fetch
    # it first with skopeo (plain `docker pull` stalls on that registry here).
    "$ROOT/scripts/fetch-baseimage.sh" alpine324 amd64
    build_one alpine-openbox alpine-openbox "alpine-openbox-${TAG}"
    build_one alpine-sway    alpine-sway    "alpine-sway-${TAG}"
    ;;
  *)
    echo "ERROR: unknown target '$TARGET' (use novnc|legacy)" >&2
    exit 1
    ;;
esac

echo
echo "=============================================="
echo " done. images:"
docker images --filter 'reference=webtop:*' --format '   {{.Repository}}:{{.Tag}}  {{.Size}}'
echo "=============================================="
