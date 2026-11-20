#!/usr/bin/env bash
set -euo pipefail

DOWNLOAD_PAGE_URL="https://antigravity.google/download"
HUB_RELEASES_API_URL="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/releases"
HUB_DOWNLOAD_BASE_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST_DIR="${DEST_DIR:-$XDG_DATA_HOME/antigravity}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
DESKTOP_DIR="${DESKTOP_DIR:-$XDG_DATA_HOME/applications}"
ICON_DIR="${ICON_DIR:-$XDG_DATA_HOME/icons/hicolor/512x512/apps}"
DOWNLOADER="${DOWNLOADER:-auto}"

normalize_dir_path() {
    local p="$1"
    while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do
        p="${p%/}"
    done
    printf '%s\n' "$p"
}

XDG_DATA_HOME="$(normalize_dir_path "$XDG_DATA_HOME")"
DEST_DIR="$(normalize_dir_path "$DEST_DIR")"
BIN_DIR="$(normalize_dir_path "$BIN_DIR")"
DESKTOP_DIR="$(normalize_dir_path "$DESKTOP_DIR")"
ICON_DIR="$(normalize_dir_path "$ICON_DIR")"

TMP_DIR=""
STAGE_DIR=""
BACKUP_CONTAINER=""
BACKUP_DIR=""
TMP_SELF_TARGET=""
SELECTED_DOWNLOADER=""
ASSUME_YES=0
CLOSE_CONFIRMED=0

cleanup() {
    if [ -n "$BACKUP_DIR" ] && [ -e "$BACKUP_DIR" ] && [ ! -e "$DEST_DIR" ]; then
        mv "$BACKUP_DIR" "$DEST_DIR" 2>/dev/null || true
    fi
    if [ -n "$BACKUP_CONTAINER" ] && [ -d "$BACKUP_CONTAINER" ]; then
        rm -rf "$BACKUP_CONTAINER"
    fi
    if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
        rm -rf "$STAGE_DIR"
    fi
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
    if [ -n "$TMP_SELF_TARGET" ] && [ -f "$TMP_SELF_TARGET" ]; then
        rm -f "$TMP_SELF_TARGET"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
    printf 'Usage: %s [OPTIONS]\n' "$(basename "$0")"
    cat <<'EOF'

Installs or updates Google Antigravity (Hub) in "$HOME/.local/share/antigravity"
(or in the directory defined by the DEST_DIR environment variable) and configures
desktop integration (.desktop launcher, icon, and 'antigravity' command).

With no arguments:
  Checks the latest available version via the official Google Antigravity
  release feed (falling back to https://antigravity.google/download), downloads
  it if Antigravity is not installed or an update is available, installs it
  (with desktop launcher and icon), and removes the downloaded archive.

Options:
  -c, --check         Only check if an update is available (read-only)
  -f, --force         Force download and reinstallation even if already up to date
  -y, --yes           Close Antigravity automatically without asking for confirmation
      --no-desktop    Do not create the .desktop launcher, icon, or BIN_DIR symlink
      --install-self  Copy this script to "$BIN_DIR/ag-setup" so it can be run from anywhere
  -h, --help          Show this help message and exit

Optional environment variables:
  DEST_DIR     Installation directory (default: $XDG_DATA_HOME/antigravity)
  BIN_DIR      Destination directory for 'antigravity' and --install-self (default: $HOME/.local/bin)
  DESKTOP_DIR  Directory for the .desktop file (default: $XDG_DATA_HOME/applications)
  ICON_DIR     Directory for the PNG icon (default: $XDG_DATA_HOME/icons/hicolor/512x512/apps)
  DOWNLOADER   Download tool: auto, curl, or wget (default: auto)
EOF
}

detect_downloader() {
    case "$DOWNLOADER" in
        auto)
            if command -v curl >/dev/null 2>&1; then
                printf 'curl\n'
            elif command -v wget >/dev/null 2>&1; then
                printf 'wget\n'
            else
                echo "Error: 'curl' or 'wget' is required for downloading." >&2
                exit 1
            fi
            ;;
        curl)
            if command -v curl >/dev/null 2>&1; then
                printf 'curl\n'
            else
                echo "Error: missing tool: curl" >&2
                exit 1
            fi
            ;;
        wget)
            if command -v wget >/dev/null 2>&1; then
                printf 'wget\n'
            else
                echo "Error: missing tool: wget" >&2
                exit 1
            fi
            ;;
        *)
            echo "Error: invalid DOWNLOADER value '$DOWNLOADER' (expected: auto, curl, or wget)." >&2
            exit 1
            ;;
    esac
}

check_os() {
    local os_name
    os_name="$(uname -s)"
    if [ "$os_name" != "Linux" ]; then
        echo "Error: Google Antigravity setup is only supported on Linux (detected: $os_name)." >&2
        exit 1
    fi
}

check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "Error: do not run this script as root or with sudo; it installs for the current user." >&2
        exit 1
    fi
}

