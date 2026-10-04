#!/usr/bin/env bash
# Registers less-bridge with Chromium browsers so the "less for X" extension can reach less.
# The sandboxed app cannot write into browser folders, so this runs once from Terminal.
#
#   scripts/install-chromium-bridge.sh [path/to/Less.app]
#   scripts/install-chromium-bridge.sh --uninstall
set -euo pipefail

host="app.less.bridge"
# fixed by the "key" in Extensions/chromium/manifest.json
extension_id="jjbgpjpagfcimgbindihanooahdabmef"

support="$HOME/Library/Application Support"
browsers=(
  "Google/Chrome"
  "Google/Chrome Beta"
  "Google/Chrome Canary"
  "Chromium"
  "BraveSoftware/Brave-Browser"
  "Arc/User Data"
  "Microsoft Edge"
  "Vivaldi"
)

if [[ "${1:-}" == "--uninstall" ]]; then
  for browser in "${browsers[@]}"; do
    manifest="$support/$browser/NativeMessagingHosts/$host.json"
    if [[ -f "$manifest" ]]; then
      rm "$manifest"
      echo "removed: $manifest"
    fi
  done
  exit 0
fi

app="${1:-/Applications/Less.app}"
app="$(cd "$app" 2>/dev/null && pwd || true)"
bridge="$app/Contents/MacOS/less-bridge"
if [[ -z "$app" || ! -x "$bridge" ]]; then
  echo "less-bridge not found in ${1:-/Applications/Less.app}" >&2
  echo "Pass the path to a built Less.app, for example from Xcode's Product > Show Build Folder." >&2
  exit 1
fi

escape_json() {
  local s="${1//\\/\\\\}"
  printf '%s' "${s//\"/\\\"}"
}

installed=0
for browser in "${browsers[@]}"; do
  # only browsers that have run at least once
  [[ -d "$support/$browser" ]] || continue
  dir="$support/$browser/NativeMessagingHosts"
  mkdir -p "$dir"
  cat > "$dir/$host.json" <<JSON
{
  "name": "$host",
  "description": "less: counts X tabs",
  "path": "$(escape_json "$bridge")",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$extension_id/"]
}
JSON
  echo "installed: $dir/$host.json"
  installed=$((installed + 1))
done

if [[ "$installed" -eq 0 ]]; then
  echo "No Chromium browser profile found under $support." >&2
  exit 1
fi
echo "Done. Reload the extension, then open its popup to check the connection."
