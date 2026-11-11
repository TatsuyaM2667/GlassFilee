#!/bin/sh
# Permanently add Odin and Zig to PATH

echo "🔧 Setting up permanent PATH for GlassFilee..."
echo ""

ODIN_PATH="/home/tatsuya/.cache/ame-shell/toolchain/odin-dev-2026-08"
ZIG_PATH="/home/tatsuya/.cache/ame-shell/toolchain/zig-x86_64-linux-0.17.0"

# Check if paths exist
if [ ! -f "$ODIN_PATH/odin" ]; then
    echo "❌ Error: Odin not found at $ODIN_PATH"
    exit 1
fi

if [ ! -f "$ZIG_PATH/zig" ]; then
    echo "❌ Error: Zig not found at $ZIG_PATH"
    exit 1
fi

echo "✓ Found Odin at: $ODIN_PATH"
echo "✓ Found Zig at: $ZIG_PATH"
echo ""

# Add to .zshrc
echo "Adding to ~/.zshrc..."
cat >> ~/.zshrc << 'EOF'

# GlassFilee toolchain paths
export PATH=/home/tatsuya/.cache/ame-shell/toolchain/odin-dev-2026-08:$PATH
export PATH=/home/tatsuya/.cache/ame-shell/toolchain/zig-x86_64-linux-0.17.0:$PATH
EOF

echo "✓ Added to ~/.zshrc"
echo ""
echo "================================"
echo "✅ Setup complete!"
echo "================================"
echo ""
echo "To apply changes:"
echo "  source ~/.zshrc"
echo ""
echo "Or simply open a new terminal"
echo ""