validate_safe_dir_var() {
    local var_name="$1"
    local val="$2"
    local resolved

    if [ -z "$val" ]; then
        echo "Error: $var_name must not be empty." >&2
        exit 1
    fi

    case "$val" in
        *$'\n'*|*$'\r'*)
            echo "Error: $var_name must not contain newline characters." >&2
            exit 1
            ;;
    esac

    case "$val" in
        /*) ;;
        *)
            echo "Error: $var_name must be an absolute path (got: '$val')." >&2
            exit 1
            ;;
    esac

    case "/$val/" in
        */../*)
            echo "Error: $var_name must not contain '..' path components (got: '$val')." >&2
            exit 1
            ;;
    esac

    resolved="$(readlink -m "$val" 2>/dev/null || printf '%s\n' "$val")"
    if [ "$val" = "/" ] || [ "$resolved" = "/" ]; then
        echo "Error: $var_name cannot be '/'." >&2
        exit 1
    fi
}

validate_dest_dir() {
    validate_safe_dir_var "DEST_DIR" "$DEST_DIR"

    local resolved_dest home_norm home_resolved xdg_norm xdg_resolved candidate
    resolved_dest="$(readlink -m "$DEST_DIR")"

    home_norm="$(normalize_dir_path "${HOME:-}")"
    home_resolved=""
    if [ -n "$home_norm" ]; then
        home_resolved="$(readlink -m "$home_norm" 2>/dev/null || printf '%s\n' "$home_norm")"
    fi

    xdg_norm="$(normalize_dir_path "$XDG_DATA_HOME")"
    xdg_resolved=""
    if [ -n "$xdg_norm" ]; then
        xdg_resolved="$(readlink -m "$xdg_norm" 2>/dev/null || printf '%s\n' "$xdg_norm")"
    fi

    for candidate in "$DEST_DIR" "$resolved_dest"; do
        if [ -n "$home_norm" ] && { [ "$candidate" = "$home_norm" ] || [ "$candidate" = "$home_resolved" ]; }; then
            echo "Error: refusing to use HOME directory as DEST_DIR ('$DEST_DIR')." >&2
            exit 1
        fi
        if [ -n "$xdg_norm" ] && { [ "$candidate" = "$xdg_norm" ] || [ "$candidate" = "$xdg_resolved" ]; }; then
            echo "Error: refusing to use XDG_DATA_HOME directory as DEST_DIR ('$DEST_DIR')." >&2
            exit 1
        fi
        case "$candidate" in
            /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/usr/local|/var)
                echo "Error: refusing to use unsafe system directory as DEST_DIR ('$DEST_DIR')." >&2
                exit 1
                ;;
        esac
    done
}

validate_existing_dest_dir() {
    if [ -L "$DEST_DIR" ] || { [ -e "$DEST_DIR" ] && [ ! -d "$DEST_DIR" ]; }; then
        echo "Error: '$DEST_DIR' exists and is not a regular directory." >&2
        exit 1
    fi

    if [ -d "$DEST_DIR" ] && [ -n "$(ls -A "$DEST_DIR" 2>/dev/null)" ]; then
        if [ ! -f "$DEST_DIR/antigravity" ] \
            && [ ! -f "$DEST_DIR/resources/app.asar" ] \
            && [ ! -d "$DEST_DIR/resources/app" ]; then
            echo "Error: '$DEST_DIR' already exists, is not empty, and does not look like a Google Antigravity installation. Refusing to overwrite it." >&2
            exit 1
        fi
    fi
}

check_dependencies() {
    local missing=()
    local cmd

    for cmd in tar python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Error: missing tool(s): ${missing[*]}" >&2
        exit 1
    fi

    SELECTED_DOWNLOADER="$(detect_downloader)"
}

download_file() {
    local url="$1"
    local output_path="$2"
    local mode="$3"
    local tool="${SELECTED_DOWNLOADER:-}"

    if [ -z "$tool" ]; then
        tool="$(detect_downloader)"
        SELECTED_DOWNLOADER="$tool"
    fi

    case "$tool" in
        curl)
            if [ "$mode" = "progress" ]; then
                curl -fL --progress-bar --proto '=https' --proto-redir '=https' \
                    --connect-timeout 15 --retry 3 --retry-delay 2 \
                    -o "$output_path" "$url"
            else
                curl -fsSL --proto '=https' --proto-redir '=https' --compressed \
                    --connect-timeout 15 --retry 3 --retry-delay 2 \
                    -o "$output_path" "$url"
            fi
            ;;
        wget)
            if [ "$mode" = "progress" ]; then
                wget -q --show-progress --https-only --timeout=15 --tries=3 \
                    -O "$output_path" "$url"
            else
                wget -q --https-only --timeout=15 --tries=3 \
                    -O "$output_path" "$url"
            fi
            ;;
        *)
            echo "Error: unknown downloader: $tool" >&2
            exit 1
            ;;
    esac
}

detect_platform() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)
            printf 'linux-x64\n'
            ;;
        aarch64|arm64)
            printf 'linux-arm\n'
            ;;
        *)
            echo "Error: unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
}

read_app_resource() {
    local install_dir="$1"
    local resource_name="$2"
    local output_path="${3:-}"
    [ -d "$install_dir" ] || return 1

    python3 - "$install_dir" "$resource_name" "$output_path" <<'PY'
import json
import os
import struct
import sys

MAX_HEADER_BYTES = 50 * 1024 * 1024
MAX_RESOURCE_BYTES = 20 * 1024 * 1024

install_dir = sys.argv[1]
resource_name = sys.argv[2]
output_path = sys.argv[3] if len(sys.argv) > 3 else ""

asar_path = os.path.join(install_dir, "resources", "app.asar")
unpacked_path = os.path.join(install_dir, "resources", "app.asar.unpacked", resource_name)
plain_path = os.path.join(install_dir, "resources", "app", resource_name)

data = None
try:
    if os.path.isfile(asar_path):
        file_size = os.path.getsize(asar_path)
        if file_size < 16:
            sys.exit(1)
        with open(asar_path, "rb") as f:
            f.seek(4)
            header_pickle_size = struct.unpack("<I", f.read(4))[0]
            f.seek(12)
            json_len = struct.unpack("<I", f.read(4))[0]
            if json_len <= 0 or json_len > MAX_HEADER_BYTES or 16 + json_len > file_size:
                sys.exit(1)
            header = json.loads(f.read(json_len).decode("utf-8"))
            base = 8 + header_pickle_size

            info = header.get("files", {}).get(resource_name)
            if isinstance(info, dict):
                if info.get("unpacked"):
                    if os.path.isfile(unpacked_path) and os.path.getsize(unpacked_path) <= MAX_RESOURCE_BYTES:
                        with open(unpacked_path, "rb") as rf:
                            data = rf.read()
                elif "offset" in info and "size" in info:
                    offset = int(info["offset"])
                    size = int(info["size"])
                    if offset < 0 or size < 0 or size > MAX_RESOURCE_BYTES or base + offset + size > file_size:
                        sys.exit(1)
                    f.seek(base + offset)
                    data = f.read(size)
    elif os.path.isfile(plain_path) and os.path.getsize(plain_path) <= MAX_RESOURCE_BYTES:
        with open(plain_path, "rb") as rf:
            data = rf.read()

    if data is None:
        sys.exit(1)

    if output_path:
        parent = os.path.dirname(output_path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(output_path, "wb") as out:
            out.write(data)
    else:
        sys.stdout.buffer.write(data)
except Exception:
    sys.exit(1)
PY
}

get_local_version() {
    local dir="${1:-$DEST_DIR}"
    [ -d "$dir" ] || return 0

    local pkg_json=""
    if ! pkg_json="$(read_app_resource "$dir" "package.json" 2>/dev/null)"; then
        return 0
    fi
    [ -n "$pkg_json" ] || return 0

    python3 -c '
import json
import sys

try:
    pkg = json.loads(sys.stdin.read())
    ver = pkg.get("version", "")
    if isinstance(ver, str) and ver:
        print(ver)
except Exception:
    pass
' <<< "$pkg_json"
}

extract_app_icon() {
    local install_dir="$1"
    local target_png="$2"
    [ -d "$install_dir" ] || return 1

    local parent_dir tmp_icon
    parent_dir="$(dirname "$target_png")"
    mkdir -p "$parent_dir"
    tmp_icon="$(mktemp "$parent_dir/.antigravity-icon.XXXXXX")"

    if ! read_app_resource "$install_dir" "icon.png" "$tmp_icon" 2>/dev/null; then
        rm -f "$tmp_icon"
        return 1
    fi

    if ! python3 - "$tmp_icon" <<'PY'
import sys

png_magic = b"\x89PNG\r\n\x1a\n"
try:
    with open(sys.argv[1], "rb") as f:
        header = f.read(8)
    sys.exit(0 if header == png_magic else 1)
except Exception:
    sys.exit(1)
PY
    then
        rm -f "$tmp_icon"
        return 1
    fi

    if ! chmod 644 "$tmp_icon" || ! mv -f "$tmp_icon" "$target_png"; then
        rm -f "$tmp_icon"
        return 1
    fi
}

format_desktop_exec() {
    local exe_path="$1"
    python3 - "$exe_path" <<'PY'
import sys

path = sys.argv[1]
reserved = set(" \t\n\"'\\><~|&;$*?#()`")

escaped = path.replace("%", "%%")
if any(ch in reserved for ch in escaped) or not escaped:
    quoted_inner = (
        escaped.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("`", "\\`")
        .replace("$", "\\$")
    )
    arg = f'"{quoted_inner}"'
    arg = arg.replace("\\", "\\\\")
else:
    arg = escaped

print(f"{arg} %U")
PY
}

setup_desktop_integration() {
    mkdir -p "$BIN_DIR"
    if [ ! -e "$BIN_DIR/antigravity" ] || [ -L "$BIN_DIR/antigravity" ]; then
        ln -sfn "$DEST_DIR/antigravity" "$BIN_DIR/antigravity"
    else
        echo "Warning: '$BIN_DIR/antigravity' already exists and is not a symlink; it was not replaced." >&2
    fi

    local icon_target="$ICON_DIR/antigravity.png"
    local icon_value="applications-development"
    if extract_app_icon "$DEST_DIR" "$icon_target"; then
        icon_value="$icon_target"
        case "$ICON_DIR" in
            */icons/hicolor|*/icons/hicolor/*)
                local hicolor_root="${ICON_DIR%/icons/hicolor*}/icons/hicolor"
                if [ -d "$hicolor_root" ] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
                    gtk-update-icon-cache -f -t "$hicolor_root" >/dev/null 2>&1 || true
                fi
                ;;
        esac
    fi

    mkdir -p "$DESKTOP_DIR"
    local desktop_file="$DESKTOP_DIR/antigravity.desktop"
    local exec_cmd
    exec_cmd="$(format_desktop_exec "$DEST_DIR/antigravity")"

    cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=Google Antigravity
Comment=Agentic Development Environment
Exec=$exec_cmd
Icon=$icon_value
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=antigravity
MimeType=x-scheme-handler/antigravity;
EOF
    chmod 644 "$desktop_file"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi

    warn_if_not_in_path "antigravity"
}

warn_if_not_in_path() {
    local cmd_name="$1"
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            echo "Info: add '$BIN_DIR' to your PATH if the '$cmd_name' command is not found."
            ;;
    esac
}

desktop_integration_complete() {
    [ -f "$DESKTOP_DIR/antigravity.desktop" ] \
        && [ -e "$BIN_DIR/antigravity" ] \
        && [ -f "$ICON_DIR/antigravity.png" ]
}

validate_download_url() {
    local url="$1"
    python3 - "$url" <<'PY'
import sys
from urllib.parse import urlparse

url = sys.argv[1]
try:
    parsed = urlparse(url)
except Exception:
    sys.stderr.write(f"Error: untrusted download URL rejected: {url}\n")
    sys.exit(1)

host = (parsed.hostname or "").lower().rstrip(".")
path = parsed.path or ""
allowed = (
    parsed.scheme == "https"
    and parsed.username is None
    and parsed.password is None
    and bool(host)
    and ".." not in path.split("/")
    and path.endswith(".tar.gz")
    and (
        (host == "storage.googleapis.com" and path.startswith("/antigravity-public/antigravity-hub/"))
        or host in ("edgedl.me.gvt1.com", "dl.google.com", "antigravity.google")
        or host.endswith(".antigravity.google")
    )
)

if not allowed:
    sys.stderr.write(f"Error: untrusted download URL rejected: {url}\n")
    sys.exit(1)
PY
}

parse_releases_json() {
    local json_file="$1"
    local platform="$2"
    local parsed_info remote_ver download_url

    parsed_info="$(python3 - "$json_file" "$platform" "$HUB_DOWNLOAD_BASE_URL" <<'PY'
import json
import re
import sys

json_path = sys.argv[1]
platform = sys.argv[2]
base_url = sys.argv[3].rstrip("/")

try:
    with open(json_path, "r", encoding="utf-8") as f:
        payload = json.load(f)
except Exception as exc:
    sys.stderr.write(f"Error: invalid release feed JSON: {exc}\n")
    sys.exit(1)

if isinstance(payload, list):
    entries = payload
elif isinstance(payload, dict) and isinstance(payload.get("versions"), list):
    entries = payload["versions"]
else:
    sys.stderr.write("Error: unexpected release feed JSON structure.\n")
    sys.exit(1)

if not entries or not isinstance(entries[0], dict):
    sys.stderr.write("Error: release feed contains no release entries.\n")
    sys.exit(1)

latest = entries[0]
version = latest.get("version")
execution_id = latest.get("execution_id")

if (
    not isinstance(version, str)
    or not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', version)
    or ".." in version
    or not isinstance(execution_id, str)
    or not re.fullmatch(r'\d+', execution_id)
):
    sys.stderr.write("Error: invalid release metadata in feed.\n")
    sys.exit(1)

download_url = f"{base_url}/{version}-{execution_id}/{platform}/Antigravity.tar.gz"
print(version)
print(download_url)
PY
)" || return 1

    remote_ver="$(printf '%s\n' "$parsed_info" | sed -n '1p')"
    download_url="$(printf '%s\n' "$parsed_info" | sed -n '2p')"
    if [ -z "$remote_ver" ] || [ -z "$download_url" ]; then
        return 1
    fi

    validate_download_url "$download_url" || return 1
    printf '%s\n%s\n' "$remote_ver" "$download_url"
}

parse_download_html() {
    local html_file="$1"
    local platform="$2"
    local parsed_info remote_ver download_url

    parsed_info="$(python3 - "$html_file" "$platform" <<'PY'
from html.parser import HTMLParser
import re
import sys

html_path = sys.argv[1]
platform = sys.argv[2]

with open(html_path, "r", encoding="utf-8", errors="replace") as f:
    html_text = f.read()


class DownloadPageParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hub_links = {}
        self._in_latest_ver = False
        self._latest_ver_chunks = []

    def handle_starttag(self, tag, attrs):
        attr_map = dict(attrs)
        if tag == "a":
            hub_plat = attr_map.get("data-hub-platform")
            href = attr_map.get("href", "")
            if hub_plat and href.startswith("https://") and href.endswith(".tar.gz"):
                self.hub_links.setdefault(hub_plat, href)
        if "data-hub-latest-version" in attr_map:
            self._in_latest_ver = True
            self._latest_ver_chunks = []

    def handle_data(self, data):
        if self._in_latest_ver:
            self._latest_ver_chunks.append(data)

    def handle_endtag(self, tag):
        if self._in_latest_ver and tag in ("a", "span", "div", "p"):
            self._in_latest_ver = False

    @property
    def latest_version_text(self):
        return "".join(self._latest_ver_chunks).strip()


parser = DownloadPageParser()
parser.feed(html_text)
parser.close()

download_url = parser.hub_links.get(platform)
if not download_url:
    pattern = (
        r'https://[^\s"\'<>]+/antigravity-hub/[^/]+/'
        + re.escape(platform)
        + r'/Antigravity\.tar\.gz'
    )
    match = re.search(pattern, html_text)
    if match:
        download_url = match.group(0)

if not download_url:
    sys.stderr.write(
        f"Error: unable to find the Antigravity Hub download link for {platform}.\n"
    )
    sys.exit(1)

remote_version = ""
ver_match = re.search(
    r'/(\d+\.\d+\.\d+(?:-(?!\d+/)[^/]+?)?)(?:-\d+)?/' + re.escape(platform) + r'/',
    download_url,
)
if ver_match:
    remote_version = ver_match.group(1)
elif parser.latest_version_text:
    candidate = parser.latest_version_text.lstrip("vV").strip()
    ver_fallback = re.match(r'^(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)', candidate)
    if ver_fallback:
        remote_version = ver_fallback.group(1)

if not remote_version:
    sys.stderr.write(
        f"Error: unable to determine the remote version from {download_url}.\n"
    )
    sys.exit(1)

print(remote_version)
print(download_url)
PY
)" || return 1

    remote_ver="$(printf '%s\n' "$parsed_info" | sed -n '1p')"
    download_url="$(printf '%s\n' "$parsed_info" | sed -n '2p')"
    if [ -z "$remote_ver" ] || [ -z "$download_url" ]; then
        return 1
    fi

    validate_download_url "$download_url" || return 1
    printf '%s\n%s\n' "$remote_ver" "$download_url"
}

fetch_remote_release() {
    local platform="$1"
    local json_file="$TMP_DIR/releases.json"
    local html_file="$TMP_DIR/download.html"
    local result="" remote_ver="" download_url=""

    if download_file "$HUB_RELEASES_API_URL" "$json_file" "quiet" 2>/dev/null; then
        if result="$(parse_releases_json "$json_file" "$platform" 2>/dev/null)"; then
            remote_ver="$(printf '%s\n' "$result" | sed -n '1p')"
            download_url="$(printf '%s\n' "$result" | sed -n '2p')"
            if [ -n "$remote_ver" ] && [ -n "$download_url" ]; then
                printf '%s\n%s\n' "$remote_ver" "$download_url"
                return 0
            fi
        fi
    fi

    echo "Warning: release feed unavailable, falling back to $DOWNLOAD_PAGE_URL..." >&2
    download_file "$DOWNLOAD_PAGE_URL" "$html_file" "quiet"
    parse_download_html "$html_file" "$platform"
}

is_newer_version() {
    local local_ver="$1"
    local remote_ver="$2"

    if [ -z "$local_ver" ]; then
        return 0
    fi

    python3 - "$local_ver" "$remote_ver" <<'PY'
import re
import sys


def parse_semver(ver):
    s = ver.strip().lstrip("vV")
    s = s.split("+", 1)[0]
    if "-" in s:
        core_str, pre_str = s.split("-", 1)
    else:
        core_str, pre_str = s, None

    core_nums = [int(x) for x in re.findall(r'\d+', core_str)]
    if not core_nums:
        return None

    if pre_str == "" or pre_str is None:
        pre = None
    else:
        pre = []
        for part in pre_str.split("."):
            tokens = re.findall(r'\d+|[A-Za-z]+', part)
            segs = [
                (0, int(tok)) if tok.isdigit() else (1, tok.lower())
                for tok in tokens
            ]
            pre.append(segs)

    return core_nums, pre


local_parsed = parse_semver(sys.argv[1])
remote_parsed = parse_semver(sys.argv[2])

if remote_parsed is None:
    sys.exit(1)
if local_parsed is None:
    sys.exit(0)

local_core, local_pre = local_parsed
remote_core, remote_pre = remote_parsed

max_len = max(len(local_core), len(remote_core))
local_core += [0] * (max_len - len(local_core))
remote_core += [0] * (max_len - len(remote_core))

if remote_core != local_core:
    sys.exit(0 if remote_core > local_core else 1)

if local_pre is None and remote_pre is None:
    sys.exit(1)
if local_pre is not None and remote_pre is None:
    sys.exit(0)
if local_pre is None and remote_pre is not None:
    sys.exit(1)

sys.exit(0 if remote_pre > local_pre else 1)
PY
}

find_antigravity_pids() {
    [ -e "$DEST_DIR" ] || return 0

    local real_dest
    real_dest="$(readlink -f "$DEST_DIR" 2>/dev/null || true)"
    [ -n "$real_dest" ] || return 0

    local exe exe_target pid
    for exe in /proc/[0-9]*/exe; do
        exe_target="$(readlink "$exe" 2>/dev/null || true)"
        if [ "$exe_target" = "$real_dest/antigravity" ] || [ "$exe_target" = "$real_dest/antigravity (deleted)" ]; then
            pid="${exe#/proc/}"
            pid="${pid%/exe}"
            printf '%s\n' "$pid"
        fi
    done
}

