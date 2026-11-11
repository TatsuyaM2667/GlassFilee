package main

// Git status dots: `git status` runs on a worker thread whenever the folder is
// (re)loaded; changed files and the folders containing them get a colored dot.

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"

GIT_MODIFIED :: 1
GIT_UNTRACKED :: 2

@(private = "file")
Git_Req :: struct {
	cwd:    string,
	result: map[string]u8, // first path component (relative to cwd) -> status
	done:   bool,
	th:     ^thread.Thread,
}

@(private = "file") reqs: [dynamic]^Git_Req

@(private = "file")
in_repo :: proc(dir: string) -> bool {
	d := dir
	for {
		g, _ := filepath.join({d, ".git"}, context.temp_allocator)
		if os.exists(g) do return true
		parent := filepath.dir(d)
		if parent == d || d == "" do return false
		d = parent
	}
}

git_refresh :: proc() {
	clear_git(&app.git)
	if !have_tool("git") || app.cwd == "" || !in_repo(app.cwd) do return
	r := new(Git_Req)
	r.cwd = strings.clone(app.cwd)
	r.th = thread.create_and_start_with_poly_data(r, git_worker)
	append(&reqs, r)
}

@(private = "file")
git_worker :: proc(r: ^Git_Req) {
	defer {
		sync.atomic_store(&r.done, true)
		wake()
	}
	_, pre, _, e1 := os.process_exec({command = {"git", "-C", r.cwd, "rev-parse", "--show-prefix"}}, context.temp_allocator)
	if e1 != nil do return
	prefix := strings.trim_space(string(pre))
	_, out, _, e2 := os.process_exec({command = {"git", "-C", r.cwd, "status", "--porcelain=v1", "-z", "--untracked-files=normal", "--ignore-submodules"}}, context.temp_allocator)
	if e2 != nil do return
	fields := strings.split(string(out), "\x00", context.temp_allocator)
	for i := 0; i < len(fields); i += 1 {
		f := fields[i]
		if len(f) < 4 do continue
		xy, path := f[:2], f[3:]
		if xy[0] == 'R' || xy[0] == 'C' do i += 1 // "-z" puts the old name in the next field
		if !strings.has_prefix(path, prefix) do continue
		rel := path[len(prefix):]
		first := rel
		if k := strings.index_byte(rel, '/'); k >= 0 do first = rel[:k]
		if first == "" do continue
		code: u8 = GIT_UNTRACKED if xy == "??" else GIT_MODIFIED
		if old, ok := r.result[first]; ok && old == GIT_MODIFIED do continue
		if first not_in r.result do r.result[strings.clone(first)] = code
		else do r.result[first] = code
	}
	free_all(context.temp_allocator)
}

clear_git :: proc(m: ^map[string]u8) {
	for k in m do delete(k)
	clear(m)
}

// Applies finished results to whichever pane shows that folder.
git_poll :: proc() -> bool {
	got := false
	for i := len(reqs) - 1; i >= 0; i -= 1 {
		r := reqs[i]
		if !sync.atomic_load(&r.done) do continue
		thread.join(r.th)
		thread.destroy(r.th)
		target: ^map[string]u8
		if r.cwd == app.cwd do target = &app.git
		else if app.split && r.cwd == app.other.cwd do target = &app.other.git
		if target != nil {
			clear_git(target)
			delete(target^)
			target^ = r.result
			got = true
		} else {
			clear_git(&r.result)
			delete(r.result)
		}
		delete(r.cwd)
		free(r)
		ordered_remove(&reqs, i)
	}
	return got
}

git_dot :: proc(x, y, r: f32, name: string) {
	if len(app.git) == 0 do return
	first := name
	if k := strings.index_byte(name, '/'); k >= 0 do first = name[:k]
	c, ok := app.git[first]
	if !ok do return
	col := hex(0xfab387) if c == GIT_MODIFIED else hex(0xa6e3a1)
	rrect({x - r, y - r, 2 * r, 2 * r}, r, hex(0x10141f, 230))
	rrect({x - r + px(1.5), y - r + px(1.5), 2 * r - px(3), 2 * r - px(3)}, r, col)
}
