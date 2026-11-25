import { compile, type ActiveRules } from "../src/core/compile";
import { buildCss, COLLAPSE_ATTR, HIDDEN_ATTR, installDom, type DomHandle } from "../src/core/dom";
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

  it("also stops scrolling past a reel opened on its own page (e.g. from Saved)", async () => {
    dom.setPath("/reel/X/");
    dom.pathChanged();
    document.querySelector("main")!.innerHTML = viewer;
    await flush();
    expect(hiddenIds()).toEqual(["more"]);
  });

  it("does nothing outside DMs and reel pages", async () => {
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
    const html =
      '<div id="inbox"><div><div id="row"><div role="presentation"><div><ul id="notes"><li><div role="button"><span>Your note</span></div></li></ul></div></div>' +
      '<button aria-label="Next"><div></div></button></div></div><ul id="threads"><li>chat</li></ul></div>';
    dom.setPath("/");
    dom.pathChanged();
    document.querySelector("main")!.innerHTML = html;
    await flush();
    expect(document.querySelectorAll(`[${HIDDEN_ATTR}]`).length).toBe(0);
    dom.setPath("/direct/inbox/");
    dom.pathChanged();
    // The row (list plus its scroll arrows) goes, wrappers included; the list rule is the
    // fallback for rows without arrows. The thread list stays.
    const hiddenRoot = (id: string) => !!document.getElementById(id)!.closest(`[${HIDDEN_ATTR}]`);
    expect(hiddenRoot("row")).toBe(true);
    expect(document.querySelector("#row")!.closest(`[${HIDDEN_ATTR}]`)!.getAttribute(HIDDEN_ATTR)).toBe("hideNotes.dom0");
    expect(hiddenRoot("threads")).toBe(false);
  });
});

describe("rev 11: DMs only hides the inbox back button", () => {
  let dom: DomHandle;
  afterEach(() => dom.uninstall());
  const back = '<div role="button" id="back"><svg aria-label="Back"></svg></div>';

  it("on the inbox, but not in a thread (where back goes to the inbox)", async () => {
    document.documentElement.innerHTML = "<head></head><body><main></main></body>";
    const rules = compile(config({ settings: settings({ mode: "dmsOnly" }) }));
    dom = installDom(() => rules, { debug: false, grayscale: false });
    dom.setPath("/direct/t/1/");
    dom.pathChanged();
    document.querySelector("main")!.innerHTML = back;
    await flush();
    expect(document.querySelectorAll(`[${HIDDEN_ATTR}]`).length).toBe(0);
    dom.setPath("/direct/inbox/");
    dom.pathChanged();
    expect(document.getElementById("back")!.getAttribute(HIDDEN_ATTR)).toBe("mode:dmsOnly.dom0");
  });
});

describe("rev 13: feed posts collapse instead of display:none", () => {
  let dom: DomHandle;
  afterEach(() => dom.uninstall());
  beforeEach(() => {
    document.documentElement.innerHTML = "<head></head><body><main></main></body>";
  });

  it("collapses hidden feed posts (so the feed keeps loading) and pauses their video", async () => {
    let rules = compile(config());
    dom = installDom(() => rules, { debug: false, grayscale: false });
    dom.setPath("/");
    document.querySelector("main")!.innerHTML = post("1", "<span>Sponsored</span><video></video>") + post("2");
    const video = document.querySelector("video")!;
    const paused = vi.spyOn(video, "pause");
    await flush();
    const ad = document.querySelector('[data-id="1"]')!;
    expect(ad.getAttribute(HIDDEN_ATTR)).toBe("blockAds.dom0");
    expect(ad.hasAttribute(COLLAPSE_ATTR)).toBe(true);
    expect(paused).toHaveBeenCalled();
    // It tries to autoplay later: paused again.
    paused.mockClear();
    video.dispatchEvent(new Event("play"));
    expect(paused).toHaveBeenCalled();
    // Turning the feature off clears both attributes.
    rules = compile(config({ settings: settings({ features: { blockAds: false } }) }));
    dom.refresh({ debug: false, grayscale: false });
    expect(ad.hasAttribute(HIDDEN_ATTR) || ad.hasAttribute(COLLAPSE_ATTR)).toBe(false);
  });

  it("still removes the extra reels after a shared one (loading should stop there)", async () => {
    const rules = compile(config());
    dom = installDom(() => rules, { debug: false, grayscale: false });
    dom.setPath("/direct/t/1/");
    dom.pathChanged();
    const player = '<div role="group"><video></video><a href="/reels/audio/1/">a</a></div>';
    document.querySelector("main")!.innerHTML = `<div><div>${player}</div><div id="more"><div>${player}</div></div></div>`;
    await flush();
    const more = document.getElementById("more")!;
    expect(more.getAttribute(HIDDEN_ATTR)).toBe("blockReels.dom2");
    expect(more.hasAttribute(COLLAPSE_ATTR)).toBe(false);
  });

  it("emits the collapse style only when hiding for real", () => {
    expect(buildCss(compile(config()), { debug: false, grayscale: false })).toContain(`[${HIDDEN_ATTR}][${COLLAPSE_ATTR}] { display: block !important; height: 0 !important;`);
    expect(buildCss(compile(config()), { debug: true, grayscale: false })).not.toContain(COLLAPSE_ATTR);
  });
});

