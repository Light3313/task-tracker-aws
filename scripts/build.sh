#!/usr/bin/env bash
set -euo pipefail

### CI build script for Docker image

COMMIT_SHA=${1:?need sha}
IMAGE_TAG="task-tracker:$COMMIT_SHA"

docker buildx build --platform linux/amd64 -t "$IMAGE_TAG" --load .