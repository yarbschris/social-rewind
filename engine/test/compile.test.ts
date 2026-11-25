import { compile, featureEnabled, resolveHome } from "../src/core/compile";
import { config, loadPack, settings } from "./helpers";

describe("compile", () => {
  const pack = loadPack("instagram");

  it("uses feature defaults when settings omit a feature", () => {
    expect(featureEnabled(pack, settings(), "blockReels")).toBe(true);
    expect(featureEnabled(pack, settings(), "hideComments")).toBe(false);
    expect(featureEnabled(pack, settings({ features: { blockReels: false } }), "blockReels")).toBe(false);
  });

  it("never enables unavailable features", () => {
    expect(featureEnabled(pack, settings({ features: { hideStoryAds: true } }), "hideStoryAds")).toBe(false);
  });

  it("tags rules with stable ids", () => {
    const r = compile(config());
    expect(r.css.some((c) => c.id === "blockReels.css0")).toBe(true);
    expect(r.ids.has("blockAds.dom0")).toBe(true);
    expect(r.ids.has("hideComments.css0")).toBe(false);
  });

  it("skips unverified network rules unless experimental", () => {
    expect(compile(config()).network).toHaveLength(0);
    expect(compile(config({ experimental: true })).network.length).toBeGreaterThan(0);
  });

  it("compiles modes and resolves templated homes", () => {
    const r = compile(config({ settings: settings({ mode: "savedOnly" }), username: "alice" }));
    expect(r.mode?.home).toBe("/alice/saved/");
    const unresolved = compile(config({ settings: settings({ mode: "savedOnly" }) }));
    expect(unresolved.mode?.home).toBeNull();
  });

  it("ignores unknown modes", () => {
    expect(compile(config({ settings: settings({ mode: "nope" }) })).mode).toBeNull();
  });

  it("drops invalid regexes and reports them instead of throwing", () => {
    const bad = loadPack("instagram");
    bad.features.blockReels!.rules.routes = [{ pattern: "([", action: "block" }];
    const errors: string[] = [];
    const r = compile(config({}, bad), (m) => errors.push(m));
    expect(r.routes.find((x) => x.id === "blockReels.route0")).toBeUndefined();
    expect(errors[0]).toMatch(/invalid regex/);
  });

  it("escapes usernames in homes", () => {
    expect(resolveHome("/{username}/saved/", "a/b")).toBe("/a%2Fb/saved/");
  });
});

describe("Threads link", () => {
  it("is hidden by default, and always in a locked mode", () => {
    const has = (r: ReturnType<typeof compile>) => r.css.some((c) => c.rule.includes("threads.net"));
    expect(has(compile(config()))).toBe(true);
    const off = { features: { hideThreadsLink: false } };
    expect(has(compile(config({ settings: settings(off) })))).toBe(false);
    expect(has(compile(config({ settings: settings({ ...off, mode: "dmsOnly" }) })))).toBe(true);
    expect(has(compile(config({ settings: settings({ ...off, mode: "savedOnly" }), username: "me" })))).toBe(true);
  });
});
