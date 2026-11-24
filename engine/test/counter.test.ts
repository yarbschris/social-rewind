import { onSend } from "../src/core/bridge";
import { installCounter, keyFor } from "../src/core/counter";
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
});
