#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "==> Smoke tests"
swift run -c debug XShotSmokeTests
echo "==> Bundle layout check"
test -f Resources/Info.plist
echo "OK"
