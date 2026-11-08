#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$(mktemp -d -t obs-filtered-installer)"
trap 'rm -rf "$fixture_dir"' EXIT
cp "$project_dir/scripts/Install.command" "$fixture_dir/Install.command"
ditto "$project_dir/build/obs-filtered-capture.plugin" "$fixture_dir/obs-filtered-capture.plugin"
export OBS_FILTERED_CONFIG_DIR="$fixture_dir/config"
# Simulate the host state; filesystem effects remain inside the fixture directory.
pgrep() { return 0; }
export -f pgrep
if bash "$fixture_dir/Install.command" > "$fixture_dir/running.log" 2>&1; then
  echo 'FAIL: installer accepted running OBS'; exit 1
fi
[[ ! -d "$OBS_FILTERED_CONFIG_DIR/plugins" ]]
pgrep() { return 1; }
export -f pgrep
bash "$fixture_dir/Install.command"
codesign --verify --deep --strict "$OBS_FILTERED_CONFIG_DIR/plugins/obs-filtered-capture.plugin"
touch "$OBS_FILTERED_CONFIG_DIR/plugins/obs-filtered-capture.plugin/prior-version-marker"
bash "$fixture_dir/Install.command"
[[ ! -e "$OBS_FILTERED_CONFIG_DIR/plugins/obs-filtered-capture.plugin/prior-version-marker" ]]
[[ $(find "$OBS_FILTERED_CONFIG_DIR/backups" -name prior-version-marker | wc -l | tr -d ' ') == 1 ]]
echo 'PASS: running-host refusal, fresh install, upgrade and prior-version recovery'