find_antigravity_root_pids() {
    [ "$#" -gt 0 ] || return 0

    python3 - "$@" <<'PY'
import os
import sys

pids = [arg for arg in sys.argv[1:] if arg.isdigit() and os.path.isdir(f"/proc/{arg}")]
pid_set = set(pids)
ppid_cache = {}


def read_ppid(pid):
    if pid in ppid_cache:
        return ppid_cache[pid]
    ppid = None
    try:
        with open(f"/proc/{pid}/status", "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("PPid:"):
                    val = line.split(":", 1)[1].strip()
                    if val.isdigit():
                        ppid = val
                    break
    except OSError:
        ppid = None
    ppid_cache[pid] = ppid
    return ppid


def is_typed_child(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            args = f.read().split(b"\x00")
        return any(arg.startswith(b"--type=") for arg in args)
    except OSError:
        return False


def has_antigravity_ancestor(pid):
    seen = set()
    cur = read_ppid(pid)
    while cur and cur not in seen and int(cur) > 1:
        if cur in pid_set:
            return True
        seen.add(cur)
        cur = read_ppid(cur)
    return False


top_level = [p for p in pids if not has_antigravity_ancestor(p)]
primary = [p for p in top_level if not is_typed_child(p)]
for pid in primary or top_level or pids:
    print(pid)
PY
}

wait_for_antigravity_exit() {
    local max_checks="$1"
    local i remaining

    for ((i = 1; i <= max_checks; i++)); do
        remaining="$(find_antigravity_pids)"
        if [ -z "$remaining" ]; then
            return 0
        fi
        sleep 0.5
    done

    remaining="$(find_antigravity_pids)"
    [ -z "$remaining" ]
}

confirm_close_if_running() {
    if [ "$ASSUME_YES" -eq 1 ] || [ "$CLOSE_CONFIRMED" -eq 1 ]; then
        return 0
    fi

    local pids=()
    local pid
    while IFS= read -r pid; do
        [ -n "$pid" ] && pids+=("$pid")
    done < <(find_antigravity_pids)

    if [ "${#pids[@]}" -eq 0 ]; then
        return 0
    fi

    local proc_label="processes"
    if [ "${#pids[@]}" -eq 1 ]; then
        proc_label="process"
    fi

    if [ ! -t 0 ]; then
        echo "Error: Google Antigravity is currently running (${#pids[@]} $proc_label). Close it first or re-run with --yes (-y)." >&2
        exit 1
    fi

    local reply=""
    echo "Google Antigravity is currently running (${#pids[@]} $proc_label)."
    printf "Do you want to close it to continue the installation? [y/N] "
    if ! read -r reply; then
        echo ""
        echo "Operation cancelled."
        exit 0
    fi

    case "$reply" in
        y|Y|yes|YES|Yes)
            CLOSE_CONFIRMED=1
            return 0
            ;;
        *)
            echo "Operation cancelled."
            exit 0
            ;;
    esac
}

