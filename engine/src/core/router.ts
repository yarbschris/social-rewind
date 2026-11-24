import type { ActiveRules } from "./compile";
import type { BridgeEvent } from "./types";

export type RouteDecision =
  | { action: "allow" }
  | { action: "redirect"; to: string; reason: string; byMode: boolean }
  | { action: "block"; reason: string };

function normalize(path: string): string {
  return path.endsWith("/") ? path : `${path}/`;
}

/**
 * A redirect target from a rule pack must be a plain same-origin path:
 * starts with one "/", no "//" or "\" (which browsers treat as host separators),
 * no scheme, no control characters.
 */
export function isSafePath(to: string): boolean {
  // eslint-disable-next-line no-control-regex
  return /^\/(?![/\\])/.test(to) && !to.includes("\\") && !to.includes("://") && !/[\u0000-\u001f\u007f]/.test(to);
}

/** Pure routing decision for a pathname. */
export function evaluateRoute(pathname: string, rules: ActiveRules): RouteDecision {
  if (rules.alwaysAllow.some((r) => r.test(pathname))) return { action: "allow" };

  const mode = rules.mode;
  if (mode) {
    const isHome = mode.home !== null && normalize(pathname) === normalize(mode.home);
    const allowedByMode = isHome || mode.allow.some((r) => r.test(pathname));
    if (!allowedByMode) {
      // Home not resolvable yet (needs username): let "/" render until identity is known.
      if (mode.home === null) {
        return pathname === "/" ? { action: "allow" } : { action: "redirect", to: "/", reason: mode.id, byMode: true };
      }
      return { action: "redirect", to: mode.home, reason: mode.id, byMode: true };
    }
  }

  for (const route of rules.routes) {
    const m = route.pattern.exec(pathname);
    if (!m) continue;
    if (route.action === "redirect" && route.to) {
      const to = route.to.replace(/\$(\d)/g, (_, n: string) => encodeURIComponent(m[Number(n)] ?? ""));
      if (!isSafePath(to)) return { action: "block", reason: `${route.id}:unsafe-target` };
      if (normalize(to) === normalize(pathname)) continue; // never redirect to self
      // If a mode is active, the redirect target itself must be reachable; otherwise use mode home.
      if (mode && mode.home && evaluateRoute(to, { ...rules, routes: [] }).action !== "allow") {
        return { action: "redirect", to: mode.home, reason: route.id, byMode: true };
      }
      return { action: "redirect", to, reason: route.id, byMode: false };
    }
    return { action: "block", reason: route.id };
  }
  return { action: "allow" };
}

function toPathname(url: string | URL | null | undefined): string | null {
  if (url === null || url === undefined) return null;
  try {
    const u = new URL(String(url), location.href);
    if (u.origin !== location.origin) return null;
    return u.pathname;
  } catch {
    return null;
  }
}

