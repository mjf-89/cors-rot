#!/usr/bin/env bash
# Rebuild vendor/snowflake-proxy/snowflake-core.js from the Tor Project's snowflake-webext at a pinned
# commit: the unmodified core files concatenated in upstream make.js order, minus webext-only files.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PIN=853070e56e4c7b8a3747997ec03a8f859d436555
WORK=${WORK:-"$ROOT/.work"}; SRC="$WORK/snowflake-webext"; DEST="$ROOT/vendor/snowflake-proxy"
mkdir -p "$WORK"
[ -d "$SRC/.git" ] || { git init -q "$SRC"; git -C "$SRC" remote add origin https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake-webext.git; }
git -C "$SRC" fetch -q --depth 1 origin "$PIN" && git -C "$SRC" checkout -q --force "$PIN"
{
  printf '// Snowflake proxy core from snowflake-webext %s (BSD-3-Clause, see LICENSE in this folder).\n// Unmodified files concatenated in the order of the upstream make.js FILES list, without the\n// webext-only files (webext/mv3messaging.js, webext/maybeChangeBackgroundPermission.js).\n' "$PIN"
  for f in broker.js config.js proxypair.js snowflake.js ui.js util.js websocket.js shims.js; do printf '\n// ---- %s ----\n' "$f"; cat "$SRC/$f"; done
} > "$DEST/snowflake-core.js"
cp "$SRC/LICENSE" "$DEST/LICENSE"
sha256sum "$DEST/snowflake-core.js"
