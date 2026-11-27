import type { ActiveRules } from "./compile";
import type { BridgeEvent } from "./types";

export type RouteDecision =
  | { action: "allow" }
  | { action: "redirect"; to: string; reason: string; byMode: boolean; navigateInApp?: boolean }
  | { action: "block"; reason: string };

function normalize(path: string): string {
  return path.endsWith("/") ? path : `${path}/`;
}

/** Split a same-origin target ("/path?query") into its path and search ("" or "?…"). */
function splitTarget(target: string): { path: string; search: string } {
  const q = target.indexOf("?");
  return q < 0 ? { path: target, search: "" } : { path: target.slice(0, q), search: target.slice(q) };
}

/** Whether `here` (path + search) is the place `target` names. A target without a query ignores it. */
function samePlace(here: string, target: string): boolean {
  const a = splitTarget(here);
  const b = splitTarget(target);
  return normalize(a.path) === normalize(b.path) && (b.search === "" || a.search === b.search);
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

/** How many redirects in a row are followed before giving up and using the last target. */
const MAX_REDIRECT_CHAIN = 3;

/**
 * Pure routing decision for a pathname and its search ("" or "?…"). A redirect whose target
 * is itself redirected (e.g. Reels → "/" → the Following feed) goes straight to the end of the
 * chain, so one forced navigation is enough.
 */
export function evaluateRoute(pathname: string, rules: ActiveRules, search = "", depth = 0): RouteDecision {
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
    if (route.search && !route.search.test(search)) continue;
    if (route.action === "redirect" && route.to) {
      const to = route.to.replace(/\$(\d)/g, (_, n: string) => encodeURIComponent(m[Number(n)] ?? ""));
      if (!isSafePath(to)) return { action: "block", reason: `${route.id}:unsafe-target` };
      if (samePlace(pathname + search, to)) continue; // never redirect to self
      // If a mode is active, the redirect target itself must be reachable; otherwise use mode home.
      const target = splitTarget(to);
      if (mode && mode.home && evaluateRoute(target.path, { ...rules, routes: [] }, target.search).action !== "allow") {
        return { action: "redirect", to: mode.home, reason: route.id, byMode: true };
      }
      let final = to;
      if (depth < MAX_REDIRECT_CHAIN) {
        const onward = evaluateRoute(target.path, rules, target.search, depth + 1);
        if (onward.action === "redirect" && !onward.byMode) final = onward.to;
      }
      return { action: "redirect", to: final, reason: route.id, byMode: false, ...(route.navigateInApp ? { navigateInApp: true } : {}) };
    }
    return { action: "block", reason: route.id };
  }
  return { action: "allow" };
}

function toLocation(url: string | URL | null | undefined): { path: string; search: string } | null {
  if (url === null || url === undefined) return null;
  try {
    const u = new URL(String(url), location.href);
    if (u.origin !== location.origin) return null;
    return { path: u.pathname, search: u.search };
  } catch {
    return null;
  }
}

const here = () => location.pathname + location.search;

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
  /** Navigation primitive (injectable for tests). */
  replace?(href: string): void;
  /** history.back (injectable for tests). */
  back?(): void;
  /** How long to wait for history.back() to land before reloading instead (ms). */
  backTimeoutMs?: number;
}

/**
 * Enforce route decisions. This is best-effort: the native shell observes the
 * web view URL as the authoritative backstop.
 *
 * - In-app navigation (pushState/replaceState, link taps) to a filtered page is
 *   **inert**: nothing happens. Redirecting here would force a full page reload,
 *   since we can't drive the site's router, which loses the user's place.
 * - Except a way out of a **mode** (pushState/replaceState or a link tap): reload
 *   to the mode's home. The site may render the new page even when its URL change
 *   is swallowed (Instagram's inbox back button does), a mode is a lock, and its
 *   home is where "back" should land (a DM thread's back button links to a profile).
 *   When the user came from the mode's home, this is history.back() (no reload).
 * - Page loads and back/forward (check) redirect to an allowed page, since there
 *   is no previous page to stay on. These go through the loop breaker.
 */
