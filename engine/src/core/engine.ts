import { compile, type ActiveRules } from "./compile";
import { installCounter, type CounterDeps, type CounterHandle } from "./counter";
import { installDom, type DomHandle } from "./dom";
import { installNetwork, type NetworkHandle } from "./network";
import { installRouter, type RouterHandle } from "./router";
import { send } from "./bridge";
import { ENGINE_VERSION, type EngineConfig, type IdentityDef, type PlatformSettings } from "./types";

export interface PublicApi {
  readonly engineVersion: number;
  /** Apply new settings without reloading (called by native). */
  update(settings: PlatformSettings): void;
  /** Tell the engine the username (e.g. entered manually in native settings). */
  setUsername(username: string): void;
  postsViewed(): number;
  stop(): void;
}

export interface StartDeps {
  counter?: CounterDeps;
  win?: typeof globalThis;
}

export function resolveIdentity(def: IdentityDef, root: ParentNode = document): string | null {
  try {
    const value = root.querySelector(def.selector)?.getAttribute(def.attr);
    if (!value) return null;
    return new RegExp(def.pattern).exec(value)?.[1] ?? null;
  } catch {
    return null;
  }
}

export function start(initial: EngineConfig, deps: StartDeps = {}): PublicApi | null {
  const reportError = (message: string) => send({ type: "error", message });

  if (initial.rules?.schemaVersion !== 1 || initial.rules.minEngineVersion > ENGINE_VERSION) {
    reportError(`incompatible rule pack (schema ${initial.rules?.schemaVersion}, needs engine ${initial.rules?.minEngineVersion})`);
    return null;
  }

  let config: EngineConfig = { ...initial };
  let rules: ActiveRules = compile(config, reportError);
  const getRules = () => rules;

  // Each layer is isolated: one failing must not disable the others.
  const guard = <T>(name: string, fn: () => T): T | null => {
    try {
      return fn();
    } catch (e) {
      reportError(`${name}: ${e instanceof Error ? e.message : String(e)}`);
      return null;
    }
  };

  const network: NetworkHandle | null = guard("network", () => installNetwork(getRules, deps.win));
  const dom: DomHandle | null = guard("dom", () =>
    installDom(getRules, { debug: !!config.debug, grayscale: config.settings.grayscale }, reportError),
  );
  const router: RouterHandle | null = guard("router", () => installRouter(getRules, (p) => dom?.setPath(p)));
  const counter: CounterHandle | null = config.rules.counter
    ? guard("counter", () => installCounter(config.rules.counter!, deps.counter))
    : null;

  const recompile = () => {
    rules = compile(config, reportError);
    dom?.refresh({ debug: !!config.debug, grayscale: config.settings.grayscale });
    router?.check();
  };

  const setUsername = (username: string) => {
    if (!username || username === config.username) return;
    config = { ...config, username };
    send({ type: "identity", username });
    recompile();
  };

  // Resolve the username from the page if we don't know it (throttled).
  let identityObserver: MutationObserver | null = null;
  const identity = config.rules.identity;
  if (identity && !config.username) {
    let last = 0;
    const tryResolve = () => {
      const now = Date.now();
      if (now - last < 500) return;
      last = now;
      const u = resolveIdentity(identity);
      if (u) {
        identityObserver?.disconnect();
        identityObserver = null;
        setUsername(u);
      }
    };
    identityObserver = new MutationObserver(tryResolve);
    identityObserver.observe(document.documentElement, { childList: true, subtree: true });
    tryResolve();
  }

  send({ type: "ready", engineVersion: ENGINE_VERSION, rulesRevision: config.rules.revision });

  return {
    engineVersion: ENGINE_VERSION,
    update(settings) {
      config = { ...config, settings };
      recompile();
    },
    setUsername,
    postsViewed: () => counter?.count() ?? 0,
    stop() {
      identityObserver?.disconnect();
      counter?.uninstall();
      router?.uninstall();
      dom?.uninstall();
      network?.uninstall();
    },
  };
}
