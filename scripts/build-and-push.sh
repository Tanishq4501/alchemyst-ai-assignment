#!/bin/bash
# Build both Docker images and push to Artifact Registry.
# Run this BEFORE terraform apply so the images exist when VMs boot.
#
# Usage:
#   ./scripts/build-and-push.sh <project-id> [<tag>]
#
# Example:
#   ./scripts/build-and-push.sh elite-elevator-452411-b6 0.1.0
set -euo pipefail

PROJECT_ID="${1:?Usage: $0 <project-id> [<tag>]}"
TAG="${2:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
REGION="us-central1"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/alchemist"

echo "==> Registry: ${REGISTRY}"
echo "==> Tag:      ${TAG}"

# Authenticate
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Create Artifact Registry repo if it doesn't exist
gcloud artifacts repositories create alchemist \
  --repository-format=docker \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --quiet 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/../docker"

build_and_push() {
  local name="$1"
  local full_tag="${REGISTRY}/${name}:${TAG}"
  echo ""
  echo "==> Building ${name} ..."
  docker build -t "${full_tag}" "${DOCKER_DIR}/${name}"
  echo "==> Pushing  ${name} ..."
  docker push "${full_tag}"
  # Also tag as :latest for convenience
  docker tag "${full_tag}" "${REGISTRY}/${name}:latest"
  docker push "${REGISTRY}/${name}:latest"
  echo "==> ${name} pushed: ${full_tag}"
}

build_and_push "caller-worker"
build_and_push "inference-worker"

echo ""
echo "==> Done. Deploy with:"
echo "    cd terraform/envs/prod"
echo "    terraform apply -var image_tag=${TAG}"
