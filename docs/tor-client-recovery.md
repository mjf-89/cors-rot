# Recovery handoff — 2026-10-13

**Historical first-pass report. Independent review found blockers; see `FOLLOWUP-REMEDIATION.md` for the current implementation, 33-test results, new required `snippets/` artifacts and remaining limitations. Keep all release gates closed.**

## Delivered

- Preserved failed agent's partial diff; resumed the installed toolchain and cached builds, without duplicate installation.
- Generated production JS/WASM/types at `vendor/webtor`, with source/patch/artifact hashes in `BUILD.txt`.
- Complete pinned source patch: `browser-streams-security.patch`.
- Bounded foreground offline build: `scripts/build-webtor-wasm.sh`; test build: same command with `--smoke`.
- Test harness: `tests/browser-tor-wasm.smoke.mjs`, Node18/ws only. Optional `--tor` sends only public HTTP GETs to example.com.
- Standard rustls/webpki/ring application TLS 1.3; no TLS1.2 fallback, trust override or insecure opt-in. Replaced Snowflake Tor-link subtle-tls too, with Arti's verifier model plus its existing pinned bridge CERTS check. Actual TLS exporter replaces zero-filled placeholder.
- Cached and refreshed directory paths verify certificate signatures/validity, nine pinned authority identities, strict 5-of-9 distinct signature quorum, and consensus validity before selecting relays. Signed microdescriptor digests remain the association mechanism.
- Independent stream read/write locks; close cancels pending IO. Client circuit locks are released before RELAY_BEGIN. EOF and empty-frame wakeups fixed.
- Provider provenance/license files included. Legacy WASM HTTPS fetch still fails closed.

## Verified

- `cargo check --offline --target wasm32-unknown-unknown -p webtor-wasm` succeeded.
- Reviewed-source production and test-feature release builds succeeded.
- 15 Node18/ws fixture tests passed (including tampering/quorum/time failures and TLS unknown-root/TLS1.2 failures).
- Live Node/ws test succeeded twice. The final combined harness authenticated the directory, waited for a Tor circuit, left a raw stream's read pending while opening and completing a second TLS1.3 stream, then completed the first raw HTTP exchange. No real credentials.
- `bash -n`, `node --check`, `git diff --check`, exact upstream diff/patch comparison, output hash comparison passed.
- WASM target dependency tree contains rustls/ring/webpki and **no subtle-tls**.
- `apps/browser/browser-net.js` still has `TOR_SECURITY_VERIFIED = false`.
- No build/server/test process left running. No host/network/shared Git/OAuth configuration edited.

Logs retained under `workspace/build/webtor-rs/recovery-*.log`, notably `recovery-smoke-live-test.log` and `recovery-dependencies.log`.

## Main-agent integration actions (not done here)

1. Publish/copy the production `vendor/webtor/` directory to `apps/browser/vendor/webtor/` so the existing browser build's nested vendor copy includes it. Do NOT copy `target/recovery-smoke`.
2. Extend the snapshot fetch/publication workflow to include `authority-certificates.txt` beside consensus/microdescriptor assets. The supplied public set is `third-party/webtor-rs/authority-certificates.txt`; runtime cryptographic validation, not HTTP origin/hash, establishes authenticity.
3. Refresh the snapshot as needed: the inspected application snapshot expires **2026-10-13 08:00 UTC**. The fixed test fixture deliberately keeps its historical timestamp and is never an evergreen production snapshot.
4. Keep `TOR_SECURITY_BLOCKED` closed. Actual browser/WebView/WebRTC validation and independent integration/security review remain outstanding. No real credentials until the main release process explicitly establishes safety.

These are tested recovery artifacts, not a declaration that the entire Tor implementation is production-secure. Existing transport/resource/guard-management behavior has not been exhaustively audited, and TLS wrong-host/expired-chain regression fixtures are not yet included (standard webpki performs those checks). Details: `vendor/webtor/README.md` and `PROVENANCE.md`.
