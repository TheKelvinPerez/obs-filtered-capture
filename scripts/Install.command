#!/bin/bash
set -euo pipefail
release_dir="$(cd "$(dirname "$0")" && pwd)"
bundle="$release_dir/obs-filtered-capture.plugin"
obs_config_dir="${OBS_FILTERED_CONFIG_DIR:-$HOME/Library/Application Support/obs-studio}"
plugins_dir="$obs_config_dir/plugins"
destination="$plugins_dir/obs-filtered-capture.plugin"
if pgrep -x OBS >/dev/null; then
  echo 'Quit OBS before installing. This installer will not stop your recording.'
  exit 1
fi
[[ -d "$bundle" ]] || { echo 'Keep Install.command next to obs-filtered-capture.plugin.'; exit 1; }
codesign --verify --deep --strict "$bundle"
mkdir -p "$plugins_dir"
if [[ -e "$destination" ]]; then
  backup_dir="$obs_config_dir/backups/filtered-capture-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$backup_dir"
  mv "$destination" "$backup_dir/obs-filtered-capture.plugin"
  echo "Previous version preserved at: $backup_dir"
fi
ditto "$bundle" "$destination"
codesign --verify --deep --strict "$destination"
echo 'Installed OBS Filtered Capture.'
echo 'Open OBS and add macOS Capture with App Exclusions to a test scene.'
echo 'Existing scenes and recording profiles were not changed.'
