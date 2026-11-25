import { compile } from "../src/core/compile";
import {
  allowForcedNavigation,
  evaluateRoute,
  installRouter,
  isSafePath,
  LOOP_LIMIT,
  LOOP_WINDOW_MS,
  resetLoopBreaker,
  type RouterHandle,
} from "../src/core/router";
import type { BridgeEvent } from "../src/core/types";
import { config, settings } from "./helpers";

const normal = compile(config());
const withComments = compile(config({ settings: settings({ features: { hideComments: true, hideStories: true } }) }));
const dms = compile(config({ settings: settings({ mode: "dmsOnly" }) }));
const saved = compile(config({ settings: settings({ mode: "savedOnly" }), username: "alice" }));
const savedUnknown = compile(config({ settings: settings({ mode: "savedOnly" }) }));

describe("evaluateRoute (instagram)", () => {
  it.each([
    ["/", "allow"],
    ["/direct/inbox/", "allow"],
    ["/alice/", "allow"],
    ["/p/ABC123/", "allow"],
    ["/explore/search/", "allow"],
  ])("normal mode allows %s", (path, action) => {
    expect(evaluateRoute(path, normal).action).toBe(action);
  });

  it("redirects the Reels tab home but lets a single (shared) reel open", () => {
    expect(evaluateRoute("/reels/", normal)).toMatchObject({ action: "redirect", to: "/" });
    expect(evaluateRoute("/reel/XYZ/", normal).action).toBe("allow");
    expect(evaluateRoute("/someone/reel/XYZ/", normal).action).toBe("allow");
  });

  it("keeps Explore reachable (for account search) but blocks tag and location grids", () => {
    expect(evaluateRoute("/explore/", normal).action).toBe("allow");
    expect(evaluateRoute("/explore/search/", normal).action).toBe("allow");
    expect(evaluateRoute("/explore/tags/cats/", normal)).toMatchObject({ action: "block" });
    expect(evaluateRoute("/explore/people/", normal)).toMatchObject({ action: "redirect", to: "/" });
  });

  it("uses capture groups in redirects", () => {
    expect(evaluateRoute("/stories/bob/123/", withComments)).toMatchObject({ action: "redirect", to: "/" });
    const r = compile(config());
    r.routes.unshift({ id: "t", pattern: /^\/x\/([^/]+)\//, action: "redirect", to: "/y/$1/" });
    expect(evaluateRoute("/x/abc/", r)).toMatchObject({ action: "redirect", to: "/y/abc/" });
  });

  it("blocks the comments page when comments are hidden", () => {
    expect(evaluateRoute("/p/ABC/comments/", withComments)).toMatchObject({ action: "block" });
    expect(evaluateRoute("/p/ABC/", withComments).action).toBe("allow");
  });

  it("always allows login and account routes, even in modes", () => {
    expect(evaluateRoute("/accounts/login/", dms).action).toBe("allow");
    expect(evaluateRoute("/challenge/xyz/", saved).action).toBe("allow");
  });

  it("DMs only: inbox and threads allowed, everything else goes to the inbox", () => {
    expect(evaluateRoute("/direct/inbox/", dms).action).toBe("allow");
    expect(evaluateRoute("/direct/t/123/", dms).action).toBe("allow");
    expect(evaluateRoute("/", dms)).toMatchObject({ action: "redirect", to: "/direct/inbox/" });
    expect(evaluateRoute("/alice/", dms)).toMatchObject({ action: "redirect", to: "/direct/inbox/" });
  });

  it("Saved only: saved collections and posts allowed", () => {
    expect(evaluateRoute("/alice/saved/", saved).action).toBe("allow");
    expect(evaluateRoute("/alice/saved/all-posts/", saved).action).toBe("allow");
    expect(evaluateRoute("/p/ABC/", saved).action).toBe("allow");
    expect(evaluateRoute("/", saved)).toMatchObject({ action: "redirect", to: "/alice/saved/" });
    expect(evaluateRoute("/direct/inbox/", saved)).toMatchObject({ action: "redirect", to: "/alice/saved/" });
  });

  it("Saved only: feature rules still apply inside the mode", () => {
    // Reels opened from saved remain blocked when blockReels is on.
    expect(evaluateRoute("/reels/", saved)).toMatchObject({ action: "redirect", to: "/alice/saved/" });
  });

  it("Saved only without a known username: stays on / until identity resolves", () => {
    expect(evaluateRoute("/", savedUnknown).action).toBe("allow");
    expect(evaluateRoute("/direct/inbox/", savedUnknown)).toMatchObject({ action: "redirect", to: "/" });
  });
});

describe("evaluateRoute: anchoring and safety", () => {
  it("doesn't catch profiles whose names start with blocked words", () => {
    expect(evaluateRoute("/reelsfan/", normal).action).toBe("allow");
    expect(evaluateRoute("/reel/", normal).action).toBe("allow"); // a profile named "reel"
    expect(evaluateRoute("/storiesbyme/", withComments).action).toBe("allow");
    expect(evaluateRoute("/two_factorx/", dms).action).not.toBe("allow");
  });

  it("allows site interstitials even inside modes", () => {
    expect(evaluateRoute("/consent/", dms).action).toBe("allow");
    expect(evaluateRoute("/terms/unblock/", saved).action).toBe("allow");
  });

  it("percent-encodes capture groups so they can't build a new host", () => {
    const r = compile(config());
    r.routes.unshift({ id: "t", pattern: /^\/x\/([^/]+)\//, action: "redirect", to: "/y/$1/" });
    expect(evaluateRoute("/x/a%2F%2Fevil/", r)).toMatchObject({ to: "/y/a%252F%252Fevil/" });
  });

  it("refuses redirect targets that would leave the origin", () => {
    const evil = compile(config());
    evil.routes.unshift({ id: "evil", pattern: /^\/x/, action: "redirect", to: "//evil.example/" });
    expect(evaluateRoute("/x/", evil)).toMatchObject({ action: "block", reason: "evil:unsafe-target" });
  });

  it.each(["//evil.example", "/\\evil.example", "/a\\b", "https://evil.example/", "/ok/../x\u0000"])("isSafePath rejects %j", (p) => {
    expect(isSafePath(p)).toBe(false);
  });

  it.each(["/", "/direct/inbox/", "/alice/saved/", "/p/ABC/?x=1"])("isSafePath accepts %j", (p) => {
    expect(isSafePath(p)).toBe(true);
  });
});

describe("loop breaker", () => {
  beforeEach(() => resetLoopBreaker());

  it(`allows ${LOOP_LIMIT} forced navigations per window, then refuses`, () => {
    const t = 1_000_000;
    for (let i = 0; i < LOOP_LIMIT; i++) expect(allowForcedNavigation(t + i)).toBe(true);
    expect(allowForcedNavigation(t + 10)).toBe(false);
    expect(allowForcedNavigation(t + LOOP_WINDOW_MS + 100)).toBe(true);
  });

  it("persists across reloads via sessionStorage", () => {
    const t = 2_000_000;
    for (let i = 0; i < LOOP_LIMIT; i++) allowForcedNavigation(t + i);
    expect(JSON.parse(sessionStorage.getItem("socialRewind.forcedNavs")!)).toHaveLength(LOOP_LIMIT);
  });
});

describe("installRouter", () => {
  let handle: RouterHandle | null = null;
  let navs: string[];
  let events: BridgeEvent[];

  const install = (rules = normal) => {
    navs = [];
    events = [];
    handle = installRouter(() => rules, {
      onPathChange: () => {},
      report: (e) => events.push(e),
      replace: (h) => navs.push(h),
    });
  };

  beforeEach(() => {
    resetLoopBreaker();
    history.replaceState(null, "", "/");
  });
  afterEach(() => {
    handle?.uninstall();
    handle = null;
  });

  it("in-app navigation to a redirected page is inert (no reload)", () => {
    install(withComments);
    history.pushState(null, "", "/explore/tags/cats/");
    history.pushState(null, "", "/p/ABC/comments/");
    expect(navs).toEqual([]);
    expect(location.pathname).toBe("/");
    expect(events.map((e) => e.type)).toEqual(["routeBlocked", "routeBlocked"]);
  });

  it("pushState to a blocked route is swallowed and reported", () => {
    install();
    history.pushState(null, "", "/explore/tags/cats/");
    expect(location.pathname).toBe("/");
    expect(navs).toEqual([]);
    expect(events[0]).toMatchObject({ type: "routeBlocked", path: "/explore/tags/cats/" });
  });

  it("DMs only lets a shared post or reel open, but nothing around it", () => {
    for (const p of ["/p/ABC/", "/someone/p/ABC/", "/reel/XYZ/"]) expect(evaluateRoute(p, dms).action).toBe("allow");
    for (const p of ["/someone/", "/p/ABC/liked_by/", "/explore/", "/"]) expect(evaluateRoute(p, dms).action).toBe("redirect");
  });

  it("pushState out of a mode reloads to the mode home (the site may render it anyway)", () => {
    history.replaceState(null, "", "/direct/inbox/");
    install(dms);
    history.pushState(null, "", "/");
    expect(location.pathname).toBe("/direct/inbox/");
    expect(navs).toEqual(["https://www.instagram.com/direct/inbox/"]);
    expect(events[0]).toMatchObject({ type: "routeBlocked", path: "/", reason: "mode:dmsOnly", redirectedTo: "/direct/inbox/" });
  });

  it("taps on links out of a mode go to the mode home", () => {
    history.replaceState(null, "", "/direct/inbox/");
    install(dms);
    const a = document.createElement("a");
    a.href = "/alice/";
    document.body.appendChild(a);
    const ev = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 });
    a.dispatchEvent(ev);
    expect(ev.defaultPrevented).toBe(true);
    expect(navs).toEqual(["https://www.instagram.com/direct/inbox/"]);
    a.remove();
  });

  it("allowed pushState goes through", () => {
    install();
    history.pushState(null, "", "/direct/inbox/");
    expect(location.pathname).toBe("/direct/inbox/");
  });

  it("taps on filtered links are inert", () => {
    install();
    const a = document.createElement("a");
    a.href = "/reels/";
    document.body.appendChild(a);
    const ev = new MouseEvent("click", { bubbles: true, cancelable: true, button: 0 });
    a.dispatchEvent(ev);
    expect(ev.defaultPrevented).toBe(true);
    expect(navs).toEqual([]);
    a.remove();
  });

  it("loading a filtered page directly redirects with replace", () => {
    history.replaceState(null, "", "/reels/");
    install();
    expect(navs).toEqual(["https://www.instagram.com/"]);
  });

  it("stops forcing navigation when it detects a loop", () => {
    history.replaceState(null, "", "/reels/");
    install();
    for (let i = 0; i < LOOP_LIMIT + 2; i++) handle!.check();
    expect(navs).toHaveLength(LOOP_LIMIT);
    expect(events.some((e) => e.type === "error" && /loop/.test(e.message))).toBe(true);
  });
});
