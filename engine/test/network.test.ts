import { compile } from "../src/core/compile";
import { installNetwork } from "../src/core/network";
import { config } from "./helpers";

const FEED_URL = "https://www.instagram.com/graphql/query";

function fakeWin(body: string, contentType = "application/json") {
  const calls: unknown[] = [];
  const win = {
    fetch: async (input: RequestInfo | URL) => {
      calls.push(input);
      const res = new Response(body, { status: 200, headers: { "content-type": contentType } });
      Object.defineProperty(res, "url", { value: String(input) });
      return res;
    },
  } as unknown as typeof globalThis;
  return { win, calls };
}

describe("installNetwork (fetch)", () => {
  const rules = compile(config({ experimental: true }));
  const feed = JSON.stringify({
    data: { edges: [{ node: { id: "1" } }, { node: { id: "2", ad_id: "a" } }, { node: { id: "3", suggested_users: {} } }] },
  });

  it("filters matching JSON responses", async () => {
    const { win } = fakeWin(feed);
    installNetwork(() => rules, win);
    const res = await win.fetch(FEED_URL);
    const json = (await res.json()) as { data: { edges: Array<{ node: { id: string } }> } };
    expect(json.data.edges.map((e) => e.node.id)).toEqual(["1"]);
    expect(res.url).toBe(FEED_URL);
  });

  it("passes through non-matching URLs untouched", async () => {
    const { win } = fakeWin(feed);
    installNetwork(() => rules, win);
    const res = await win.fetch("https://www.instagram.com/api/v1/users/web_profile_info/");
    expect(await res.text()).toBe(feed);
  });

  it("passes through non-JSON content types", async () => {
    const { win } = fakeWin("\u0000binary", "image/jpeg");
    installNetwork(() => rules, win);
    expect(await (await win.fetch(FEED_URL)).text()).toBe("\u0000binary");
  });

  it("does nothing when no network rules are active", async () => {
    const { win } = fakeWin(feed);
    installNetwork(() => compile(config()), win);
    expect(await (await win.fetch(FEED_URL)).text()).toBe(feed);
  });

  it("uninstall restores the original fetch", () => {
    const { win } = fakeWin(feed);
    const orig = win.fetch;
    installNetwork(() => rules, win).uninstall();
    expect(win.fetch).toBe(orig);
  });
});
