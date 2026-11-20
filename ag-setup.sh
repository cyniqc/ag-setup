#!/usr/bin/env bash
set -euo pipefail

DOWNLOAD_PAGE_URL="https://antigravity.google/download"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST_DIR="${DEST_DIR:-$XDG_DATA_HOME/antigravity}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
DESKTOP_DIR="${DESKTOP_DIR:-$XDG_DATA_HOME/applications}"
ICON_DIR="${ICON_DIR:-$XDG_DATA_HOME/icons/hicolor/512x512/apps}"
DOWNLOADER="${DOWNLOADER:-auto}"

[ "$XDG_DATA_HOME" != "/" ] && XDG_DATA_HOME="${XDG_DATA_HOME%/}"
[ "$DEST_DIR" != "/" ] && DEST_DIR="${DEST_DIR%/}"
[ "$BIN_DIR" != "/" ] && BIN_DIR="${BIN_DIR%/}"
[ "$DESKTOP_DIR" != "/" ] && DESKTOP_DIR="${DESKTOP_DIR%/}"
[ "$ICON_DIR" != "/" ] && ICON_DIR="${ICON_DIR%/}"

TMP_DIR=""
STAGE_DIR=""
SELECTED_DOWNLOADER=""
ASSUME_YES=0
CLOSE_CONFIRMED=0

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
Usage: ag-setup.sh [OPTIONS] [chemin_vers_archive.tar.gz]

Installe ou met à jour Google Antigravity (Hub) dans "$HOME/.local/share/antigravity"
(ou dans le dossier défini par la variable d'environnement DEST_DIR) et configure
l'intégration bureau (lanceur .desktop, icône et commande 'antigravity').

Sans argument :
  Vérifie la dernière version disponible sur https://antigravity.google/download,
  la télécharge si Antigravity n'est pas installé ou si une mise à jour existe,
  l'installe (avec raccourci bureau et icône), puis supprime l'archive téléchargée.

Options :
  -c, --check         Vérifie uniquement si une mise à jour est disponible (lecture seule)
  -f, --force         Force le téléchargement et la réinstallation même si déjà à jour
  -y, --yes           Ferme Antigravity automatiquement sans demander confirmation
      --no-desktop    Ne crée ni le lanceur .desktop, ni l'icône, ni le lien dans BIN_DIR
      --install-self  Copie ce script dans "$BIN_DIR/ag-setup" pour l'utiliser de partout
  -h, --help          Affiche cette aide et quitte

Compatibilité :
  <chemin_vers_archive.tar.gz>  Installe l'archive locale fournie puis la supprime

Variables d'environnement optionnelles :
  DEST_DIR     Dossier d'installation (défaut : $XDG_DATA_HOME/antigravity)
  BIN_DIR      Dossier de destination pour 'antigravity' et --install-self (défaut : $HOME/.local/bin)
  DESKTOP_DIR  Dossier du fichier .desktop (défaut : $XDG_DATA_HOME/applications)
  ICON_DIR     Dossier de l'icône PNG (défaut : $XDG_DATA_HOME/icons/hicolor/512x512/apps)
  DOWNLOADER   Outil de téléchargement : auto, curl ou wget (défaut : auto)
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
                echo "Erreur : 'curl' ou 'wget' est requis pour le téléchargement." >&2
                exit 1
            fi
            ;;
        curl)
            if command -v curl >/dev/null 2>&1; then
                printf 'curl\n'
            else
                echo "Erreur : outil manquant : curl" >&2
                exit 1
            fi
            ;;
        wget)
            if command -v wget >/dev/null 2>&1; then
                printf 'wget\n'
            else
                echo "Erreur : outil manquant : wget" >&2
                exit 1
            fi
            ;;
        *)
            echo "Erreur : valeur DOWNLOADER invalide '$DOWNLOADER' (attendu : auto, curl ou wget)." >&2
            exit 1
            ;;
    esac
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

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Erreur : outil(s) manquant(s) : ${missing[*]}" >&2
        exit 1
    fi

    if [ "$mode" != "local" ]; then
        SELECTED_DOWNLOADER="$(detect_downloader)"
    fi
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
            echo "Erreur : téléchargeur inconnu : $tool" >&2
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