describe("rev 16: stories row takes its wrappers with it", () => {
  let dom: DomHandle;
  afterEach(() => dom.uninstall());

  it("hides the outermost single-child wrapper, not the shared parent", async () => {
    document.documentElement.innerHTML = "<head></head><body></body>";
    const rules = compile(config({ settings: settings({ features: { hideStories: true } }) }));
    dom = installDom(() => rules, { debug: false, grayscale: false });
    // Live shape: main > … > div(2) > div(1) ×5 > tray(10 story buttons)
    const stories = '<div role="button" aria-label="Story by a"></div><div role="button" aria-label="Story by b"></div>';
    document.body.innerHTML =
      `<main><div id="shared"><div id="w5"><div><div><div><div id="w1"><div id="tray">${stories}</div></div></div></div></div></div>` +
      '<div id="feed"><article><a href="/p/A/">post</a></article></div></div></main>';
    await flush();
    expect([...document.querySelectorAll(`[${HIDDEN_ATTR}]`)].map((e) => e.id)).toEqual(["w5"]);
  });
});

describe("rev 17: notes row takes its wrappers with it", () => {
  let dom: DomHandle;
  afterEach(() => dom.uninstall());

  it("hides the row's single-child wrapper, keeping the thread list", async () => {
    document.documentElement.innerHTML = "<head></head><body></body>";
    const rules = compile(config({ settings: settings({ features: { hideNotes: true } }) }));
    dom = installDom(() => rules, { debug: false, grayscale: false });
    dom.setPath("/direct/inbox/");
    dom.pathChanged();
    // Live shape: div(3) > div(1) > row(2: presentation + Next button), next to the thread list.
    document.body.innerHTML =
      '<div id="inbox"><div id="search"></div><div id="wrap"><div id="row"><div role="presentation"><div><ul><li><div role="button"><span>Your note</span></div></li></ul></div></div>' +
      '<button aria-label="Next"></button></div></div><div id="threads"><ul><li>chat</li></ul></div></div>';
    await flush();
    // Outermost hidden element is the wrapper; the list fallback only marks things inside it.
    const outer = [...document.querySelectorAll(`[${HIDDEN_ATTR}]`)].filter((e) => !e.parentElement!.closest(`[${HIDDEN_ATTR}]`));
    expect(outer.map((e) => e.id)).toEqual(["wrap"]);
    expect(document.getElementById("threads")!.closest(`[${HIDDEN_ATTR}]`)).toBeNull();
    expect(document.getElementById("search")!.hasAttribute(HIDDEN_ATTR)).toBe(false);
  });
});

describe("rev 19: AI content label", () => {
  let dom: DomHandle;
  afterEach(() => dom.uninstall());
  it("hides posts labelled AI content (inside a button in the post)", async () => {
    document.documentElement.innerHTML = "<head></head><body><main></main></body>";
    const rules = compile(config({ settings: settings({ features: { hideAiLabeled: true } }) }));
    dom = installDom(() => rules, { debug: false, grayscale: false });
    document.querySelector("main")!.innerHTML = post("ai", "<button><div><span>AI content</span></div></button>") + post("ok");
    await flush();
    expect([...document.querySelectorAll(`[${HIDDEN_ATTR}]`)].map((e) => `${e.getAttribute("data-id")}:${e.getAttribute(HIDDEN_ATTR)}`)).toEqual(["ai:hideAiLabeled.dom0"]);
  });
});
