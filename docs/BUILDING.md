# Building GlassFilee

## Prerequisites

### Required

- **Zig** 0.13.0 or later
  ```bash
  # Linux
  wget https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz
  tar xf zig-linux-x86_64-0.13.0.tar.xz
  export PATH=$PATH:$(pwd)/zig-linux-x86_64-0.13.0
  
  # Or use package manager
  # Arch Linux
  sudo pacman -S zig
  
  # Chimera Linux
  sudo apk add zig
  ```

- **Odin** (latest)
  ```bash
  git clone https://github.com/odin-lang/Odin
  cd Odin
  make
  export PATH=$PATH:$(pwd)
  ```

### Optional (for full functionality)

- **SDL3** (for GUI, v0.2+)
  ```bash
  # Arch
  yay -S sdl3-git
  
  # From source
  git clone https://github.com/libsdl-org/SDL
  cd SDL
  cmake -B build -DCMAKE_BUILD_TYPE=Release
  cmake --build build
  sudo cmake --install build
  ```

- **ImageMagick** (for image conversion)
  ```bash
  sudo pacman -S imagemagick  # Arch
  sudo apk add imagemagick    # Chimera
  ```

- **FFmpeg** (for video conversion)
  ```bash
  sudo pacman -S ffmpeg       # Arch
  sudo apk add ffmpeg         # Chimera
  ```

## Building

### Quick Start

```bash
# Clone repository
git clone <repository-url>
cd AmeFileManger

# Build everything
make build

# Or use zig build directly
zig build
```

### Manual Build Steps

1. **Build Odin Core Layer**
   ```bash
   # Create output directory
   mkdir -p zig-cache
   
   # Compile Odin code to object file
   odin build src/core -file -build-mode:obj -target:linux_amd64 -out:zig-cache/gfcore
   
   # This creates zig-cache/gfcore.o
   ```

2. **Build Zig CLI**
   ```bash
   # Zig build system handles linking with Odin object
   zig build
   
   # Output: zig-out/bin/gf-cli
   ```

3. **Run**
   ```bash
   ./zig-out/bin/gf-cli help
   ./zig-out/bin/gf-cli ls .
   ```

## Build Configurations

### Debug Build (default)
```bash
zig build
```

### Release Build
```bash
zig build -Doptimize=ReleaseFast
```

### Release Small
```bash
zig build -Doptimize=ReleaseSmall
```

## Cross-Compilation

### FreeBSD
```bash
# Build Odin core for FreeBSD
odin build src/core -file -build-mode:obj -target:freebsd_amd64 -out:zig-cache/gfcore

# Build Zig CLI for FreeBSD
zig build -Dtarget=x86_64-freebsd
```

### WebAssembly (v1.0+)
```bash
# Future feature
zig build -Dtarget=wasm32-freestanding
```

## Testing

```bash
# Run all tests
zig build test

# Run specific test
zig test src/core/tests.zig
```

## Troubleshooting

### "Odin not found"
- Ensure Odin is in your PATH
- Check: `which odin`

### "Cannot find gfcore.o"
- Build Odin core first: `make odin-core`
- Check file exists: `ls zig-cache/gfcore.o`

### "Undefined reference to gf_*"
- Odin FFI functions not exported correctly
- Rebuild Odin core with `-build-mode:obj`

### SDL3 not found
- Install SDL3 development package
- Or set `SDL3_DIR` environment variable

## Project Structure

```
AmeFileManger/
├── src/
│   ├── core/          # Odin core (compiled to .o)
│   ├── bindings/      # Zig FFI bindings
│   ├── cli/           # CLI application
│   └── gui/           # GUI application (future)
├── zig-cache/         # Build artifacts
│   └── gfcore.o       # Compiled Odin code
├── zig-out/           # Final binaries
│   └── bin/
│       └── gf-cli     # CLI executable
└── build.zig          # Zig build configuration
```

## Next Steps

After building successfully:

1. Try the CLI commands:
   ```bash
   ./zig-out/bin/gf-cli ls ~
   ./zig-out/bin/gf-cli stat README.md
   ```

2. Check the [ARCHITECTURE.md](ARCHITECTURE.md) for code structure

3. Start developing! See [CONTRIBUTING.md](CONTRIBUTING.md)
