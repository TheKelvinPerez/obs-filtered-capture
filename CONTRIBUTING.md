# Contributing

Open an issue with a concrete problem or a pull request with a focused change. Preserve the direct GPU capture path and avoid extra image conversions or unbounded frame queues.

For bug reports, include macOS version, OBS version, architecture, plugin version, display resolution, reproduction steps, and expected versus actual behavior. Relevant `[filtered-capture]` log lines help. Remove private paths, application content, keys and account information.

Build with `./scripts/build.sh`. It verifies pinned dependency revisions, compiles the module and runs focused tests. Run `bash -n scripts/*.sh scripts/Install.command` for shell changes. Source changes should pass Clang static analysis and relevant checks in QA.md. Capture changes need live OBS tests; unconfigured-source tests cannot prove live behavior.

Privacy-transition reports should identify app relaunches, new windows, display reconnects or wake. Use disposable content. Never upload sensitive screen recordings to a public issue.

Release binaries must identify architecture, tested OBS version, signing/notarization state and known limits. Keep credentials out of scripts and artifacts. Contributions use the project's GPL-2.0-or-later license.
