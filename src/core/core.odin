package gfcore

import "core:c/libc"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"

// ============================================================================
// Core Types
// ============================================================================

FileType :: enum u8 {
	Unknown   = 0,
	Regular   = 1,
	Directory = 2,
	Symlink   = 3,
}

FileInfo :: struct {
	name:      [256]u8,
	name_len:  u32,
	path:      [1024]u8,
	path_len:  u32,
	size:      i64,
	modified:  i64,
	file_type: FileType,
	is_hidden: bool,
}

OperationStatus :: enum i32 {
	Success          = 0,
	ErrorNotFound    = -1,
	ErrorPermission  = -2,
	ErrorExists      = -3,
	ErrorIO          = -4,
	ErrorInvalidPath = -5,
	Cancelled        = -6,
	ErrorUnknown     = -100,
}

// ============================================================================
// Internal Helpers
// ============================================================================

file_info_from_os :: proc(path: string, info: os.File_Info) -> FileInfo {
	fi: FileInfo
	mem.zero_slice(fi.name[:])
	mem.zero_slice(fi.path[:])

	name := filepath.base(path)
	name_len := min(len(name), len(fi.name))
	mem.copy(&fi.name[0], raw_data(name), name_len)
	fi.name_len = u32(name_len)

	path_len := min(len(path), len(fi.path))
	mem.copy(&fi.path[0], raw_data(path), path_len)
	fi.path_len = u32(path_len)

	fi.size = info.size
	fi.modified = info.modification_time._nsec

	// Check if directory using type field
	#partial switch info.type {
	case .Directory:
		fi.file_type = .Directory
	case .Symlink:
		fi.file_type = .Symlink
	case .Regular:
		fi.file_type = .Regular
	case:
		fi.file_type = .Unknown
	}

	fi.is_hidden = len(name) > 0 && name[0] == '.'

	return fi
}

// ============================================================================
// Core File Operations
// ============================================================================

list_directory :: proc(path: string) -> ([]FileInfo, OperationStatus) {
	context.allocator = context.temp_allocator

	handle, err := os.open(path, os.O_RDONLY)
	if err != nil {
		return nil, .ErrorNotFound
	}
	defer os.close(handle)

	file_infos, read_err := os.read_dir(handle, -1, context.allocator)
	if read_err != nil {
		return nil, .ErrorIO
	}
	defer os.file_info_slice_delete(file_infos, context.allocator)

	results := make([]FileInfo, len(file_infos))
	for info, i in file_infos {
		full_path, join_err := filepath.join({path, info.name}, context.temp_allocator)
		if join_err != nil {
			continue
		}
		results[i] = file_info_from_os(full_path, info)
	}

	return results, .Success
}

copy_file :: proc(src: string, dst: string) -> OperationStatus {
	if path_exists(dst) {
		return .ErrorExists
	}
	context.allocator = context.temp_allocator
	info, stat_err := os.stat(src, context.allocator)
	if stat_err != nil {
		return .ErrorNotFound
	}
	err := os.copy_directory_all(dst, src) if info.type == .Directory else os.copy_file(dst, src)
	if err != nil {
		return .ErrorIO
	}
	return .Success
}

move_file :: proc(src: string, dst: string) -> OperationStatus {
	err := os.rename(src, dst)
	if err != nil {
		// cross-device: copy then delete
		copy_status := copy_file(src, dst)
		if copy_status != .Success {
			return copy_status
		}

		del_err := os.remove_all(src)
		if del_err != nil {
			return .ErrorIO
		}
	}

	return .Success
}

// Recursive: callers (CLI prompt, GUI dialog) confirm first.
delete_path :: proc(path: string) -> OperationStatus {
	context.allocator = context.temp_allocator
	info, stat_err := os.lstat(path, context.allocator)
	if stat_err != nil {
		return .ErrorNotFound
	}
	// remove_all would follow a symlink to a dir and empty its target
	err := os.remove(path) if info.type == .Symlink else os.remove_all(path)
	if err != nil {
		return .ErrorPermission
	}
	return .Success
}

rename_path :: proc(old_path: string, new_path: string) -> OperationStatus {
	err := os.rename(old_path, new_path)
	if err != nil {
		return .ErrorIO
	}
	return .Success
}

