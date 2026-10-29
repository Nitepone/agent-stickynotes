#!/usr/bin/env bash
# Print the version string used in release artifact names.
#
#   tag v1.2.3 (GITHUB_REF=refs/tags/v1.2.3, or HEAD is tagged)  ->  1.2.3
#   anything else                  ->  <Cargo workspace version>-<short sha>, e.g. 0.1.0-7ee8067
#
# VERSION in the environment overrides everything (CI computes it once and
# passes it on, including into the build container).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

if [ -n "${VERSION:-}" ]; then
    echo "$VERSION"
    exit 0
fi

cargo_version="$(sed -n '/^\[workspace.package\]/,/^\[/{s/^version *= *"\([^"]*\)".*/\1/p;}' "$root/Cargo.toml" | head -1)"
if [ -z "$cargo_version" ]; then
    echo "version.sh: cannot read the version from Cargo.toml" >&2
    exit 1
fi

tag=""
case "${GITHUB_REF:-}" in
    refs/tags/v*) tag="${GITHUB_REF#refs/tags/}" ;;
    *) tag="$(git -C "$root" describe --tags --exact-match --match 'v*' 2>/dev/null || true)" ;;
esac

if [ -n "$tag" ]; then
    if [ "${tag#v}" != "$cargo_version" ]; then
        echo "version.sh: warning: tag $tag does not match Cargo version $cargo_version" >&2
    fi
    echo "${tag#v}"
    exit 0
fi

sha="${GITHUB_SHA:-}"
if [ -z "$sha" ]; then
    sha="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)"
fi
echo "${cargo_version}-${sha:0:7}"
