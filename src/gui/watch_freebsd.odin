package main

import "core:sys/kqueue"
import "core:sys/posix"

_watch_open :: proc() -> posix.FD {
	kq, err := kqueue.kqueue()
	return kq if err == .NONE else -1
}

_watch_add :: proc(path: cstring) -> (int, bool) {
	fd := posix.open(path, {.DIRECTORY, .CLOEXEC}) // O_RDONLY is 0
	if fd < 0 do return 0, false
	ev := kqueue.KEvent{ident = uintptr(fd), filter = .VNode, flags = {.Add, .Clear}}
	ev.fflags.vnode = {.Write, .Delete, .Rename}
	if _, err := kqueue.kevent(watch_fd, {ev}, nil, nil); err != .NONE {
		posix.close(fd)
		return 0, false
	}
	return int(fd), true
}

_watch_remove :: proc(id: int) {
	posix.close(posix.FD(id)) // closing the fd drops its kevent
}

_watch_drain :: proc(changed: ^[dynamic]string) {
	evs: [16]kqueue.KEvent
	zero: posix.timespec
	for {
		n, err := kqueue.kevent(watch_fd, nil, evs[:], &zero)
		if err != .NONE || n <= 0 do break
		for e in evs[:n] do watch_mark(changed, int(e.ident))
	}
}
