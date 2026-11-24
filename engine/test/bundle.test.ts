import { build } from "esbuild";
import { join } from "node:path";

// Structural guarantees of the two-world split (see core/engine.ts).
const root = join(import.meta.dirname, "..");

async function bundle(entry: string): Promise<string> {
  const r = await build({
    entryPoints: [join(root, entry)],
    bundle: true,
    format: "iife",
    target: ["safari17"],
    write: false,
  });
  return r.outputFiles[0]!.text;
}

describe("bundles", () => {
  it("page-world bundle has no bridge access and defines no globals", async () => {
    const page = await bundle("src/page.ts");
    expect(page).not.toMatch(/messageHandlers|SocialRewindAndroid/);
    expect(page).not.toMatch(/defineProperty\(window/);
    expect(page).not.toMatch(/window\.SocialRewind|__SOCIAL_REWIND_CONFIG__/);
    expect(page).toContain("__SR_CONFIG__");
  });

  it("isolated bundle contains the bridge and the DOM filter", async () => {
    const iso = await bundle("src/isolated.ts");
    expect(iso).toContain("messageHandlers");
    expect(iso).toContain("social-rewind-style");
    expect(iso).not.toMatch(/pushState\s*=/);
  });

  it("bundles run when wrapped the way native wraps them", async () => {
    const page = await bundle("src/page.ts");
    // No config → no-op, and nothing leaks into globals.
    const before = Object.keys(globalThis).length;
    new Function(`(function(){"use strict";const __SR_CONFIG__ = undefined;\n${page}\n})();`)();
    expect(Object.keys(globalThis).length).toBe(before);
  });
});
