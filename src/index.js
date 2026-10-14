// cors-rot — the browser networking stack of Self Forming, as a source-only library.
// Experimental and unaudited. See ./README.md for what it is, how it works, and its security notes.
//
// Two transports only: 'tailscale' (default; the user's own exit node) and 'tor' (Tor over
// Snowflake). While 'tor' is selected, a Snowflake proxy runs to give back to the network.
//
//   import { createCorsRot } from './cors-rot/index.js';
//   const net = createCorsRot({ transport: 'tailscale' });
//   const response = await net.fetch('https://example.org/');   // standard streaming Response
//
// All vendored WASM/assets are resolved relative to import.meta.url, so this folder can be copied
// anywhere and served as static files (serve .wasm as application/wasm).
import { createBrowserNetwork, createTorClientOptions } from './network.js';
import { createTailscaleManager } from './tailscale.js';
import { createSnowflakeProxy } from './snowflake.js';

// Lower-level building blocks, re-exported for advanced callers and tests.
export { createBrowserNetwork, createTorClientOptions } from './network.js';
export { createConnectionPool, poolKey, requestHttp, validateHeaders, validateHttpUrl } from './http-stream.js';
export { createTailscaleManager } from './tailscale.js';
export { createSnowflakeProxy } from './snowflake.js';
export { loadTorDirectory, saveTorDirectory } from './tor-cache.js';
export { createGitHttp } from './git-http.js';

/**
 * createCorsRot(options) -> a bundled networking stack.
 *
 * options:
 *   transport   'tailscale' (default) | 'tor'
 *   tailscale   { storage, hostname }         forwarded to the Tailscale manager
 *   tor         { ... }                       forwarded to the network (timeoutMs, maxRedirects, ...)
 *   onStatus    (snapshot) => void            network status observer
 *   timeoutMs   per setup stage / HTTP exchange (default 120000)
 *   nativeFetch fetch used for same-origin and WASM asset loading (default globalThis.fetch)
 *   keepAlive   false to disable connection pooling
 *   document    DOM document for the Snowflake frame (default globalThis.document)
 *
 * Returns:
 *   fetch(input, init)          standard streaming Response through the selected transport
 *   fetchTor(input, init)       explicit Tor, regardless of the selected transport
 *   connect(host, port, {tls})  raw stream through the selected transport
 *   preconnect(url)             warm a connection into the keep-alive pool
 *   warmUp()                    start the selected transport in the background
 *   setTransport(name)          'tailscale' | 'tor'
 *   getStatus()                 status snapshot (includes `transport`)
 *   subscribe(cb)               status subscription; returns an unsubscribe function
 *   tailscale                   { start, getStatus, subscribe, setExitNode, login, logout }
 *   snowflakeProxy              { getStatus, subscribe }
 *   network                     the lower-level network object (fetchTor, getMode, ...)
 */
export function createCorsRot({
  transport = 'tailscale',
  tailscale = {},
  tor = {},
  onStatus,
  timeoutMs,
  nativeFetch,
  keepAlive,
  document = globalThis.document,
} = {}) {
  const ts = createTailscaleManager(tailscale);
  const network = createBrowserNetwork({
    mode: transport,
    tailscale: ts,
    onStatus,
    nativeFetch,
    ...(keepAlive === undefined ? {} : { keepAlive }),
    ...(timeoutMs === undefined ? {} : { timeoutMs }),
    ...tor,
  });
  const snowflakeProxy = createSnowflakeProxy({ network, document });

  return {
    fetch: (input, init) => network.fetch(input, init),
    fetchTor: (input, init) => network.fetchTor(input, init),
    connect: (host, port, options) => network.connect(host, port, options),
    preconnect: (url) => network.preconnect(url),
    warmUp: () => network.warmUp(),
    setTransport: (name) => network.setMode(name),
    getStatus: () => network.getStatus(),
    subscribe: (cb) => network.subscribe(cb),
    tailscale: {
      start: () => ts.start(),
      getStatus: () => ts.getStatus(),
      subscribe: (cb) => ts.subscribe(cb),
      setExitNode: (id) => ts.setExitNode(id),
      login: () => ts.login(),
      logout: () => ts.logout(),
    },
    snowflakeProxy,
    network,
  };
}
