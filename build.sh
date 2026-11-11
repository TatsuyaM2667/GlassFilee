#!/bin/bash
# GlassFilee Build Script
# Builds both Odin core and Zig CLI

set -e

echo "================================"
echo "GlassFilee Build Script"
echo "================================"
echo ""

# Check prerequisites
echo "[1/4] Checking prerequisites..."
if ! command -v odin &> /dev/null; then
    echo "❌ Error: Odin not found in PATH"
    echo "   Please install Odin from https://odin-lang.org/"
    exit 1
fi

# Zig 0.13 is required; prefer the local 0.13 toolchain over a newer zig in PATH
ZIG="${ZIG:-zig}"
[ -x "$HOME/.cache/ame-shell/toolchain/zig-linux-x86_64-0.13.0/zig" ] && ZIG="$HOME/.cache/ame-shell/toolchain/zig-linux-x86_64-0.13.0/zig"
if ! command -v "$ZIG" &> /dev/null; then
    echo "❌ Error: Zig not found in PATH"
    echo "   Please install Zig from https://ziglang.org/"
    exit 1
fi

echo "✓ Odin version: $(odin version)"
echo "✓ Zig version: $("$ZIG" version)"
echo ""

# Create build directory
echo "[2/4] Creating build directories..."
mkdir -p zig-cache
mkdir -p zig-out/bin
echo "✓ Build directories created"
echo ""

# Build Odin core (remove old archive: odin appends members, stale ones linger)
rm -f zig-cache/libgfcore.a
echo "[3/4] Building Odin core layer..."
odin build src/core \
    -build-mode:static -no-entry-point \
    -target:linux_amd64 \
    -out:zig-cache/libgfcore.a

if [ ! -f "zig-cache/libgfcore.a" ]; then
    echo "❌ Error: Failed to build Odin core"
    echo "   Expected file: zig-cache/libgfcore.a"
    exit 1
fi

echo "✓ Odin core built successfully"
echo "  Output: zig-cache/libgfcore.a"
echo ""

# Build Zig CLI
echo "[4/4] Building Zig CLI + Odin GUI..."
"$ZIG" build

# GUI (pure Odin: Wayland + FreeType + xkbcommon)
odin build src/gui -out:zig-out/bin/gf-gui -o:speed

if [ ! -f "zig-out/bin/gf-cli" ]; then
    echo "❌ Error: Failed to build Zig CLI"
    echo "   Expected file: zig-out/bin/gf-cli"
    exit 1
fi

echo "✓ Zig CLI built successfully"
echo "  Output: zig-out/bin/gf-cli"
echo ""

# Summary
echo "================================"
echo "✨ Build completed successfully!"
echo "================================"
echo ""
echo "Run the CLI:"
echo "  ./zig-out/bin/gf-cli help"
echo "  ./zig-out/bin/gf-cli ls ."
echo ""
echo "Run the GUI:"
echo "  ./zig-out/bin/gf-gui [path]"
echo ""
echo "Run tests:"
echo "  zig build test"
echo ""
