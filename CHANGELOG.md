# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.9.0]: https://github.com/cyniqc/ag-setup/releases/tag/v0.9.0
