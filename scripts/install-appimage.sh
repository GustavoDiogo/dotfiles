#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-appimage.sh [options] <file.AppImage | directory>

Options:
  -n NAME         Menu/display name (required; if omitted, you’ll be prompted)
  -i ICON         Path to .png/.svg icon (optional; empty Enter ignores)
  -c CATEGORIES   Desktop categories, e.g. "Utility;Development;" (optional; empty Enter ignores)
  -h              Help

Examples:
  ./install-appimage.sh ~/Downloads/MyApp-1.0-x86_64.AppImage
  ./install-appimage.sh -n "My App" -i ~/icon.png -c "Utility;" ~/Downloads/
EOF
}

NAME=""
ICON_PATH=""
CATEGORIES=""

while getopts ":n:i:c:h" opt; do
  case "$opt" in
    n) NAME="$OPTARG" ;;
    i) ICON_PATH="$OPTARG" ;;
    c) CATEGORIES="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 2 ;;
    :) echo "Option -$OPTARG requires a value" >&2; usage; exit 2 ;;
  esac
done
shift $((OPTIND -1))

[[ $# -lt 1 ]] && { usage; exit 2; }
INPUT="$1"

# Locate AppImage
find_appimage_in_dir() {
  local dir="$1"
  find "$dir" -type f -iname "*.AppImage" -printf "%s\t%p\n" \
    | sort -nr | awk -F'\t' 'NR==1{print $2}'
}

if [[ -d "$INPUT" ]]; then
  APPIMAGE_PATH="$(find_appimage_in_dir "$INPUT" || true)"
  [[ -z "${APPIMAGE_PATH:-}" ]] && { echo "No .AppImage found in: $INPUT"; exit 1; }
else
  APPIMAGE_PATH="$INPUT"
fi

[[ -f "$APPIMAGE_PATH" ]] || { echo "File not found: $APPIMAGE_PATH"; exit 1; }

BASENAME="$(basename "$APPIMAGE_PATH")"
SUGGESTED_NAME="$(echo "${BASENAME%.*}" \
  | sed -E 's/-?[0-9][0-9\.]*.*$//; s/_/ /g; s/-/ /g; s/ +/ /g; s/^ *| *$//g')"
[[ -z "$SUGGESTED_NAME" ]] && SUGGESTED_NAME="AppImageApp"

# Prompts if missing
if [[ -z "$NAME" ]]; then
  read -r -p "App name (required) [Suggested: $SUGGESTED_NAME]: " NAME
  if [[ -z "$NAME" ]]; then
    NAME="$SUGGESTED_NAME"
    echo "Using suggested name: $NAME"
  fi
  while [[ -z "$NAME" ]]; do
    read -r -p "Name cannot be empty. Enter the app name: " NAME
  done
fi

if [[ -z "$ICON_PATH" ]]; then
  read -r -p "Icon path (.png/.svg) [Enter to skip]: " ICON_PATH || true
fi
if [[ -n "$ICON_PATH" && ! -f "$ICON_PATH" ]]; then
  echo "Warning: icon '$ICON_PATH' not found. Icon will be skipped."
  ICON_PATH=""
fi

if [[ -z "$CATEGORIES" ]]; then
  read -r -p "Desktop categories (e.g., Utility;Development;) [Enter to skip]: " CATEGORIES || true
fi

# Paths
INSTALL_DIR="$HOME/.local/opt"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
ICONS_ROOT="$HOME/.local/share/icons/hicolor"

APP_ID="$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | sed 's/^$/appimageapp/')"
APP_DIR="$INSTALL_DIR/$APP_ID"
DESKTOP_FILE="$APPS_DIR/$APP_ID.desktop"

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APPS_DIR" "$APP_DIR"

# Copy AppImage
TARGET_APP="$APP_DIR/$(basename "$APPIMAGE_PATH")"
cp -f "$APPIMAGE_PATH" "$TARGET_APP"
chmod +x "$TARGET_APP"

# Symlink in ~/.local/bin
LINK_NAME="$BIN_DIR/$APP_ID"
ln -sf "$TARGET_APP" "$LINK_NAME"

# Install icon (if provided)
ICON_KEY=""
if [[ -n "$ICON_PATH" ]]; then
  ext="${ICON_PATH##*.}"
  size_dir="512x512"
  dest_dir="$ICONS_ROOT/$size_dir/apps"
  mkdir -p "$dest_dir"
  cp -f "$ICON_PATH" "$dest_dir/$APP_ID.$ext"
  ICON_KEY="$APP_ID"
fi

# Create .desktop (omit Icon/Categories if empty)
{
  echo "[Desktop Entry]"
  echo "Name=$NAME"
  echo "Exec=$TARGET_APP %U"
  echo "Terminal=false"
  echo "Type=Application"
  [[ -n "$ICON_KEY" ]] && echo "Icon=$ICON_KEY"
  [[ -n "$CATEGORIES" ]] && echo "Categories=$CATEGORIES"
  echo "StartupWMClass=$(echo "$NAME" | tr -cd 'A-Za-z0-9')"
} > "$DESKTOP_FILE"

# Refresh caches (if available)
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  THEME_DIR="$HOME/.local/share/icons/hicolor"
  [[ -d "$THEME_DIR" ]] && gtk-update-icon-cache -q "$THEME_DIR" || true
fi
command -v xdg-desktop-menu >/dev/null 2>&1 && xdg-desktop-menu forceupdate || true

echo "✅ Installed!"
echo "  App:     $TARGET_APP"
echo "  Link:    $LINK_NAME"
echo "  Desktop: $DESKTOP_FILE"
[[ -n "$ICON_KEY" ]] && echo "  Icon:    $HOME/.local/share/icons/hicolor/512x512/apps/$APP_ID.*"
echo "Open your applications menu and search for: $NAME"

