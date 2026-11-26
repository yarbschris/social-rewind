# 0005: Settings live outside the feed, behind an optional PIN

**Status:** accepted (2026-11-26)

## Context
Filters only help if loosening them takes more than an impulse. Two ways around them existed:
- The filtered view had a settings button, so a filter could be switched off mid-scroll.
- Any setting could be changed at any time, with nothing in the way.

## Decision
- **No settings in the filtered view.** Filters, modes and wellbeing options change from Home only.
- **An optional settings PIN** (4–6 digits, separate from the phone's passcode). The user sets it, or a friend sets it for them.
- **Only loosening asks for the PIN.** Making things stricter never does. `RewindCore.Loosening` defines what counts:
  - turning a filter off;
  - leaving a mode such as DMs only, including switching straight to another mode;
  - turning off grayscale or the post counter;
  - turning reminders off or making them less frequent;
  - unlocking an app, or swapping which app is locked;
  - changing or removing the PIN.
- **The PIN guards loosening, not every screen.** A correct PIN unlocks settings for 5 minutes, or until the app goes to the background.
- **Face ID is deliberately not an option,** since the phone's owner always passes it.
- **No permanent lockout.**
  - Five wrong guesses pause entry for a minute.
  - "Forgot PIN" removes the PIN after 24 hours, and entering the right PIN cancels that.
- **Storage:** only a salted SHA-256 hash, in the App Group's UserDefaults rather than the Keychain, so deleting the app clears it along with everything else.

## Consequences
- The PIN is friction, not security. Anyone holding the phone can delete the app, and with it the Screen Time shields. Settings copy shouldn't promise more than that.
- Every setter that can loosen something goes through `AppModel.guarded`. Bindings call the model's methods, never its stored properties: `reminders` is `private(set)` for this reason.
- Settings that neither loosen nor tighten skip the PIN: the username, and the opt-in rule refresh.
