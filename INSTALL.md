# Installation Guide

## Prerequisites

### 1. Install Zig (0.13.0+)

#### Linux (Arch, Chimera)
```bash
# Arch Linux
sudo pacman -S zig

# Chimera Linux
sudo apk add zig

# Or download binary
wget https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz
tar xf zig-linux-x86_64-0.13.0.tar.xz
sudo mv zig-linux-x86_64-0.13.0 /opt/zig
export PATH=$PATH:/opt/zig
```

#### FreeBSD
```bash
pkg install zig
```

### 2. Install Odin (latest)

```bash
# Clone and build
git clone https://github.com/odin-lang/Odin
cd Odin
make
sudo mv odin /usr/local/bin/
cd ..

# Verify
odin version
```

## Building GlassFilee

### Method 1: Automated Build (Recommended)

```bash
git clone <repository-url>
cd AmeFileManger
./build.sh
```

This will:
1. Check prerequisites
2. Build Odin core layer
3. Build Zig CLI
4. Create `zig-out/bin/gf-cli`

### Method 2: Manual Build

```bash
# Step 1: Build Odin core
mkdir -p zig-cache
odin build src/core -file -build-mode:obj -target:linux_amd64 -out:zig-cache/gfcore

# Step 2: Build Zig CLI
zig build

# Result
ls -lh zig-out/bin/gf-cli
```

### Method 3: Using Makefile

```bash
make build
```

## Testing

### Run All Tests

```bash
./test.sh
```

### Run Unit Tests Only

```bash
zig build test
```

### Manual Testing

```bash
./zig-out/bin/gf-cli help
./zig-out/bin/gf-cli ls .
./zig-out/bin/gf-cli stat README.md
```

## Installation (System-Wide)

### Option 1: Copy to /usr/local/bin

```bash
sudo cp zig-out/bin/gf-cli /usr/local/bin/
gf-cli help
```

### Option 2: Add to PATH

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH=$PATH:$(pwd)/zig-out/bin

# Reload
source ~/.bashrc

# Test
gf-cli help
```

### Option 3: Create Symlink

```bash
sudo ln -s $(pwd)/zig-out/bin/gf-cli /usr/local/bin/gf-cli
gf-cli help
```

## Platform-Specific Notes

### Arch Linux

Works out of the box with:
```bash
sudo pacman -S zig odin
./build.sh
```

### Chimera Linux (musl)

```bash
sudo apk add zig git make
# Build Odin from source
git clone https://github.com/odin-lang/Odin
cd Odin && make && sudo make install
cd ../AmeFileManger
./build.sh
```

### FreeBSD

```bash
pkg install zig git gmake
# Build Odin from source
git clone https://github.com/odin-lang/Odin
cd Odin && gmake && sudo gmake install
cd ../AmeFileManger

# Use FreeBSD target
odin build src/core -file -build-mode:obj -target:freebsd_amd64 -out:zig-cache/gfcore
zig build -Dtarget=x86_64-freebsd
```

## Troubleshooting

### "odin: command not found"

Odin is not in PATH. Either:
1. Add Odin to PATH: `export PATH=$PATH:/path/to/Odin`
2. Install system-wide: `sudo make install` in Odin directory

### "zig: command not found"

Zig is not in PATH. Either:
1. Install via package manager
2. Download and add to PATH

### "Cannot find gfcore.o"

The Odin build failed. Check:
1. Odin is correctly installed: `odin version`
2. Run manually: `odin build src/core -file -build-mode:obj -target:linux_amd64 -out:zig-cache/gfcore`
3. Verify output: `ls -l zig-cache/gfcore.o`

### "undefined reference to gf_*"

Odin FFI symbols not exported. Ensure:
1. Using `-build-mode:obj` flag
2. FFI functions have `@(export)` attribute
3. Rebuild Odin core: `./clean.sh && ./build.sh`

### Build succeeds but binary doesn't run

Check:
1. Executable permissions: `chmod +x zig-out/bin/gf-cli`
2. Library dependencies: `ldd zig-out/bin/gf-cli`
3. Run with full path: `./zig-out/bin/gf-cli help`

## Cleaning Build Artifacts

```bash
./clean.sh
# Or manually
rm -rf zig-cache zig-out
```

## Next Steps

1. **Try the CLI:**
   ```bash
   gf-cli ls ~
   gf-cli stat ~/.bashrc
   gf-cli mkdir test_folder
   ```

2. **Read documentation:**
   - [QUICKSTART.md](QUICKSTART.md)
   - [docs/API.md](docs/API.md)
   - [CONTRIBUTING.md](CONTRIBUTING.md)

3. **Report issues:**
   - GitHub Issues (add link here)
   - Include output of `odin version` and `zig version`

## Uninstallation

```bash
# If copied to /usr/local/bin
sudo rm /usr/local/bin/gf-cli

# If using symlink
sudo rm /usr/local/bin/gf-cli

# Remove source
cd ..
rm -rf AmeFileManger
```

---

**Need help?** Check the [documentation](docs/) or open an issue on GitHub.
