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
  Tests/LessCoreTests/LedgerTests.swift
  App/Less/LessApp.swift
  App/Less/ContentView.swift
  App/Less/AppModel.swift
  App/Less/Less.entitlements
  App/Less/Assets.xcassets/Contents.json
  App/Less/Assets.xcassets/AccentColor.colorset/Contents.json
  App/Less/Assets.xcassets/AppIcon.appiconset/Contents.json
  App/Less.xcodeproj/project.pbxproj
  App/Less.xcodeproj/project.xcworkspace/contents.xcworkspacedata
  .github/workflows/ci.yml
  scripts/verify.sh
)

fail=0
for path in "${required[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "missing: $path"
    fail=1
  fi
done

if ! grep -q "Ledger.swift" App/Less.xcodeproj/project.pbxproj; then
  echo "pbxproj missing Ledger.swift"
  fail=1
fi

if ! grep -q "LessApp.swift" App/Less.xcodeproj/project.pbxproj; then
  echo "pbxproj missing LessApp.swift"
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

if command -v swift >/dev/null 2>&1; then
  swift test
else
  echo "skipped: swift test (swift not on PATH)"
fi
