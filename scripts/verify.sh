#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

required=(
  .gitignore
  LICENSE
  README.md
  Package.swift
  Sources/LessCore/Ledger.swift
  Sources/LessCore/Bridge.swift
  Sources/LessCore/TabLog.swift
  Tests/LessCoreTests/LedgerTests.swift
  Tests/LessCoreTests/BridgeTests.swift
  Tests/LessCoreTests/TabLogTests.swift
  App/Less/LessApp.swift
  App/Less/ContentView.swift
  App/Less/AppModel.swift
  App/Less/TabReviewView.swift
  App/Less/TabPrompt.swift
  App/Less/Less.entitlements
  App/LessBridge/main.swift
  App/LessBridge/LessBridge.entitlements
  App/Shared/GroupContainer.swift
  App/Less/Assets.xcassets/Contents.json
  App/Less/Assets.xcassets/AccentColor.colorset/Contents.json
  App/Less/Assets.xcassets/AppIcon.appiconset/Contents.json
  App/Less.xcodeproj/project.pbxproj
  App/Less.xcodeproj/project.xcworkspace/contents.xcworkspacedata
  .github/workflows/ci.yml
  scripts/verify.sh
  scripts/install-chromium-bridge.sh
  Extensions/chromium/manifest.json
  Extensions/chromium/background.js
  Extensions/chromium/tracker.js
  Extensions/chromium/x.js
  Extensions/chromium/x.test.mjs
  Extensions/chromium/popup.html
  Extensions/chromium/popup.css
  Extensions/chromium/popup.js
)

fail=0
for path in "${required[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "missing: $path"
    fail=1
  fi
done

for name in Ledger.swift LessApp.swift Bridge.swift TabLog.swift TabReviewView.swift \
  TabPrompt.swift GroupContainer.swift main.swift less-bridge; do
  if ! grep -q "$name" App/Less.xcodeproj/project.pbxproj; then
    echo "pbxproj missing $name"
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

if command -v node >/dev/null 2>&1; then
  (cd Extensions/chromium && node --test)
else
  echo "skipped: extension tests (node not on PATH)"
fi

if command -v swift >/dev/null 2>&1; then
  swift test
else
  echo "skipped: swift test (swift not on PATH)"
fi