/** Resolve a decided target against our origin; null if it would leave it. */
function sameOriginHref(to: string): string | null {
  try {
    const u = new URL(to, location.origin);
    return u.origin === location.origin ? u.href : null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Loop breaker: forced navigations survive reloads via sessionStorage. If a site
// interstitial or a bad pack makes us bounce, stop enforcing instead of storming.
// ---------------------------------------------------------------------------

const LOOP_KEY = "socialRewind.forcedNavs";
export const LOOP_LIMIT = 3;
export const LOOP_WINDOW_MS = 10_000;
let memoryNavs: number[] = [];

function readNavs(): number[] {
  try {
    const raw = sessionStorage.getItem(LOOP_KEY);
    return raw ? (JSON.parse(raw) as number[]).filter((n) => typeof n === "number") : [];
  } catch {
    return memoryNavs;
  }
}

function writeNavs(navs: number[]): void {
  memoryNavs = navs;
  try {
    sessionStorage.setItem(LOOP_KEY, JSON.stringify(navs));
  } catch {
    /* storage unavailable: in-memory only */
  }
}

/** Record a forced navigation; returns false if we're looping and must not navigate. */
export function allowForcedNavigation(now = Date.now()): boolean {
  const recent = readNavs().filter((t) => now - t < LOOP_WINDOW_MS);
  if (recent.length >= LOOP_LIMIT) {
    writeNavs(recent);
    return false;
  }
  writeNavs([...recent, now]);
  return true;
}

export function resetLoopBreaker(): void {
  writeNavs([]);
}

// ---------------------------------------------------------------------------

export interface RouterHandle {
  /** Re-check the current location (after settings change or identity resolves). */
  check(): void;
  uninstall(): void;
}

export interface RouterHooks {
  onPathChange(path: string): void;
  report(event: BridgeEvent): void;
  /** Navigation primitives (injectable for tests). */
  assign?(href: string): void;
  replace?(href: string): void;
}

/**
 * Enforce route decisions for SPA navigations (history API), back/forward,
 * link clicks, and the initial load. This is best-effort: the native shell
 * observes the web view URL as the authoritative backstop.
 */
export function installRouter(getRules: () => ActiveRules, hooks: RouterHooks): RouterHandle {
  const origPush = history.pushState.bind(history);
  const origReplace = history.replaceState.bind(history);
  const assign = hooks.assign ?? ((href: string) => location.assign(href));
  const replace = hooks.replace ?? ((href: string) => location.replace(href));

  const report = (path: string, d: RouteDecision) => {
    if (d.action === "allow") return;
    hooks.report({
      type: "routeBlocked",
      path,
      reason: d.reason,
      ...(d.action === "redirect" ? { redirectedTo: d.to } : {}),
    });
  };

  const navigate = (to: string, how: "assign" | "replace") => {
    const href = sameOriginHref(to);
    if (!href) {
      hooks.report({ type: "error", message: `refused off-origin redirect: ${to}` });
      return;
    }
    if (!allowForcedNavigation()) {
      hooks.report({ type: "error", message: `redirect loop detected at ${location.pathname}; enforcement paused` });
      return;
    }
    (how === "assign" ? assign : replace)(href);
  };

  const wrap =
    (orig: typeof history.pushState, how: "assign" | "replace") =>
    (data: unknown, unused: string, url?: string | URL | null): void => {
      const path = toPathname(url);
      if (path === null) return orig(data, unused, url);
      const d = evaluateRoute(path, getRules());
      report(path, d);
      if (d.action === "allow") {
        orig(data, unused, url);
        hooks.onPathChange(path);
      } else if (d.action === "redirect") {
        // push → assign keeps the page the user was on in history; replace stays replace.
        navigate(d.to, how);
      }
      // block: swallow. Native URL observation is the backstop if the site renders anyway.
    };

  history.pushState = wrap(origPush, "assign");
  history.replaceState = wrap(origReplace, "replace");

  const check = () => {
    const path = location.pathname;
    const d = evaluateRoute(path, getRules());
    report(path, d);
    if (d.action === "redirect") navigate(d.to, "replace");
    else if (d.action === "block") navigate(getRules().mode?.home ?? "/", "replace");
    else hooks.onPathChange(path);
  };

  const onPop = () => check();

  const onClick = (e: MouseEvent) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const a = (e.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
    if (!a) return;
    const path = toPathname(a.getAttribute("href"));
    if (path === null) return;
    const d = evaluateRoute(path, getRules());
    if (d.action === "allow") return;
    e.preventDefault();
    e.stopImmediatePropagation();
    report(path, d);
    // Mode-blocked links are simply inert: reloading to the mode home would lose
    // the user's place (e.g. a DM thread and its draft).
    if (d.action === "redirect" && !d.byMode && normalize(d.to) !== normalize(location.pathname)) {
      navigate(d.to, "assign");
    }
  };

  addEventListener("popstate", onPop);
  addEventListener("click", onClick, true);
  check();

  return {
    check,
    uninstall() {
      history.pushState = origPush;
      history.replaceState = origReplace;
      removeEventListener("popstate", onPop);
      removeEventListener("click", onClick, true);
    },
  };
}
