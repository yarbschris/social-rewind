import { build } from "esbuild";
import { readFileSync } from "node:fs";

const { version } = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));

await build({
  entryPoints: ["src/index.ts"],
  outfile: "dist/social-rewind-engine.js",
  bundle: true,
  format: "iife",
  target: ["safari17"],
  minify: process.argv.includes("--minify"),
  legalComments: "none",
  banner: { js: `/* Social Rewind engine ${version} | Apache-2.0 | https://github.com/yarbschris/social-rewind */` },
  logLevel: "info",
});
