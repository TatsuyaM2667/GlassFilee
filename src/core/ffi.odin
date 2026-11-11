package gfcore

import "base:runtime"
import "core:c"

// ============================================================================
// C ABI FFI Interface
// All exported functions use C calling convention for Zig interop
// ============================================================================

@(export, link_name = "gf_list_dir")
gf_list_dir :: proc "c" (
	path: cstring,
	out_files: [^]FileInfo,
	out_count: ^c.int,
	max_count: c.int,
) -> OperationStatus {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if path == nil || out_files == nil || out_count == nil {
		return .ErrorInvalidPath
	}

	path_str := string(path)
	files, status := list_directory(path_str)
	if status != .Success {
		return status
	}

	count := min(len(files), int(max_count))
	for i := 0; i < count; i += 1 {
		out_files[i] = files[i]
	}

	out_count^ = c.int(count)
	return .Success
}

@(export, link_name = "gf_copy")
gf_copy :: proc "c" (src: cstring, dst: cstring) -> OperationStatus {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if src == nil || dst == nil {
		return .ErrorInvalidPath
	}

	return copy_file(string(src), string(dst))
}

@(export, link_name = "gf_move")
gf_move :: proc "c" (src: cstring, dst: cstring) -> OperationStatus {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if src == nil || dst == nil {
		return .ErrorInvalidPath
	}

	return move_file(string(src), string(dst))
}

@(export, link_name = "gf_delete")
gf_delete :: proc "c" (path: cstring) -> OperationStatus {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if path == nil {
		return .ErrorInvalidPath
	}

	return delete_path(string(path))
}

@(export, link_name = "gf_rename")
gf_rename :: proc "c" (old_path: cstring, new_path: cstring) -> OperationStatus {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if old_path == nil || new_path == nil {
		return .ErrorInvalidPath
	}

	return rename_path(string(old_path), string(new_path))
}

@(export, link_name = "gf_mkdir")
gf_mkdir :: proc "c" (path: cstring) -> OperationStatus {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if path == nil {
		return .ErrorInvalidPath
	}

	return create_directory(string(path))
}

@(export, link_name = "gf_exists")
gf_exists :: proc "c" (path: cstring) -> c.bool {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if path == nil {
		return false
	}

	return path_exists(string(path))
}

@(export, link_name = "gf_stat")
gf_stat :: proc "c" (path: cstring, out_info: ^FileInfo) -> OperationStatus {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if path == nil || out_info == nil {
		return .ErrorInvalidPath
	}

	info, status := get_file_info(string(path))
	if status != .Success {
		return status
	}

	out_info^ = info
	return .Success
}

@(export, link_name = "gf_init")
gf_init :: proc "c" () {
	// Initialization placeholder
}

@(export, link_name = "gf_cleanup")
gf_cleanup :: proc "c" () {
	// Cleanup placeholder
}
