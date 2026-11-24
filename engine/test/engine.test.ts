import { onSend } from "../src/core/bridge";
import { compile } from "../src/core/compile";
import { EVENT_ATTR, onPlatformHost, resolveIdentity, sanitizePageEvent, startIsolated, startPage } from "../src/core/engine";
import type { BridgeEvent } from "../src/core/types";
import { config, loadPack, settings } from "./helpers";

const flush = () => new Promise((r) => setTimeout(r, 0));

describe("modes", () => {
  it("withhold mode CSS until the home path is known", () => {
    const unresolved = compile(config({ settings: settings({ mode: "savedOnly" }) }));
    expect(unresolved.css.some((c) => c.id.startsWith("mode:"))).toBe(false);
    const resolved = compile(config({ settings: settings({ mode: "savedOnly" }), username: "alice" }));
    expect(resolved.css.some((c) => c.id.startsWith("mode:"))).toBe(true);
  });

  it("refuse unsafe mode homes", () => {
    const pack = loadPack("instagram");
    pack.modes!.dmsOnly!.home = "//evil.example/";
    const errors: string[] = [];
    const r = compile(config({ settings: settings({ mode: "dmsOnly" }) }, pack), (m) => errors.push(m));
    expect(r.mode?.home).toBeNull();
    expect(errors[0]).toMatch(/unsafe mode home/);
  });
});

describe("identity", () => {
  const def = { selector: "nav a", attr: "href", pattern: "^/([^/]+)/$" };
  it("accepts valid usernames only", () => {
    document.body.innerHTML = '<nav><a href="/alice.b_1/">me</a></nav>';
    expect(resolveIdentity(def)).toBe("alice.b_1");
    document.body.innerHTML = '<nav><a href="/<script>/">me</a></nav>';
    expect(resolveIdentity(def)).toBeNull();
  });
});

describe("page → isolated events", () => {
  it("forwards only well-formed routeBlocked/error events", () => {
    expect(sanitizePageEvent('{"type":"routeBlocked","path":"/reels/","reason":"blockReels.route0"}')).toEqual({
      type: "routeBlocked",
      path: "/reels/",
      reason: "blockReels.route0",
    });
    expect(sanitizePageEvent('{"type":"identity","username":"mallory"}')).toBeNull();
    expect(sanitizePageEvent('{"type":"postViewed","key":"x","sessionCount":999}')).toBeNull();
    expect(sanitizePageEvent("not json")).toBeNull();
    expect(sanitizePageEvent("x".repeat(5000))).toBeNull();
  });

  it("isolated world relays page events to native", async () => {
    const events: BridgeEvent[] = [];
    const off = onSend((e) => events.push(e));
    const api = startIsolated(config());
    document.documentElement.setAttribute(EVENT_ATTR, '{"type":"routeBlocked","path":"/reels/","reason":"r"}');
    await flush();
    expect(events.map((e) => e.type)).toEqual(expect.arrayContaining(["ready", "routeBlocked"]));
    api?.stop();
    off();
  });
});

describe("platform hosts", () => {
  it("acts only on the platform's own hosts", () => {
    const c = config({ hosts: ["instagram.com", "www.instagram.com"] });
    expect(onPlatformHost(c, "www.instagram.com")).toBe(true);
    expect(onPlatformHost(c, "www.facebook.com")).toBe(false);
    expect(onPlatformHost(config(), "anything.example")).toBe(true); // no list → legacy behavior
  });

  it("both worlds stay inert off-host (no ready, no patches)", () => {
    const events: BridgeEvent[] = [];
    const off = onSend((e) => events.push(e));
    const push = history.pushState;
    const c = config({ hosts: ["www.facebook.com"] }); // test document is www.instagram.com
    expect(startIsolated(c)).toBeNull();
    expect(startPage(c)).toBeNull();
    expect(history.pushState).toBe(push);
    expect(events).toEqual([]);
    off();
  });
});

describe("identity via nav-bar scope", () => {
  const def = loadPack("instagram").identity!;
  const nav = (profileHref: string) =>
    `<main><article><a href="/stranger/">x</a></article></main>` +
    `<div><a href="/">Home</a><a href="/explore/">Search</a><a href="/reels/">Reels</a><a href="/direct/inbox/">DMs</a><a href="${profileHref}">Profile</a></div>`;

  it("finds the profile link next to Home and Inbox, ignoring feed links and nav routes", () => {
    document.body.innerHTML = nav("/me.the_user/");
    expect(resolveIdentity(def)).toBe("me.the_user");
  });

  it("returns null when the nav bar isn't there", () => {
    document.body.innerHTML = '<main><a href="/stranger/">x</a></main>';
    expect(resolveIdentity(def)).toBeNull();
  });
});
