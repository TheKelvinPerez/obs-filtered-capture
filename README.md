# OBS Filtered Capture

**Capture your Mac desktop in OBS while hiding selected applications.**

Keep a teleprompter, notes or chat visible to you while excluding them from your OBS display source. Frames go directly from Apple's ScreenCaptureKit into OBS through shared GPU surfaces. No intermediate sharing window is required.

[Download the beta](https://github.com/TheKelvinPerez/obs-filtered-capture/releases/tag/v0.1.0-beta.1) · [Report a bug](https://github.com/TheKelvinPerez/obs-filtered-capture/issues)

## Compatibility

* Apple Silicon download, arm64 only.
* Tested with OBS Studio 33.0.1 on macOS 15.7. Deployment target is macOS 13.0; older OS versions are not validated.
* SDR BGRA video. Use existing OBS sources for audio.
* Developer ID signed, not notarized.
* Intel builds, earlier OBS releases, HDR and independent performance benchmarks are outside this beta's validated scope.

## Install

1. Download the arm64 ZIP and SHA256SUMS from the release page. Verify with `shasum -a 256 -c SHA256SUMS` in the download directory.
2. Extract the ZIP and quit OBS.
3. Run the included `Install.command`. It verifies the bundle signature, preserves a previous version in OBS's backups directory and installs for the current user.
4. Open OBS and add **macOS Capture with App Exclusions** to a temporary scene.
5. Choose your display and test the exclusions before using this source in an existing recording scene.

For manual installation, copy the intact `obs-filtered-capture.plugin` bundle into:

```text
~/Library/Application Support/obs-studio/plugins/
```

Create that folder if necessary, then restart OBS. The installer leaves scenes, profiles and permissions unchanged. Screen recording permission belongs to OBS.

This beta is signed but not notarized. If macOS blocks it, do not disable Gatekeeper. Build from source using the instructions below, or wait for a notarized release. Report the exact warning and macOS version without private screen content.

## Configure

* **Display:** select the monitor. Nothing is selected automatically, and a missing monitor never falls back to another display.
* **Excluded application bundle IDs:** edit exact identifiers, or use **Add running application to exclusions**. OBS is hidden by default and NotchPrompter is in the initial exclusion list. Both are configurable.
* **Show cursor:** include or omit the pointer.
* **Capture width limit:** use native resolution for detail or a lower width to reduce bandwidth while preserving aspect ratio.
* **Frame rate:** follows OBS at capture startup. For 60 FPS, set OBS Settings → Video accordingly, then click **Restart capture / refresh applications**.

Capture stops when the source is no longer shown. Excluded app launches/terminations, wake and monitor changes trigger a refresh. Refreshes and settings changes temporarily blank the source.

## Privacy boundaries

Exclusions apply to this source only. Other display sources, screenshots and screen-sharing apps are unaffected. Content inside an allowed app stays visible; excluding a chat app does not hide chat inside an allowed browser.

Application relaunch detection and filter refresh are asynchronous. **This beta does not guarantee that every transition frame is protected.** Test relaunches, new windows, workspace switches and display reconnects with disposable content before relying on exclusions. This is not a text-redaction or data-loss-prevention system.

## Architecture

```text
Display + app exclusion IDs
            ↓
ScreenCaptureKit application filter
            ↓
Dedicated serial frame callback
            ↓
Latest retained IOSurface frame
            ↓
OBS GPU texture import → scene → encoder
```

The latest frame replaces old pending frames instead of growing a queue. OBS reuses texture bindings when dimensions match. Capture avoids preview image conversion and recapturing another app's window. Configuration work runs separately from frame delivery. Numeric latency and throughput claims still require measurements.

## Troubleshooting

**Blank source:** choose a display, check OBS screen recording permission in System Settings → Privacy & Security, and restart capture. Reopen OBS after permission changes. Stream failures leave the source blank.

**Missing source:** verify the plugins directory, arm64 architecture and OBS version, then restart OBS.

**Choppy video:** compare a simple scene against native capture at identical settings, with one capture source active per run. Inspect View → Stats and try a capture width limit. OBS output FPS alone does not prove unique captured frames.

**Logs:** look for `[filtered-capture]`. Share only relevant lines with private paths and content removed.

**Uninstall or roll back:** quit OBS and move the plugin out of the plugins directory. Restore an older bundle from OBS's backups directory if available. Scenes using a removed source report it missing until restored or removed.

## Build from source

Requires an Apple Silicon Mac, Xcode command-line tools, Git, CMake 3.28+, Ninja and OBS Studio 33.0.1 at `/Applications/OBS.app`.

```sh
git clone https://github.com/TheKelvinPerez/obs-filtered-capture.git
cd obs-filtered-capture
./scripts/build.sh
./scripts/install.sh
```

The build downloads pinned OBS and SIMDe checkouts into ignored `.deps/` and ad hoc signs local builds. No downloaded package install scripts are executed. The development installer refuses to overwrite an existing plugin; quit OBS and preserve the old bundle before replacing it.

For a custom OBS location, configure CMake manually with `OBS_APP`, `OBS_SOURCE_DIR` and `SIMDE_INCLUDE_DIR`. The distributed plugin resolves OBS's framework relative to the running OBS executable.

To package a signed release after building:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/package.sh
```

Credentials stay in your local keychain. Packaging does not publish artifacts.

## Validation and contributing

`ctest --test-dir build --output-on-failure` runs exclusion-policy tests and a real libobs module-load/source-lifecycle smoke test. The latter initializes OBS's Metal backend at 1920×1080 and 60 FPS, verifies defaults, properties and settings, and exercises show/hide/removal. It does not request screen capture or validate live captured frames.

The workflow has been used successfully in a live OBS setup. Broad compatibility, quantified performance and privacy-transition acceptance remain open testing work. See [QA.md](QA.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-2.0-or-later. The GPU source integration follows OBS Studio's mac-capture implementation. See [LICENSE](LICENSE), [THIRD_PARTY.md](THIRD_PARTY.md) and [LICENSES/SIMDe.txt](LICENSES/SIMDe.txt).
