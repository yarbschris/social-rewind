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
