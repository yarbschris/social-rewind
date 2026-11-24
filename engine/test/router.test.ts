import { compile } from "../src/core/compile";
import { evaluateRoute } from "../src/core/router";
import { config, settings } from "./helpers";

const normal = compile(config());
const withComments = compile(config({ settings: settings({ features: { hideComments: true, hideStories: true } }) }));
const dms = compile(config({ settings: settings({ mode: "dmsOnly" }) }));
const saved = compile(config({ settings: settings({ mode: "savedOnly" }), username: "alice" }));
const savedUnknown = compile(config({ settings: settings({ mode: "savedOnly" }) }));

describe("evaluateRoute (instagram)", () => {
  it.each([
    ["/", "allow"],
    ["/direct/inbox/", "allow"],
    ["/alice/", "allow"],
    ["/p/ABC123/", "allow"],
    ["/explore/search/", "allow"],
  ])("normal mode allows %s", (path, action) => {
    expect(evaluateRoute(path, normal).action).toBe(action);
  });

  it("redirects the Reels tab home and blocks individual reels", () => {
    expect(evaluateRoute("/reels/", normal)).toMatchObject({ action: "redirect", to: "/" });
    expect(evaluateRoute("/reel/XYZ/", normal)).toMatchObject({ action: "block" });
    expect(evaluateRoute("/someone/reel/XYZ/", normal)).toMatchObject({ action: "block" });
  });

  it("sends Explore to account search", () => {
    expect(evaluateRoute("/explore/", normal)).toMatchObject({ action: "redirect", to: "/explore/search/" });
    expect(evaluateRoute("/explore", normal)).toMatchObject({ action: "redirect", to: "/explore/search/" });
    expect(evaluateRoute("/explore/tags/cats/", normal)).toMatchObject({ action: "redirect" });
  });

  it("uses capture groups in redirects", () => {
    expect(evaluateRoute("/p/ABC/comments/", withComments)).toMatchObject({ action: "redirect", to: "/p/ABC/" });
    expect(evaluateRoute("/stories/bob/123/", withComments)).toMatchObject({ action: "redirect", to: "/" });
  });

  it("always allows login and account routes, even in modes", () => {
    expect(evaluateRoute("/accounts/login/", dms).action).toBe("allow");
    expect(evaluateRoute("/challenge/xyz/", saved).action).toBe("allow");
  });

  it("DMs only: inbox and threads allowed, everything else goes to the inbox", () => {
    expect(evaluateRoute("/direct/inbox/", dms).action).toBe("allow");
    expect(evaluateRoute("/direct/t/123/", dms).action).toBe("allow");
    expect(evaluateRoute("/", dms)).toMatchObject({ action: "redirect", to: "/direct/inbox/" });
    expect(evaluateRoute("/alice/", dms)).toMatchObject({ action: "redirect", to: "/direct/inbox/" });
  });

  it("Saved only: saved collections and posts allowed", () => {
    expect(evaluateRoute("/alice/saved/", saved).action).toBe("allow");
    expect(evaluateRoute("/alice/saved/all-posts/", saved).action).toBe("allow");
    expect(evaluateRoute("/p/ABC/", saved).action).toBe("allow");
    expect(evaluateRoute("/", saved)).toMatchObject({ action: "redirect", to: "/alice/saved/" });
    expect(evaluateRoute("/direct/inbox/", saved)).toMatchObject({ action: "redirect", to: "/alice/saved/" });
  });

  it("Saved only: feature rules still apply inside the mode", () => {
    // Reels opened from saved remain blocked when blockReels is on.
    expect(evaluateRoute("/reels/", saved)).toMatchObject({ action: "redirect", to: "/alice/saved/" });
  });

  it("Saved only without a known username: stays on / until identity resolves", () => {
    expect(evaluateRoute("/", savedUnknown).action).toBe("allow");
    expect(evaluateRoute("/direct/inbox/", savedUnknown)).toMatchObject({ action: "redirect", to: "/" });
  });
});
