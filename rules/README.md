# Rule packs

One JSON file per platform, validated by [`schema/rule-pack.schema.json`](schema/rule-pack.schema.json). The app ships these bundled. Users who opt in to rule updates fetch the copy on `main` from GitHub.

**Packs are data, not code.** They can't contain scripts or hosts. The app enforces this, and so does `engine/test/rules.test.ts`.

## Rule kinds

| Kind | Use for | Example |
|---|---|---|
| `css` | Elements identifiable by a selector. Fastest, and there's no flash. Use `html[data-sr-path^="/x"]` to limit a selector to a route. | `a[href="/reels/"]` |
| `dom.hideClosest` | Hiding a container because of something inside it | reel link → its `article` |
| `dom.hideIfText` | Labels such as "Sponsored" (matched as an exact text node) | `article` + `["Sponsored"]` |
| `routes` | Blocking or redirecting pages (`$1` capture groups allowed) | `^/reels/?` → `/` |
| `network` | Dropping items from JSON API responses before render. **Must be `verified: false` until confirmed against real responses.** | `product_type == "clips"` |

Selector stability, best first: `href` patterns → ARIA roles/labels → visible text → structure. **Never use generated class names.**

## Changing a pack
1. Edit it, then bump `revision`.
2. Add `minEngineVersion` if you use a new engine capability.
3. `cd engine && pnpm validate-rules && pnpm test`.

## Status of `instagram.json`
Revision 1 hasn't been checked against the live site yet (see roadmap spikes 0.2/0.3/0.6). Expect selectors to need fixing during the first on-device test.
