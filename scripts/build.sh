#!/usr/bin/env bash
#
# build.sh -- build the webtop noVNC image.
#
#   ./scripts/build.sh                       # standard build, alpine:openbox-novnc
#   BUILD_PACKAGES="wine xdotool xwininfo" ./scripts/build.sh
#
# `docker compose up -d --build` does the same thing; this script exists to pass
# a real BUILD_DATE and to add an extra tag in one go.
#
# ENV
#   IMAGE           image to produce (default alpine:openbox-novnc)
#   BUILD_PACKAGES  extra Alpine packages, space separated. The default is the
#                   standard three (wine xdotool xwininfo); set it to "" for the
#                   lean image, or append anything else you want.
#   APK_MIRROR      Alpine mirror host (default mirror.nju.edu.cn)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-alpine:openbox-novnc}"
BUILD_PACKAGES="${BUILD_PACKAGES-wine xdotool xwininfo}"
APK_MIRROR="${APK_MIRROR:-mirror.nju.edu.cn}"
EXTRA_TAG="${1:-}"

BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"

echo "=============================================="
echo " webtop rebuild (noVNC)"
echo "   image          : $IMAGE"
echo "   extra packages : ${BUILD_PACKAGES:-none}"
echo "   apk mirror     : $APK_MIRROR"
echo "=============================================="

TAGS=(--tag "$IMAGE")
if [ -n "$EXTRA_TAG" ]; then
  TAGS+=(--tag "${IMAGE%:*}:$EXTRA_TAG")
fi

docker build \
  --build-arg "BUILD_DATE=${BUILD_DATE}" \
  --build-arg "VERSION=${IMAGE#*:}" \
  --build-arg "APK_MIRROR=${APK_MIRROR}" \
  --build-arg "BUILD_PACKAGES=${BUILD_PACKAGES}" \
  "${TAGS[@]}" \
  "$ROOT"

echo
docker image inspect "$IMAGE" --format '   built {{.RepoTags}} size={{.Size}} bytes'
