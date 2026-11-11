#!/bin/sh
# Build and install GlassFilee (Chimera Linux, Arch Linux, FreeBSD, other Wayland systems).
#   ./install.sh                 → ~/.local, and make it the default file manager
#   PREFIX=/usr/local sudo -E ./install.sh   → system-wide
#   NO_DEFAULT=1 ./install.sh    → don't change the default file manager
# Needs: odin (recent dev build), wayland, libxkbcommon, freetype2, bsdtar (libarchive).
set -e
cd "$(dirname "$0")"
PREFIX="${PREFIX:-$HOME/.local}"

LINK=""
case "$(uname -s)" in
FreeBSD) LINK='-extra-linker-flags:-L/usr/local/lib' ;; # ports install libs under /usr/local
esac

mkdir -p zig-out/bin
# GUI: pure Odin (Wayland + FreeType + xkbcommon)
odin build src/gui -out:zig-out/bin/gf-gui -o:speed $LINK

# CLI (optional): written for Zig 0.13 exactly
ZIG="${ZIG:-zig}"
[ -x "$HOME/.cache/ame-shell/toolchain/zig-linux-x86_64-0.13.0/zig" ] && ZIG="$HOME/.cache/ame-shell/toolchain/zig-linux-x86_64-0.13.0/zig"
if command -v "$ZIG" >/dev/null 2>&1 && "$ZIG" version | grep -q '^0\.13\.'; then
    mkdir -p zig-cache
    rm -f zig-cache/libgfcore.a
    odin build src/core -build-mode:static -no-entry-point -o:speed -out:zig-cache/libgfcore.a $LINK
    "$ZIG" build -Doptimize=ReleaseSafe
else
    echo "note: Zig 0.13 not found, skipping gf-cli (the GUI does not need it)"
fi

# BSD install(1) has no -D, so create directories first
mkdir -p "$PREFIX/bin" "$PREFIX/share/applications"
install -m 755 zig-out/bin/gf-gui "$PREFIX/bin/gf-gui"
[ -f zig-out/bin/gf-cli ] && install -m 755 zig-out/bin/gf-cli "$PREFIX/bin/gf-cli"
install -m 644 glassfilee.desktop "$PREFIX/share/applications/glassfilee.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$PREFIX/share/applications" || true

if [ -z "$NO_DEFAULT" ]; then
    # default for folders (also used by browsers' "show in folder" fallbacks and xdg-open)
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default glassfilee.desktop inode/directory
    else
        cfg="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
        mkdir -p "$(dirname "$cfg")"
        touch "$cfg"
        grep -q '^\[Default Applications\]' "$cfg" || printf '[Default Applications]\n' >> "$cfg"
        awk '!/^inode\/directory=/ {print} /^\[Default Applications\]$/ {print "inode/directory=glassfilee.desktop"}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    fi
    echo "GlassFilee is now the default file manager (undo: NO_DEFAULT=1 and set another app with xdg-mime)"
fi

echo "Installed: $PREFIX/bin/gf-gui"
