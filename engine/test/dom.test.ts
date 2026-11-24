import { compile, type ActiveRules } from "../src/core/compile";
import { buildCss, HIDDEN_ATTR, installDom, type DomHandle } from "../src/core/dom";
import { config, settings } from "./helpers";

const flush = () => new Promise((r) => setTimeout(r, 0));

function post(id: string, inner = ""): string {
  return `<article data-id="${id}"><header><a href="/bob/">bob</a>${inner}</header><a href="/p/${id}/">post</a></article>`;
}

describe("DOM filter", () => {
  let rules: ActiveRules;
  let dom: DomHandle;

  beforeEach(() => {
    document.documentElement.innerHTML = "<head></head><body><main></main></body>";
    rules = compile(config());
    dom = installDom(() => rules, { debug: false, grayscale: false });
  });
  afterEach(() => dom.uninstall());

  const main = () => document.querySelector("main")!;
  const hidden = () => [...document.querySelectorAll(`[${HIDDEN_ATTR}]`)].map((e) => e.getAttribute("data-id"));

  it("hides sponsored and suggested posts by exact label text", async () => {
    main().innerHTML =
      post("1") + post("2", "<span>Sponsored</span>") + post("3", "<span> Suggested for you </span>") + post("4", "<span>Sponsored content we love</span>");
    await flush();
    expect(hidden()).toEqual(["2", "3"]);
  });

  it("hides reels in the feed via hideClosest", async () => {
    main().innerHTML = `<article data-id="r"><a href="/reel/XYZ/">reel</a></article>` + post("1");
    await flush();
    expect(hidden()).toEqual(["r"]);
  });

  it("catches labels added after the post rendered", async () => {
    main().innerHTML = post("5");
    await flush();
    expect(hidden()).toEqual([]);
    const span = document.createElement("span");
    span.textContent = "Sponsored";
    document.querySelector('[data-id="5"] header')!.appendChild(span);
    await flush();
    expect(hidden()).toEqual(["5"]);
  });

  it("un-hides when the feature is turned off", async () => {
    main().innerHTML = post("6", "<span>Sponsored</span>");
    await flush();
    expect(hidden()).toEqual(["6"]);
    rules = compile(config({ settings: settings({ features: { blockAds: false } }) }));
    dom.refresh({ debug: false, grayscale: false });
    expect(hidden()).toEqual([]);
  });

  it("injects a style element and keeps it attached", async () => {
    const style = document.getElementById("social-rewind-style")!;
    expect(style.textContent).toContain('a[href="/reels/"] { display: none !important; }');
    style.remove();
    main().appendChild(document.createElement("div"));
    await flush();
    expect(document.getElementById("social-rewind-style")).not.toBeNull();
  });

  it("sets the route attribute used for path-scoped CSS", () => {
    dom.setPath("/explore/search/");
    expect(document.documentElement.getAttribute("data-sr-path")).toBe("/explore/search/");
  });
});

describe("buildCss", () => {
  it("emits one rule per selector, skipping invalid ones", () => {
    const rules = compile(config());
    rules.css.push({ id: "x", rule: "a[[[" });
    const errors: string[] = [];
    const css = buildCss(rules, { debug: false, grayscale: true }, (m) => errors.push(m));
    expect(css).not.toContain("a[[[");
    expect(errors).toEqual(["invalid selector: a[[["]);
    expect(css).toContain("html { filter: grayscale(1) !important; }");
  });

  it("outlines instead of hiding in debug mode", () => {
    const css = buildCss(compile(config()), { debug: true, grayscale: false });
    expect(css).not.toContain("display: none");
    expect(css).toContain("outline");
  });
});

describe("debug labels", () => {
  it("label CSS-matched and JS-hidden elements with their rule id", () => {
    const css = buildCss(compile(config()), { debug: true, grayscale: false });
    expect(css).toContain('a[href="/reels/"]::before { content: "SR blockReels.css0"');
    expect(css).toContain(`[${HIDDEN_ATTR}]::before { content: "SR " attr(${HIDDEN_ATTR})`);
    expect(buildCss(compile(config()), { debug: false, grayscale: false })).not.toContain("::before");
  });
});
