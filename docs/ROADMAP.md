# GlassFilee Development Roadmap

## Version 0.1 - Core Foundation (Current)

**Status:** 🚧 In Progress  
**Goal:** Working CLI with Odin/Zig FFI boundary

### Deliverables
- [x] Project structure
- [x] Odin core layer with C ABI exports
- [x] Zig FFI bindings
- [x] CLI application skeleton
- [ ] Basic file operations (list, copy, move, delete, rename, mkdir)
- [ ] Tests for FFI boundary
- [ ] Documentation (API, Building, Architecture)
- [ ] Working on all 3 target platforms (Arch, FreeBSD, Chimera)

### Success Criteria
- CLI can list directories
- CLI can copy/move/delete files
- All operations work across Odin/Zig boundary
- Tests pass on Linux

---

## Version 0.2 - GUI Foundation

**Status:** 📝 Planned  
**Goal:** Basic GUI with file browser

### Deliverables
- [ ] DVUI integration
- [ ] SDL3 window and event loop
- [ ] File list view (simple table)
- [ ] Directory navigation (double-click, breadcrumbs)
- [ ] Basic keyboard shortcuts (Ctrl+C, Ctrl+V, Delete)
- [ ] File operations via context menu

### Success Criteria
- GUI launches and shows file list
- Can navigate directories
- Can select files
- Can trigger copy/move/delete from GUI

---

## Version 0.3 - Essential Features

**Status:** 📝 Planned  
**Goal:** Feature parity with basic file managers

### Deliverables
- [ ] Icon view (grid layout)
- [ ] File icons (generic types: folder, text, image, video, etc.)
- [ ] Drag and drop (internal)
- [ ] Multi-selection (Ctrl+Click, Shift+Click, Ctrl+A)
- [ ] Sorting (name, size, date, type)
- [ ] Hidden files toggle
- [ ] Address bar (manual path entry)
- [ ] Back/Forward navigation

### Success Criteria
- Daily file management tasks possible
- Keyboard power user can work efficiently
- No mouse required for common operations

---

## Version 0.4 - Glass Morphism UI

**Status:** 📝 Planned  
**Goal:** Beautiful, modern interface

### Deliverables
- [ ] DVUI `BlurBackdrop` integration
- [ ] Semi-transparent panels
- [ ] Blur effects on overlays
- [ ] Context menus with blur
- [ ] Modal dialogs with blur
- [ ] Smooth animations (fade in/out)
- [ ] Color theme system
- [ ] Custom theme: "Glass Dark", "Glass Light"

### Success Criteria
- Visually distinctive glass UI
- Works without window transparency
- Blur performance acceptable (>30fps)
- User can customize appearance

---

## Version 0.5 - Filee Integration

**Status:** 📝 Planned  
**Goal:** Built-in file conversion

### Deliverables
- [ ] Conversion menu ("Convert to...")
- [ ] Image format detection
- [ ] External tool integration (ImageMagick, FFmpeg)
- [ ] Conversion presets (Web, Print, Archive, etc.)
- [ ] Progress bar for conversions
- [ ] Batch conversion support
- [ ] Donut-style conversion UI (Filee-inspired)
- [ ] Drag-and-drop to convert

### Supported Formats (Initial)
- **Images:** PNG ↔ JPEG ↔ WebP ↔ AVIF ↔ GIF ↔ BMP
- **Documents:** PDF → images, images → PDF
- **Video:** Basic FFmpeg operations (resize, format change)

### Success Criteria
- Can convert common image formats
- External tools auto-detected
- Conversion succeeds with clear error messages
- User can create custom presets

---

## Version 0.6 - Advanced Features

**Status:** 📝 Planned  
**Goal:** Power user features

### Deliverables
- [ ] Thumbnail cache
- [ ] Image preview panel
- [ ] PDF preview (first page)
- [ ] Video preview (thumbnail + metadata)
- [ ] Search (name filter)
- [ ] Extension filter (*.txt, *.jpg, etc.)
- [ ] Multiple tabs
- [ ] Dual pane mode
- [ ] Bookmarks/favorites
- [ ] Recent locations

### Success Criteria
- Thumbnails load quickly
- Search is instant for small directories
- Tabs don't interfere with each other
- Preview panel is useful

---

## Version 0.7 - Window Transparency

**Status:** 📝 Planned  
**Goal:** True transparent windows (when supported)

### Deliverables
- [ ] Compositor detection (Wayland/X11)
- [ ] SDL3 transparent window support
- [ ] Wayland protocol: `ext-background-effect-v1`
- [ ] Graceful fallback (no transparency)
- [ ] KDE Plasma integration
- [ ] GNOME integration
- [ ] Performance optimization

### Success Criteria
- Window transparency works on KDE
- Window transparency works on GNOME
- Fallback to opaque window on unsupported compositors
- No visual glitches
- Performance impact minimal

---

## Version 1.0 - First Stable Release

**Status:** 📝 Planned  
**Goal:** Production-ready, cross-platform file manager

### Deliverables
- [ ] WebAssembly version (limited features)
- [ ] Packages for all target platforms
  - [ ] Arch Linux (AUR)
  - [ ] FreeBSD (ports)
  - [ ] Chimera Linux (cports)
- [ ] Complete documentation
- [ ] Tutorial/getting started guide
- [ ] Website with screenshots
- [ ] Release announcement

### Success Criteria
- All tests pass
- No critical bugs
- Documentation complete
- Packages installable on all platforms
- Performance meets goals:
  - Startup <1s
  - Idle CPU ~0%
  - Memory <100MB
  - Binary <20MB

---

## Future (Post-1.0)

### Possible Features

#### Content Search
- Full-text search with `ripgrep`
- SQLite FTS index
- Search history

#### Advanced Conversion
- Office documents (LibreOffice integration)
- Audio conversion
- Archive creation/extraction (ZIP, TAR, 7z)
- Batch renaming with patterns

#### Cloud Integration
- Mount remote locations (SFTP, WebDAV)
- Cloud storage providers (Nextcloud, etc.)

#### Plugins
- Lua scripting API
- Custom file viewers
- Custom converters

#### Performance
- Lazy loading for huge directories
- Streaming for large file operations
- GPU-accelerated blur (Vulkan compute)

---

## Milestone Timeline (Estimates)

| Version | Target Date | Status |
|---------|-------------|--------|
| v0.1    | 2026-11-15  | 🚧 In Progress |
| v0.2    | 2026-12-01  | 📝 Planned |
| v0.3    | 2026-12-20  | 📝 Planned |
| v0.4    | 2027-01-15  | 📝 Planned |
| v0.5    | 2027-02-01  | 📝 Planned |
| v0.6    | 2027-02-20  | 📝 Planned |
| v0.7    | 2027-03-10  | 📝 Planned |
| v1.0    | 2027-04-01  | 📝 Planned |

*Timeline is aspirational and subject to change based on complexity and available development time.*

---

## How to Contribute

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Code style guidelines
- How to submit PRs
- Feature request process
- Bug reporting

Pick any unimplemented feature from this roadmap and start contributing!
