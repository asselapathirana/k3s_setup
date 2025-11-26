#!/usr/bin/env bash
# Build and push a Postgres image with PostGIS + pgvector to Docker Hub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (override via env): REGISTRY_USER, IMAGE_REPO, TAG, BASE_IMAGE, DOCKERFILE
REGISTRY_USER="${REGISTRY_USER:-assela}"
IMAGE_REPO="${IMAGE_REPO:-postgres}"
TAG="${TAG:-16-3.4-pgvector-v2}"
BASE_IMAGE="${BASE_IMAGE:-postgis/postgis:16-3.4}"
DOCKERFILE="${DOCKERFILE:-${SCRIPT_DIR}/Dockerfile.pgvector-postgis}"
IMAGE="docker.io/${REGISTRY_USER}/${IMAGE_REPO}:${TAG}"

log() { printf '%s\n' "$*"; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing command: $1"
    exit 1
  fi
}

require_cmd docker

log "[info] Using base image: ${BASE_IMAGE}"
log "[info] Target image: ${IMAGE}"

if [[ ! -f "${DOCKERFILE}" ]]; then
  log "[error] Dockerfile not found at ${DOCKERFILE}"
  exit 1
fi

# Build args allow overriding base image without editing the Dockerfile.
log "[info] Building image..."
docker build \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  -f "${DOCKERFILE}" \
  -t "${IMAGE}" \
  "${SCRIPT_DIR}"

log "[info] Pushing to ${IMAGE} (ensure you ran 'docker login')..."
docker push "${IMAGE}"

log "[done] Image ready: ${IMAGE}"
