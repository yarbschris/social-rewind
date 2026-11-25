// @ts-expect-error: plain .mjs script, no types
import { labConfig, makeSnippet } from "../scripts/lab.mjs";
import { loadPack } from "./helpers";

const flush = () => new Promise((r) => setTimeout(r, 0));

describe("Safari lab snippet", () => {
  it("enables every available feature in debug mode by default", () => {
    const c = labConfig(loadPack("instagram"));
    expect(c.debug).toBe(true);
    expect(c.settings.features.hideComments).toBe(true);
    expect(c.settings.features.hideStoryAds).toBe(false); // unavailable
    expect(labConfig(loadPack("instagram"), { defaults: true }).settings.features.hideComments).toBe(false);
  });

  it("runs in a page and reports rule matches", async () => {
    document.documentElement.innerHTML =
      '<head></head><body><main><article><span>Sponsored</span><a href="/p/AAA/">x</a></article><article><a href="/p/BBB/">y</a></article></main></body>';
    const snippet: string = await makeSnippet(loadPack("instagram"));
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const table = vi.spyOn(console, "table").mockImplementation(() => {});
    new Function(snippet)();
    await flush();
    const rows = (window as unknown as { SocialRewindLab: { report(): Array<{ rule: string; matches: unknown }> } }).SocialRewindLab.report();
    expect(rows.find((r) => r.rule === "blockAds.dom0")?.matches).toBe(1);
    expect(rows.every((r) => r.matches !== "INVALID")).toBe(true);
    expect(table).toHaveBeenCalled();
    log.mockRestore();
    table.mockRestore();
  });
});

describe("Safari lab helpers", () => {
  it("leaves Hide feed off unless --all", () => {
    expect(labConfig(loadPack("instagram")).settings.features.hideFeed).toBe(false);
    expect(labConfig(loadPack("instagram"), { all: true }).settings.features.hideFeed).toBe(true);
  });

  it("inspect() prints structure without text content or usernames", async () => {
    document.documentElement.innerHTML =
      '<head></head><body><main><div role="list"><div role="button" aria-label="Story by alice.b, seen"><a href="/alice/" aria-label="alice"><span>Suggested for you</span></a></div></div></main></body>';
    (window as unknown as { __socialRewindLab?: boolean }).__socialRewindLab = false;
    const snippet: string = await makeSnippet(loadPack("instagram"));
    const lines: string[] = [];
    const log = vi.spyOn(console, "log").mockImplementation((...a: unknown[]) => void lines.push(a.join(" ")));
    new Function(snippet)();
    const lab = (window as unknown as { SocialRewindLab: { inspect(t: string): number } }).SocialRewindLab;
    expect(lab.inspect("Suggested for you")).toBe(1);
    const out = lines.join("\n");
    expect(out).toContain('a[aria-label="<w>"][href~"/<user>/"]');
    expect(out).toContain('div[role="button"][aria-label="Story by <w>, seen"]');
    expect(out).toContain('div[role="list"]');
    expect(out).not.toContain("alice");
    log.mockRestore();
  });

  it("tree() prints the subtree around a match, masked", async () => {
    document.documentElement.innerHTML =
      '<head></head><body><main><div id="w"><div role="presentation"><ul data-x><li><div role="button" aria-label="Note by alice"></div></li></ul></div>' +
      '<div role="button" aria-label="Scroll right"><svg aria-label="Chevron"></svg></div></div></main></body>';
    (window as unknown as { __socialRewindLab?: boolean }).__socialRewindLab = false;
    new Function(await makeSnippet(loadPack("instagram")))();
    const lines: string[] = [];
    const log = vi.spyOn(console, "log").mockImplementation((...a: unknown[]) => void lines.push(a.join(" ")));
    const lab = (window as unknown as { SocialRewindLab: { tree(s: string, up?: number): number } }).SocialRewindLab;
    expect(lab.tree("ul[data-x]", 2)).toBeGreaterThan(4);
    const out = lines.join("\n");
    expect(out).toMatch(/ul \(1 children\)\s+◀/);
    expect(out).toContain('div[role="button"][aria-label="Scroll right"]');
    expect(out).toContain('aria-label="Note by <w>"');
    expect(out).not.toContain("alice");
    log.mockRestore();
  });
});
