# GlassFilee Makefile
# Simple build helper (delegates to zig build)

ZIG ?= $(shell ls $$HOME/.cache/ame-shell/toolchain/zig-linux-x86_64-0.13.0/zig 2>/dev/null || echo zig)

.PHONY: gui all clean build run test help odin-core

all: build

# Build Odin core library first
odin-core:
	@echo "Building Odin core layer..."
	@mkdir -p zig-cache
	rm -f zig-cache/libgfcore.a
	odin build src/core -build-mode:static -no-entry-point -target:linux_amd64 -out:zig-cache/libgfcore.a

# Build CLI tool
build: odin-core
	@echo "Building GlassFilee CLI..."
	$(ZIG) build

# Run CLI
run: build
	./zig-out/bin/gf-cli

gui: build
	./zig-out/bin/gf-gui

# Run tests
test: odin-core
	$(ZIG) build test

# Clean build artifacts
clean:
	rm -rf zig-cache zig-out

# Help
help:
	@echo "GlassFilee Build Commands:"
	@echo "  make build    - Build CLI tool"
	@echo "  make run      - Build and run CLI"
	@echo "  make test     - Run tests"
	@echo "  make clean    - Clean build artifacts"
	@echo "  make help     - Show this help"