close_antigravity() {
    local pids=()
    local root_pids=()
    local remaining_pids=()
    local pid
    while IFS= read -r pid; do
        if [ -n "$pid" ]; then
            pids+=("$pid")
        fi
    done < <(find_antigravity_pids)

    if [ "${#pids[@]}" -eq 0 ]; then
        return 0
    fi

    local proc_label="processes"
    if [ "${#pids[@]}" -eq 1 ]; then
        proc_label="process"
    fi

    echo "Closing Antigravity (${#pids[@]} $proc_label)..."
    trap '' HUP

    while IFS= read -r pid; do
        if [ -n "$pid" ]; then
            root_pids+=("$pid")
        fi
    done < <(find_antigravity_root_pids "${pids[@]}")

    if [ "${#root_pids[@]}" -eq 0 ]; then
        root_pids=("${pids[@]}")
    fi

    kill -TERM "${root_pids[@]}" 2>/dev/null || true

    if wait_for_antigravity_exit 16; then
        return 0
    fi

    while IFS= read -r pid; do
        if [ -n "$pid" ]; then
            remaining_pids+=("$pid")
        fi
    done < <(find_antigravity_pids)

    if [ "${#remaining_pids[@]}" -eq 0 ]; then
        return 0
    fi

    kill -TERM "${remaining_pids[@]}" 2>/dev/null || true

    if wait_for_antigravity_exit 6; then
        return 0
    fi

    echo "Warning: some Antigravity processes are still running; continuing installation." >&2
}

