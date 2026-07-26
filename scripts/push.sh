#!/usr/bin/env bash
set -euo pipefail

### CI push script for Docker image

COMMIT_SHA=${1:?need sha}
IMAGE_TAG="$ECR_REGISTRY/$ECR_REPOSITORY:$COMMIT_SHA"

# Push the Docker image to ECR if it doesn't already exist
if aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids imageTag="$COMMIT_SHA" >/dev/null 2>&1; then
    echo "Image $IMAGE_TAG already exists in ECR."
    echo "Skipping Docker build and push."
else
    docker tag "task-tracker:$COMMIT_SHA" "$IMAGE_TAG"
    docker push "$IMAGE_TAG"
fi