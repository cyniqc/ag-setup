# toolz

A collection of personal Linux utilities.

## `ag-setup.sh`

An **automatic installation and update script** for **Google Antigravity (Hub / 2.0)** on Linux.

It can both **install Google Antigravity from scratch** on a fresh system (Ubuntu, Linux Mint, etc.) and automatically **update** it afterward.

### How it works

1. Checks the latest available version at [antigravity.google/download](https://antigravity.google/download).
2. Compares it with the locally installed version, if any (read from `resources/app.asar`).
3. Downloads the Linux archive matching the system architecture (`linux-x64` or `linux-arm`) using `curl` or `wget` if Antigravity is not installed or a newer version is available.
4. Extracts the archive into a temporary staging directory and verifies that the `antigravity` binary is present before touching any existing installation.
5. Prompts for confirmation before gracefully closing Antigravity processes tied to the installation directory if it is currently running (unless `--yes` is passed).
6. Installs or replaces the application atomically (with automatic rollback on error).
7. Sets up desktop integration:
   - extracts the official PNG icon (`512x512`) to `~/.local/share/icons/hicolor/512x512/apps/antigravity.png`;
   - creates the `~/.local/share/applications/antigravity.desktop` launcher (with `antigravity://` URL scheme support);
   - creates the `~/.local/bin/antigravity` symlink so you can launch `antigravity` from the terminal.
8. Removes the downloaded archive and temporary files.

### Requirements

- Linux (`x86_64` or `arm64`)
- `bash`
- `tar`
- `python3` (standard library only, installed by default on Ubuntu / Linux Mint)
- `curl` **or** `wget` (automatic fallback to `wget`, preinstalled on a fresh Ubuntu system)

### Usage

```bash
# Automatically install or update to the latest version
./ag-setup.sh

# Only check if an update is available (read-only, downloads nothing)
./ag-setup.sh --check

# Force download and reinstallation
./ag-setup.sh --force

# Install or update without asking for confirmation to close Antigravity
./ag-setup.sh --yes

# Install or update without creating the desktop launcher, icon, or CLI symlink
./ag-setup.sh --no-desktop

# Install (or update) a copy of the script to ~/.local/bin/ag-setup
./ag-setup.sh --install-self

# Install from a local .tar.gz archive (and remove it afterward)
./ag-setup.sh /path/to/Antigravity.tar.gz

# Show help
./ag-setup.sh --help
```

### Optional environment variables

- `XDG_DATA_HOME`: user data directory (default: `$HOME/.local/share`).
- `DEST_DIR`: Antigravity installation directory (default: `$XDG_DATA_HOME/antigravity`).
- `BIN_DIR`: destination directory for the `antigravity` symlink and the copy installed via `--install-self` (default: `$HOME/.local/bin`).
- `DESKTOP_DIR`: directory for the `.desktop` launcher (default: `$XDG_DATA_HOME/applications`).
- `ICON_DIR`: directory for the PNG icon (default: `$XDG_DATA_HOME/icons/hicolor/512x512/apps`).
- `DOWNLOADER`: HTTP download tool to use: `auto`, `curl`, or `wget` (default: `auto`).

> **Note:** When updating, prefer running the script from an external terminal rather than Antigravity's integrated terminal, as the script closes Antigravity processes associated with `DEST_DIR` when replacing files.
