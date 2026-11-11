#!/usr/bin/env bash
# Install canva-affinity to ~/.local/bin and run its setup.
#
#   ./install.sh                 install and set up (auto-detects your Affinity prefix)
#   ./install.sh --prefix DIR    same, for a specific Wine prefix
#   ./install.sh --no-setup      only install the command
#
# Any other options are passed to `canva-affinity setup` (see `canva-affinity help`).

set -o errexit -o nounset -o pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}
TARGET="$BIN_DIR/canva-affinity"

run_setup=1
args=()
for a in "$@"; do
    if [[ "$a" == --no-setup ]]; then run_setup=0; else args+=("$a"); fi
done

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    echo "error: bash 4.3 or newer is required" >&2; exit 1
fi

missing=()
command -v curl >/dev/null || command -v wget >/dev/null || missing+=("curl")
command -v 7z >/dev/null || missing+=("7z (p7zip)")
command -v xdg-mime >/dev/null || missing+=("xdg-utils")
command -v tar >/dev/null || missing+=("tar")
command -v xz >/dev/null || missing+=("xz")
if (( ${#missing[@]} )); then
    echo "Missing tools: ${missing[*]}"
    echo "  Debian/Ubuntu: sudo apt install curl p7zip-full xdg-utils xz-utils"
    echo "  Fedora:        sudo dnf install curl p7zip p7zip-plugins xdg-utils xz"
    echo "  Arch:          sudo pacman -S curl 7zip xdg-utils xz"
    echo
fi

mkdir -p "$BIN_DIR"
install -m 0755 "$SRC_DIR/bin/canva-affinity" "$TARGET"
echo "Installed $TARGET"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Note: $BIN_DIR is not on your PATH. Add it, or run $TARGET directly." ;;
esac

if (( run_setup )); then
    echo
    exec "$TARGET" setup "${args[@]}"
fi
