#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$project_dir/build/obs-filtered-capture.plugin"
if pgrep -x OBS >/dev/null; then
  echo 'Quit OBS before installing. This installer will not stop your recording.'
  exit 1
fi
plugins_dir="$HOME/Library/Application Support/obs-studio/plugins"
destination="$plugins_dir/obs-filtered-capture.plugin"
[[ -d "$bundle" ]] || { echo 'Run scripts/build.sh first'; exit 1; }
codesign --verify --deep --strict "$bundle"
mkdir -p "$plugins_dir"
if [[ -e "$destination" ]]; then
  echo 'An installed version already exists. Quit OBS and preserve that version before replacing it.'
  exit 1
fi
ditto "$bundle" "$destination"
codesign --verify --deep --strict "$destination"
echo "Installed: $destination"
echo 'Restart OBS when you are ready. Existing scenes are unchanged.'
