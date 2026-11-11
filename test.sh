#!/bin/bash
# GlassFilee Test Script
# Runs comprehensive tests

set -e

echo "================================"
echo "GlassFilee Test Suite"
echo "================================"
echo ""

# Build first
if [ ! -f "zig-out/bin/gf-cli" ]; then
    echo "[0/3] Building project first..."
    ./build.sh
    echo ""
fi

# Run unit tests
echo "[1/3] Running unit tests..."
ZIG="${ZIG:-zig}"
[ -x "$HOME/.cache/ame-shell/toolchain/zig-linux-x86_64-0.13.0/zig" ] && ZIG="$HOME/.cache/ame-shell/toolchain/zig-linux-x86_64-0.13.0/zig"
"$ZIG" build test
echo "✓ Unit tests passed"
echo "  Running Odin trash tests (isolated XDG_DATA_HOME)..."
GF_TEST_DIR="$(mktemp -d)" odin test tests/trash > /dev/null
echo "✓ Trash tests passed"
echo ""

# Run integration tests
echo "[2/3] Running integration tests..."
CLI="./zig-out/bin/gf-cli"

# Create test directory
TEST_DIR="test_gf_temp"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

echo "  Testing ls command..."
$CLI ls . > /dev/null
echo "  ✓ ls works"

echo "  Testing mkdir command..."
$CLI mkdir "$TEST_DIR/test_folder"
echo "  ✓ mkdir works"

echo "  Testing file creation and cp command..."
echo "test content" > "$TEST_DIR/test.txt"
$CLI cp "$TEST_DIR/test.txt" "$TEST_DIR/test_copy.txt"
echo "  ✓ cp works"

echo "  Testing mv command..."
$CLI mv "$TEST_DIR/test_copy.txt" "$TEST_DIR/test_moved.txt"
echo "  ✓ mv works"

echo "  Testing stat command..."
$CLI stat "$TEST_DIR/test.txt" > /dev/null
echo "  ✓ stat works"

echo "  Testing rm command..."
echo "y" | $CLI rm "$TEST_DIR/test_moved.txt" > /dev/null
echo "  ✓ rm works"

# Cleanup
rm -rf "$TEST_DIR"
echo "✓ Integration tests passed"
echo ""

# Manual verification
echo "[3/3] Manual verification test..."
echo ""
echo "Contents of current directory:"
$CLI ls .
echo ""

echo "================================"
echo "✨ All tests passed!"
echo "================================"
echo ""
echo "The CLI is working correctly."
echo "Try these commands:"
echo "  $CLI help"
echo "  $CLI ls /tmp"
echo "  $CLI stat README.md"
echo ""
