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

describe("route-scoped rules (when) and hideAllButFirst", () => {
  let dom: DomHandle;
  const reel = (id: string) => `<article data-id="${id}"><a href="/reel/${id}/">reel</a></article>`;
  const hiddenIds = () => [...document.querySelectorAll(`[${HIDDEN_ATTR}]`)].map((e) => `${e.getAttribute("data-id")}:${e.getAttribute(HIDDEN_ATTR)}`);

  beforeEach(() => {
    document.documentElement.innerHTML = "<head></head><body><main></main></body>";
  });
  afterEach(() => dom.uninstall());

  it("hides reels in the feed", async () => {
    const rules = compile(config());
    dom = installDom(() => rules, { debug: false, grayscale: false });
    dom.setPath("/");
    document.querySelector("main")!.innerHTML = reel("a") + post("1");
    await flush();
    expect(hiddenIds()).toEqual(["a:blockReels.dom0"]);
  });

  it("on a reel page keeps the first reel and hides the ones after it", async () => {
    const rules = compile(config());
    dom = installDom(() => rules, { debug: false, grayscale: false });
    dom.setPath("/reel/a/");
    document.querySelector("main")!.innerHTML = reel("a") + reel("b") + reel("c");
    await flush();
    expect(hiddenIds()).toEqual(["b:blockReels.dom1", "c:blockReels.dom1"]);
  });

  it("re-evaluates when the path changes", async () => {
    const rules = compile(config());
    dom = installDom(() => rules, { debug: false, grayscale: false });
    dom.setPath("/");
    document.querySelector("main")!.innerHTML = reel("a") + reel("b");
    await flush();
    expect(hiddenIds()).toEqual(["a:blockReels.dom0", "b:blockReels.dom0"]);
    dom.setPath("/reel/a/");
    dom.pathChanged();
    expect(hiddenIds()).toEqual(["b:blockReels.dom1"]);
  });
});

describe("rev 7 rules from live markup", () => {
  let dom: DomHandle;
  afterEach(() => dom.uninstall());

  it("hides the comment button by walking up from its icon", async () => {
    document.documentElement.innerHTML = "<head></head><body><main></main></body>";
    const rules = compile(config({ settings: settings({ features: { hideComments: true } }) }));
    dom = installDom(() => rules, { debug: false, grayscale: false });
    document.querySelector("main")!.innerHTML =
      '<article><div role="button" data-id="like"><div><span><svg aria-label="Like"></svg></span></div></div>' +
      '<div role="button" data-id="comment"><div><div><span><svg aria-label="Comment"></svg></span></div></div></div></article>';
    await flush();
    expect([...document.querySelectorAll(`[${HIDDEN_ATTR}]`)].map((e) => e.getAttribute("data-id"))).toEqual(["comment"]);
  });

  it("targets the stories tray, not a single story ring", () => {
    const rules = compile(config({ settings: settings({ features: { hideStories: true } }) }));
    const tray = rules.css.find((c) => c.id === "hideStories.css0")!.rule;
    document.documentElement.innerHTML =
      '<head></head><body><main><div id="tray"><div role="button" aria-label="Story by a, seen"></div><div role="button" aria-label="Story by b"></div></div>' +
      '<article><header><div id="ring"><div role="button" aria-label="Story by c"></div></div></header></article></main></body>';
    expect([...document.querySelectorAll(tray)].map((e) => e.id)).toEqual(["tray"]);
  });
});

describe("shared-reel viewer in DMs (hideAllButFirst with branch)", () => {
  let dom: DomHandle;
  afterEach(() => dom.uninstall());
  // Mirrors the live markup: the opened reel and the list of more reels are
  // siblings under one wrapper, nested to different depths.
  const player = (id: string) =>
    `<div role="group" aria-label="Video player" data-id="${id}"><div><video></video><a href="/reels/audio/1/">audio</a></div></div>`;
  const viewer =
    `<section><div id="wrap"><div id="opened"><div><div>${player("r1")}</div></div></div>` +
    `<div id="more"><div>${player("r2")}</div><div>${player("r3")}</div><div id="sentinel"></div></div></div></section>`;
  const hiddenIds = () => [...document.querySelectorAll(`[${HIDDEN_ATTR}]`)].map((e) => e.id || e.getAttribute("data-id"));

  beforeEach(() => {
    document.documentElement.innerHTML = "<head></head><body><main></main></body>";
    const rules = compile(config());
    dom = installDom(() => rules, { debug: false, grayscale: false });
  });

  it("hides the whole list after the opened reel, loading slot included", async () => {
    dom.setPath("/direct/t/1/");
    dom.pathChanged();
    document.querySelector("main")!.innerHTML = `<div id="thread"><a href="/reel/X/">shared reel</a></div>` + viewer;
    await flush();
    expect(hiddenIds()).toEqual(["more"]);
  });

  it("does nothing outside DMs", async () => {
    dom.setPath("/");
    dom.pathChanged();
    document.querySelector("main")!.innerHTML = viewer;
    await flush();
    expect(hiddenIds()).toEqual([]);
  });

  it("hides reels that load later", async () => {
    dom.setPath("/direct/t/1/");
    dom.pathChanged();
    document.querySelector("main")!.innerHTML = `<section><div><div id="opened">${player("r1")}</div><div id="more2"></div></div></section>`;
    await flush();
    expect(hiddenIds()).toEqual([]);
    document.getElementById("more2")!.innerHTML = `<div>${player("r2")}</div>`;
    await flush();
    expect(hiddenIds()).toEqual(["more2"]);
  });
});

describe("rev 9: suggested accounts and notes", () => {
  let dom: DomHandle;
  afterEach(() => dom?.uninstall());

  it("hides the suggested-accounts block around its See all link, not the feed", () => {
    const rules = compile(config());
    const sel = rules.css.find((c) => c.id === "hideSuggestedAccounts.css0")!.rule;
    document.documentElement.innerHTML =
      '<head></head><body><main><div id="feed"><div id="item"><div id="block"><div><span>Suggested for you</span><a href="/explore/people/">See all</a></div><div>cards</div></div></div>' +
      '<div><article><a href="/p/A/">post</a></article></div></div></main></body>';
    // happy-dom treats a chained `:has(> a > b)` as a descendant match, so it also matches
    // #feed and #item. WebKit follows the spec; the lab count on the live site checks exactness.
    expect([...document.querySelectorAll(sel)].map((e) => e.id)).toContain("block");
  });

  it("hides the notes row in DMs only", async () => {
    document.documentElement.innerHTML = "<head></head><body><main></main></body>";
    const rules = compile(config({ settings: settings({ features: { hideNotes: true } }) }));
    dom = installDom(() => rules, { debug: false, grayscale: false });
    const html = '<ul id="notes"><li><div role="button"><span>Your note</span></div></li></ul><ul id="threads"><li>chat</li></ul>';
    dom.setPath("/");
    dom.pathChanged();
    document.querySelector("main")!.innerHTML = html;
    await flush();
    expect(document.querySelectorAll(`[${HIDDEN_ATTR}]`).length).toBe(0);
    dom.setPath("/direct/inbox/");
    dom.pathChanged();
    expect([...document.querySelectorAll(`[${HIDDEN_ATTR}]`)].map((e) => e.id)).toEqual(["notes"]);
  });
});
