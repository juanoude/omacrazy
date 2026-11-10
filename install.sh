#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR=${OMACRAZY_INSTALL_DIR:-"$HOME/.local/bin"}
DESTINATION="$INSTALL_DIR/omacrazy"
THEMES_DIR="$HOME/.config/omacrazy/themes"

if ! command -v swift >/dev/null 2>&1; then
    printf '%s\n' "install: Swift is required. Install Xcode Command Line Tools or Xcode first." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
printf 'Building Omacrazy in release mode...\n'
swift build --package-path "$PROJECT_DIR" -c release

BUILT_BINARY="$PROJECT_DIR/.build/release/omacrazy"
if [ ! -x "$BUILT_BINARY" ]; then
    printf 'install: build did not produce %s\n' "$BUILT_BINARY" >&2
    exit 1
fi

# Copy only adapter inputs, inference sources, wallpapers, and license notices.
# Preserve installed edits once before updating; leave added themes untouched.
install_theme_file() {
    source_file=$1
    target_file=$2
    [ -f "$source_file" ] || return 0
    mkdir -p "$(dirname -- "$target_file")"
    if [ -e "$target_file" ]; then
        if cmp -s "$source_file" "$target_file"; then
            return 0
        fi
        if [ ! -e "$target_file.omacrazy-backup" ]; then
            cp -p "$target_file" "$target_file.omacrazy-backup"
        fi
    fi
    install -m 644 "$source_file" "$target_file"
}

mkdir -p "$THEMES_DIR"
for theme in "$PROJECT_DIR"/themes/*; do
    [ -d "$theme" ] || continue
    name=$(basename -- "$theme")
    mkdir -p "$THEMES_DIR/$name"
    for source_file in "$theme"/*; do
        case "$(basename -- "$source_file")" in
            colors.toml|alacritty.toml|hyprland.conf|ghostty.conf|jankyborders.conf|zed.json|LICENSE|LICENSE.*|COPYING|NOTICE)
                install_theme_file "$source_file" "$THEMES_DIR/$name/$(basename -- "$source_file")"
                ;;
        esac
    done
    for source_file in "$theme"/zed/themes/*; do
        extension=$(printf '%s' "${source_file##*.}" | tr '[:upper:]' '[:lower:]')
        case "$extension" in
            json) install_theme_file "$source_file" "$THEMES_DIR/$name/zed/themes/$(basename -- "$source_file")" ;;
        esac
    done
    for source_file in "$theme"/backgrounds/*; do
        extension=$(printf '%s' "${source_file##*.}" | tr '[:upper:]' '[:lower:]')
        case "$extension" in
            jpg|jpeg|png|heic|webp)
                install_theme_file "$source_file" "$THEMES_DIR/$name/backgrounds/$(basename -- "$source_file")"
                ;;
        esac
    done
done
printf 'Installed themes in %s\n' "$THEMES_DIR"

TEMP_BINARY="$INSTALL_DIR/.omacrazy.$$"
trap 'rm -f "$TEMP_BINARY"' EXIT HUP INT TERM
install -m 755 "$BUILT_BINARY" "$TEMP_BINARY"
mv -f "$TEMP_BINARY" "$DESTINATION"
trap - EXIT HUP INT TERM

printf 'Installed %s\n' "$DESTINATION"
case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        printf '\n%s\n' "Add this to your shell configuration to run 'omacrazy' directly:"
        printf '  export PATH="%s:$PATH"\n' "$INSTALL_DIR"
        ;;
esac
