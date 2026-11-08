#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
deps_dir="$project_dir/.deps"
mkdir -p "$deps_dir"
if [[ ! -d "$deps_dir/obs/.git" ]]; then
  git clone --depth 1 --branch 33.0.1 https://github.com/obsproject/obs-studio.git "$deps_dir/obs"
fi
if [[ ! -d "$deps_dir/simde/.git" ]]; then
  git clone --depth 1 --branch v0.8.2 https://github.com/simd-everywhere/simde.git "$deps_dir/simde"
fi
[[ "$(git -C "$deps_dir/obs" rev-parse HEAD)" == 65c320b46e1af5c7a555161aea6182cdf7a8c524 ]] || { echo 'Unexpected OBS SDK revision'; exit 1; }
[[ "$(git -C "$deps_dir/simde" rev-parse HEAD)" == 71fd833d9666141edcd1d3c109a80e228303d8d7 ]] || { echo 'Unexpected SIMDe revision'; exit 1; }
cmake -S "$project_dir" -B "$project_dir/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DOBS_SOURCE_DIR="$deps_dir/obs" -DSIMDE_INCLUDE_DIR="$deps_dir/simde"
cmake --build "$project_dir/build"
ctest --test-dir "$project_dir/build" --output-on-failure
codesign --force --sign - "$project_dir/build/obs-filtered-capture.plugin"
codesign --verify --deep --strict "$project_dir/build/obs-filtered-capture.plugin"
