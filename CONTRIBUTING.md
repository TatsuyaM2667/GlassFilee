# Contributing to GlassFilee

Thank you for your interest in contributing! This document provides guidelines and information for contributors.

## Getting Started

1. **Fork the repository**
2. **Clone your fork**
   ```bash
   git clone https://github.com/your-username/AmeFileManger.git
   cd AmeFileManger
   ```

3. **Create a branch**
   ```bash
   git checkout -b feature/my-new-feature
   ```

4. **Build and test**
   ```bash
   make build
   make test
   ```

## Code Structure

```
AmeFileManger/
├── src/
│   ├── core/          # Odin code (file operations)
│   ├── bindings/      # Zig FFI bindings
│   ├── cli/           # CLI application
│   └── gui/           # GUI application
├── tests/             # Integration tests
├── docs/              # Documentation
└── build.zig          # Build configuration
```

## Development Workflow

### 1. Make Changes

**Odin Code (src/core/)**
- Follow Odin naming conventions (snake_case)
- Export C ABI functions with `@(export, link_name="...")`
- Use `"c"` calling convention for exported functions
- Set context in each exported function: `context = get_context()`

**Zig Code (src/bindings/, src/cli/, src/gui/)**
- Follow Zig style guide
- Use `camelCase` for function names
- Use `snake_case` for variables
- Add error handling for all fallible operations

### 2. Test Your Changes

```bash
# Run all tests
zig build test

# Run specific test file
zig test src/core/tests.zig

# Manual testing
./zig-out/bin/gf-cli ls /tmp
```

### 3. Format Code

**Zig:**
```bash
zig fmt src/**/*.zig
```

**Odin:**
```bash
# Use your editor's formatter (no official tool yet)
# Follow style: https://github.com/odin-lang/Odin/wiki/Style-Guide
```

### 4. Commit

Use conventional commits:
```
feat: add thumbnail cache
fix: correct file copy bug on FreeBSD
docs: update building instructions
refactor: simplify FFI boundary
test: add tests for directory operations
```

### 5. Push and Create PR

```bash
git push origin feature/my-new-feature
```

Then create a Pull Request on GitHub.

## Coding Guidelines

### Odin

```odin
// Good
file_info_from_os :: proc(path: string, info: os.File_Info) -> FileInfo {
    // Implementation
}

// Exported for C ABI
@(export, link_name="gf_list_dir")
gf_list_dir :: proc "c" (path: cstring, out: [^]FileInfo, count: ^c.int) -> i32 {
    context = get_context()
    // Implementation
}
```

### Zig

```zig
// Good
pub fn listDir(allocator: Allocator, path: []const u8) ![]FileInfo {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    
    // Implementation
}

// Error handling
const result = operation() catch |err| {
    std.log.err("Operation failed: {}", .{err});
    return err;
};
```

### FFI Boundary

**Rules:**
1. **Fixed-size buffers** for strings (with explicit length)
2. **Caller allocates**, callee writes
3. **No dynamic memory** crosses boundary
4. **C-compatible types** only (no slices, no optionals)
5. **Set Odin context** in every exported function

**Example:**
```odin
// Odin side
FileInfo :: struct {
    name: [256]u8,      // Fixed buffer
    name_len: u32,      // Explicit length
    // ...
}
```

```zig
// Zig side
pub const FileInfo = extern struct {
    name: [256]u8,
    name_len: u32,
    // Must match exactly!
};
```

## Testing

### Unit Tests

Add tests to `src/core/tests.zig`:

```zig
test "my new feature" {
    const allocator = std.testing.allocator;
    
    core.init();
    defer core.cleanup();
    
    // Test implementation
    const result = try core.myFeature(allocator);
    defer allocator.free(result);
    
    try std.testing.expect(result.len > 0);
}
```

### Integration Tests

Add integration tests to `tests/` directory.

### Manual Testing

Test on all target platforms:
- Arch Linux (glibc)
- Chimera Linux (musl)
- FreeBSD

## Documentation

### Code Documentation

**Odin:**
```odin
// List all files in a directory
// Returns slice of FileInfo (caller must free) and operation status
list_directory :: proc(path: string) -> ([]FileInfo, OperationStatus)
```

**Zig:**
```zig
/// List directory contents
/// Caller owns returned slice and must free it
pub fn listDir(allocator: Allocator, path: []const u8) ![]FileInfo
```

### User Documentation

Update relevant docs when adding features:
- `docs/API.md` - API changes
- `docs/ROADMAP.md` - Feature completion
- `README.md` - User-facing changes

## Pull Request Process

1. **Update documentation** if needed
2. **Add tests** for new features
3. **Ensure all tests pass**
4. **Follow code style** (run formatters)
5. **Write clear PR description**:
   - What does this PR do?
   - Why is this change needed?
   - How was it tested?
6. **Link related issues** (#123)

### PR Review

We will review:
- Code quality and style
- Test coverage
- Documentation completeness
- Performance implications
- Cross-platform compatibility

## Bug Reports

### Good Bug Report

```
**Environment:**
- OS: Arch Linux (kernel 6.6)
- Zig version: 0.13.0
- Odin version: dev-2024-11

**Steps to Reproduce:**
1. Run `gf-cli ls /mnt/nfs`
2. Observe error

**Expected:** List files
**Actual:** Crashes with "OperationStatus.ErrorIO"

**Additional context:**
Works fine with local directories, only fails on NFS mount
```

## Feature Requests

Before requesting a feature:
1. Check [ROADMAP.md](docs/ROADMAP.md)
2. Search existing issues
3. Consider implementing it yourself!

## Questions?

- Open a discussion on GitHub
- Check existing documentation
- Ask in pull request comments

## Code of Conduct

- Be respectful and constructive
- Welcome newcomers
- Focus on technical merit
- Keep discussions on-topic

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to GlassFilee! 🎉
