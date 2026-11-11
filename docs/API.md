# GlassFilee API Documentation

## Core Layer (Odin)

The core layer provides low-level file system operations through a C ABI.

### Types

#### FileType
```odin
FileType :: enum u8 {
    Unknown = 0,
    Regular = 1,
    Directory = 2,
    Symlink = 3,
}
```

#### FileInfo
```odin
FileInfo :: struct {
    name:       [256]u8,     // Fixed-size buffer for name
    name_len:   u32,         // Actual name length
    path:       [1024]u8,    // Fixed-size buffer for path
    path_len:   u32,         // Actual path length
    size:       i64,         // File size in bytes
    modified:   i64,         // Modification time (nanoseconds)
    file_type:  FileType,    // Type of file
    is_hidden:  bool,        // Hidden file flag
}
```

#### OperationStatus
```odin
OperationStatus :: enum i32 {
    Success = 0,
    ErrorNotFound = -1,
    ErrorPermission = -2,
    ErrorExists = -3,
    ErrorIO = -4,
    ErrorInvalidPath = -5,
    ErrorUnknown = -100,
}
```

### C ABI Functions

#### gf_init
```c
void gf_init(void);
```
Initialize the core library. Must be called before any other functions.

#### gf_cleanup
```c
void gf_cleanup(void);
```
Cleanup and release resources.

#### gf_list_dir
```c
OperationStatus gf_list_dir(
    const char* path,
    FileInfo* out_files,
    int* out_count,
    int max_count
);
```
List directory contents.

**Parameters:**
- `path`: Directory path (null-terminated)
- `out_files`: Output buffer for file info (caller-allocated)
- `out_count`: Output parameter for actual count
- `max_count`: Maximum number of entries to return

**Returns:** Operation status

#### gf_copy
```c
OperationStatus gf_copy(const char* src, const char* dst);
```
Copy file from source to destination.

#### gf_move
```c
OperationStatus gf_move(const char* src, const char* dst);
```
Move/rename file from source to destination.

#### gf_delete
```c
OperationStatus gf_delete(const char* path);
```
Delete file or directory.

#### gf_rename
```c
OperationStatus gf_rename(const char* old_path, const char* new_path);
```
Rename file or directory.

#### gf_mkdir
```c
OperationStatus gf_mkdir(const char* path);
```
Create directory.

#### gf_exists
```c
bool gf_exists(const char* path);
```
Check if path exists.

#### gf_stat
```c
OperationStatus gf_stat(const char* path, FileInfo* out_info);
```
Get file information.

---

## Zig Bindings

Safe Zig wrappers around the C ABI.

### Functions

#### init
```zig
pub fn init() void
```
Initialize core library.

#### cleanup
```zig
pub fn cleanup() void
```
Cleanup resources.

#### listDir
```zig
pub fn listDir(allocator: Allocator, path: []const u8) ![]FileInfo
```
List directory contents. Returns owned slice (caller must free).

**Example:**
```zig
const files = try core.listDir(allocator, "/home/user");
defer allocator.free(files);

for (files) |file| {
    std.debug.print("{s}\n", .{file.getName()});
}
```

#### copy
```zig
pub fn copy(path: []const u8, src: []const u8, dst: []const u8) !void
```
Copy file.

#### move
```zig
pub fn move(src: []const u8, dst: []const u8) !void
```
Move file.

#### delete
```zig
pub fn delete(path: []const u8) !void
```
Delete file or directory.

#### rename
```zig
pub fn rename(old_path: []const u8, new_path: []const u8) !void
```
Rename file or directory.

#### mkdir
```zig
pub fn mkdir(path: []const u8) !void
```
Create directory.

#### exists
```zig
pub fn exists(path: []const u8) !bool
```
Check if path exists.

#### stat
```zig
pub fn stat(path: []const u8) !FileInfo
```
Get file information.

### FileInfo Methods

#### getName
```zig
pub fn getName(self: *const FileInfo) []const u8
```
Get file name as slice.

#### getPath
```zig
pub fn getPath(self: *const FileInfo) []const u8
```
Get full path as slice.

---

## Error Handling

All Zig wrapper functions return Zig errors:

```zig
const FileError = error{
    NotFound,
    PermissionDenied,
    AlreadyExists,
    IoError,
    InvalidPath,
    Unknown,
};
```

**Usage:**
```zig
const info = core.stat("/some/path") catch |err| {
    std.debug.print("Error: {}\n", .{err});
    return;
};
```

---

## Thread Safety

⚠️ **Current Implementation:** Not thread-safe

The core layer uses Odin's default context, which is not thread-safe by default.

**Future:** Thread-safe version will use:
- Per-thread contexts in Odin
- Mutex protection for shared state
- Async I/O for GUI responsiveness

---

## Platform-Specific Notes

### Linux
- Uses standard POSIX APIs
- XDG Base Directory specification for config
- Hidden files: starts with `.`

### FreeBSD
- Same as Linux, uses POSIX APIs
- Native endianness handling

### Chimera Linux (musl)
- Fully compatible with glibc-based Linux
- Static linking supported

### WebAssembly (future)
- Limited file system access
- Uses File System Access API
- Async operations only

---

## Performance Characteristics

### listDir
- **Time Complexity:** O(n) where n is number of files
- **Memory:** Allocates array of FileInfo structs
- **Notes:** Reads entire directory at once (not streaming)

### copy
- **Time Complexity:** O(n) where n is file size
- **Memory:** Reads entire file into memory
- **Notes:** Not suitable for very large files (>1GB)

### move
- **Time Complexity:** O(1) if same filesystem, O(n) otherwise
- **Memory:** Minimal if rename, full file size if cross-filesystem
- **Notes:** Tries rename first, falls back to copy+delete

---

## Future API (v0.2+)

### Async Operations
```zig
pub fn copyAsync(
    allocator: Allocator,
    src: []const u8,
    dst: []const u8,
    progress: *fn(u64, u64) void,
) !AsyncHandle
```

### Streaming
```zig
pub fn openStream(path: []const u8) !FileStream
```

### Batch Operations
```zig
pub fn copyBatch(operations: []CopyOp) ![]OperationResult
```

### Conversion
```zig
pub fn convert(
    src: []const u8,
    dst_format: Format,
    options: ConvertOptions,
) !void
```
