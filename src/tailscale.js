// Tailscale transport manager for the browser edition: an in-page Tailscale node (Go->WASM,
// vendor/tailscale) that joins the user's tailnet and sends requests out through the user's own
// exit node (Settings -> Network -> "Through my Tailscale exit node").
//  - The 38 MB client loads only when Tailscale mode is used (start()).
//  - Login state is kept in this browser (localStorage), so reloads do not ask to sign in again.
//  - The chosen exit node is remembered; with exactly one online exit node it is chosen automatically.
const STATE_PREFIX = "self-forming.tailscale.state.";
const EXIT_KEY = "self-forming.tailscale.exit-node";

export function createTailscaleManager({ storage = globalThis.localStorage, hostname = "self-forming-browser" } = {}) {
  let client;
  let starting;
  let state = "off";        // off | loading | NoState | NeedsLogin | NeedsMachineAuth | Starting | Running | Stopped | error
  let loginURL;
  let exitNodes = [];
  let error;
  let appliedExit;           // exit node id/ip currently applied to the running client
  const listeners = new Set();

  const read = (key) => { try { return storage?.getItem(key) ?? ""; } catch { return ""; } };
  const write = (key, value) => { try { value ? storage?.setItem(key, value) : storage?.removeItem(key); } catch { /* not persisted */ } };
  const chosenExit = () => read(EXIT_KEY);
  const view = () => ({ state, loginURL, exitNodes: exitNodes.map((n) => ({ ...n })), selectedExitNode: chosenExit() || null, appliedExitNode: appliedExit ?? null, error });
  const notify = () => { for (const listener of listeners) { try { listener(view()); } catch { /* UI only */ } } };
  const nodeStorage = {
    getState: (id) => read(STATE_PREFIX + id),
    setState: (id, value) => write(STATE_PREFIX + id, value),
  };

  async function applyExit() {
    if (!client || state !== "Running") return;
    let wanted = chosenExit();
    const online = exitNodes.filter((n) => n.online);
    if (!wanted && online.length === 1) { wanted = online[0].id; write(EXIT_KEY, wanted); }
    if (!wanted || wanted === appliedExit) return;
    try { await client.setExitNode(wanted); appliedExit = wanted; error = undefined; }
    catch (cause) { error = `Could not use that exit node: ${cause?.message ?? cause}`; }
    notify();
  }

  function start() {
    starting ??= (async () => {
      state = "loading"; error = undefined; notify();
      const { createTailscaleClient } = await import("./vendor/tailscale/tailscale-client.js");
      client = await createTailscaleClient({
        storage: nodeStorage,
        hostname,
        onLoginURL: (url) => { loginURL = url; notify(); },
        onStatus: (s) => {
          state = s.state;
          exitNodes = Array.isArray(s.exitNodes) ? s.exitNodes : [];
          if (state === "Running") { loginURL = undefined; void applyExit(); }
          notify();
        },
      });
      return client;
    })().catch((cause) => {
      state = "error"; error = String(cause?.message ?? cause); starting = undefined; notify();
      throw cause;
    });
    return starting;
  }

  return {
    start,
    getStatus: view,
    subscribe(listener) { listeners.add(listener); listener(view()); return () => listeners.delete(listener); },
    /** The client when it can carry traffic right now (signed in, exit node applied), else undefined. */
    readyClient: () => (client && state === "Running" && appliedExit ? client : undefined),
    /** Resolves with a client ready to carry internet traffic, or fails with what the user must do. */
    async getClient() {
      await start();
      if (state === "NeedsLogin" || state === "NeedsMachineAuth") {
        throw Object.assign(new Error("Sign in to Tailscale in Settings → Network first."), { code: "TAILSCALE_LOGIN" });
      }
      if (state !== "Running") await client.whenRunning(60000);
      await applyExit();
      if (!appliedExit) {
        throw Object.assign(new Error(exitNodes.some((n) => n.online)
          ? "Choose a Tailscale exit node in Settings → Network."
          : "No Tailscale exit node is online in your tailnet (or your access rules don't allow this device to use one)."), { code: "TAILSCALE_EXIT_NODE" });
      }
      return client;
    },
    async setExitNode(id) {
      write(EXIT_KEY, id || "");
      appliedExit = undefined;
      if (!id) { try { await client?.clearExitNode(); } catch { /* ignore */ } notify(); return; }
      await applyExit();
    },
    login() { client?.login(); },
    async logout() {
      try { client?.logout(); } catch { /* ignore */ }
      appliedExit = undefined; loginURL = undefined;
      try { for (const key of Object.keys(storage ?? {})) if (key.startsWith(STATE_PREFIX)) storage.removeItem(key); } catch { /* ignore */ }
      notify();
      // Ask for a fresh login link so the user can sign in again (or with another account).
      setTimeout(() => { try { client?.login(); } catch { /* ignore */ } }, 1000);
    },
  };
}
