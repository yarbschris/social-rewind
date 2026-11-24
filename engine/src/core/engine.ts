/**
 * The engine runs as two bundles in two WebKit content worlds:
 *
 *  page world     (startPage)      history + fetch/XHR patches. Must share the
 *                                  page's JS globals to wrap them. No bridge,
 *                                  no globals; the page can tamper with it, but
 *                                  only to weaken its own filtering.
 *  isolated world (startIsolated)  CSS/DOM filter, counter, identity, bridge.
 *                                  Invisible to page scripts.
 *
 * The worlds share only the DOM. The page world writes attributes on <html>
 * (data-sr-path, data-sr-event); the isolated world treats them as untrusted hints.
 * Native passes config to each bundle by closure (see docs/architecture.md).
 */
import { compile, type ActiveRules } from "./compile";
import { installCounter, type CounterDeps, type CounterHandle } from "./counter";
import { installDom, PATH_ATTR, type DomHandle } from "./dom";
import { installNetwork, type NetworkHandle } from "./network";
import { installRouter, type RouterHandle, type RouterHooks } from "./router";
import { send } from "./bridge";
import { ENGINE_VERSION, type BridgeEvent, type EngineConfig, type IdentityDef, type PlatformSettings } from "./types";

export const EVENT_ATTR = "data-sr-event";
const USERNAME_RE = /^[A-Za-z0-9._]{1,30}$/;

/** User scripts run on every main-frame origin (e.g. Facebook login); act only on the platform's own hosts. */
export function onPlatformHost(config: EngineConfig, hostname = location.hostname): boolean {
  return !config.hosts || config.hosts.includes(hostname);
}

function compatible(config: EngineConfig, onError: (m: string) => void): boolean {
  if (config.rules?.schemaVersion !== 1 || config.rules.minEngineVersion > ENGINE_VERSION) {
    onError(`incompatible rule pack (schema ${config.rules?.schemaVersion}, needs engine ${config.rules?.minEngineVersion})`);
    return false;
  }
  return true;
}