create_directory :: proc(path: string) -> OperationStatus {
	err := os.make_directory(path)
	if err != nil {
		return .ErrorExists
	}
	return .Success
}

path_exists :: proc(path: string) -> bool {
	context.allocator = context.temp_allocator
	_, err := os.stat(path, context.allocator)
	return err == nil
}

get_file_info :: proc(path: string) -> (FileInfo, OperationStatus) {
	context.allocator = context.temp_allocator

	info, err := os.stat(path, context.allocator)
	if err != nil {
		return {}, .ErrorNotFound
	}

	fi := file_info_from_os(path, info)
	return fi, .Success
}

// ============================================================================
// Trash (freedesktop.org Trash spec, same layout GNOME Files uses)
// ============================================================================

// Returns $XDG_DATA_HOME/Trash (usually ~/.local/share/Trash).
trash_dir :: proc(allocator := context.allocator) -> string {
	data, err := os.user_data_dir(context.temp_allocator)
	if err != nil {
		return ""
	}
	dir, _ := filepath.join({data, "Trash"}, allocator)
	return dir
}

@(private)
url_escape :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< len(s) {
		ch := s[i]
		switch ch {
		case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '-', '.', '_', '~', '/':
			strings.write_byte(&b, ch)
		case:
			fmt.sbprintf(&b, "%%%02X", ch)
		}
	}
	return strings.to_string(b)
}

@(private)
url_unescape :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	hex :: proc(c: u8) -> int {
		switch c {
		case '0' ..= '9': return int(c - '0')
		case 'a' ..= 'f': return int(c - 'a' + 10)
		case 'A' ..= 'F': return int(c - 'A' + 10)
		}
		return -1
	}
	for i := 0; i < len(s); i += 1 {
		if s[i] == '%' && i + 2 < len(s) && hex(s[i + 1]) >= 0 && hex(s[i + 2]) >= 0 {
			strings.write_byte(&b, u8(hex(s[i + 1]) * 16 + hex(s[i + 2])))
			i += 2
		} else {
			strings.write_byte(&b, s[i])
		}
	}
	return strings.to_string(b)
}

// Moves path into the trash, writing the matching .trashinfo.
trash_path :: proc(path: string) -> OperationStatus {
	st, _ := trash_path_named(path)
	return st
}

// Like trash_path, also returning the name inside Trash/files (temp-allocated) for undo.
trash_path_named :: proc(path: string) -> (OperationStatus, string) {
	context.allocator = context.temp_allocator
	td := trash_dir()
	if td == "" {
		return .ErrorIO, ""
	}
	files, _ := filepath.join({td, "files"})
	info, _ := filepath.join({td, "info"})
	os.make_directory_all(files)
	os.make_directory_all(info)

	abs, abs_err := os.get_absolute_path(path, context.allocator)
	if abs_err != nil || !path_exists(abs) {
		return .ErrorNotFound, ""
	}
	base := filepath.base(abs)
	name := base
	for i := 2; ; i += 1 {
		f, _ := filepath.join({files, name})
		n, _ := filepath.join({info, strings.concatenate({name, ".trashinfo"})})
		if !path_exists(f) && !path_exists(n) {
			break
		}
		name = fmt.tprintf("%s.%d", base, i)
	}

	now := libc.time(nil)
	t := libc.localtime(&now)
	content := fmt.tprintf(
		"[Trash Info]\nPath=%s\nDeletionDate=%04d-%02d-%02dT%02d:%02d:%02d\n",
		url_escape(abs), t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec,
	)
	info_path, _ := filepath.join({info, strings.concatenate({name, ".trashinfo"})})
	if os.write_entire_file_from_string(info_path, content) != nil {
		return .ErrorPermission, ""
	}
	dst, _ := filepath.join({files, name})
	if os.rename(abs, dst) != nil {
		// shortcut: no per-volume trash; files on other filesystems can't be trashed (delete instead)
		os.remove(info_path)
		return .ErrorIO, ""
	}
	return .Success, name
}

