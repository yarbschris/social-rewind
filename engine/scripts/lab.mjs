// Safari "lab": build a single snippet to paste into Safari's Web Inspector console
// on instagram.com (in Responsive Design Mode as an iPhone). It runs both engine
// bundles in debug mode, so rules outline what they'd hide instead of hiding it,
// and adds SocialRewindLab.report() to show which rules match the live page.
//
//   pnpm lab                      # every available feature except "Hide feed", outlines only
//   pnpm lab -- --all             # include "Hide feed" (outlines every post on Home)
//   pnpm lab -- --defaults        # the app's default features
//   pnpm lab -- --mode dmsOnly    # or savedOnly (add --username you)
//   pnpm lab -- --hide            # actually hide instead of outlining
//   pnpm lab -- --experimental    # also apply unverified network rules
//
// The snippet is written to engine/dist/lab-snippet.js and copied to the clipboard.
import { build } from "esbuild";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dirname, "..");

async function bundle(entry) {
  const r = await build({
    entryPoints: [join(root, entry)],
    bundle: true,
    format: "iife",
    target: ["safari17"],
    write: false,
  });
  return r.outputFiles[0].text;
}

// Features that would outline everything and drown out the rules being tested.
const LAB_OFF_BY_DEFAULT = ["hideFeed"];

export function labConfig(pack, opts = {}) {
  const features = {};
  for (const [id, f] of Object.entries(pack.features)) {
    features[id] = opts.defaults
      ? f.default
      : f.available !== false && (opts.all || !LAB_OFF_BY_DEFAULT.includes(id));
  }
  return {
    platform: pack.platform,
    hosts: ["instagram.com", "www.instagram.com"],
    settings: { mode: opts.mode ?? "normal", features, grayscale: false, postCounter: true },
    rules: pack,
    ...(opts.username ? { username: opts.username } : {}),
    debug: !opts.hide,
    experimental: !!opts.experimental,
  };
}

/** Runs in the page. Kept dependency-free; receives the config as an argument. */
function labRuntime(config) {
  const pack = config.rules;
  const count = (sel) => {
    try {
      return document.querySelectorAll(sel).length;
    } catch {
      return "INVALID";
    }
  };
  const rowsFor = (prefix, set, active) => {
    const rows = [];
    (set?.css ?? []).forEach((sel, i) =>
      rows.push({ rule: `${prefix}.css${i}`, active, kind: "css", matches: count(sel), target: sel }),
    );
    (set?.dom ?? []).forEach((r, i) => {
      const id = `${prefix}.dom${i}`;
      rows.push({
        rule: id,
        active,
        kind: r.type,
        matches: count(`[data-sr-hidden="${id}"]`),
        target: r.type === "hideIfText" ? `${r.container} ∋ ${JSON.stringify(r.text)}` : `${r.match} → ${r.closest}`,
      });
    });
    return rows;
  };

  // Structure only: tags, roles, ARIA labels (truncated), href *patterns*. No text content,
  // so the output is safe to share. Usernames in hrefs are replaced with <user>.
  const KNOWN = new Set(["p", "reel", "reels", "explore", "stories", "direct", "accounts", "saved", "people", "tags", "create"]);
  const hrefPattern = (href) => {
    if (!href) return null;
    try {
      const u = new URL(href, location.href);
      if (u.origin !== location.origin) return `${u.hostname}/…`;
      return "/" + u.pathname.split("/").filter(Boolean).map((seg, i) => (KNOWN.has(seg) ? seg : i === 0 ? "<user>" : "<id>")).join("/") + "/";
    } catch {
      return "?";
    }
  };
  const describe = (el) => {
    let s = el.tagName.toLowerCase();
    for (const a of ["role", "aria-label", "aria-hidden", "data-sr-hidden", "tabindex"]) {
      const v = el.getAttribute(a);
      if (v !== null) s += `[${a}="${v.length > 32 ? v.slice(0, 32) + "…" : v}"]`;
    }
    const href = hrefPattern(el.getAttribute("href"));
    if (href) s += `[href~"${href}"]`;
    s += ` (${el.children.length} children)`;
    return s;
  };

  return {
    config,
    /** Show the element chain above every text node equal to `text`, e.g. inspect("Suggested for you"). */
    inspect(text, depth = 14) {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      const chains = [];
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        if (n.nodeValue?.trim() !== text) continue;
        const chain = [];
        for (let el = n.parentElement, d = 0; el && el !== document.body && d < depth; el = el.parentElement, d++) {
          chain.push(describe(el));
        }
        chains.push(chain);
      }
      if (!chains.length) console.log(`[Social Rewind lab] no text node equal to ${JSON.stringify(text)}`);
      chains.slice(0, 5).forEach((c, i) =>
        console.log(`#${i + 1} of ${chains.length}: innermost first\n` + c.map((s, j) => "  ".repeat(j) + s).join("\n")),
      );
      return chains.length;
    },
    /** Same, starting from an element (e.g. $0, the one selected in the Elements tab). */
    inspectElement(el, depth = 14) {
      const chain = [];
      for (let e = el, d = 0; e && e !== document.body && d < depth; e = e.parentElement, d++) chain.push(describe(e));
      console.log(chain.map((s, j) => "  ".repeat(j) + s).join("\n"));
    },
    report() {
      const rows = [];
      for (const [id, f] of Object.entries(pack.features)) {
        rows.push(...rowsFor(id, f.rules, !!config.settings.features[id] && f.available !== false));
      }
      for (const [id, m] of Object.entries(pack.modes ?? {})) {
        rows.push(...rowsFor(`mode:${id}`, m.rules, config.settings.mode === id));
      }
      const style = document.getElementById("social-rewind-style");
      let cssRules = null;
      try {
        cssRules = style?.sheet?.cssRules.length ?? null;
      } catch {
        cssRules = null;
      }
      let username = null;
      if (pack.identity) {
        try {
          const v = document.querySelector(pack.identity.selector)?.getAttribute(pack.identity.attr);
          username = v ? (new RegExp(pack.identity.pattern).exec(v)?.[1] ?? null) : null;
        } catch {
          username = "INVALID selector";
        }
      }
      console.log(
        "%cSocial Rewind lab",
        "font-weight:bold",
        `\n  path: ${document.documentElement.getAttribute("data-sr-path") ?? location.pathname}` +
          `\n  style sheet applied: ${cssRules ? `yes (${cssRules} rules)` : "NO (blocked by the site's Content-Security-Policy?)"}` +
          `\n  username detected: ${username ?? "no"}` +
          `\n  posts counted: ${window.SocialRewind?.postsViewed?.() ?? "n/a"}` +
          `\n  articles on page: ${count("article")}`,
      );
      console.table(rows);
      return rows;
    },
  };
}

