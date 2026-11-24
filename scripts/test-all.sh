#!/usr/bin/env bash
# Run every test suite that doesn't need a device: engine (TS) + rule validation + RewindCore (Swift).
# Rule packs are shared by both, so a rules change must pass both.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
(cd "$ROOT/engine" && pnpm -s validate-rules && pnpm -s typecheck && pnpm -s test)
(cd "$ROOT/ios/Packages/RewindCore" && swift test 2>&1 | tail -1)
