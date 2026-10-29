#!/usr/bin/env bash
# Build the Linux AppImage inside the pinned build container, the same way CI does.
#
#   scripts/build-linux-container.sh            # builds the image, then the AppImage
#   scripts/build-linux-container.sh bash       # ...or run any command in the container
#
# Result: target/container-cache/target/dist/stickynotes-<version>-linux-x86_64.AppImage
# Cargo's registry and the target directory live in target/container-cache/ so rebuilds are
# incremental, which git already ignores and which is separate from the host build output.
#
# Environment: IMAGE (default agent-stickynotes-build), SKIP_IMAGE_BUILD=1 to
# reuse an image that is already loaded (CI builds it with a layer cache).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
image="${IMAGE:-agent-stickynotes-build}"
cache="${CACHE_DIR:-$root/target/container-cache}"

if [ "${SKIP_IMAGE_BUILD:-0}" != 1 ]; then
    docker build -t "$image" "$root"
fi

mkdir -p "$cache/cargo" "$cache/target"
version="$("$root/scripts/version.sh")"

if [ "$#" -eq 0 ]; then
    set -- scripts/package-appimage.sh
fi

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e VERSION="$version" \
    -v "$root:/src" \
    -v "$cache/cargo:/cache/cargo" \
    -v "$cache/target:/cache/target" \
    "$image" "$@"

echo "Artifacts in $cache/target/dist/"