function guard<T>(name: string, onError: (m: string) => void, fn: () => T): T | null {
  try {
    return fn();
  } catch (e) {
    onError(`${name}: ${e instanceof Error ? e.message : String(e)}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Page world
// ---------------------------------------------------------------------------

export interface PageHandle {
  rules(): ActiveRules;
  stop(): void;
}

export interface PageDeps {
  win?: typeof globalThis;
  router?: Pick<RouterHooks, "replace">;
}

/** Hand an event to the isolated world through the shared DOM. */
function postToIsolated(event: BridgeEvent): void {
  try {
    document.documentElement.setAttribute(EVENT_ATTR, JSON.stringify(event));
  } catch {
    /* nothing to do */
  }
}

export function startPage(config: EngineConfig, deps: PageDeps = {}): PageHandle | null {
  if (!onPlatformHost(config)) return null;
  const onError = (message: string) => postToIsolated({ type: "error", message });
  if (!compatible(config, onError)) return null;

  const rules = compile(config, onError);
  const getRules = () => rules;

  const network: NetworkHandle | null = guard("network", onError, () => installNetwork(getRules, deps.win));
  const router: RouterHandle | null = guard("router", onError, () =>
    installRouter(getRules, {
      onPathChange: (p) => document.documentElement.setAttribute(PATH_ATTR, p),
      report: postToIsolated,
      ...deps.router,
    }),
  );

  return {
    rules: getRules,
    stop() {
      router?.uninstall();
      network?.uninstall();
    },
  };
}

// ---------------------------------------------------------------------------
// Isolated world
// ---------------------------------------------------------------------------

export interface PublicApi {
  readonly engineVersion: number;
  /** Apply CSS/DOM-affecting settings live. Route/network changes need a reload (native does this). */
  update(settings: PlatformSettings): void;
  postsViewed(): number;
  stop(): void;
}

export interface IsolatedDeps {
  counter?: CounterDeps;
}

export function resolveIdentity(def: IdentityDef, root: ParentNode = document): string | null {
  try {
    const value = root.querySelector(def.selector)?.getAttribute(def.attr);
    if (!value) return null;
    const u = new RegExp(def.pattern).exec(value)?.[1] ?? null;
    return u && USERNAME_RE.test(u) ? u : null;
  } catch {
    return null;
  }
}

/** Only forward well-formed, expected event types from the (untrusted) page world. */
export function sanitizePageEvent(raw: string | null): BridgeEvent | null {
  if (!raw || raw.length > 2000) return null;
  try {
    const e = JSON.parse(raw) as Record<string, unknown>;
    const str = (v: unknown) => (typeof v === "string" ? v.slice(0, 500) : undefined);
    if (e.type === "routeBlocked" && typeof e.path === "string" && typeof e.reason === "string") {
      const redirectedTo = str(e.redirectedTo);
      return { type: "routeBlocked", path: str(e.path)!, reason: str(e.reason)!, ...(redirectedTo ? { redirectedTo } : {}) };
    }
    if (e.type === "error" && typeof e.message === "string") return { type: "error", message: `page: ${str(e.message)}` };
  } catch {
    /* ignore */
  }
  return null;
}

export function startIsolated(initial: EngineConfig, deps: IsolatedDeps = {}): PublicApi | null {
  if (!onPlatformHost(initial)) return null;
  const onError = (message: string) => send({ type: "error", message });
  if (!compatible(initial, onError)) return null;

  let config: EngineConfig = { ...initial };
  let rules: ActiveRules = compile(config, onError);
  const getRules = () => rules;
  const html = document.documentElement;

  const dom: DomHandle | null = guard("dom", onError, () =>
    installDom(getRules, { debug: !!config.debug, grayscale: config.settings.grayscale }, onError),
  );
  // Counting always runs (stats and scroll reminders); settings.postCounter only controls native display.
  const counter: CounterHandle | null = config.rules.counter
    ? guard("counter", onError, () => installCounter(config.rules.counter!, deps.counter))
    : null;

  // Forward page-world events, and resolve the username, from one <html>/subtree observer.
  const forward = () => {
    const ev = sanitizePageEvent(html.getAttribute(EVENT_ATTR));
    if (ev) send(ev);
  };
  const eventObserver = new MutationObserver((records) => {
    for (const r of records) {
      if (r.attributeName === EVENT_ATTR) forward();
      else if (r.attributeName === PATH_ATTR) dom?.pathChanged();
    }
  });
  eventObserver.observe(html, { attributes: true, attributeFilter: [EVENT_ATTR, PATH_ATTR] });
  forward();

  // Identity: keep checking (throttled) so an account switch corrects a stale username.
  // Native validates the value and reloads with it; the page-world router then uses it.
  let identityObserver: MutationObserver | null = null;
  const identity = config.rules.identity;
  if (identity) {
    let last = 0;
    let reported = config.username;
    const tryResolve = () => {
      const now = Date.now();
      if (now - last < 1000) return;
      last = now;
      const u = resolveIdentity(identity);
      if (u && u !== reported) {
        reported = u;
        send({ type: "identity", username: u });
      }
    };
    identityObserver = new MutationObserver(tryResolve);
    identityObserver.observe(html, { childList: true, subtree: true });
    tryResolve();
  }

  send({ type: "ready", engineVersion: ENGINE_VERSION, rulesRevision: config.rules.revision });

  return {
    engineVersion: ENGINE_VERSION,
    update(settings) {
      config = { ...config, settings };
      rules = compile(config, onError);
      dom?.refresh({ debug: !!config.debug, grayscale: config.settings.grayscale });
    },
    postsViewed: () => counter?.count() ?? 0,
    stop() {
      eventObserver.disconnect();
      identityObserver?.disconnect();
      counter?.uninstall();
      dom?.uninstall();
    },
  };
}
