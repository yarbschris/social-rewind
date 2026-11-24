import type { CounterDef } from "./types";
import { HIDDEN_ATTR } from "./dom";
import { send } from "./bridge";

export interface CounterHandle {
  scan(root: ParentNode): void;
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

/** Count each unique post once it has been at least `minVisibleRatio` visible for `minVisibleMs`. */
export function installCounter(def: CounterDef, deps: CounterDeps = {}): CounterHandle {
  const IO = deps.IntersectionObserver ?? globalThis.IntersectionObserver;
  const setT = deps.setTimeout ?? ((fn, ms) => globalThis.setTimeout(fn, ms));
  const clearT = deps.clearTimeout ?? ((h) => globalThis.clearTimeout(h as number));
  const ratio = def.minVisibleRatio ?? 0.5;
  const ms = def.minVisibleMs ?? 1000;

  const seen = new Set<string>();
  const observed = new WeakSet<Element>();
  const timers = new Map<Element, unknown>();

  const commit = (el: Element) => {
    if (!el.isConnected || el.closest(`[${HIDDEN_ATTR}]`)) return;
    const key = keyFor(el, def);
    if (!key || seen.has(key)) return;
    seen.add(key);
    send({ type: "postViewed", key, sessionCount: seen.size });
  };

  if (typeof IO !== "function") {
    return { scan() {}, count: () => seen.size, uninstall() {} };
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
    count: () => seen.size,
    uninstall() {
      mo.disconnect();
      io.disconnect();
      for (const t of timers.values()) clearT(t);
      timers.clear();
    },
  };
}
