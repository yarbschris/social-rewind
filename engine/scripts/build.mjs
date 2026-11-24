import { build } from "esbuild";
import { readFileSync } from "node:fs";

const { version } = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));

/** Shared options; also used by test/bundle.test.ts. */
export const options = {
  entryPoints: { "social-rewind-page": "src/page.ts", "social-rewind-isolated": "src/isolated.ts" },
  outdir: "dist",
  bundle: true,
  format: "iife",
  target: ["safari17"],
  legalComments: "none",
  banner: { js: `/* Social Rewind engine ${version} | Apache-2.0 | https://github.com/yarbschris/social-rewind */` },
};

if (import.meta.url === `file://${process.argv[1]}`) {
  await build({ ...options, minify: process.argv.includes("--minify"), logLevel: "info" });
}
