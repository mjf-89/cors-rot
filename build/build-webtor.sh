#!/usr/bin/env bash
# Build the in-page Tor client (vendor/webtor) from webtor-rs at a pinned commit + our reviewed patch.
# Needs: git, rustup (installs the pinned nightly + wasm32 target), wasm-bindgen-cli 0.2.106, clang.
# Usage: build/build-webtor.sh            (production build into vendor/webtor)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PIN=cba29fb44970f4be37ebe7ce85bd50690d66413d
TOOLCHAIN=nightly-2026-01-05
WORK=${WORK:-"$ROOT/.work"}
SRC="$WORK/webtor-rs"
PATCH="$ROOT/build/patches/webtor-rs/browser-streams-security.patch"
DEST="$ROOT/src/vendor/webtor"
export CC_wasm32_unknown_unknown=${CC_wasm32_unknown_unknown:-clang}

[[ "$(wasm-bindgen --version)" == "wasm-bindgen 0.2.106" ]] || { echo "Need wasm-bindgen-cli 0.2.106 (cargo install wasm-bindgen-cli --version 0.2.106 --locked)" >&2; exit 1; }
rustup toolchain install "$TOOLCHAIN" --profile minimal --target wasm32-unknown-unknown >/dev/null

mkdir -p "$WORK"
if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin https://github.com/ethereum/webtor-rs.git
fi
git -C "$SRC" fetch -q --depth 1 origin "$PIN"
git -C "$SRC" checkout -q --force "$PIN"
git -C "$SRC" clean -qfdx -e target
git -C "$SRC" apply "$PATCH"

( cd "$SRC" && cargo "+$TOOLCHAIN" build --locked --release --target wasm32-unknown-unknown -p webtor-wasm )

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
wasm-bindgen --target web --out-name webtor_wasm --out-dir "$STAGE" "$SRC/target/wasm32-unknown-unknown/release/webtor_wasm.wasm"

# Production exports must equal the reviewed allowlist (no test-only hooks can ship).
# wasm-bindgen's internal closure glue names embed 16-hex-digit crate hashes that depend on the build
# machine and path; they are masked as _H_ on both sides, so only real API differences fail the build.
ALLOW="$ROOT/build/patches/webtor-rs/production-exports"
mask() { sed -E 's/_[0-9a-f]{16}_/_H_/g' | sort; }
diff <(grep -oE '^export (async )?(function|class|const|let) [A-Za-z0-9_]+|^export \{[^}]*\}' "$STAGE/webtor_wasm.js" | mask) <(mask < "$ALLOW.js.txt")
diff <(grep -oE 'export const [a-zA-Z0-9_]+' "$STAGE/webtor_wasm_bg.wasm.d.ts" | mask) <(mask < "$ALLOW.wasm.txt")

mkdir -p "$DEST"
rm -rf "$DEST/snippets"
cp -R "$STAGE/." "$DEST/"
printf '{"name":"cors-rot-webtor-wasm","private":true,"type":"module"}\n' > "$DEST/package.json"
{
  echo "webtor-rs $PIN + build/patches/webtor-rs/browser-streams-security.patch"
  rustc "+$TOOLCHAIN" --version
  wasm-bindgen --version
  sha256sum "$PATCH" | sed "s|$ROOT/||"
  ( cd "$DEST" && sha256sum webtor_wasm.js webtor_wasm_bg.wasm && find snippets -type f -print0 | sort -z | xargs -0 sha256sum )
} > "$DEST/BUILD.txt"
cat "$DEST/BUILD.txt"
