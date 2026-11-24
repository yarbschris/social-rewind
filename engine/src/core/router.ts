import type { ActiveRules } from "./compile";
import { send } from "./bridge";

export type RouteDecision =
  | { action: "allow" }
  | { action: "redirect"; to: string; reason: string }
  | { action: "block"; reason: string };

function normalize(path: string): string {
  return path.endsWith("/") ? path : `${path}/`;
}

/** Pure routing decision for a pathname. */
export function evaluateRoute(pathname: string, rules: ActiveRules): RouteDecision {
  if (rules.alwaysAllow.some((r) => r.test(pathname))) return { action: "allow" };

  const mode = rules.mode;
  if (mode) {
    const isHome = mode.home !== null && normalize(pathname) === normalize(mode.home);
    const allowedByMode = isHome || mode.allow.some((r) => r.test(pathname));
    if (!allowedByMode) {
      // Home not resolvable yet (needs username): let "/" render; mode CSS hides its content.
      if (mode.home === null) {
        return pathname === "/" ? { action: "allow" } : { action: "redirect", to: "/", reason: mode.id };
      }
      return { action: "redirect", to: mode.home, reason: mode.id };
    }
  }

  for (const route of rules.routes) {
    const m = route.pattern.exec(pathname);
    if (!m) continue;
    if (route.action === "redirect" && route.to) {
      const to = route.to.replace(/\$(\d)/g, (_, n: string) => m[Number(n)] ?? "");
      if (normalize(to) === normalize(pathname)) continue; // never redirect to self
      // If a mode is active, the redirect target itself must be reachable; otherwise use mode home.
      if (mode && mode.home && evaluateRoute(to, { ...rules, routes: [] }).action !== "allow") {
        return { action: "redirect", to: mode.home, reason: route.id };
      }
      return { action: "redirect", to, reason: route.id };
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

export interface RouterHandle {
  /** Re-check the current location (after settings change or identity resolves). */
  check(): void;
  uninstall(): void;
}

/**
 * Enforce route decisions for SPA navigations (history API), back/forward,
 * link clicks, and the initial load. Hard navigation (location.replace) is the
 * fallback because we can't rely on the site's router to honor a swallowed pushState.
 */
export function installRouter(getRules: () => ActiveRules, onPathChange: (path: string) => void): RouterHandle {
  const origPush = history.pushState.bind(history);
  const origReplace = history.replaceState.bind(history);

  const report = (path: string, d: RouteDecision) => {
    if (d.action === "allow") return;
    send({
      type: "routeBlocked",
      path,
      reason: d.reason,
      ...(d.action === "redirect" ? { redirectedTo: d.to } : {}),
    });
  };

  const wrap =
    (orig: typeof history.pushState) =>
    (data: unknown, unused: string, url?: string | URL | null): void => {
      const path = toPathname(url);
      if (path === null) return orig(data, unused, url);
      const d = evaluateRoute(path, getRules());
      report(path, d);
      if (d.action === "allow") {
        orig(data, unused, url);
        onPathChange(path);
      } else if (d.action === "redirect") {
        location.replace(d.to);
      }
      // block: swallow the navigation; the URL (and, for most routers, the view) stays put.
    };

  history.pushState = wrap(origPush);
  history.replaceState = wrap(origReplace);

  const check = () => {
    const path = location.pathname;
    const d = evaluateRoute(path, getRules());
    report(path, d);
    if (d.action === "redirect") location.replace(d.to);
    else if (d.action === "block") location.replace(getRules().mode?.home ?? "/");
    onPathChange(path);
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
    if (d.action === "redirect") location.assign(d.to);
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
