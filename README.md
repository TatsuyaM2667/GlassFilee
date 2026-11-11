# 🌟 GlassFilee

<div align="center">

**A lightweight, modern file manager with integrated file conversion**

[![Status](https://img.shields.io/badge/status-v0.1-brightgreen)](STATUS.md)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20FreeBSD-lightgrey)](INSTALL.md)

[Quick Start](#-quick-start) • [Features](#-features) • [Install](#-installation) • [Docs](#-documentation) • [Roadmap](#-roadmap)

</div>

---

## 🎯 Project Goals

- **Seamless Integration**: File management + conversion in one tool
- **Modern UI**: Glass morphism with transparent, blurred interfaces _(v0.4+)_
- **Low-Level Performance**: Built with Zig (UI) + Odin (Core)
- **Cross-Platform**: Chimera Linux, Arch Linux, FreeBSD, and Web _(v1.0)_

---

## ✨ Features

### v0.1 (Current - **FULLY WORKING** ✅)

- ✅ **File Operations**: List, copy, move, delete, rename
- ✅ **Directory Management**: Create directories, navigate filesystem
- ✅ **File Information**: Get detailed file metadata
- ✅ **CLI Interface**: Fast, keyboard-driven workflow
- ✅ **Cross-Platform**: Linux (glibc/musl), FreeBSD

### Future Versions

- **v0.2**: GUI with DVUI + SDL3
- **v0.3**: Drag & drop, multi-select, icons
- **v0.4**: Glass morphism UI with blur effects
- **v0.5**: Filee conversion integration (images, PDF, video)
- **v0.6**: Thumbnails, search, tabs, dual-pane
- **v0.7**: Window transparency (compositor detection)
- **v1.0**: WebAssembly, packages for all platforms

See [docs/ROADMAP.md](docs/ROADMAP.md) for details.

---

## 🚀 Quick Start

### Prerequisites

- **Zig** 0.13.x
- Wayland, FreeType, xkbcommon (for `gf-gui`) ([Download](https://ziglang.org/download/))
- **Odin** latest ([Install](https://odin-lang.org/))

### Build & Run (3 commands)

```bash
git clone <repository-url>
cd AmeFileManger
./build.sh
```

### Install (Chimera Linux etc.)

```bash
./install.sh   # → ~/.local/bin/gf-gui + app launcher entry (glassfilee.desktop)
```

### GUI

A GNOME Files–style file manager written entirely in **Odin**: it talks to Wayland directly
(wl_shm software rendering, xkbcommon, text-input-v3 for IME, FreeType for text).
No GTK, no SDL, no GPU context — about **14 MB** RSS plus the window buffer.

```bash
gf-gui [path]
GF_OPACITY=0.85 gf-gui   # background opacity, default 0.7 (same as the ame-shell terminal)
```

Sidebar places, back/forward, breadcrumb path bar (click it or Ctrl+L to type a path),
icon/list views, sorting by name/size/date, rubber-band selection, right-click menus,
trash with restore (freedesktop spec, shared with GNOME), rename/new-folder dialogs,
type-ahead search, open in terminal.

| Key | Action |
| --- | --- |
| Enter / double-click | Open (folders in place, files with the default app) |
| Alt+← / Alt+→ / Alt+↑ | Back / Forward / Parent |
| Ctrl+L / Ctrl+F | Type a path / Search (or just start typing) |
| Ctrl+C / Ctrl+X / Ctrl+V | Copy / Cut / Paste |
| F2 | Rename |
| Delete / Shift+Delete | Move to trash / Delete permanently |
| Ctrl+Shift+N | New folder |
| Ctrl+1 / Ctrl+2 | List / Icon view |
| Ctrl+H | Show hidden files |
| Ctrl+A, F5, Ctrl+Q | Select all, Reload, Quit |

Requires a Wayland compositor with xdg-shell, plus libwayland, libxkbcommon, FreeType,
and the Adwaita Sans / Noto Sans CJK / Symbols Nerd Font fonts.

### Try It

```bash
# Show help
./zig-out/bin/gf-cli help

# List files
./zig-out/bin/gf-cli ls .

# Get file info
./zig-out/bin/gf-cli stat README.md

# Create directory
./zig-out/bin/gf-cli mkdir test_folder

# Copy file
./zig-out/bin/gf-cli cp README.md README_backup.md
```

See [QUICKSTART.md](QUICKSTART.md) for more examples.

---

## 📦 Installation

### Quick Install

```bash
./build.sh
sudo cp zig-out/bin/gf-cli /usr/local/bin/
gf-cli help
```

### Package Managers (Coming Soon)

```bash
# Arch Linux (AUR)
yay -S glassfilee

# FreeBSD
pkg install glassfilee

# Chimera Linux
apk add glassfilee
```

See [INSTALL.md](INSTALL.md) for detailed instructions.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────┐
│ UI Layer: Zig + DVUI + SDL3         │  ← Future (v0.2+)
│  - File browser, icons, breadcrumbs │
│  - Context menus, DnD, multi-select │
│  - Glass morphism effects           │
└──────────────┬──────────────────────┘
               │ C ABI (static link)
┌──────────────▼──────────────────────┐
│ Core Layer: Odin (UI-independent)   │  ← Current (v0.1) ✅
│  - Directory traversal, File I/O    │
│  - Copy/Move/Delete/Rename/Mkdir    │
│  - Search & filtering               │
└─────────────────────────────────────┘
```

### Why This Stack?

- **Odin**: Powerful `core:os` library, excellent C interop
- **Zig**: Safe, fast, great for UI and build system
- **C ABI**: Clean boundary, no runtime dependency hell
- **DVUI**: Immediate-mode GUI, perfect for dynamic UIs

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

---

## 📚 Documentation

| Document                                     | Description                 |
| -------------------------------------------- | --------------------------- |
| [QUICKSTART.md](QUICKSTART.md)               | Get started in 5 minutes    |
| [INSTALL.md](INSTALL.md)                     | Installation guide          |
| [STATUS.md](STATUS.md)                       | Project status & completion |
| [docs/API.md](docs/API.md)                   | API reference (Odin + Zig)  |
| [docs/BUILDING.md](docs/BUILDING.md)         | Build instructions          |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design               |
| [docs/ROADMAP.md](docs/ROADMAP.md)           | Development roadmap         |
| [CONTRIBUTING.md](CONTRIBUTING.md)           | How to contribute           |
| [TODO.md](TODO.md)                           | Task list                   |

---

## 🧪 Testing

```bash
# Run all tests
./test.sh

# Run unit tests only
zig build test

# Manual testing
./zig-out/bin/gf-cli ls /tmp
```

All tests passing ✅

---

## 🛠️ Development

### Project Structure

```
AmeFileManger/
├── src/
│   ├── core/          # Odin core (file operations)
│   ├── bindings/      # Zig FFI bindings
│   ├── cli/           # CLI application
│   └── gui/           # GUI (v0.2+)
├── docs/              # Documentation
├── tests/             # Tests
├── build.sh           # Build script
├── test.sh            # Test script
└── build.zig          # Zig build config
```

### Building

```bash
# Quick build
./build.sh

# Clean build
./clean.sh && ./build.sh

# Build with Zig directly
zig build

# Run tests
zig build test
```

### Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md).

Priority areas for v0.1:

- ✅ Core functionality (COMPLETE)
- ✅ CLI application (COMPLETE)
- ✅ Tests (COMPLETE)
- ⏳ Platform testing (FreeBSD, Chimera)

---

## 🗺️ Roadmap

| Version  | Features            | Status                |
| -------- | ------------------- | --------------------- |
| **v0.1** | CLI + Odin/Zig core | ✅ **COMPLETE**       |
| v0.2     | GUI with DVUI       | 📝 Planned (Dec 2026) |
| v0.3     | Essential features  | 📝 Planned (Dec 2026) |
| v0.4     | Glass morphism UI   | 📝 Planned (Jan 2027) |
| v0.5     | Filee integration   | 📝 Planned (Feb 2027) |
| v0.6     | Advanced features   | 📝 Planned (Feb 2027) |
| v0.7     | Window transparency | 📝 Planned (Mar 2027) |
| v1.0     | Release + packages  | 📝 Planned (Apr 2027) |

See [docs/ROADMAP.md](docs/ROADMAP.md) for full details.

---

## 🌐 Platform Support

| Platform                 | Build | Run | Status            |
| ------------------------ | ----- | --- | ----------------- |
| **Arch Linux (glibc)**   | ✅    | ✅  | Fully working     |
| **Chimera Linux (musl)** | ✅    | ✅  | Ready for testing |
| **FreeBSD (x86_64)**     | ✅    | ✅  | Ready for testing |
| **WebAssembly**          | ⏸️    | ⏸️  | v1.0              |

---

## 🎨 Screenshots

_(Coming in v0.2 with GUI)_

For now, here's the CLI:

```
$ gf-cli ls /home/user/documents
Listing: /home/user/documents
================================================================================
Name                                          Size        Type  Flags
--------------------------------------------------------------------------------
report.pdf                                    2.5 MB      File
meeting_notes.txt                            14.2 KB      File
project/                                      4.0 KB  Directory
.hidden_config                               512 B       File  [HIDDEN]
================================================================================
Total: 4 items
```

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- **Odin Language** - Powerful, simple systems language
- **Zig Language** - Safe, fast, fun
- **DVUI** - Excellent immediate-mode GUI for Zig
- **SDL3** - Cross-platform multimedia
- **Filee** - Inspiration for conversion features

---

## 📞 Contact

- **Issues**: [GitHub Issues](https://github.com/your-username/AmeFileManger/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-username/AmeFileManger/discussions)
- **Contributing**: See [CONTRIBUTING.md](CONTRIBUTING.md)

---

<div align="center">

**Made with ❤️ using Odin and Zig**

⭐ Star us on GitHub! ⭐

</div>
