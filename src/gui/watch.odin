package main

// Directory change notifications (inotify on Linux, kqueue on FreeBSD) and a wake-up
// pipe for worker threads. Both are file descriptors polled by plat_wait, so the UI
// still sleeps when nothing happens.

import "core:strings"
import "core:sys/posix"

watch_fd: posix.FD = -1
watched: map[string]int // path -> wd (Linux) or open dir fd (FreeBSD)
wake_fds: [2]posix.FD = {-1, -1}

@(private = "file")
set_nonblock :: proc(fd: posix.FD) {
	posix.fcntl(fd, .SETFL, posix.fcntl(fd, .GETFL) | posix.O_NONBLOCK)
}

watch_init :: proc() {
	if posix.pipe(&wake_fds) == .OK {
		set_nonblock(wake_fds[0])
		set_nonblock(wake_fds[1])
	}
	watch_fd = _watch_open()
}

// Fds for plat_wait to poll.
watch_fds :: proc() -> []posix.FD {
	@(static) buf: [2]posix.FD
	n := 0
	if watch_fd >= 0 {buf[n] = watch_fd; n += 1}
	if wake_fds[0] >= 0 {buf[n] = wake_fds[0]; n += 1}
	return buf[:n]
}

// Called from worker threads: makes the main loop run.
wake :: proc "contextless" () {
	b: u8 = 1
	posix.write(wake_fds[1], &b, 1)
}

// Watches exactly these directories (adds new ones, drops the rest).
watch_set :: proc(paths: []string) {
	if watch_fd < 0 do return
	want := make(map[string]bool, context.temp_allocator)
	for p in paths do if p != "" do want[p] = true
	drop := make([dynamic]string, context.temp_allocator)
	for p in watched do if p not_in want do append(&drop, p)
	for p in drop {
		_watch_remove(watched[p])
		k := p
		delete_key(&watched, p)
		delete(k)
	}
	for p in want {
		if p in watched do continue
		if id, ok := _watch_add(strings.clone_to_cstring(p, context.temp_allocator)); ok do watched[strings.clone(p)] = id
	}
}

watch_mark :: proc(changed: ^[dynamic]string, id: int) {
	for p, v in watched do if v == id {
		for c in changed do if c == p do return
		append(changed, p)
		return
	}
}

// Drains notifications; returns the watched directories that changed.
watch_poll :: proc() -> [dynamic]string {
	changed := make([dynamic]string, context.temp_allocator)
	// drain the wake pipe too (threads only need the loop to run)
	junk: [64]u8
	if wake_fds[0] >= 0 do for posix.read(wake_fds[0], &junk[0], len(junk)) > 0 {}
	if watch_fd < 0 do return changed
	_watch_drain(&changed)
	return changed
}