detect_strip_components() {
    local archive_path="$1"
    python3 - "$archive_path" <<'PY'
import subprocess
import sys

archive_path = sys.argv[1]
proc = subprocess.run(["tar", "-tzf", archive_path], capture_output=True, text=True)
if proc.returncode != 0:
    if proc.stderr:
        sys.stderr.write(proc.stderr)
    sys.exit(proc.returncode)

entries = []
for raw in proc.stdout.splitlines():
    line = raw.rstrip("\r\n")
    if not line:
        continue
    if line.startswith("/") or ".." in line.split("/"):
        sys.stderr.write(f"Error: archive contains unsafe path: {line}\n")
        sys.exit(1)
    if line in (".", "./"):
        continue
    entries.append(line)

if not entries:
    sys.stderr.write("Error: archive is empty.\n")
    sys.exit(1)

if all(e.startswith("./") and len(e) > 2 for e in entries):
    trimmed = [e[2:] for e in entries]
    prefix_strip = 1
else:
    trimmed = entries
    prefix_strip = 0

first_components = {e.split("/", 1)[0] for e in trimmed if e}
has_nested = any("/" in e.rstrip("/") for e in trimmed)

if len(first_components) == 1 and has_nested:
    print(prefix_strip + 1)
else:
    print(prefix_strip)
PY
}

