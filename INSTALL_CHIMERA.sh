#!/bin/sh
# GlassFilee - Chimera Linux Quick Setup
# Installs Odin binary and sets up the project

set -e

echo "================================"
echo "GlassFilee - Chimera Linux Setup"
echo "================================"
echo ""

# Check if running on Chimera Linux
if [ ! -f /etc/os-release ] || ! grep -q "Chimera" /etc/os-release; then
    echo "⚠️  Warning: This script is designed for Chimera Linux"
    echo "   Continue anyway? (y/N)"
    read -r response
    if [ "$response" != "y" ]; then
        exit 1
    fi
fi

# Check Zig
echo "[1/3] Checking Zig installation..."
if command -v zig >/dev/null 2>&1; then
    echo "✓ Zig found: $(zig version)"
else
    echo "❌ Zig not found!"
    echo ""
    echo "Please install Zig first:"
    echo "  1. Download: https://ziglang.org/download/"
    echo "  2. Extract to ~/opt/zig"
    echo "  3. Add to PATH: export PATH=\$HOME/opt/zig:\$PATH"
    exit 1
fi

# Check/Install Odin
echo ""
echo "[2/3] Checking Odin installation..."
if command -v odin >/dev/null 2>&1; then
    echo "✓ Odin found: $(odin version)"
else
    echo "❌ Odin not found. Installing Odin binary..."
    echo ""

    # Create installation directory
    mkdir -p "$HOME/opt"
    cd "$HOME/opt"

    # Download Odin binary (latest dev build for Linux)
    echo "Downloading Odin..."
    