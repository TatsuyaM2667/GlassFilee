# GlassFilee TODO List

## v0.1 - Core Foundation (Current Sprint)

### Critical (Must Have)
- [ ] Complete CLI main.zig implementation
  - [ ] formatSize function completion
  - [ ] Error handling polish
  - [ ] Help text refinement
- [ ] Finish test suite (src/core/tests.zig)
  - [ ] Test all file operations
  - [ ] Test error cases
  - [ ] Test edge cases (empty dir, permissions, etc.)
- [ ] Fix build.zig Odin integration
  - [ ] Ensure gfcore.o is built correctly
  - [ ] Handle build errors gracefully
  - [ ] Add proper dependency tracking
- [ ] Test on all platforms
  - [ ] Arch Linux
  - [ ] FreeBSD
  - [ ] Chimera Linux

### Important (Should Have)
- [ ] Add more file operation tests
- [ ] Improve error messages
- [ ] Add logging system
- [ ] Create example scripts

### Nice to Have
- [ ] Shell completion (bash, zsh, fish)
- [ ] Man page
- [ ] Performance benchmarks
- [ ] Memory leak detection

## v0.2 - GUI Foundation

### Core GUI
- [ ] Install and setup DVUI
- [ ] Install and setup SDL3
- [ ] Create basic window
- [ ] Implement event loop
- [ ] Add file list widget

### Navigation
- [ ] Directory navigation
- [ ] Breadcrumb component
- [ ] Back/forward buttons
- [ ] Path input bar

### File Operations
- [ ] File selection
- [ ] Context menu
- [ ] Keyboard shortcuts
- [ ] File operation confirmation dialogs

## v0.3 - Essential Features

### Views
- [ ] List view
- [ ] Icon/grid view
- [ ] View switcher

### Selection
- [ ] Single selection
- [ ] Multi-selection (Ctrl, Shift)
- [ ] Select all (Ctrl+A)
- [ ] Rubber band selection

### Sorting
- [ ] Sort by name
- [ ] Sort by size
- [ ] Sort by date
- [ ] Sort by type
- [ ] Ascending/descending toggle

### Icons
- [ ] Generic file icon
- [ ] Folder icon
- [ ] Document icon
- [ ] Image icon
- [ ] Video icon
- [ ] Audio icon

## v0.4 - Glass Morphism UI

### Visual Effects
- [ ] BlurBackdrop integration
- [ ] Semi-transparent panels
- [ ] Blur shader optimization
- [ ] Shadow effects
- [ ] Border highlights

### Theming
- [ ] Theme system
- [ ] Glass Dark theme
- [ ] Glass Light theme
- [ ] Color customization
- [ ] Theme switcher UI

### Animations
- [ ] Fade in/out
- [ ] Slide animations
- [ ] Scale animations
- [ ] Spring physics (optional)

## v0.5 - Filee Integration

### Conversion Core
- [ ] External tool detection (ImageMagick, FFmpeg)
- [ ] Subprocess management
- [ ] Progress tracking
- [ ] Error handling

### UI
- [ ] Conversion menu
- [ ] Format selector
- [ ] Options panel
- [ ] Progress dialog
- [ ] Donut menu (Filee style)

### Formats
- [ ] Image: PNG, JPEG, WebP, AVIF, GIF
- [ ] PDF: PDF to images, images to PDF
- [ ] Video: Basic format conversion
- [ ] Presets: Web, Print, Archive

## v0.6 - Advanced Features

### Thumbnails
- [ ] Thumbnail cache
- [ ] Image thumbnail generation
- [ ] Video thumbnail generation
- [ ] PDF thumbnail generation
- [ ] Cache management

### Preview
- [ ] Preview panel
- [ ] Image preview
- [ ] Text file preview
- [ ] PDF preview
- [ ] Video metadata display

### Search
- [ ] Name filter
- [ ] Extension filter
- [ ] Incremental search
- [ ] Search history

### Tabs
- [ ] Tab bar
- [ ] New tab
- [ ] Close tab
- [ ] Tab switching (Ctrl+Tab)
- [ ] Drag tab to reorder

### Dual Pane
- [ ] Split view
- [ ] Sync scrolling (optional)
- [ ] Copy between panes

## v0.7 - Window Transparency

### Compositor Integration
- [ ] Detect Wayland compositor
- [ ] Detect X11 compositor
- [ ] Wayland protocol: ext-background-effect-v1
- [ ] Fallback to opaque window

### Platform Support
- [ ] KDE Plasma
- [ ] GNOME
- [ ] Sway
- [ ] Other compositors (best effort)

### Performance
- [ ] Optimize blur for transparency
- [ ] GPU acceleration (Vulkan)
- [ ] Frame rate monitoring

## v1.0 - Release

### WebAssembly
- [ ] Port core to WASM
- [ ] Browser file access API
- [ ] WASM UI (DVUI Web backend)
- [ ] Limited conversion support

### Packaging
- [ ] Arch Linux AUR package
- [ ] FreeBSD port
- [ ] Chimera Linux cports
- [ ] AppImage (optional)
- [ ] Flatpak (optional)

### Documentation
- [ ] User manual
- [ ] Tutorial videos
- [ ] Screenshots
- [ ] Website
- [ ] Release notes

### Polish
- [ ] All tests passing
- [ ] No known critical bugs
- [ ] Performance goals met
- [ ] Code cleanup
- [ ] Final review

## Future Ideas (Post-1.0)

### Advanced Features
- [ ] Cloud integration (SFTP, WebDAV)
- [ ] Archive support (ZIP, TAR, 7z)
- [ ] Batch rename
- [ ] Advanced search (content, regex)
- [ ] File watchers
- [ ] Git integration

### Plugin System
- [ ] Lua scripting API
- [ ] Custom file viewers
- [ ] Custom converters
- [ ] Extension marketplace

### Performance
- [ ] Lazy loading
- [ ] Virtual scrolling
- [ ] Streaming operations
- [ ] Multi-threading

### Accessibility
- [ ] Screen reader support
- [ ] High contrast mode
- [ ] Keyboard-only navigation
- [ ] Localization (i18n)

---

## How to Use This TODO

1. **Pick a task** from the current version section
2. **Create a branch**: `git checkout -b feature/task-name`
3. **Implement and test** the feature
4. **Submit a PR** with description
5. **Mark as done** with `[x]` when merged

**Priority:**  
Critical > Important > Nice to Have

**Status:**
- [ ] Not started
- [x] Complete
- 🚧 In progress (add emoji in commit messages)
