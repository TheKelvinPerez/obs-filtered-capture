# 0.1.0-beta.1

Initial public beta of OBS Filtered Capture for macOS on Apple Silicon.

## Features

* Capture an entire display while excluding selected applications.
* Direct ScreenCaptureKit to IOSurface to OBS texture path, with no intermediate share window.
* Follow the OBS frame rate, including 60 FPS configurations.
* Add running applications through a dropdown, or enter exact bundle identifiers.
* Exclude OBS by default; NotchPrompter is included in the default exclusion list.
* Optional capture width limits and cursor visibility.
* Stop capture when the source is hidden; refresh after excluded app lifecycle events and display changes.

## Compatibility

* Download: arm64 only, for Apple Silicon Macs.
* Minimum deployment target: macOS 13.0.
* Tested with OBS Studio 33.0.1 on an Apple Silicon Mac. Earlier OBS releases and Intel builds are not validated.
* SDR video only. Use separate OBS sources for audio.
* Developer ID signed. This beta is not notarized.

## Validation and limits

The capture workflow has been used successfully in a live local OBS setup. Automated checks cover exclusion matching, module loading, defaults, source properties, settings changes and source lifecycle under the installed OBS Metal backend. Static analysis and signature verification pass.

No independent frame-rate or end-to-end latency benchmark is published. The capture requests OBS's frame rate; output FPS does not prove every captured frame is unique. App relaunches and display changes refresh asynchronously and can cause a blank transition. This beta is not a guarantee against every sensitive transition frame. Test your exact setup before relying on exclusions.

## Installation

Download and extract the arm64 ZIP from this release, quit OBS, and run Install.command. Alternatively copy obs-filtered-capture.plugin to ~/Library/Application Support/obs-studio/plugins/. Restart OBS and add **macOS Capture with App Exclusions** to a temporary scene. Choose your display and test exclusions before using it in an existing recording scene.

The installer preserves a previous plugin under OBS's backups folder and leaves scenes and profiles unchanged. For macOS security and permission troubleshooting, see README.md. Do not disable Gatekeeper to install this beta.