export async function makeSnippet(pack, opts = {}) {
  const [page, isolated] = await Promise.all([bundle("src/page.ts"), bundle("src/isolated.ts")]);
  const cfg = JSON.stringify(labConfig(pack, opts)).replaceAll("<", "\\u003c");
  const wrap = (src) => `(function(){"use strict";const __SR_CONFIG__ = ${cfg};\n${src}\n})();`;
  return `/* Social Rewind lab snippet. Paste into Safari's console on instagram.com. */
(function(){
  if (window.__socialRewindLab) { console.warn("[Social Rewind lab] already loaded. Reload the page to run it again."); return; }
  window.__socialRewindLab = true;
  // Plain Safari has no native bridge: log engine events to the console instead.
  try {
    if (!window.webkit?.messageHandlers?.socialRewind) {
      window.webkit = Object.assign(window.webkit || {}, { messageHandlers: { socialRewind: { postMessage: (e) => console.log("[SR]", e.type, e) } } });
    }
  } catch (e) { console.warn("[Social Rewind lab] couldn't attach event logger", e); }
})();
${wrap(page)}
${wrap(isolated)}
window.SocialRewindLab = (${labRuntime.toString()})(${cfg});
console.log("[Social Rewind lab] loaded. Outlined elements are labeled with the rule that matched. Then run: SocialRewindLab.report()  or  SocialRewindLab.inspect('Suggested for you')");
`;
}

function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--defaults") opts.defaults = true;
    else if (a === "--all") opts.all = true;
    else if (a === "--hide") opts.hide = true;
    else if (a === "--experimental") opts.experimental = true;
    else if (a === "--mode") opts.mode = argv[++i];
    else if (a === "--username") opts.username = argv[++i];
  }
  return opts;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const pack = JSON.parse(readFileSync(join(root, "../rules/instagram.json"), "utf8"));
  const opts = parseArgs(process.argv.slice(2));
  const snippet = await makeSnippet(pack, opts);
  mkdirSync(join(root, "dist"), { recursive: true });
  const out = join(root, "dist/lab-snippet.js");
  writeFileSync(out, snippet);
  let copied = false;
  try {
    execFileSync("pbcopy", { input: snippet });
    copied = true;
  } catch {
    /* not macOS */
  }
  console.log(`Wrote ${out} (${(snippet.length / 1024).toFixed(1)} KB)${copied ? ", copied to clipboard" : ""}.`);
  console.log(`Settings: mode=${opts.mode ?? "normal"}, features=${opts.defaults ? "defaults" : opts.all ? "all" : "all except hideFeed"}, ${opts.hide ? "hiding" : "outlining (debug)"}${opts.experimental ? ", experimental network rules" : ""}`);
}
