#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR=${OMACRAZY_INSTALL_DIR:-"$HOME/.local/bin"}
DESTINATION="$INSTALL_DIR/omacrazy"

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
