#!/usr/bin/env bash
# Download the prebuilt WebAssembly clients (vendor/webtor, vendor/tailscale) from a GitHub release
# of this repository and verify their checksum. Usage: scripts/fetch-vendor.sh [tag]   (default: latest)
# For a private repository set GH_TOKEN (a token with read access); uses the GitHub CLI if present.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=${REPO:-$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')}
TAG=${1:-}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
if command -v gh >/dev/null; then
  gh release download ${TAG:+"$TAG"} --repo "$REPO" --pattern 'cors-rot-vendor.tar.gz*'
else
  API="https://api.github.com/repos/$REPO/releases/${TAG:+tags/$TAG}"; [ -n "$TAG" ] || API="${API}latest"
  AUTH=(); [ -n "${GH_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer $GH_TOKEN")
  for name in cors-rot-vendor.tar.gz cors-rot-vendor.tar.gz.sha256; do
    id=$(curl -fsSL "${AUTH[@]}" "$API" | grep -B3 "\"name\": \"$name\"" | sed -n 's/.*"id": \([0-9]*\).*/\1/p' | head -1)
    curl -fsSL "${AUTH[@]}" -H "Accept: application/octet-stream" -o "$name" "https://api.github.com/repos/$REPO/releases/assets/$id"
  done
fi
sha256sum -c cors-rot-vendor.tar.gz.sha256
tar -xzf cors-rot-vendor.tar.gz -C "$ROOT"
echo "Vendor files installed into $ROOT/vendor"
