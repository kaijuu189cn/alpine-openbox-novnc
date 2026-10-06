#!/usr/bin/env bash
#
# fetch-baseimage.sh
#
# Fetch ghcr.io/linuxserver/baseimage-selkies WITHOUT relying on `docker pull`.
#
# WHY THIS EXISTS
# ---------------
# On China-facing networks ghcr.io behaves badly with the Docker daemon: the
# manifest resolves and layers are queued, but blob downloads stall forever with
# no progress and no error ("<id>: Pulling fs layer" then nothing). Measured
# from this host:
#
#   * `docker pull ghcr.io/...`        -> hangs indefinitely, 0 bytes
#   * plain `curl` of the same blob    -> 200 OK at ~1.2 MB/s
#   * `skopeo copy` of the same image  -> succeeds (~600 KB/s, ~10 min)
#
# So we fetch with skopeo (which uses its own HTTP stack, not dockerd's) into a
# local dir, convert it to a docker-archive, and `docker load` it. After this
# runs once, the normal `docker build` works because the base image is local.
#
# USAGE
#   ./scripts/fetch-baseimage.sh [TAG] [ARCH]
#     TAG   base image tag          (default: alpine324 -> Alpine 3.24.1)
#     ARCH  amd64 | arm64v8         (default: amd64)
#
# EXAMPLES
#   ./scripts/fetch-baseimage.sh                 # alpine324 / amd64
#   ./scripts/fetch-baseimage.sh alpine324 arm64v8
#
set -euo pipefail

TAG="${1:-alpine324}"
ARCH="${2:-amd64}"

case "$ARCH" in
  amd64)   PREFIX="" ;;
  arm64v8) PREFIX="arm64v8-" ;;
  *) echo "ERROR: ARCH must be amd64 or arm64v8 (got: $ARCH)" >&2; exit 1 ;;
esac

IMAGE="ghcr.io/linuxserver/baseimage-selkies:${PREFIX}${TAG}"
WORKDIR="${WORKDIR:-/tmp/baseimage-fetch}"
DIR="${WORKDIR}/${ARCH}-${TAG}"
TAR="${WORKDIR}/${ARCH}-${TAG}.tar"

# --- mirror for the Docker Hub side is not needed here (ghcr only) ----------

echo "==> target image : ${IMAGE}"
echo "==> work dir     : ${WORKDIR}"

if ! command -v skopeo > /dev/null 2>&1; then
  echo "==> skopeo not found, installing..."
  if command -v apt-get > /dev/null 2>&1; then
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -q skopeo
  elif command -v apk > /dev/null 2>&1; then
    apk add --no-cache skopeo
  else
    echo "ERROR: cannot install skopeo automatically; install it manually." >&2
    exit 1
  fi
fi

# Skip if the image is already loaded locally.
if docker image inspect "${IMAGE}" > /dev/null 2>&1; then
  echo "==> ${IMAGE} already present locally, nothing to do."
  docker image inspect "${IMAGE}" --format '    id={{.Id}} size={{.Size}}'
  exit 0
fi

mkdir -p "$WORKDIR"

echo "==> [1/4] skopeo copy ghcr -> dir (this is the slow step, ~10 min)"
rm -rf "$DIR"
skopeo copy --retry-times 5 "docker://${IMAGE}" "dir:${DIR}"

echo "==> [2/4] dir -> docker-archive"
rm -f "$TAR"
skopeo copy "dir:${DIR}" "docker-archive:${TAR}:${IMAGE}"

echo "==> [3/4] docker load"
docker load -i "$TAR"

echo "==> [4/4] verify"
docker image inspect "${IMAGE}" --format '    id={{.Id}} size={{.Size}}'

# Reclaim the intermediate copies (the image now lives in the daemon store).
echo "==> cleanup intermediate files"
rm -rf "$DIR" "$TAR"

echo "==> done: ${IMAGE}"
