#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="0.1.0-beta.1"
architecture="$(uname -m)"
[[ "$architecture" == arm64 ]] || { echo 'This release script currently packages the tested arm64 build only.'; exit 1; }
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity}"
stage="$project_dir/dist/obs-filtered-capture-$version-macos-arm64"
[[ ! -e "$stage" ]] || { echo "Release staging directory already exists: $stage"; exit 1; }
mkdir -p "$stage"
ditto "$project_dir/build/obs-filtered-capture.plugin" "$stage/obs-filtered-capture.plugin"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$stage/obs-filtered-capture.plugin"
codesign --verify --deep --strict "$stage/obs-filtered-capture.plugin"
cp "$project_dir/scripts/Install.command" "$stage/Install.command"
chmod +x "$stage/Install.command"
cp "$project_dir/README.md" "$project_dir/LICENSE" "$project_dir/THIRD_PARTY.md" "$project_dir/RELEASE_NOTES.md" "$stage/"
ditto "$project_dir/LICENSES" "$stage/LICENSES"
archive="$stage.zip"
ditto -c -k --sequesterRsrc --keepParent "$stage" "$archive"
(cd "$project_dir/dist" && shasum -a 256 "$(basename "$archive")" > SHA256SUMS)
echo "Packaged: $archive"