extract_app_icon() {
    local install_dir="$1"
    local target_png="$2"
    [ -d "$install_dir" ] || return 1

    python3 - "$install_dir" "$target_png" <<'PY'
import json
import os
import struct
import sys

install_dir = sys.argv[1]
target_png = sys.argv[2]
asar_path = os.path.join(install_dir, "resources", "app.asar")
unpacked_icon = os.path.join(install_dir, "resources", "app.asar.unpacked", "icon.png")
plain_icon = os.path.join(install_dir, "resources", "app", "icon.png")
png_magic = b"\x89PNG\r\n\x1a\n"

icon_data = None
try:
    if os.path.isfile(asar_path):
        with open(asar_path, "rb") as f:
            f.seek(4)
            header_pickle_size = struct.unpack("<I", f.read(4))[0]
            f.seek(12)
            json_len = struct.unpack("<I", f.read(4))[0]
            header = json.loads(f.read(json_len).decode("utf-8"))
            base = 8 + header_pickle_size

            info = header.get("files", {}).get("icon.png")
            if isinstance(info, dict):
                if info.get("unpacked"):
                    if os.path.isfile(unpacked_icon):
                        with open(unpacked_icon, "rb") as icf:
                            icon_data = icf.read()
                elif "offset" in info and "size" in info:
                    f.seek(base + int(info["offset"]))
                    icon_data = f.read(int(info["size"]))
    elif os.path.isfile(plain_icon):
        with open(plain_icon, "rb") as icf:
            icon_data = icf.read()

    if not icon_data or not icon_data.startswith(png_magic):
        sys.exit(1)

    os.makedirs(os.path.dirname(target_png), exist_ok=True)
    with open(target_png, "wb") as out:
        out.write(icon_data)
except Exception:
    sys.exit(1)
PY
}

setup_desktop_integration() {
    mkdir -p "$BIN_DIR"
    if [ ! -e "$BIN_DIR/antigravity" ] || [ -L "$BIN_DIR/antigravity" ]; then
        ln -sfn "$DEST_DIR/antigravity" "$BIN_DIR/antigravity"
    else
        echo "Avertissement : '$BIN_DIR/antigravity' existe déjà et n'est pas un lien symbolique, il n'a pas été remplacé." >&2
    fi

    local icon_target="$ICON_DIR/antigravity.png"
    local icon_value="applications-development"
    if extract_app_icon "$DEST_DIR" "$icon_target"; then
        chmod 644 "$icon_target"
        icon_value="$icon_target"
        if command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache -f -t "$XDG_DATA_HOME/icons/hicolor" >/dev/null 2>&1 || true
        fi
    fi

    mkdir -p "$DESKTOP_DIR"
    local desktop_file="$DESKTOP_DIR/antigravity.desktop"
    local exec_cmd
    case "$DEST_DIR" in
        *" "*)
            exec_cmd="\"$DEST_DIR/antigravity\" %U"
            ;;
        *)
            exec_cmd="$DEST_DIR/antigravity %U"
            ;;
    esac

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
            echo "Info : ajoute '$BIN_DIR' à ton PATH si la commande '$cmd_name' n'est pas reconnue."
            ;;
    esac
}

desktop_integration_complete() {
    [ -f "$DESKTOP_DIR/antigravity.desktop" ] \
        && [ -e "$BIN_DIR/antigravity" ] \
        && [ -f "$ICON_DIR/antigravity.png" ]
}

fetch_remote_release() {
    local platform="$1"
    local html_file="$TMP_DIR/download.html"

    download_file "$DOWNLOAD_PAGE_URL" "$html_file" "quiet"

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

    if [ ! -t 0 ]; then
        echo "Erreur : Google Antigravity est en cours d'exécution (${#pids[@]} processus). Ferme-le d'abord ou relance avec --yes (-y)." >&2
        exit 1
    fi

    local reply=""
    echo "Google Antigravity est en cours d'exécution (${#pids[@]} processus)."
    printf "Veux-tu le fermer pour poursuivre l'installation ? [o/N] "
    if ! read -r reply; then
        echo ""
        echo "Opération annulée."
        exit 0
    fi

    case "$reply" in
        o|O|oui|OUI|Oui|y|Y|yes|YES|Yes)
            CLOSE_CONFIRMED=1
            return 0
            ;;
        *)
            echo "Opération annulée."
            exit 0
            ;;
    esac
}

