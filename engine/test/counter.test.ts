import { onSend } from "../src/core/bridge";
import { installCounter, keyFor, routeKeyFor } from "../src/core/counter";
import type { BridgeEvent } from "../src/core/types";
import { FakeIO, loadPack } from "./helpers";

const def = loadPack("instagram").counter!;

describe("post counter", () => {
  let timers: Array<{ fn: () => void; cancelled: boolean }>;
  let events: BridgeEvent[];
  let off: () => void;

  const deps = () => ({
    IntersectionObserver: FakeIO as unknown as typeof IntersectionObserver,
    setTimeout: (fn: () => void) => {
      const t = { fn, cancelled: false };
      timers.push(t);
      return t;
    },
    clearTimeout: (t: unknown) => {
      (t as { cancelled: boolean }).cancelled = true;
    },
  });
  const runTimers = () => timers.filter((t) => !t.cancelled).forEach((t) => t.fn());

  beforeEach(() => {
    FakeIO.instances = [];
    timers = [];
    events = [];
    off = onSend((e) => events.push(e));
    document.body.innerHTML = `
      <article id="a"><a href="/p/AAA/">x</a></article>
      <article id="b"><a href="/bob/reel/BBB/?utm=1">x</a></article>
      <article id="c" data-sr-hidden="blockAds.dom0"><a href="/p/CCC/">x</a></article>`;
  });
  afterEach(() => off());

  const el = (id: string) => document.getElementById(id)!;
  const counted = () => events.filter((e) => e.type === "postViewed");

  it("derives keys from post links", () => {
    expect(keyFor(el("a"), def)).toBe("AAA");
    expect(keyFor(el("b"), def)).toBe("BBB");
  });

  it("counts a post once after it has been visible long enough", () => {
    const c = installCounter(def, deps());
    const io = FakeIO.instances[0]!;
    io.fire(el("a"), 0.8);
    runTimers();
    io.fire(el("a"), 0);
    io.fire(el("a"), 0.9);
    runTimers();
    expect(c.count()).toBe(1);
    expect(counted()).toEqual([{ type: "postViewed", key: "AAA", sessionCount: 1 }]);
  });

  it("doesn't count posts scrolled past quickly", () => {
    const c = installCounter(def, deps());
    const io = FakeIO.instances[0]!;
    io.fire(el("a"), 0.8);
    io.fire(el("a"), 0.1); // left before timer fired
    runTimers();
    expect(c.count()).toBe(0);
  });

  it("doesn't count posts the filter hid", () => {
    const c = installCounter(def, deps());
    FakeIO.instances[0]!.fire(el("c"), 1);
    runTimers();
    expect(c.count()).toBe(0);
  });

  describe("post and reel pages", () => {
    const routes = (def.routes ?? []).map((r) => new RegExp(r));

    it("keys single-post paths the same way as feed links", () => {
      expect(routeKeyFor("/p/AAA/", routes)).toBe("AAA");
      expect(routeKeyFor("/reel/BBB/", routes)).toBe("BBB");
      expect(routeKeyFor("/someone/p/CCC/", routes)).toBe("CCC");
      expect(routeKeyFor("/someone/reel/DDD", routes)).toBe("DDD");
      for (const path of ["/", "/direct/inbox/", "/direct/t/123/", "/reels/", "/reels/EEE/", "/p/AAA/liked_by/", "/someone/", "/someone/saved/"]) {
        expect(routeKeyFor(path, routes), path).toBeNull();
      }
    });

    it("keys each story by its media id, and a highlight once", () => {
      expect(routeKeyFor("/stories/someone/3141592653589793/", routes)).toBe("3141592653589793");
      expect(routeKeyFor("/stories/someone/3141592653589793", routes)).toBe("3141592653589793");
      expect(routeKeyFor("/stories/highlights/17900000000000000/", routes)).toBe("17900000000000000");
      for (const path of ["/stories/", "/stories/someone/", "/stories/someone/abc/"]) {
        expect(routeKeyFor(path, routes), path).toBeNull();
      }
    });

    it("counts each story the user watches as it advances", () => {
      const c = installCounter(def, deps(), "/");
      c.pathChanged("/stories/someone/111/");
      runTimers();
      c.pathChanged("/stories/someone/222/");
      runTimers();
      c.pathChanged("/stories/someone/111/");
      runTimers();
      expect(c.count()).toBe(2);
    });

    it("counts a post page the user stays on, e.g. one opened from DMs", () => {
      const c = installCounter(def, deps(), "/direct/t/123/");
      c.pathChanged("/p/ZZZ/");
      runTimers();
      expect(c.count()).toBe(1);
      expect(counted()).toEqual([{ type: "postViewed", key: "ZZZ", sessionCount: 1 }]);
    });

    it("counts the page it starts on", () => {
      const c = installCounter(def, deps(), "/reel/YYY/");
      runTimers();
      expect(c.count()).toBe(1);
    });

    it("doesn't count a page left before the delay", () => {
      const c = installCounter(def, deps(), "/direct/t/123/");
      c.pathChanged("/p/ZZZ/");
      c.pathChanged("/direct/t/123/");
      runTimers();
      expect(c.count()).toBe(0);
    });

    it("doesn't count a post twice when its page and its feed article are both seen", () => {
      const c = installCounter(def, deps(), "/");
      FakeIO.instances[0]!.fire(el("a"), 1);
      runTimers();
      c.pathChanged("/p/AAA/");
      runTimers();
      c.pathChanged("/");
      c.pathChanged("/p/AAA/");
      runTimers();
      expect(c.count()).toBe(1);
      expect(counted()).toHaveLength(1);
    });

    it("stops pending page timers on uninstall", () => {
      const c = installCounter(def, deps(), "/p/ZZZ/");
      c.uninstall();
      runTimers();
      expect(c.count()).toBe(0);
    });
  });
});