install_archive() {
    local archive_path="$1"
    local parent_dir strip_count

    validate_existing_dest_dir

    parent_dir="$(dirname "$DEST_DIR")"
    mkdir -p "$parent_dir"

    STAGE_DIR="$(mktemp -d "$parent_dir/.antigravity-staging.XXXXXX")"

    echo "Extracting archive..."
    strip_count="$(detect_strip_components "$archive_path")"
    if [ "$strip_count" -gt 0 ]; then
        tar --no-same-owner -xzf "$archive_path" -C "$STAGE_DIR" --strip-components="$strip_count"
    else
        tar --no-same-owner -xzf "$archive_path" -C "$STAGE_DIR"
    fi

    if [ ! -f "$STAGE_DIR/antigravity" ]; then
        echo "Error: extracted archive does not contain the 'antigravity' binary." >&2
        exit 1
    fi
    [ -x "$STAGE_DIR/antigravity" ] || chmod 755 "$STAGE_DIR/antigravity"

    chmod 755 "$STAGE_DIR"

    confirm_close_if_running
    close_antigravity

    if [ -e "$DEST_DIR" ]; then
        BACKUP_CONTAINER="$(mktemp -d "$parent_dir/.antigravity-backup.XXXXXX")"
        BACKUP_DIR="$BACKUP_CONTAINER/previous"
        mv "$DEST_DIR" "$BACKUP_DIR"
    fi

    if ! mv "$STAGE_DIR" "$DEST_DIR"; then
        echo "Error: unable to install the new version into $DEST_DIR." >&2
        if [ -n "$BACKUP_DIR" ] && [ -e "$BACKUP_DIR" ] && [ ! -e "$DEST_DIR" ]; then
            mv "$BACKUP_DIR" "$DEST_DIR" || true
        fi
        exit 1
    fi
    STAGE_DIR=""

    if [ -n "$BACKUP_CONTAINER" ] && [ -d "$BACKUP_CONTAINER" ]; then
        rm -rf "$BACKUP_CONTAINER"
    fi
    BACKUP_CONTAINER=""
    BACKUP_DIR=""
}