// Puts a trashed item (name inside Trash/files) back where it came from.
restore_from_trash :: proc(name: string) -> OperationStatus {
	context.allocator = context.temp_allocator
	td := trash_dir()
	info_path, _ := filepath.join({td, "info", strings.concatenate({name, ".trashinfo"})})
	data, err := os.read_entire_file_from_path(info_path, context.allocator)
	if err != nil {
		return .ErrorNotFound
	}
	orig := ""
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		if strings.has_prefix(line, "Path=") {
			orig = url_unescape(line[5:])
		}
	}
	if orig == "" {
		return .ErrorInvalidPath
	}
	if path_exists(orig) {
		return .ErrorExists
	}
	os.make_directory_all(filepath.dir(orig))
	src, _ := filepath.join({td, "files", name})
	if os.rename(src, orig) != nil {
		return .ErrorIO
	}
	os.remove(info_path)
	return .Success
}

// Permanently deletes one trashed item and its .trashinfo.
delete_from_trash :: proc(name: string) -> OperationStatus {
	context.allocator = context.temp_allocator
	td := trash_dir()
	src, _ := filepath.join({td, "files", name})
	status := delete_path(src)
	info_path, _ := filepath.join({td, "info", strings.concatenate({name, ".trashinfo"})})
	os.remove(info_path)
	return status
}

empty_trash :: proc() -> OperationStatus {
	context.allocator = context.temp_allocator
	td := trash_dir()
	files, _ := filepath.join({td, "files"})
	infos, err := os.read_all_directory_by_path(files, context.allocator)
	if err != nil {
		return .Success
	}
	result := OperationStatus.Success
	for fi in infos {
		if delete_from_trash(fi.name) != .Success {
			result = .ErrorPermission
		}
	}
	return result
}

// ============================================================================
// Copy with progress and cancellation (used by the GUI's background operations)
// ============================================================================

// Shared with a worker thread: read/write the fields with sync atomics.
Progress :: struct {
	total, done: i64,
	cancel:      bool,
}

// Total bytes under path (symlinks are not followed).
tree_size :: proc(path: string, p: ^Progress = nil) -> i64 {
	context.allocator = context.temp_allocator
	info, err := os.lstat(path, context.allocator)
	if err != nil do return 0
	if info.type != .Directory do return info.size
	infos, rerr := os.read_all_directory_by_path(path, context.allocator)
	if rerr != nil do return 0
	n: i64
	for fi in infos {
		if p != nil && sync.atomic_load(&p.cancel) do return n
		n += tree_size(fi.fullpath, p)
	}
	return n
}

// Recursively copies src to dst (dst must not exist), streaming file data so
// progress can be reported and the copy cancelled between chunks.
copy_tree :: proc(src, dst: string, p: ^Progress) -> OperationStatus {
	if sync.atomic_load(&p.cancel) do return .Cancelled
	info, err := os.lstat(src, context.temp_allocator)
	if err != nil do return .ErrorNotFound
	if path_exists(dst) do return .ErrorExists
	#partial switch info.type {
	case .Directory:
		if os.make_directory(dst) != nil do return .ErrorPermission
		os.change_mode(dst, info.mode)
		infos, rerr := os.read_all_directory_by_path(src, context.temp_allocator)
		if rerr != nil do return .ErrorPermission
		for fi in infos {
			d, _ := filepath.join({dst, fi.name}, context.temp_allocator)
			if st := copy_tree(fi.fullpath, d, p); st != .Success do return st
		}
		return .Success
	case .Symlink:
		target, lerr := os.read_link(src, context.temp_allocator)
		if lerr != nil || os.symlink(target, dst) != nil do return .ErrorIO
		return .Success
	}
	in_f, oerr := os.open(src)
	if oerr != nil do return .ErrorPermission
	defer os.close(in_f)
	out_f, cerr := os.open(dst, {.Write, .Create, .Excl, .Trunc}, info.mode)
	if cerr != nil do return .ErrorPermission
	buf := make([]byte, 1 << 20, context.temp_allocator)
	for {
		if sync.atomic_load(&p.cancel) {
			os.close(out_f)
			os.remove(dst) // drop the half-written file only
			return .Cancelled
		}
		n, rerr := os.read(in_f, buf)
		if n > 0 {
			if w, werr := os.write(out_f, buf[:n]); werr != nil || w != n {
				os.close(out_f)
				os.remove(dst)
				return .ErrorIO
			}
			sync.atomic_add(&p.done, i64(n))
		}
		if rerr != nil || n == 0 do break
	}
	os.close(out_f)
	return .Success
}
