#!/usr/bin/env bash
set -euo pipefail

DOWNLOAD_PAGE_URL="https://antigravity.google/download"
DEST_DIR="${DEST_DIR:-$HOME/.local/share/antigravity}"

TMP_DIR=""
STAGE_DIR=""

cleanup() {
    if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
        rm -rf "$STAGE_DIR"
    fi
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

usage() {
    cat <<'EOF'
Usage: update-antigravity.sh [OPTIONS] [chemin_vers_archive.tar.gz]

Met à jour Google Antigravity (Hub) dans "$HOME/.local/share/antigravity"
(ou dans le dossier défini par la variable d'environnement DEST_DIR).

Sans argument :
  Vérifie la dernière version disponible sur https://antigravity.google/download,
  la télécharge si elle est plus récente que la version installée, l'installe,
  puis supprime l'archive téléchargée.

Options :
  -c, --check   Vérifie uniquement si une mise à jour est disponible (sans télécharger ni installer)
  -f, --force   Force le téléchargement et la réinstallation même si la version est déjà à jour
  -h, --help    Affiche cette aide et quitte

Compatibilité :
  <chemin_vers_archive.tar.gz>  Installe l'archive locale fournie puis la supprime
EOF
}

check_dependencies() {
    local mode="$1"
    local missing=()
    local cmd

    for cmd in tar python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ "$mode" != "local" ] && ! command -v curl >/dev/null 2>&1; then
        missing+=("curl")
    fi

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Erreur : outil(s) manquant(s) : ${missing[*]}" >&2
        exit 1
    fi
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
            echo "Erreur : architecture non prise en charge : $arch" >&2
            exit 1
            ;;
    esac
}

get_local_version() {
    local dir="${1:-$DEST_DIR}"
    [ -d "$dir" ] || return 0

    python3 - "$dir" <<'PY'
import json
import os
import struct
import sys

install_dir = sys.argv[1]
asar_path = os.path.join(install_dir, "resources", "app.asar")
unpacked_pkg = os.path.join(install_dir, "resources", "app.asar.unpacked", "package.json")
plain_pkg = os.path.join(install_dir, "resources", "app", "package.json")

try:
    if os.path.isfile(asar_path):
        with open(asar_path, "rb") as f:
            f.seek(4)
            header_pickle_size = struct.unpack("<I", f.read(4))[0]
            f.seek(12)
            json_len = struct.unpack("<I", f.read(4))[0]
            header = json.loads(f.read(json_len).decode("utf-8"))
            base = 8 + header_pickle_size

            info = header.get("files", {}).get("package.json")
            if isinstance(info, dict):
                if info.get("unpacked"):
                    if os.path.isfile(unpacked_pkg):
                        with open(unpacked_pkg, "r", encoding="utf-8") as pf:
                            pkg = json.load(pf)
                            ver = pkg.get("version", "")
                            if isinstance(ver, str) and ver:
                                print(ver)
                elif "offset" in info and "size" in info:
                    f.seek(base + int(info["offset"]))
                    pkg = json.loads(f.read(int(info["size"])).decode("utf-8"))
                    ver = pkg.get("version", "")
                    if isinstance(ver, str) and ver:
                        print(ver)
    elif os.path.isfile(plain_pkg):
        with open(plain_pkg, "r", encoding="utf-8") as pf:
            pkg = json.load(pf)
            ver = pkg.get("version", "")
            if isinstance(ver, str) and ver:
                print(ver)
except Exception:
    pass
PY
}

fetch_remote_release() {
    local platform="$1"
    local html_file="$TMP_DIR/download.html"

    curl -fsSL --proto '=https' --proto-redir '=https' --compressed \
        -o "$html_file" "$DOWNLOAD_PAGE_URL"

    python3 - "$html_file" "$platform" <<'PY'
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
        f"Erreur : impossible de trouver le lien Antigravity Hub pour {platform}.\n"
    )
    sys.exit(1)

remote_version = ""
ver_match = re.search(
    r'/(\d+\.\d+\.\d+)(?:-[^/]+)?/' + re.escape(platform) + r'/',
    download_url,
)
if ver_match:
    remote_version = ver_match.group(1)
elif parser.latest_version_text:
    candidate = parser.latest_version_text.lstrip("vV").strip()
    if re.match(r'^\d+\.\d+\.\d+', candidate):
        remote_version = candidate

if not remote_version:
    sys.stderr.write(
        f"Erreur : impossible de déterminer la version distante depuis {download_url}.\n"
    )
    sys.exit(1)

print(remote_version)
print(download_url)
PY
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

local_ver = sys.argv[1]
remote_ver = sys.argv[2]

local_parts = tuple(int(x) for x in re.findall(r'\d+', local_ver))
remote_parts = tuple(int(x) for x in re.findall(r'\d+', remote_ver))

if not remote_parts:
    sys.exit(1)
if not local_parts:
    sys.exit(0)

sys.exit(0 if remote_parts > local_parts else 1)
PY
}

