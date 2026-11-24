#!/usr/bin/env bash
# Builds the filter engine (two bundles) and copies them, plus the rule packs, into the iOS app.
#
# - Run from Xcode (pre-build phase): copies into "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Generated".
# - Run by hand: copies into ios/SocialRewind/Resources/Generated (gitignored) for inspection.
#
# Exits non-zero if anything is missing: an app without its filters must never ship (fail closed).
set -euo pipefail

# Xcode build phases don't load your shell profile, so Homebrew isn't on PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ROOT/engine"
RULES="$ROOT/rules"

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Generated"
else
  DEST="$ROOT/ios/SocialRewind/Resources/Generated"
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "error: pnpm not found. Install it with: brew install pnpm" >&2
  exit 1
fi

pnpm --dir "$ENGINE" install --frozen-lockfile || pnpm --dir "$ENGINE" install
pnpm --dir "$ENGINE" build

# Two bundles, two content worlds (see docs/architecture.md):
#   social-rewind-page.js      → page world (history + fetch/XHR patches only)
#   social-rewind-isolated.js  → "SocialRewind" world (CSS/DOM filter, counter, bridge)
BUNDLES=("$ENGINE/dist/social-rewind-page.js" "$ENGINE/dist/social-rewind-isolated.js")
for bundle in "${BUNDLES[@]}"; do
  if [[ ! -s "$bundle" ]]; then
    echo "error: engine bundle missing at $bundle" >&2
    exit 1
  fi
done

shopt -s nullglob
PACKS=("$RULES"/*.json)
if [[ ${#PACKS[@]} -eq 0 ]]; then
  echo "error: no rule packs in $RULES" >&2
  exit 1
fi

mkdir -p "$DEST"
cp "${BUNDLES[@]}" "$DEST/"
cp "${PACKS[@]}" "$DEST/"
echo "Copied engine and ${#PACKS[@]} rule pack(s) to $DEST"
