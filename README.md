# ag-setup

[![Lint](https://github.com/cyniqc/ag-setup/actions/workflows/lint.yml/badge.svg)](https://github.com/cyniqc/ag-setup/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A **single-file Bash script** to automatically install and update **Google Antigravity (App / Hub)** on Linux (`x86_64` and `arm64`).

Lightweight, easy to audit, and requiring only standard Linux tools — it can **install Google Antigravity from scratch** on a fresh system (Ubuntu, Linux Mint, etc.) and automatically **update** it afterward.

## Quick Start

Download the script, inspect it, and install the `ag-setup` command into `~/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/cyniqc/ag-setup/main/ag-setup.sh -o ag-setup.sh
chmod +x ag-setup.sh
less ag-setup.sh
./ag-setup.sh --install-self
```

Or clone the repository:

```bash
git clone https://github.com/cyniqc/ag-setup.git
cd ag-setup
./ag-setup.sh --install-self
```

Then run `ag-setup` to install or update Google Antigravity.

## How it works

1. Checks the latest release via the official Google Antigravity Hub release feed (falling back to [antigravity.google/download](https://antigravity.google/download)) and validates that the download URL points to an allowed official Google host and path prefix.
2. Compares the remote version with the locally installed version, if any (read from `resources/app.asar`, using SemVer comparison including pre-releases).
3. Downloads the Linux archive matching the system architecture (`linux-x64` or `linux-arm`) over HTTPS only using `curl` or `wget` when Antigravity is not installed or a newer version is available.
4. Validates every `tar` archive path (rejecting absolute paths and `..` traversal), extracts into a temporary staging directory with `--no-same-owner`, and verifies that the `antigravity` binary is present before touching any existing installation.
5. Prompts for confirmation before gracefully closing Antigravity processes tied to `DEST_DIR` if it is currently running (unless `--yes` is passed).
6. Installs or replaces the application atomically, with automatic rollback on error or interruption (`SIGINT` / `SIGTERM`).
7. Sets up desktop integration:
   - validates the PNG signature and extracts the official icon to `~/.local/share/icons/hicolor/512x512/apps/antigravity.png`;
   - creates the `~/.local/share/applications/antigravity.desktop` launcher (with `antigravity://` URL scheme support);
   - creates the `~/.local/bin/antigravity` symlink so you can launch `antigravity` from the terminal.
8. Cleans up the downloaded archive and temporary directories.

## Requirements

- Linux (`x86_64` or `arm64`), executed as a regular non-root user
- `bash`
- `tar`
- `python3` (standard library only, preinstalled on most distributions)
- `curl` **or** `wget` (automatic fallback to `wget`)

## Usage

```bash
# Automatically install or update to the latest version
ag-setup

# Only check if an update is available (read-only; downloads no archive)
# Exits 0 whether an update is available or already up to date, and non-zero on error
ag-setup --check

# Force download and reinstallation even if already up to date
ag-setup --force

# Close Antigravity automatically without asking for confirmation
ag-setup --yes

# Install or update without creating the .desktop launcher, icon, or BIN_DIR symlink
ag-setup --no-desktop

# Copy this script to ~/.local/bin/ag-setup so it can be run from anywhere
./ag-setup.sh --install-self

# Show version
ag-setup --version

# Show help
ag-setup --help
```

Short flags are also available for `--check` (`-c`), `--force` (`-f`), `--yes` (`-y`), and `--help` (`-h`).

> **Note:** When updating, run the command from an external terminal rather than Antigravity's integrated terminal, as the script closes Antigravity processes associated with `DEST_DIR` before replacing files.

## Optional environment variables

- `XDG_DATA_HOME`: user data directory (default: `$HOME/.local/share`).
- `DEST_DIR`: Antigravity installation directory (default: `$XDG_DATA_HOME/antigravity`).
- `BIN_DIR`: destination directory for the `antigravity` symlink and `--install-self` (default: `$HOME/.local/bin`).
- `DESKTOP_DIR`: directory for the `.desktop` launcher (default: `$XDG_DATA_HOME/applications`).
- `ICON_DIR`: directory for the PNG icon (default: `$XDG_DATA_HOME/icons/hicolor/512x512/apps`).
- `DOWNLOADER`: HTTP download tool to use: `auto`, `curl`, or `wget` (default: `auto`).

> **Safety guardrails:** `DEST_DIR` must be an absolute path without `..` components, and the script refuses `/`, `$HOME`, `$XDG_DATA_HOME`, system directories, symlinks/non-directory targets, or non-empty directories that do not look like an existing Google Antigravity installation.

## Uninstall

To remove Google Antigravity and the desktop integration installed by `ag-setup` (without touching your personal configuration or workspace data):

```bash
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/antigravity"
rm -f "${BIN_DIR:-$HOME/.local/bin}/antigravity" \
      "${BIN_DIR:-$HOME/.local/bin}/ag-setup" \
      "${DESKTOP_DIR:-$HOME/.local/share/applications}/antigravity.desktop" \
      "${ICON_DIR:-$HOME/.local/share/icons/hicolor/512x512/apps}/antigravity.png"
```

## Disclaimer

This is an **unofficial community tool** and is not affiliated with, endorsed by, or supported by Google.

- It does not redistribute Google binaries; archives are downloaded directly from Google's official distribution endpoints and remain subject to Google's terms.
- Version detection relies on Google's official release feed and download page structure, which may change without notice.
- Developed with AI assistance, reviewed, and tested on Linux. As a single-file script, you are encouraged to inspect `ag-setup.sh` before running it.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release notes and version history.

## License

Released under the [MIT License](LICENSE).