print_completion_message() {
    local previous_ver="$1"
    local new_ver="$2"
    local desktop_enabled="$3"

    if [ -z "$previous_ver" ]; then
        if [ -n "$new_ver" ]; then
            echo "Installation completed successfully (version $new_ver)!"
        else
            echo "Installation completed successfully!"
        fi
        if [ "$desktop_enabled" -eq 1 ]; then
            echo "You can now launch Google Antigravity from your application menu or with the 'antigravity' command."
        fi
    else
        if [ -n "$new_ver" ]; then
            echo "Update completed successfully ($previous_ver -> $new_ver)!"
        else
            echo "Update completed successfully!"
        fi
    fi
}

install_self() {
    local src_raw="${BASH_SOURCE[0]:-}"
    if [ -z "$src_raw" ] || [ ! -f "$src_raw" ]; then
        echo "Error: unable to locate the source script file (run the script from a local file)." >&2
        exit 1
    fi

    local src_real target target_real
    src_real="$(readlink -f "$src_raw")"
    target="$BIN_DIR/ag-setup"

    mkdir -p "$BIN_DIR"

    if [ -e "$target" ] && [ ! -L "$target" ]; then
        target_real="$(readlink -f "$target" 2>/dev/null || true)"
        if [ -n "$target_real" ] && [ "$src_real" = "$target_real" ]; then
            echo "The script is already running from '$target' (no copy needed)."
            return 0
        fi
    fi

    TMP_SELF_TARGET="$(mktemp "$BIN_DIR/.ag-setup.XXXXXX")"
    if ! cp "$src_real" "$TMP_SELF_TARGET" || ! chmod 755 "$TMP_SELF_TARGET" || ! mv -f "$TMP_SELF_TARGET" "$target"; then
        rm -f "$TMP_SELF_TARGET"
        TMP_SELF_TARGET=""
        echo "Error: unable to install the script to '$target'." >&2
        exit 1
    fi
    TMP_SELF_TARGET=""

    echo "Script successfully installed to '$target'."
    warn_if_not_in_path "ag-setup"
}

