#!/usr/bin/env bash
# Build the in-page Tailscale client (vendor/tailscale) from tailscale/tailscale at a pinned commit +
# our cmd/tsconnect/wasm patch (exit nodes, dial, dialTLS). Needs: git, Go matching tailscale's go.mod.
# Usage: build/build-tailscale.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PIN=f61c86852783a963d96cd0a4c913f886472478d1
WORK=${WORK:-"$ROOT/.work"}
SRC="$WORK/tailscale"
PATCH="$ROOT/build/patches/tailscale/wasm_js.go.patch"
DEST="$ROOT/vendor/tailscale"

echo "Go: $(go version)"
mkdir -p "$WORK"
if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin https://github.com/tailscale/tailscale.git
fi
git -C "$SRC" fetch -q --depth 1 origin "$PIN"
git -C "$SRC" checkout -q --force "$PIN"
git -C "$SRC" clean -qfdx
git -C "$SRC" apply "$PATCH"

mkdir -p "$DEST"
( cd "$SRC" && GOFLAGS=-mod=mod GOOS=js GOARCH=wasm go build -trimpath -ldflags="-s -w" -o "$DEST/tailscale.wasm" ./cmd/tsconnect/wasm )
WASM_EXEC="$(go env GOROOT)/lib/wasm/wasm_exec.js"
[ -f "$WASM_EXEC" ] || WASM_EXEC="$(go env GOROOT)/misc/wasm/wasm_exec.js"
cp "$WASM_EXEC" "$DEST/wasm_exec.js"
cp "$SRC/LICENSE" "$DEST/LICENSE"
{
  echo "tailscale $PIN + build/patches/tailscale/wasm_js.go.patch"
  go version
  sha256sum "$PATCH" | sed "s|$ROOT/||"
  ( cd "$DEST" && sha256sum tailscale.wasm wasm_exec.js )
} > "$DEST/BUILD.txt"
cat "$DEST/BUILD.txt"
