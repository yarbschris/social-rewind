# Safari lab: test filter rules without an iPhone

This runs the filter engine on instagram.com in desktop Safari, using Instagram's mobile layout. It checks most of the selector and label questions in [instagram-checklist.md](instagram-checklist.md) without a phone or an Apple developer account.

**What it can't test:** Screen Time, the native app, and true document-start injection (the snippet runs after the page loads, so the first page's network requests aren't filtered). The two-world isolation also doesn't apply: both bundles run in the page.

## One-time setup
1. Safari → Settings → Advanced → turn on **Show features for web developers**.
2. Open https://www.instagram.com and log in.
3. **Develop → Enter Responsive Design Mode**, pick an iPhone, and set the user agent to **Safari — iOS**. Reload so Instagram serves its mobile site.

## Each run
1. In Terminal: `cd engine && pnpm lab`. This builds the snippet and copies it to the clipboard.
   - `pnpm lab -- --defaults`: only the app's default features
   - `pnpm lab -- --mode dmsOnly`, or `--mode savedOnly --username you`
   - `pnpm lab -- --hide`: actually hide instead of outlining
2. Reload Instagram, open **Develop → Show JavaScript Console**, paste, and press Return.
3. Scroll the feed and open stories, a post, DMs and saved posts. Elements the filter would hide get a **dashed red outline** and are faded.
4. Run `SocialRewindLab.report()` in the console. It prints:
   - **style sheet applied:** if this says **NO**, Instagram's Content-Security-Policy is blocking our injected CSS. That's important for the app too. Report it.
   - **username detected:** checks the identity rule used for Saved-only mode
   - **a table of every rule**, with how many elements it matches right now
5. Paste the summary and table (or screenshots) back to Claude, along with anything outlined that *shouldn't* be, and anything that should be but isn't.

Re-pasting needs a page reload first.
