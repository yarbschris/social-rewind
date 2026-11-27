# Plan: painless sign-in

**Status:** proposed (2026-11-26). Instagram first. The same approach should carry over to every Meta platform.

## Why it matters
Signing in is the first thing a new user does, and the most likely place they give up. Meta's login checks are built for its own apps and Safari. Social Rewind breaks those assumptions twice:
- Its web view is a new, unfamiliar browser: a fresh cookie jar and, until #22, a non-Safari user agent.
- The one app Meta most wants you to approve the login in is the app Social Rewind has just locked, or that the user deleted.

Seen on a real account: Meta offered only "approve in the Instagram app", even with the app deleted, and no other option.

No screen-time app we know of handles this well. Doing it well is a reason to pick Social Rewind.

## Principles
- **Never touch credentials.** The user types into Instagram's own page, or Apple's Passwords AutoFill fills it. Social Rewind doesn't read, store or relay passwords or codes.
- **Sign in once, stay signed in.** The per-platform persistent `WKWebsiteDataStore` is never cleared without asking, and the user agent is stable. A sign-in should last months.
- **Never strand the user.** Every dead end has a way out inside the app that doesn't need them to know about Locked apps or the PIN.
- **Stay within the constraints.** No analytics, no backend, no Meta private APIs, nothing leaves the device.

## What Meta can ask for
| Challenge | What the user sees | What makes it hard here |
|---|---|---|
| Password only | Login form | Nothing; AutoFill is the only question (spike S3) |
| Code by SMS or WhatsApp | Code entry | AutoFill of the code (spike S4) |
| Authenticator app code | Code entry | None |
| **Approve on another device** | "Check your notifications" | The approving app is locked, or deleted |
| "Confirm it's you" checkpoint | Email or SMS code, sometimes a selfie video | Can't be skipped; just explain it |
| Backup code | Code entry | Users rarely have them |

## Plan

### Phase 1: done or in review
- Mobile Safari user agent (#22). Spike S1 checks whether Meta then shows the code options.
- **Sign-in help** in the filtered view (#21):
  - unlocks the locked app until you come back, with a 15-minute backstop;
  - points to "Try another way".

### Phase 2: sign in before locking (onboarding)
New order: Welcome → **Sign in to Instagram** → Screen Time → pick the app → notifications.
- The sign-in step embeds the platform's page with the filters on. Signing in while the native app is still unlocked makes "approve in the app" trivial.
- The step finishes on a reliable **signed-in signal** (spike S6), not on the user tapping Next.
- The user can skip it. Home then shows "Not signed in" until they do.
- **Acceptance:**
  - A new user with the Instagram app installed and "approve on another device" signs in without a temporary unlock.
  - A user with no 2FA signs in with one form.

### Phase 3: a sign-in coach inside the browser
Recognise which challenge is on screen: by path, plus a small DOM check in the isolated world for a password field or a code field. Show one bottom card that fits it, not a generic help sheet.
- **Approve in the app, app installed and locked:** "Unlock Instagram to approve", which already exists.
- **Approve in the app, app not installed:**
  - Meta often reveals **Try another way** only after a delay. Say so, and show a live countdown.
  - Suggest approving from another signed-in session, such as a computer or the Facebook app.
  - Don't suggest reinstalling the app: a fresh install is signed out, so it has nothing to approve with.
- **Code entry:** "Check your messages". If spike S4 shows iOS won't fill the code in, offer to paste it from the clipboard.
- **Checkpoint:** a plain explanation, no action.
- **Acceptance:** each row in the table above reaches a signed-in state in a device test, or is documented as impossible with the reason.

### Phase 4: make the next sign-in easy
Right after a successful sign-in, offer once, and allow skipping: "Add a backup sign-in method so you never need the Instagram app to get in". It opens Accounts Center's two-factor page in the web view (`accountscenter.instagram.com` is already allowed), with three short steps:
1. Add an authentication app. Apple's Passwords app can generate the codes, so no third-party app is needed.
2. Save backup codes, in the Passwords app or anywhere safe.
3. Optionally, keep "approve on another device" for when the app is around.

**Acceptance:** after setting this up, a fresh sign-in offers a code and needs no other device.

### Phase 5: stay signed in, and notice when you aren't
- **Session health:** when the platform opens to a login form, Home shows "Signed out of Instagram" with **Sign in**, which opens the coach. Users shouldn't land on a bare login page inside the filtered view.
- **Explicit sign-out:** "Sign out of Instagram" in settings clears that platform's data store only, after confirming.
- **Spike S5:** measure how long a session lasts, and what ends it (iOS updates, user agent changes, Meta's own expiry).

## Spikes (device needed)
| | Question | Decides |
|---|---|---|
| S1 | With the Safari user agent, does Meta offer code options, or "Try another way" sooner? | How much of Phase 3 is needed |
| S2 | How long until "Try another way" appears, and does it always? | The countdown copy |
| S3 | Does Passwords AutoFill offer instagram.com logins in our `WKWebView`? (Associated Domains can't be claimed for Meta's domains.) | Phase 2 copy; whether to say "copy from Passwords" |
| S4 | Does iOS fill SMS codes (`autocomplete="one-time-code"`) inside `WKWebView`? | Paste-from-clipboard fallback |
| S5 | How long does a session last, and what ends it? | Session-health design |
| S6 | Which DOM signal reliably means "signed in"? Today identity reports only *changes*; this needs a `session` event from the isolated world. | Phase 2's finish condition, Phase 5's banner |

## Out of scope
- Signing in with Facebook, and passkeys. Passkeys in a third-party `WKWebView` need Associated Domains for Meta's domains, which only Meta can grant.
- Moving a Safari session into the app. Safari's cookies aren't shared with `WKWebView`, and `ASWebAuthenticationSession` returns a callback URL, not cookies.
- Anything that stores or relays credentials or codes.
