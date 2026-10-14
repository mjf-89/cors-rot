# cors-rot reference

Details behind the short [README](../README.md).

## API

### `createCorsRot(options) -> net`

Options: `transport` (`'tailscale'` default | `'tor'`), `tailscale` (`{ storage, hostname }`),
`tor` (forwarded to the network: `timeoutMs`, `maxRedirects`, `maxHeaderBytes`,
`maxRequestBodyBytes`, `bootstrapTimeoutMs`, `keepAlive`), `onStatus(snapshot)`, `timeoutMs`,
`nativeFetch` (default `globalThis.fetch`, used for same-origin and WASM loading only), `keepAlive`,
`document` (for the Snowflake frame; default `globalThis.document`).

`net` methods:

| Member | Description |
| --- | --- |
| `fetch(input, init)` | Standard streaming `Response` through the selected transport (same-origin uses the browser's fetch). |
| `fetchTor(input, init)` | Explicit Tor, regardless of the selected transport. |
| `connect(host, port, { tls })` | Raw stream (`read()`/`write(bytes)`/`close()`) through the selected transport. |
| `preconnect(url)` | Warm a keep-alive connection to `url`'s origin. |
| `warmUp()` | Start the selected transport in the background. |
| `setTransport(name)` | `'tailscale'` \| `'tor'`; starts/stops the Snowflake proxy. |
| `getStatus()` | Snapshot (`transport`, `torState`, `progress`, `recentTorRequests`, …). |
| `subscribe(cb)` | Status subscription; returns an unsubscribe function. |
| `tailscale` | `{ start, getStatus, subscribe, setExitNode, login, logout }`. |
| `snowflakeProxy` | `{ getStatus, subscribe }` (status of the give-back proxy). |
| `network` | The lower-level network object. |

### Lower-level exports (`src/index.js`)

`createBrowserNetwork`, `createTorClientOptions`, `createConnectionPool`, `poolKey`, `requestHttp`,
`validateHeaders`, `validateHttpUrl`, `createTailscaleManager`, `createSnowflakeProxy`,
`loadTorDirectory`, `saveTorDirectory`, `createGitHttp` (an `isomorphic-git` `http` plugin backed by
any fetch; `isomorphic-git` itself is **not** bundled).

## How it works

- **Tailscale transport.** `createTailscaleManager()` lazily loads `src/vendor/tailscale/` (Go→WASM, ~38
  MB, from `tailscale/cmd/tsconnect` with a small patch). The node joins the user's tailnet; sign-in,
  exit-node choice and state live in the provided `storage` (default `localStorage`). Requests are
  framed as HTTP/1.1 over a `connect()`/`connectTls()` stream that the WASM client proxies through the
  user's exit node. TLS for HTTPS is terminated **in the page** by Go's `crypto/tls`.
- **Tor transport.** `createBrowserNetwork()` lazily loads `src/vendor/webtor/` (patched `webtor-rs`). It
  opens a **WebSocket** to a public Snowflake bridge, downloads and authenticates the Tor network
  directory over Tor (~20–30 MB on a cold start; cached in IndexedDB by `tor-cache.js` and re-verified
  on every use), builds a circuit, and runs HTTP/1.1 over Tor streams. HTTPS is terminated **in the
  page** by rustls/webpki (TLS 1.3 only, Mozilla roots).
- **Snowflake give-back.** While `tor` is selected, `snowflake.js` runs the Tor Project's
  `snowflake-webext` core in a hidden same-origin frame (`snowflake-proxy.html`). Over **WebRTC** it
  relays encrypted Tor traffic for censored users between their browser and the Snowflake bridge. It
  **never** connects to websites. It stops when `tailscale` is selected. There is no off switch.
- **HTTP layer.** `http-stream.js` implements HTTP/1.1 over a transport stream with an optional
  keep-alive pool: streaming bodies (pulled, not buffered), chunked/`content-length` framing,
  redirects with cross-origin credential stripping, bounded buffered uploads, and no decompression,
  cookie jar, cache, referrer, or HTTP/2.

### Who sees what

| | Tailscale | Tor |
| --- | --- | --- |
| Your IP address | Your tailnet + your exit node's egress | Snowflake bridge / Tor entry; destination sees a Tor exit |
| HTTPS plaintext | Nobody in transit (TLS in-page, end to end) | Nobody in transit (TLS in-page, end to end) |
| Plain `http://` plaintext | Readable by your exit node | **Readable by the Tor exit** |
| The destination | Sees your exit node's address | Sees a Tor exit address |

## Security notes

- **TLS is terminated in the page.** For Tor, HTTPS uses **rustls/webpki (TLS 1.3 only, Mozilla
  roots)**; the upstream client's fail-open TLS and unsigned directory were replaced, and the Tor
  directory must carry a **5-of-9 quorum** of signatures from the pinned directory authorities and be
  currently valid. For Tailscale, HTTPS uses **Go's `crypto/tls`**. The exit/relay cannot read or
  change HTTPS.
- **Plain `http://` is readable by the exit** (Tor exit or Tailscale exit node). Prefer `https://`.
- Two independent code reviews of the Tor build; **not** a formal audit. See
  `build/patches/webtor-rs/` for the patch and `docs/` for the reviews and remaining limits.
- No cookie jar, ambient credentials, browser cache, referrer, integrity verification, or response
  decompression. `Accept-Encoding: identity` is requested. Cross-origin redirects drop `Authorization`,
  `Cookie`, API-key and custom-secret headers. Non-idempotent requests are never replayed after a
  failure.

## Snowflake infrastructure caveat

From the Snowflake project: *"At the moment we do not have the ability to share Snowflake
infrastructure between different types of applications…"* Deployments of this library **should run
their own Snowflake bridge and proxies** rather than relying on the Tor Project's public
infrastructure. Give-back and self-hosting links:

- https://snowflake.torproject.org/
- https://community.torproject.org/relay/setup/snowflake/standalone/
- https://community.torproject.org/relay/setup/snowflake/
- https://community.torproject.org/relay/
- https://community.torproject.org/relay/setup/bridge/
- https://community.torproject.org/relay/setup/webtunnel/
- https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake

**This product is not endorsed or sponsored by, or affiliated with, the Tor Project.** "Tor" and the
Tor Project logos are trademarks of The Tor Project, Inc.; use here does not imply endorsement.

## Tailscale exit-node setup

1. On an always-on device in your tailnet, enable **Run as exit node**
   (`tailscale set --advertise-exit-node`). https://tailscale.com/kb/1408/quick-guide-exit-nodes
2. Approve it in the admin console. https://login.tailscale.com/admin/machines
3. If you use custom access controls, allow internet access through exit nodes
   (`autogroup:internet`). https://login.tailscale.com/admin/acls
4. Exit-node docs: https://tailscale.com/kb/1103/exit-nodes

## Licenses / third-party notices

- **Our code** (`index.js`, `network.js`, `http-stream.js`, `tor-cache.js`, `tailscale.js`,
  `snowflake.js`, `snowflake-proxy.js`, `git-http.js`): MIT.
- **`src/vendor/webtor`** — patched `webtor-rs` (MIT) embedding **Arti** (MIT/Apache-2.0). Bundled Rust
  crates include **rustls**, **ring**, and **webpki-roots**; see `src/vendor/webtor/licenses/` for the
  per-crate notices (MPL-2.0 applies to parts of the rustls/webpki-roots stack).
- **`src/vendor/tailscale`** — Tailscale `cmd/tsconnect` (BSD-3-Clause), see `src/vendor/tailscale/LICENSE`.
- **`src/vendor/snowflake-proxy`** — the Tor Project's `snowflake-webext` core (BSD-3-Clause), see
  `src/vendor/snowflake-proxy/LICENSE`.

See each `src/vendor/*/PROVENANCE.md` for exact upstream commits and hashes.

## Tests and demo

```sh
node --test tests/*.test.mjs   # HTTP layer, pool, network (fake tor/tailscale), tor cache, preconnect
```

`demo/index.html` is a self-contained page (no external scripts): pick a transport, sign in to
Tailscale and choose an exit node, fetch a URL and stream the response, and do a raw TLS GET.