close_antigravity() {
    [ -e "$DEST_DIR" ] || return 0

    local real_dest
    real_dest="$(readlink -f "$DEST_DIR" 2>/dev/null || true)"
    [ -n "$real_dest" ] || return 0

    local pids=()
    local exe exe_target pid
    for exe in /proc/[0-9]*/exe; do
        exe_target="$(readlink "$exe" 2>/dev/null || true)"
        if [ "$exe_target" = "$real_dest/antigravity" ] || [ "$exe_target" = "$real_dest/antigravity (deleted)" ]; then
            pid="${exe#/proc/}"
            pid="${pid%/exe}"
            pids+=("$pid")
        fi
    done

    if [ "${#pids[@]}" -eq 0 ]; then
        return 0
    fi

    echo "Fermeture d'Antigravity (${#pids[@]} processus)..."
    trap '' HUP
    kill -TERM "${pids[@]}" 2>/dev/null || true

    local i alive
    for i in $(seq 1 10); do
        alive=0
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                alive=1
                break
            fi
        done
        if [ "$alive" -eq 0 ]; then
            return 0
        fi
        sleep 0.5
    done

    echo "Avertissement : certains processus Antigravity sont encore actifs, poursuite de l'installation." >&2
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
    if not line or line in (".", "./"):
        continue
    entries.append(line)

if not entries:
    sys.stderr.write("Erreur : l'archive est vide.\n")
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
    local parent_dir backup_dir strip_count

    parent_dir="$(dirname "$DEST_DIR")"
    mkdir -p "$parent_dir"

    STAGE_DIR="$(mktemp -d "$parent_dir/.antigravity-staging.XXXXXX")"

    echo "Extraction de la mise à jour..."
    strip_count="$(detect_strip_components "$archive_path")"
    if [ "$strip_count" -gt 0 ]; then
        tar -xzf "$archive_path" -C "$STAGE_DIR" --strip-components="$strip_count"
    else
        tar -xzf "$archive_path" -C "$STAGE_DIR"
    fi

    if [ ! -f "$STAGE_DIR/antigravity" ]; then
        echo "Erreur : l'archive extraite ne contient pas le binaire 'antigravity'." >&2
        exit 1
    fi

    chmod 755 "$STAGE_DIR"

    close_antigravity

    backup_dir="$parent_dir/.antigravity-backup.$$"
    if [ -e "$backup_dir" ]; then
        rm -rf "$backup_dir"
    fi

    if [ -e "$DEST_DIR" ]; then
        mv "$DEST_DIR" "$backup_dir"
    fi

    if ! mv "$STAGE_DIR" "$DEST_DIR"; then
        echo "Erreur : impossible d'installer la nouvelle version dans $DEST_DIR." >&2
        if [ -e "$backup_dir" ] && [ ! -e "$DEST_DIR" ]; then
            mv "$backup_dir" "$DEST_DIR" || true
        fi
        exit 1
    fi
    STAGE_DIR=""

    if [ -e "$backup_dir" ]; then
        rm -rf "$backup_dir"
    fi

    echo "Suppression du fichier téléchargé..."
    rm -f "$archive_path"
}

main() {
    local check_only=0
    local force_install=0
    local local_archive=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -c|--check)
                check_only=1
                ;;
            -f|--force)
                force_install=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Erreur : option inconnue : $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                if [ -n "$local_archive" ]; then
                    echo "Erreur : un seul fichier archive peut être spécifié." >&2
                    usage >&2
                    exit 1
                fi
                local_archive="$1"
                ;;
        esac
        shift
    done

    if [ -n "$local_archive" ] && [ "$check_only" -eq 1 ]; then
        echo "Erreur : l'option --check est incompatible avec une archive locale." >&2
        exit 1
    fi

    if [ -n "$local_archive" ]; then
        check_dependencies "local"
        if [ ! -f "$local_archive" ]; then
            echo "Erreur : fichier introuvable : $local_archive" >&2
            exit 1
        fi
        local local_ver new_ver
        local_ver="$(get_local_version "$DEST_DIR")"
        echo "Version installée : ${local_ver:-non installée}"
        install_archive "$local_archive"
        new_ver="$(get_local_version "$DEST_DIR")"
        if [ -n "$local_ver" ] && [ -n "$new_ver" ]; then
            echo "Mise à jour terminée avec succès ($local_ver -> $new_ver) !"
        elif [ -n "$new_ver" ]; then
            echo "Mise à jour terminée avec succès (version $new_ver) !"
        else
            echo "Mise à jour terminée avec succès !"
        fi
        exit 0
    fi

    check_dependencies "remote"

    local platform local_ver remote_info remote_ver download_url archive_file new_ver
    platform="$(detect_platform)"
    local_ver="$(get_local_version "$DEST_DIR")"

    TMP_DIR="$(mktemp -d -t antigravity-update.XXXXXX)"

    echo "Vérification de la dernière version de Google Antigravity ($platform)..."
    remote_info="$(fetch_remote_release "$platform")"
    remote_ver="$(printf '%s\n' "$remote_info" | sed -n '1p')"
    download_url="$(printf '%s\n' "$remote_info" | sed -n '2p')"

    echo "Version installée : ${local_ver:-non installée}"
    echo "Dernière version  : $remote_ver"

    if [ "$check_only" -eq 1 ]; then
        if is_newer_version "$local_ver" "$remote_ver"; then
            echo "Une nouvelle version est disponible : $remote_ver"
            echo "Lien : $download_url"
        else
            echo "Google Antigravity est déjà à jour ($local_ver)."
        fi
        exit 0
    fi

    if [ "$force_install" -eq 0 ] && ! is_newer_version "$local_ver" "$remote_ver"; then
        echo "Google Antigravity est déjà à jour ($local_ver)."
        exit 0
    fi

    archive_file="$TMP_DIR/Antigravity.tar.gz"
    echo "Téléchargement de Google Antigravity $remote_ver..."
    curl -fL --progress-bar --proto '=https' --proto-redir '=https' \
        -o "$archive_file" "$download_url"

    install_archive "$archive_file"

    new_ver="$(get_local_version "$DEST_DIR")"
    if [ -n "$local_ver" ] && [ -n "$new_ver" ]; then
        echo "Mise à jour terminée avec succès ($local_ver -> $new_ver) !"
    elif [ -n "$new_ver" ]; then
        echo "Mise à jour terminée avec succès (version $new_ver) !"
    else
        echo "Mise à jour terminée avec succès !"
    fi
}

main "$@"
