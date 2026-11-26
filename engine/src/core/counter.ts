import type { CounterDef } from "./types";
import { HIDDEN_ATTR } from "./dom";
import { send } from "./bridge";

export interface CounterHandle {
  scan(root: ParentNode): void;
  /** Call after every navigation: a post or reel page counts once the user stays on it. */
  pathChanged(path: string): void;
  count(): number;
  uninstall(): void;
}

export interface CounterDeps {
  IntersectionObserver?: typeof IntersectionObserver;
  setTimeout?: (fn: () => void, ms: number) => unknown;
  clearTimeout?: (h: unknown) => void;
}

export function keyFor(el: Element, def: CounterDef): string | null {
  let value: string | null = null;
  try {
    value = el.querySelector(def.key.selector)?.getAttribute(def.key.attr) ?? null;
  } catch {
    return null;
  }
  if (!value) return null;
  if (!def.key.pattern) return value;
  try {
    const m = new RegExp(def.key.pattern).exec(value);
    return m ? (m[1] ?? m[0]) : null;
  } catch {
    return null;
  }
}

/** The key for a single-post page, from the first `routes` pattern that matches the path. */
export function routeKeyFor(path: string, routes: RegExp[]): string | null {
  for (const re of routes) {
    const m = re.exec(path);
    if (m) return m[1] ?? m[0];
  }
  return null;
}

/**
 * Count each unique post once it has been at least `minVisibleRatio` visible for `minVisibleMs`,
 * and each post or reel page (`routes`) the user stays on for `minVisibleMs`. A post opened from
 * DMs, Saved or a profile is its own page, often without a feed-style article to observe.
 */
export function installCounter(def: CounterDef, deps: CounterDeps = {}, initialPath = location.pathname): CounterHandle {
  const IO = deps.IntersectionObserver ?? globalThis.IntersectionObserver;
  const setT = deps.setTimeout ?? ((fn, ms) => globalThis.setTimeout(fn, ms));
  const clearT = deps.clearTimeout ?? ((h) => globalThis.clearTimeout(h as number));
  const ratio = def.minVisibleRatio ?? 0.5;
  const ms = def.minVisibleMs ?? 1000;

  const seen = new Set<string>();
  const observed = new WeakSet<Element>();
  const timers = new Map<Element, unknown>();

  const record = (key: string) => {
    if (seen.has(key)) return;
    seen.add(key);
    send({ type: "postViewed", key, sessionCount: seen.size });
  };

  const commit = (el: Element) => {
    if (!el.isConnected || el.closest(`[${HIDDEN_ATTR}]`)) return;
    const key = keyFor(el, def);
    if (key) record(key);
  };

  const routes: RegExp[] = [];
  for (const pattern of def.routes ?? []) {
    try {
      routes.push(new RegExp(pattern));
    } catch {
      // An invalid pattern counts nothing; the schema and tests catch it before release.
    }
  }
  let currentPath: string | null = null;
  let routeTimer: unknown;
  const pathChanged = (path: string) => {
    if (path === currentPath) return;
    currentPath = path;
    if (routeTimer !== undefined) {
      clearT(routeTimer);
      routeTimer = undefined;
    }
    const key = routeKeyFor(path, routes);
    if (!key || seen.has(key)) return;
    routeTimer = setT(() => {
      routeTimer = undefined;
      if (currentPath === path) record(key);
    }, ms);
  };
  pathChanged(initialPath);
  const stopRouteTimer = () => {
    if (routeTimer !== undefined) clearT(routeTimer);
    routeTimer = undefined;
  };

  if (typeof IO !== "function") {
    return { scan() {}, pathChanged, count: () => seen.size, uninstall: stopRouteTimer };
  }

  const io = new IO(
    (entries) => {
      for (const e of entries) {
        const visible = e.isIntersecting && e.intersectionRatio >= ratio;
        const pending = timers.get(e.target);
        if (visible && pending === undefined) {
          timers.set(
            e.target,
            setT(() => {
              timers.delete(e.target);
              commit(e.target);
            }, ms),
          );
        } else if (!visible && pending !== undefined) {
          clearT(pending);
          timers.delete(e.target);
        }
      }
    },
    { threshold: [0, ratio] },
  );

  const scan = (root: ParentNode) => {
    let items: Element[] = [];
    try {
      items = [...root.querySelectorAll(def.item)];
      if (root instanceof Element && root.matches(def.item)) items.push(root);
    } catch {
      return;
    }
    for (const el of items) {
      if (observed.has(el)) continue;
      observed.add(el);
      io.observe(el);
    }
  };

  const mo = new MutationObserver((records) => {
    for (const r of records) for (const n of r.addedNodes) if (n.nodeType === Node.ELEMENT_NODE) scan(n as Element);
  });
  mo.observe(document.documentElement, { childList: true, subtree: true });
  scan(document);

  return {
    scan,
    pathChanged,
    count: () => seen.size,
    uninstall() {
      stopRouteTimer();
      mo.disconnect();
      io.disconnect();
      for (const t of timers.values()) clearT(t);
      timers.clear();
    },
  };
}
