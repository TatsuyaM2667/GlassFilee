#!/bin/sh
# Build (release) and install GlassFilee for the current user.
# PREFIX defaults to ~/.local (bin/ and share/applications/ under it).
set -e
cd "$(dirname "$0")"
PREFIX="${PREFIX:-$HOME/.local}"

ZIG="${ZIG:-zig}"
[ -x "$HOME/.cache/ame-shell/toolchain/zig-linux-x86_64-0.13.0/zig" ] && ZIG="$HOME/.cache/ame-shell/toolchain/zig-linux-x86_64-0.13.0/zig"

mkdir -p zig-cache
rm -f zig-cache/libgfcore.a
odin build src/core -build-mode:static -no-entry-point -o:speed -target:linux_amd64 -out:zig-cache/libgfcore.a
"$ZIG" build -Doptimize=ReleaseSafe

# GUI: pure Odin (Wayland + FreeType + xkbcommon)
odin build src/gui -out:zig-out/bin/gf-gui -o:speed

install -Dm755 zig-out/bin/gf-gui "$PREFIX/bin/gf-gui"
install -Dm755 zig-out/bin/gf-cli "$PREFIX/bin/gf-cli"
install -Dm644 glassfilee.desktop "$PREFIX/share/applications/glassfilee.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$PREFIX/share/applications" || true

echo "Installed: $PREFIX/bin/gf-gui, $PREFIX/share/applications/glassfilee.desktop"
