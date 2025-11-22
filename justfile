set unstable := true

IMAGE := "ghcr.io/chadxz/drift"
VERSION := "dev"

# Build ARM64 container image using Docker buildx
build-image:
  docker buildx build --platform linux/arm64 \
      -t {{ IMAGE }}:{{ VERSION }} \
      -t {{ IMAGE }}:latest \
      .

# Format source files in the repository
format:
  mise exec -- dprint fmt
