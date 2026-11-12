package main

import "core:sys/linux"
import "core:sys/posix"

_watch_open :: proc() -> posix.FD {
	fd, err := linux.inotify_init1({.NONBLOCK, .CLOEXEC})
	return posix.FD(fd) if err == .NONE else -1
}

_watch_add :: proc(path: cstring) -> (int, bool) {
	mask := linux.Inotify_Event_Mask{.CREATE, .DELETE, .MOVED_FROM, .MOVED_TO, .CLOSE_WRITE, .ATTRIB, .DELETE_SELF, .MOVE_SELF, .ONLYDIR}
	wd, err := linux.inotify_add_watch(linux.Fd(watch_fd), path, mask)
	return int(wd), err == .NONE
}

_watch_remove :: proc(id: int) {
	linux.inotify_rm_watch(linux.Fd(watch_fd), linux.Wd(id))
}

_watch_drain :: proc(changed: ^[dynamic]string) {
	buf: [8192]u8 = ---
	for {
		n := posix.read(watch_fd, &buf[0], len(buf))
		if n <= 0 do break
		off := 0
		for off + size_of(linux.Inotify_Event) <= int(n) {
			ev := (^linux.Inotify_Event)(&buf[off])
			// hidden files nobody is looking at (e.g. apps rewriting ~/.something) don't need a reload
			hidden := ev.len > 0 && buf[off + size_of(linux.Inotify_Event)] == '.'
			if !hidden || app.show_hidden do watch_mark(changed, int(ev.wd))
			off += size_of(linux.Inotify_Event) + int(ev.len)
		}
	}
}
