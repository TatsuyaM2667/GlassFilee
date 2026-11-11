package gfcore

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

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
