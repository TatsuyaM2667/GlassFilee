#!/bin/bash
# GlassFilee Clean Script
# Removes all build artifacts

echo "Cleaning build artifacts..."

rm -rf zig-cache
rm -rf zig-out
rm -rf .zig-cache
rm -f gfcore.o

# Clean test files
rm -f test_*_gf.txt
rm -rf test_directory_gf
rm -rf test_gf_temp

echo "✓ Cleaned all build artifacts"
echo ""
echo "Run ./build.sh to rebuild"
