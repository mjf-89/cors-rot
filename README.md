# cors-rot

A source-only, build-step-free browser networking library. It gives a page a standard `fetch()`
(and a raw `connect()`) that leaves through one of **two in-page transports** instead of the
browser's own network stack, which lets an app reach HTTP(S) endpoints that refuse cross-origin
(CORS) browser requests:

- **`tailscale`** (default) — an in-page Tailscale node (Go→WASM) joins the user's tailnet and sends
  traffic out through the user's own **exit node**.
- **`tor`** — Tor over **Snowflake** (a patched `webtor-rs` build). While `tor` is selected, the
  library also runs a Snowflake **proxy** in a hidden frame to give back to the network it uses.

There is no "direct" or "auto" route and no CORS guessing: same-origin requests (the page's own
files) may use the browser's `fetch`; everything else goes through the selected transport.

> **Experimental and unaudited.** This is a CORS workaround, not an anonymity tool, and it has not
> had a formal security audit. Tor path selection here is weaker than Tor Browser (no persistent
> guards, no relay family/subnet separation). Android WebView is untested. Sites see a Tor exit or
> your Tailscale exit node, **not** your address — but your accounts still identify you, and some
> sites block Tor exits. Treat executed/imported page code as trusted: routing only covers requests
> that go through this library, it is not a browser-wide network boundary.

## Install

Not on npm, on purpose: this is experimental. Use the source:

```sh
git clone <this repository> cors-rot
cd cors-rot
scripts/fetch-vendor.sh          # downloads the prebuilt WASM clients from the latest release (checksum verified)
#   or build them yourself:  build/build-webtor.sh  &&  build/build-tailscale.sh
```

Then copy the folder next to your app and serve it as static files (serve `.wasm` as
`application/wasm`, over HTTPS or `http://localhost`). No bundler, no build step for your app, no
dependencies beyond the vendored WASM. Every asset URL is resolved relative to `import.meta.url`, so
the folder works wherever you put it.

## Quick start

```js
import { createCorsRot } from './cors-rot/index.js';

const net = createCorsRot({ transport: 'tailscale' }); // or 'tor'

// Standard, streaming Response:
const response = await net.fetch('https://api.example.com/v1/thing', { method: 'POST', body });
for await (const chunk of response.body) { /* ... */ }

// Raw TLS stream (read()/write(bytes)/close()):
const stream = await net.connect('example.com', 443, { tls: true });

net.warmUp();                 // start the transport in the background
net.setTransport('tor');      // switch transports; starts/stops the Snowflake proxy
net.subscribe((s) => console.log(s.transport, s.torState));
```

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

### Lower-level exports (`index.js`)

`createBrowserNetwork`, `createTorClientOptions`, `createConnectionPool`, `poolKey`, `requestHttp`,
`validateHeaders`, `validateHttpUrl`, `createTailscaleManager`, `createSnowflakeProxy`,
`loadTorDirectory`, `saveTorDirectory`, `createGitHttp` (an `isomorphic-git` `http` plugin backed by
any fetch; `isomorphic-git` itself is **not** bundled).

## How it works

- **Tailscale transport.** `createTailscaleManager()` lazily loads `vendor/tailscale/` (Go→WASM, ~38
  MB, from `tailscale/cmd/tsconnect` with a small patch). The node joins the user's tailnet; sign-in,
  exit-node choice and state live in the provided `storage` (default `localStorage`). Requests are
  framed as HTTP/1.1 over a `connect()`/`connectTls()` stream that the WASM client proxies through the
  user's exit node. TLS for HTTPS is terminated **in the page** by Go's `crypto/tls`.
- **Tor transport.** `createBrowserNetwork()` lazily loads `vendor/webtor/` (patched `webtor-rs`). It
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
- **`vendor/webtor`** — patched `webtor-rs` (MIT) embedding **Arti** (MIT/Apache-2.0). Bundled Rust
  crates include **rustls**, **ring**, and **webpki-roots**; see `vendor/webtor/licenses/` for the
  per-crate notices (MPL-2.0 applies to parts of the rustls/webpki-roots stack).
- **`vendor/tailscale`** — Tailscale `cmd/tsconnect` (BSD-3-Clause), see `vendor/tailscale/LICENSE`.
- **`vendor/snowflake-proxy`** — the Tor Project's `snowflake-webext` core (BSD-3-Clause), see
  `vendor/snowflake-proxy/LICENSE`.

See each `vendor/*/PROVENANCE.md` for exact upstream commits and hashes.

## Build (regenerating the vendored WASM)

The two WebAssembly clients are **not committed**: they are built from pinned upstream sources plus
the patches in `build/patches/`, by GitHub Actions (`.github/workflows/build.yml`) on every push, and
published as release assets (`cors-rot-vendor.tar.gz` + `.sha256`) for every `v*` tag.
`scripts/fetch-vendor.sh [tag]` downloads and verifies them. To build locally:

```sh
build/build-webtor.sh       # Tor client: webtor-rs cba29fb4 + build/patches/webtor-rs/browser-streams-security.patch
                            # needs rustup (pinned nightly is installed), wasm-bindgen-cli 0.2.106, clang
build/build-tailscale.sh    # Tailscale client: tailscale f61c8685 + build/patches/tailscale/wasm_js.go.patch
                            # needs Go matching tailscale's go.mod (1.27.2)
build/build-snowflake-proxy.sh   # optional: re-creates the committed vendor/snowflake-proxy/snowflake-core.js
```

The Tor build refuses to publish if the WASM's exports differ from the reviewed allowlist
(`build/patches/webtor-rs/production-exports.*.txt`), so test-only hooks can never ship. Each build
writes `vendor/*/BUILD.txt` with toolchain versions and checksums. Background on the Tor client's
security fixes: `docs/`.

## Tests and demo

```sh
node --test tests/         # HTTP layer, pool, network (fake tor/tailscale), tor cache, preconnect
```

`demo/index.html` is a self-contained page (no external scripts): pick a transport, sign in to
Tailscale and choose an exit node, fetch a URL and stream the response, and do a raw TLS GET.