export function installRouter(getRules: () => ActiveRules, hooks: RouterHooks): RouterHandle {
  const origPush = history.pushState.bind(history);
  const origReplace = history.replaceState.bind(history);
  const replace = hooks.replace ?? ((href: string) => location.replace(href));
  const back = hooks.back ?? (() => history.back());
  // The page the user was on before the current one (path + search), when we know it: set by
  // our own allowed pushState, unknown (null) after back/forward or a page load.
  let prevPath: string | null = null;

  const report = (path: string, d: RouteDecision) => {
    if (d.action === "allow") return;
    // A redirect that takes part in normal navigation (Home → Following feed) isn't a block:
    // reporting it would show "Blocked by your settings" on every Home tap.
    if (d.action === "redirect" && d.navigateInApp) return;
    hooks.report({
      type: "routeBlocked",
      path,
      reason: d.reason,
      ...(d.action === "redirect" ? { redirectedTo: d.to } : {}),
    });
  };

  const navigate = (to: string) => {
    const href = sameOriginHref(to);
    if (!href) {
      hooks.report({ type: "error", message: `refused off-origin redirect: ${to}` });
      return;
    }
    if (!allowForcedNavigation()) {
      hooks.report({ type: "error", message: `redirect loop detected at ${location.pathname}; enforcement paused` });
      return;
    }
    replace(href);
  };

  /**
   * Leave to the mode's home. If that's the page the user came from (DMs only: thread →
   * inbox), step back in history so the site's own router shows it without a reload.
   * Fall back to a reload if the back doesn't land.
   */
  const leaveTo = (to: string) => {
    if (prevPath === null || !samePlace(prevPath, to)) return navigate(to);
    const from = here();
    prevPath = null;
    back();
    setTimeout(() => {
      if (here() === from) navigate(to);
    }, hooks.backTimeoutMs ?? 1000);
  };

  const wrap =
    (orig: typeof history.pushState, isPush: boolean) =>
    (data: unknown, unused: string, url?: string | URL | null): void => {
      const loc = toLocation(url);
      if (loc === null) return orig(data, unused, url);
      const { path } = loc;
      const d = evaluateRoute(path, getRules(), loc.search);
      report(path, d);
      if (d.action === "allow") {
        const before = here();
        orig(data, unused, url);
        if (isPush && !samePlace(before, path + loc.search)) prevPath = before;
        hooks.onPathChange(path);
      }
      // block/redirect: swallow (inert). Native URL observation is the backstop
      // if the site renders the filtered view anyway. A mode's way out, or a redirect marked
      // navigateInApp, goes to its target: the site may already be rendering the swallowed page.
      else if (d.action === "redirect" && (d.byMode || d.navigateInApp)) leaveTo(d.to);
    };

  history.pushState = wrap(origPush, true);
  history.replaceState = wrap(origReplace, false);

  const check = () => {
    const path = location.pathname;
    const d = evaluateRoute(path, getRules(), location.search);
    report(path, d);
    if (d.action === "redirect") navigate(d.to);
    else if (d.action === "block") navigate(getRules().mode?.home ?? "/");
    else hooks.onPathChange(path);
  };

  const onPop = () => {
    prevPath = null;
    check();
  };

  const onClick = (e: MouseEvent) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const a = (e.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
    if (!a) return;
    const loc = toLocation(a.getAttribute("href"));
    if (loc === null) return;
    const { path } = loc;
    const d = evaluateRoute(path, getRules(), loc.search);
    if (d.action === "allow") return;
    // Already where an in-app redirect would go (a link to "/" on the Following feed): leave the
    // tap to the site. Instagram's logo is such a link and opens the Following/Favorites menu;
    // if the site navigates to "/" instead, the pushState wrapper sends it back here.
    if (d.action === "redirect" && d.navigateInApp && samePlace(here(), d.to)) return;
    // Inert: stay where the user is...
    e.preventDefault();
    e.stopImmediatePropagation();
    report(path, d);
    // ...unless it's a way out of a mode: go to the mode's home instead. In DMs only,
    // a thread's back button links to the other person's profile, and the inbox is
    // where "back" should land.
    if (d.action === "redirect" && d.byMode) leaveTo(d.to);
    else if (d.action === "redirect" && d.navigateInApp) leaveTo(d.to);
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
