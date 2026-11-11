#!/bin/sh
# Quick PATH setup for Odin and Zig

echo "================================"
echo "GlassFilee - PATH Setup Helper"
echo "================================"
echo ""

# Common installation locations
COMMON_PATHS=(
    "$HOME/opt/odin"
    "$HOME/odin"
    "$HOME/Odin"
    "$HOME/.local/odin"
    "/opt/odin"
    "$HOME/opt/zig"
    "$HOME/zig"
    "$HOME/.local/zig"
    "/opt/zig"
)

echo "Searching for Odin and Zig installations..."
echo ""

ODIN_PATH=""
ZIG_PATH=""

# Search for Odin
for path in "${COMMON_PATHS[@]}"; do
    if [ -f "$path/odin" ]; then
        ODIN_PATH="$path"
        echo "✓ Found Odin at: $ODIN_PATH"
        break
    fi
done

# Search for Zig
for path in "${COMMON_PATHS[@]}"; do
    if [ -f "$path/zig" ]; then
        ZIG_PATH="$path"
        echo "✓ Found Zig at: $ZIG_PATH"
        break
    fi
done

echo ""
echo "================================"
echo "Setup Instructions"
echo "================================"
echo ""

if [ -z "$ODIN_PATH" ]; then
    echo "❌ Odin not found in common locations"
    echo ""
    echo "Please locate your Odin binary and run:"
    echo "  export PATH=/path/to/odin:\$PATH"
    echo ""
    echo "Example:"
    echo "  export PATH=\$HOME/opt/odin:\$PATH"
    echo ""
fi

if [ -z "$ZIG_PATH" ]; then
    echo "❌ Zig not found in common locations"
    echo ""
    echo "Please locate your Zig binary and run:"
    echo "  export PATH=/path/to/zig:\$PATH"
else
    echo "✓ Zig is ready"
fi

echo ""
echo "To make this permanent, add to your ~/.profile or ~/.config/sh/profile:"
echo ""

if [ -n "$ODIN_PATH" ]; then
    echo "export PATH=\"$ODIN_PATH:\$PATH\""
fi

if [ -n "$ZIG_PATH" ] && [ "$ZIG_PATH" != "$(dirname $(command -v zig 2>/dev/null) 2>/dev/null)" ]; then
    echo "export PATH=\"$ZIG_PATH:\$PATH\""
fi

echo ""
echo "Then run: source ~/.profile"
echo ""

# Quick test if both found
if [ -n "$ODIN_PATH" ] && [ -n "$ZIG_PATH" ]; then
    echo "================================"
    echo "Quick Test (in current shell)"
    echo "================================"
    echo ""
    echo "Run these commands:"
    echo ""
    echo "  export PATH=\"$ODIN_PATH:\$PATH\""
    if [ "$ZIG_PATH" != "$(dirname $(command -v zig 2>/dev/null) 2>/dev/null)" ]; then
        echo "  export PATH=\"$ZIG_PATH:\$PATH\""
    fi
    echo "  ./build.sh"
    echo ""
fi