close_antigravity() {
    local pids=()
    local pid
    while IFS= read -r pid; do
        [ -n "$pid" ] && pids+=("$pid")
    done < <(find_antigravity_pids)

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

    echo "Extraction de l'archive..."
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

    confirm_close_if_running
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

print_completion_message() {
    local previous_ver="$1"
    local new_ver="$2"
    local desktop_enabled="$3"

    if [ -z "$previous_ver" ]; then
        if [ -n "$new_ver" ]; then
            echo "Installation terminée avec succès (version $new_ver) !"
        else
            echo "Installation terminée avec succès !"
        fi
        if [ "$desktop_enabled" -eq 1 ]; then
            echo "Tu peux maintenant lancer Google Antigravity depuis le menu d'applications ou avec la commande 'antigravity'."
        fi
    else
        if [ -n "$new_ver" ]; then
            echo "Mise à jour terminée avec succès ($previous_ver -> $new_ver) !"
        else
            echo "Mise à jour terminée avec succès !"
        fi
    fi
}

install_self() {
    local src_raw="${BASH_SOURCE[0]:-}"
    if [ -z "$src_raw" ] || [ ! -f "$src_raw" ]; then
        echo "Erreur : impossible de localiser le fichier du script source (exécute le script depuis un fichier local)." >&2
        exit 1
    fi

    local src_real target target_real tmp_target
    src_real="$(readlink -f "$src_raw")"
    target="$BIN_DIR/ag-setup"

    mkdir -p "$BIN_DIR"

    if [ -e "$target" ] && [ ! -L "$target" ]; then
        target_real="$(readlink -f "$target" 2>/dev/null || true)"
        if [ -n "$target_real" ] && [ "$src_real" = "$target_real" ]; then
            echo "Le script est déjà exécuté depuis '$target' (aucune copie nécessaire)."
            return 0
        fi
    fi

    tmp_target="$(mktemp "$BIN_DIR/.ag-setup.XXXXXX")"
    if ! cp "$src_real" "$tmp_target" || ! chmod 755 "$tmp_target" || ! mv -f "$tmp_target" "$target"; then
        rm -f "$tmp_target"
        echo "Erreur : impossible d'installer le script dans '$target'." >&2
        exit 1
    fi

    echo "Script installé avec succès dans '$target'."
    warn_if_not_in_path "ag-setup"
}

main() {
    local check_only=0
    local force_install=0
    local setup_desktop=1
    local install_self_mode=0
    local local_archive=""

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

    if [ "$install_self_mode" -eq 1 ]; then
        if [ "$check_only" -eq 1 ] || [ "$force_install" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ] || [ "$setup_desktop" -eq 0 ] || [ -n "$local_archive" ]; then
            echo "Erreur : l'option --install-self doit être utilisée seule." >&2
            exit 1
        fi
        install_self
        exit 0
    fi

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
        confirm_close_if_running
        install_archive "$local_archive"
        if [ "$setup_desktop" -eq 1 ]; then
            setup_desktop_integration
        fi
        new_ver="$(get_local_version "$DEST_DIR")"
        print_completion_message "$local_ver" "$new_ver" "$setup_desktop"
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
            if [ -z "$local_ver" ]; then
                echo "Google Antigravity n'est pas encore installé. Version disponible : $remote_ver"
            else
                echo "Une nouvelle version est disponible : $remote_ver"
            fi
            echo "Lien : $download_url"
        else
            echo "Google Antigravity est déjà à jour ($local_ver)."
        fi
        exit 0
    fi

    if [ "$force_install" -eq 0 ] && ! is_newer_version "$local_ver" "$remote_ver"; then
        if [ "$setup_desktop" -eq 1 ] && ! desktop_integration_complete; then
            echo "Google Antigravity est déjà à jour ($local_ver). Configuration de l'intégration bureau..."
            setup_desktop_integration
            echo "Intégration bureau configurée avec succès !"
        else
            echo "Google Antigravity est déjà à jour ($local_ver)."
        fi
        exit 0
    fi

    confirm_close_if_running

    archive_file="$TMP_DIR/Antigravity.tar.gz"
    echo "Téléchargement de Google Antigravity $remote_ver..."
    download_file "$download_url" "$archive_file" "progress"

    install_archive "$archive_file"
    if [ "$setup_desktop" -eq 1 ]; then
        setup_desktop_integration
    fi

    new_ver="$(get_local_version "$DEST_DIR")"
    print_completion_message "$local_ver" "$new_ver" "$setup_desktop"
}

main "$@"