main() {
    local check_only=0
    local force_install=0
    local setup_desktop=1
    local install_self_mode=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -c|--check)
                check_only=1
                ;;
            -f|--force)
                force_install=1
                ;;
            -y|--yes)
                ASSUME_YES=1
                ;;
            --no-desktop)
                setup_desktop=0
                ;;
            --install-self)
                install_self_mode=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Error: unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                echo "Error: unexpected argument: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
        shift
    done

    check_os
    check_not_root

    if [ "$install_self_mode" -eq 1 ]; then
        if [ "$check_only" -eq 1 ] || [ "$force_install" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ] || [ "$setup_desktop" -eq 0 ]; then
            echo "Error: the --install-self option must be used by itself." >&2
            exit 1
        fi
        validate_safe_dir_var "BIN_DIR" "$BIN_DIR"
        install_self
        exit 0
    fi

    validate_dest_dir
    if [ "$check_only" -eq 0 ] && [ "$setup_desktop" -eq 1 ]; then
        validate_safe_dir_var "BIN_DIR" "$BIN_DIR"
        validate_safe_dir_var "DESKTOP_DIR" "$DESKTOP_DIR"
        validate_safe_dir_var "ICON_DIR" "$ICON_DIR"
    fi

    check_dependencies

    local platform local_ver tmp_base remote_info remote_ver download_url archive_file new_ver
    platform="$(detect_platform)"
    local_ver="$(get_local_version "$DEST_DIR")"

    tmp_base="$(normalize_dir_path "${TMPDIR:-/tmp}")"
    [ -z "$tmp_base" ] && tmp_base="/tmp"
    TMP_DIR="$(mktemp -d "$tmp_base/antigravity-update.XXXXXX")"

    echo "Checking for the latest version of Google Antigravity ($platform)..."
    remote_info="$(fetch_remote_release "$platform")"
    remote_ver="$(printf '%s\n' "$remote_info" | sed -n '1p')"
    download_url="$(printf '%s\n' "$remote_info" | sed -n '2p')"

    echo "Installed version: ${local_ver:-not installed}"
    echo "Latest version:    $remote_ver"

    if [ "$check_only" -eq 1 ]; then
        if is_newer_version "$local_ver" "$remote_ver"; then
            if [ -z "$local_ver" ]; then
                echo "Google Antigravity is not installed yet. Available version: $remote_ver"
            else
                echo "A new version is available: $remote_ver"
            fi
            echo "Link: $download_url"
        else
            echo "Google Antigravity is already up to date ($local_ver)."
        fi
        exit 0
    fi

    if [ "$force_install" -eq 0 ] && ! is_newer_version "$local_ver" "$remote_ver"; then
        if [ "$setup_desktop" -eq 1 ] && ! desktop_integration_complete; then
            echo "Google Antigravity is already up to date ($local_ver). Setting up desktop integration..."
            setup_desktop_integration
            echo "Desktop integration configured successfully!"
        else
            echo "Google Antigravity is already up to date ($local_ver)."
        fi
        exit 0
    fi

    validate_existing_dest_dir
    confirm_close_if_running

    archive_file="$TMP_DIR/Antigravity.tar.gz"
    echo "Downloading Google Antigravity $remote_ver..."
    download_file "$download_url" "$archive_file" "progress"

    install_archive "$archive_file"
    if [ "$setup_desktop" -eq 1 ]; then
        setup_desktop_integration
    fi

    new_ver="$(get_local_version "$DEST_DIR")"
    print_completion_message "$local_ver" "$new_ver" "$setup_desktop"
}

main "$@"
