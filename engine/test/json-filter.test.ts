import { filterBody, filterJson, matches, protectBigInts } from "../src/core/json-filter";
import type { Predicate } from "../src/core/types";

const isAd: Predicate = { anyOf: [{ path: "ad_id", exists: true }, { path: "node.injected", exists: true }] };
const isClip: Predicate = { path: "media.product_type", equals: "clips" };

describe("matches", () => {
  it("handles exists, equals, in, not, allOf", () => {
    expect(matches({ a: { b: 1 } }, { path: "a.b", exists: true })).toBe(true);
    expect(matches({ a: { b: null } }, { path: "a.b", exists: true })).toBe(false);
    expect(matches({}, { path: "a.b", exists: false })).toBe(true);
    expect(matches({ t: "clips" }, { path: "t", in: ["clips", "igtv"] })).toBe(true);
    expect(matches({ t: "feed" }, { not: { path: "t", equals: "clips" } })).toBe(true);
    expect(matches({ a: 1, b: 2 }, { allOf: [{ path: "a", equals: 1 }, { path: "b", equals: 3 }] })).toBe(false);
  });
});

describe("filterJson", () => {
  it("removes matching objects from arrays at any depth", () => {
    const data = {
      data: {
        feed: {
          edges: [
            { node: { id: "1" } },
            { node: { id: "2", injected: { label: "Sponsored" } } },
            { node: { id: "3" } },
          ],
        },
        other: [{ ad_id: "x" }, { media: { product_type: "clips" } }, { media: { product_type: "feed" } }],
      },
    };
    expect(filterJson(data, [isAd, isClip])).toBe(3);
    expect(data.data.feed.edges.map((e) => e.node.id)).toEqual(["1", "3"]);
    expect(data.data.other).toEqual([{ media: { product_type: "feed" } }]);
  });

  it("does not remove the root or non-array properties", () => {
    const data = { ad_id: "root" };
    expect(filterJson(data, [isAd])).toBe(0);
    expect(data).toEqual({ ad_id: "root" });
  });
});

describe("filterBody", () => {
  it("returns null when nothing changes (so the original passes through)", () => {
    expect(filterBody(JSON.stringify({ items: [{ id: 1 }] }), [isAd])).toBeNull();
    expect(filterBody("<html>not json</html>", [isAd])).toBeNull();
  });

  it("preserves XSSI prefixes", () => {
    const out = filterBody(`for (;;);${JSON.stringify({ items: [{ ad_id: 1 }, { id: 2 }] })}`, [isAd]);
    expect(out?.text).toBe(`for (;;);${JSON.stringify({ items: [{ id: 2 }] })}`);
  });

  it("filters newline-delimited JSON chunk by chunk", () => {
    const body = [JSON.stringify({ items: [{ ad_id: 1 }, { id: 2 }] }), "", JSON.stringify({ label: "x" })].join("\n");
    const out = filterBody(body, [isAd]);
    expect(out?.removed).toBe(1);
    expect(out?.text.split("\n")[0]).toBe(JSON.stringify({ items: [{ id: 2 }] }));
    expect(out?.text.split("\n")[2]).toBe(JSON.stringify({ label: "x" }));
  });
});

describe("big integers", () => {
  it("survive filtering byte-for-byte", () => {
    const body = '{"items":[{"pk":9007199254740993,"id":"1"},{"ad_id":1},{"pk":-12345678901234567}],"f":1.25,"s":"9007199254740993"}';
    const out = filterBody(body, [isAd]);
    expect(out?.text).toBe('{"items":[{"pk":9007199254740993,"id":"1"},{"pk":-12345678901234567}],"f":1.25,"s":"9007199254740993"}');
  });

  it("leaves digits inside strings (including escaped quotes) alone", () => {
    expect(protectBigInts('{"a":"x\\"12345678901234567","b":12345678901234567}')).toBe(
      '{"a":"x\\"12345678901234567","b":"\\u0000SRBIG:12345678901234567"}',
    );
  });

  it("refuses to filter bodies that already contain the marker", () => {
    expect(filterBody('{"items":[{"ad_id":1,"x":"\\u0000SRBIG:1"}]}', [isAd])).toBeNull();
  });
});
