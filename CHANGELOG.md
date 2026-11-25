# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.0] - 2026-11-25

### Added

- Add `--changelog` read-only option to fetch and display full release notes (newest first) from `https://antigravity.google/docs/changelog` for all pending updates between the installed version and the latest release (or for the current/latest version when already up to date or not yet installed), with a graceful fallback link if notes are unavailable or not yet published.

### Changed

- Show a hint (`Run 'ag-setup --changelog' to see what changed.`) in `--check` output when a newer version is available, leaving the up-to-date output unchanged.

## [0.9.1] - 2026-11-21

### Changed

- Extract `.tar.gz` archives in a single pass instead of running a separate `tar -tzf` pre-scan, promoting a single top-level directory directly from staging.
- Scan `/proc` in Python (`os.scandir` / `os.readlink`) inside `find_antigravity_pids` to eliminate per-process `readlink` forks during detection and shutdown polling.
- Merge duplicate `python3` invocations in `get_local_version` and `extract_app_icon` into `read_app_resource` (`json-version` and `png-file` modes).
- Simplify Bash internals: replace `while read` loops with `mapfile -t`, replace `printf | sed` pipelines with `read`, deduplicate process count formatting, condense `detect_downloader` / `validate_dest_dir`, and rely on `trap cleanup EXIT` for error rollbacks.

### Fixed

- Avoid re-running desktop integration on every execution when icon extraction falls back to `Icon=applications-development`.

## [0.9.0] - 2026-11-20

Initial public beta release of `ag-setup`.

### Added

- Automatic installation and update of Google Antigravity (App / Hub) on Linux (`x86_64` and `arm64`) into `DEST_DIR` (`$XDG_DATA_HOME/antigravity` by default).
- Live release detection via the official Hub JSON release feed with automatic HTML fallback on `https://antigravity.google/download`, enforcing a strict HTTPS URL host/path allowlist.
- Local version detection from `resources/app.asar` (with unpacked/plain fallback) and SemVer comparison including pre-release versions.
- HTTPS-only archive downloads using `curl` with automatic fallback to `wget` (configurable via `DOWNLOADER`).
- Archive path validation (rejecting absolute paths and `..` traversal), `--no-same-owner` extraction into a temporary staging directory, and atomic swap with rollback on error or `SIGINT`/`SIGTERM`.
- Graceful shutdown of running Antigravity processes tied to `DEST_DIR` (targeting the root Electron process first to avoid Chromium child crashes, with confirmation prompt and `--yes` / `-y` override).
- XDG desktop integration: PNG signature validation and icon extraction from `app.asar`, Freedesktop-escaped `antigravity.desktop` launcher (with `antigravity://` URL scheme handling), and `~/.local/bin/antigravity` CLI symlink.
- CLI flags: `--check` (`-c`), `--force` (`-f`), `--yes` (`-y`), `--no-desktop`, `--install-self`, `--version`, and `--help` (`-h`).
- Safety guardrails: Linux-only check, root/`sudo` refusal, strict validation of `DEST_DIR` and XDG directory variables, and protection against overwriting non-Antigravity directories.
- MIT `LICENSE`, public `README.md`, and GitHub Actions lint workflow (`bash -n` and `shellcheck`).

[0.10.0]: https://github.com/cyniqc/ag-setup/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/cyniqc/ag-setup/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/cyniqc/ag-setup/releases/tag/v0.9.0
