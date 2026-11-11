package main

// Direct Wayland client: wl_shm software buffers, xdg-shell window, xkbcommon
// keyboard, text-input-v3 (IME), wayland-cursor. No toolkit, no GPU context.

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import "core:sys/posix"
import "core:time"

foreign import wlc "system:wayland-client"
foreign import wlcur "system:wayland-cursor"
foreign import xkbc "system:xkbcommon"

wl_message :: struct {
	name:      cstring,
	signature: cstring,
	types:     [^]^wl_interface,
}
wl_interface :: struct {
	name:         cstring,
	version:      c.int,
	method_count: c.int,
	methods:      [^]wl_message,
	event_count:  c.int,
	events:       [^]wl_message,
}
wl_array :: struct {
	size, alloc: c.size_t,
	data:        rawptr,
}
wl_argument :: struct #raw_union {
	i: i32,
	u: u32,
	s: cstring,
	o: rawptr,
	a: ^wl_array,
}
Proxy :: rawptr
Dispatcher :: #type proc "c" (impl: rawptr, target: rawptr, opcode: u32, msg: ^wl_message, args: [^]wl_argument) -> c.int

wl_cursor_image :: struct {
	width, height, hotspot_x, hotspot_y, delay: u32,
}
wl_cursor :: struct {
	image_count: u32,
	images:      [^]^wl_cursor_image,
	name:        cstring,
}

@(default_calling_convention = "c")
foreign wlc {
	wl_compositor_interface: wl_interface
	wl_surface_interface:    wl_interface
	wl_shm_interface:        wl_interface
	wl_shm_pool_interface:   wl_interface
	wl_buffer_interface:     wl_interface
	wl_seat_interface:       wl_interface
	wl_pointer_interface:    wl_interface
	wl_keyboard_interface:   wl_interface
	wl_registry_interface:   wl_interface
	wl_callback_interface:   wl_interface
	wl_data_device_manager_interface: wl_interface
	wl_data_device_interface: wl_interface
	wl_data_source_interface: wl_interface
	wl_data_offer_interface:  wl_interface

	wl_display_connect :: proc(name: cstring) -> Proxy ---
	wl_display_get_fd :: proc(d: Proxy) -> c.int ---
	wl_display_roundtrip :: proc(d: Proxy) -> c.int ---
	wl_display_dispatch_pending :: proc(d: Proxy) -> c.int ---
	wl_display_prepare_read :: proc(d: Proxy) -> c.int ---
	wl_display_read_events :: proc(d: Proxy) -> c.int ---
	wl_display_cancel_read :: proc(d: Proxy) ---
	wl_display_flush :: proc(d: Proxy) -> c.int ---
	wl_proxy_marshal_flags :: proc(p: Proxy, opcode: u32, iface: ^wl_interface, version: u32, flags: u32, #c_vararg args: ..any) -> Proxy ---
	wl_proxy_add_dispatcher :: proc(p: Proxy, f: Dispatcher, impl: rawptr, data: rawptr) -> c.int ---
	wl_proxy_get_version :: proc(p: Proxy) -> u32 ---
	wl_proxy_get_user_data :: proc(p: Proxy) -> rawptr ---
}

@(default_calling_convention = "c")
foreign wlcur {
	wl_cursor_theme_load :: proc(name: cstring, size: c.int, shm: Proxy) -> rawptr ---
	wl_cursor_theme_get_cursor :: proc(theme: rawptr, name: cstring) -> ^wl_cursor ---
	wl_cursor_image_get_buffer :: proc(img: ^wl_cursor_image) -> Proxy ---
}

@(default_calling_convention = "c")
foreign xkbc {
	xkb_context_new :: proc(flags: c.int) -> rawptr ---
	xkb_keymap_new_from_string :: proc(ctx: rawptr, s: cstring, format: c.int, flags: c.int) -> rawptr ---
	xkb_keymap_unref :: proc(km: rawptr) ---
	xkb_keymap_key_repeats :: proc(km: rawptr, key: u32) -> c.int ---
	xkb_state_new :: proc(km: rawptr) -> rawptr ---
	xkb_state_unref :: proc(st: rawptr) ---
	xkb_state_update_mask :: proc(st: rawptr, dep, lat, lock, dep_l, lat_l, lock_l: u32) -> c.int ---
	xkb_state_key_get_one_sym :: proc(st: rawptr, key: u32) -> u32 ---
	xkb_state_key_get_utf8 :: proc(st: rawptr, key: u32, buf: [^]u8, size: c.size_t) -> c.int ---
	xkb_state_mod_name_is_active :: proc(st: rawptr, name: cstring, type: c.int) -> c.int ---
}

// xkb keysyms used by the app
K_BACKSPACE :: 0xff08
K_TAB :: 0xff09
K_ISO_LEFT_TAB :: 0xfe20
K_PAGEUP :: 0xff55
K_PAGEDOWN :: 0xff56
K_T :: 't'
K_E :: 'e'
K_SPACE :: ' '
K_RETURN :: 0xff0d
K_ESCAPE :: 0xff1b
K_DELETE :: 0xffff
K_HOME :: 0xff50
K_LEFT :: 0xff51
K_UP :: 0xff52
K_RIGHT :: 0xff53
K_DOWN :: 0xff54
K_END :: 0xff57
K_MENU :: 0xff67
K_KP_ENTER :: 0xff8d
K_F2 :: 0xffbf
K_F3 :: 0xffc0
K_F5 :: 0xffc2
K_F10 :: 0xffc7
K_A :: 'a'
K_C :: 'c'
K_F :: 'f'
K_H :: 'h'
K_L :: 'l'
K_N :: 'n'
K_Q :: 'q'
K_R :: 'r'
K_V :: 'v'
K_W :: 'w'
K_X :: 'x'
K_Z :: 'z'
K_D :: 'd'
K_I :: 'i'
K_1 :: '1'
K_2 :: '2'

Mod :: enum {
	Ctrl, Shift, Alt,
}
Mods :: bit_set[Mod]

Ev_Kind :: enum {
	None, Quit, Motion, Down, Up, Wheel, Key, Text, Preedit, Focus,
	Dnd_Motion, Dnd_Leave, Dnd_Drop, Drag_End, // drag-and-drop (Dnd_Drop: text = paths, button = 1 copy / 2 move)
}
Ev :: struct {
	kind:   Ev_Kind,
	x, y:   f32, // surface-local, logical px
	button: u8, // 1 left, 2 middle, 3 right
	clicks: u8,
	wheel:  f32,
	key:    u32, // keysym, letters lowercased
	mods:   Mods,
	text:   string, // heap, freed by consumer
}

Edge :: enum u32 {
	Top = 1, Bottom = 2, Left = 4, Top_Left = 5, Bottom_Left = 6, Right = 8, Top_Right = 9, Bottom_Right = 10,
}

Shm_Buf :: struct {
	proxy: Proxy,
	busy:  bool,
	px:    [^]u32,
}

@(private = "file")
W :: struct {
	display, registry, compositor, shm, seat, wm: Proxy,
	ti_mgr, ti:                                   Proxy,
	surface, xsurface, toplevel:                  Proxy,
	pointer, keyboard:                            Proxy,
	cursor_theme:                                 rawptr,
	cursor_surface:                               Proxy,
	xkb_ctx, keymap, xkb_state:                   rawptr,
	mods:                                         Mods,
	// window
	width, height:                                i32, // logical
	scale:                                        i32,
	configured, closed:                           bool,
	redraw:                                       bool, // size/scale/configure changed
	frame_cb:                                     Proxy, // pending wl_surface.frame callback
	frame_cb_ms:                                  i64,
	// buffers
	pool:                                         Proxy,
	pool_fd:                                      posix.FD,
	// clipboard
	ddm, ddev:                                    Proxy,
	source:                                       Proxy, // our selection while we own it
	source_payload:                               [3]string, // gnome, uri-list, text
	sel_offer:                                    Proxy,
	offer_mimes:                                  map[Proxy]u8, // 1 gnome-copied-files, 2 text/uri-list
	dnd_offer:                                    Proxy, // offer currently dragged over us
	dnd_action:                                   u32,
	drag_source:                                  Proxy, // our own drag in progress
	drag_payload:                                 [3]string,
	drag_paths:                                   string, // newline separated, for drops onto ourselves
	pool_mem:                                     rawptr,
	pool_size:                                    int,
	buf_w, buf_h:                                 i32,
	bufs:                                         [2]Shm_Buf,
	// input
	px, py:                                       f32,
	serial:                                       u32,
	last_click_ms:                                i64,
	last_click_btn:                               u8,
	last_click_x, last_click_y:                   f32,
	clicks:                                       u8,
	wheel:                                        f32,
	repeat_key:                                   u32,
	repeat_rate, repeat_delay:                    i32,
	repeat_next:                                  i64,
	// text input
	ti_on, ti_entered:                            bool,
	ti_rect:                                      [4]i32,
	ti_pre, ti_commit:                            string,
}
@(private = "file") w: W

events: [dynamic]Ev

@(private = "file") start_tick: time.Tick

ticks_ms :: proc() -> i64 {
	return i64(time.duration_milliseconds(time.tick_since(start_tick)))
}

// ---------------------------------------------------------------------------
// xdg-shell + text-input-v3 interface tables (not exported by libwayland)

@(private = "file") null_types: [8]^wl_interface
@(private = "file") xdg_wm_base_iface, xdg_surface_iface, xdg_toplevel_iface, xdg_positioner_iface, xdg_popup_iface: wl_interface
@(private = "file") ti_mgr_iface, ti_iface: wl_interface
@(private = "file") wm_req: [4]wl_message
@(private = "file") wm_ev: [1]wl_message
@(private = "file") xs_req: [5]wl_message
@(private = "file") xs_ev: [1]wl_message
@(private = "file") tl_req: [14]wl_message
@(private = "file") tl_ev: [2]wl_message
@(private = "file") tim_req: [2]wl_message
@(private = "file") ti_req: [8]wl_message
@(private = "file") ti_ev: [6]wl_message

@(private = "file")
msgs :: proc(dst: []wl_message, defs: []string) {
	for d, i in defs {
		name, _, sig := strings.partition(d, ":")
		dst[i] = {strings.clone_to_cstring(name), strings.clone_to_cstring(sig), &null_types[0]}
	}
}

@(private = "file")
iface :: proc(i: ^wl_interface, name: cstring, req: []wl_message, ev: []wl_message) {
	i^ = {name, 1, c.int(len(req)), raw_data(req), c.int(len(ev)), raw_data(ev)}
}

@(private = "file")
init_ifaces :: proc() {
	msgs(wm_req[:], {"destroy:", "create_positioner:n", "get_xdg_surface:no", "pong:u"})
	msgs(wm_ev[:], {"ping:u"})
	msgs(xs_req[:], {"destroy:", "get_toplevel:n", "get_popup:n?oo", "set_window_geometry:iiii", "ack_configure:u"})
	msgs(xs_ev[:], {"configure:u"})
	msgs(tl_req[:], {
		"destroy:", "set_parent:?o", "set_title:s", "set_app_id:s", "show_window_menu:ouii", "move:ou", "resize:ouu",
		"set_max_size:ii", "set_min_size:ii", "set_maximized:", "unset_maximized:", "set_fullscreen:?o", "unset_fullscreen:", "set_minimized:",
	})
	msgs(tl_ev[:], {"configure:iia", "close:"})
	msgs(tim_req[:], {"destroy:", "get_text_input:no"})
	msgs(ti_req[:], {"destroy:", "enable:", "disable:", "set_surrounding_text:sii", "set_text_change_cause:u", "set_content_type:uu", "set_cursor_rectangle:iiii", "commit:"})
	msgs(ti_ev[:], {"enter:o", "leave:o", "preedit_string:?sii", "commit_string:?s", "delete_surrounding_text:uu", "done:u"})
	iface(&xdg_wm_base_iface, "xdg_wm_base", wm_req[:], wm_ev[:])
	iface(&xdg_surface_iface, "xdg_surface", xs_req[:], xs_ev[:])
	iface(&xdg_toplevel_iface, "xdg_toplevel", tl_req[:], tl_ev[:])
	iface(&xdg_positioner_iface, "xdg_positioner", nil, nil)
	iface(&xdg_popup_iface, "xdg_popup", nil, nil)
	iface(&ti_mgr_iface, "zwp_text_input_manager_v3", tim_req[:], nil)
	iface(&ti_iface, "zwp_text_input_v3", ti_req[:], ti_ev[:])
}

@(private = "file")
listen :: proc(p: Proxy, f: Dispatcher, data: rawptr = nil) {
	@(static) dummy: int
	wl_proxy_add_dispatcher(p, f, &dummy, data)
}

@(private = "file")
ver :: proc "contextless" (p: Proxy) -> u32 {return wl_proxy_get_version(p)}

// ---------------------------------------------------------------------------
// Dispatchers

@(private = "file")
on_registry :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	context = runtime.default_context()
	if op != 0 do return 0
	name, ifname, v := a[0].u, string(a[1].s), a[2].u
	bind :: proc(name: u32, i: ^wl_interface, v: u32) -> Proxy {
		return wl_proxy_marshal_flags(w.registry, 0, i, v, 0, name, i.name, v, rawptr(nil))
	}
	switch ifname {
	case "wl_compositor": w.compositor = bind(name, &wl_compositor_interface, min(v, 6))
	case "wl_shm":        w.shm = bind(name, &wl_shm_interface, 1)
	case "wl_seat":
		w.seat = bind(name, &wl_seat_interface, min(v, 5))
		listen(w.seat, on_seat)
	case "xdg_wm_base":
		w.wm = bind(name, &xdg_wm_base_iface, 1)
		listen(w.wm, on_wm)
	case "zwp_text_input_manager_v3":
		w.ti_mgr = bind(name, &ti_mgr_iface, 1)
	case "wl_data_device_manager":
		w.ddm = bind(name, &wl_data_device_manager_interface, min(v, 3))
	}
	return 0
}

@(private = "file")
on_wm :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	if op == 0 do wl_proxy_marshal_flags(w.wm, 3, nil, ver(w.wm), 0, a[0].u) // pong
	return 0
}

@(private = "file")
on_xsurface :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	if op == 0 {
		wl_proxy_marshal_flags(w.xsurface, 4, nil, ver(w.xsurface), 0, a[0].u) // ack_configure
		w.configured, w.redraw = true, true
	}
	return 0
}

@(private = "file")
on_toplevel :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	switch op {
	case 0:
		if a[0].i > 0 && a[1].i > 0 do w.width, w.height = a[0].i, a[1].i
	case 1:
		w.closed = true
	}
	return 0
}

@(private = "file")
on_surface :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	if op == 2 && a[0].i > 0 && a[0].i != w.scale { // preferred_buffer_scale
		w.scale, w.redraw = a[0].i, true
	}
	return 0
}

@(private = "file")
on_buffer :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	b := (^Shm_Buf)(wl_proxy_get_user_data(target))
	if op == 0 && b != nil do b.busy = false
	return 0
}

@(private = "file")
on_frame_done :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	if target == w.frame_cb do w.frame_cb = nil // the callback object is destroyed by the server
	return 0
}

// True when the compositor is ready for a new frame (throttles redraws to the refresh rate).
// A callback older than 100 ms is treated as lost: some compositors hold it back while
// a resize (e.g. starting an interactive move) waits for our new-size buffer.
plat_can_draw :: proc() -> bool {return w.frame_cb == nil || ticks_ms() - w.frame_cb_ms > 100}

@(private = "file")
on_seat :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	context = runtime.default_context()
	if op != 0 do return 0
	caps := a[0].u
	if caps & 1 != 0 && w.pointer == nil {
		w.pointer = wl_proxy_marshal_flags(w.seat, 0, &wl_pointer_interface, ver(w.seat), 0, rawptr(nil))
		listen(w.pointer, on_pointer)
	}
	if caps & 2 != 0 && w.keyboard == nil {
		w.keyboard = wl_proxy_marshal_flags(w.seat, 1, &wl_keyboard_interface, ver(w.seat), 0, rawptr(nil))
		listen(w.keyboard, on_keyboard)
	}
	return 0
}

@(private = "file")
set_cursor :: proc(serial: u32) {
	if w.cursor_theme == nil || w.pointer == nil do return
	cur := wl_cursor_theme_get_cursor(w.cursor_theme, "default")
	if cur == nil do cur = wl_cursor_theme_get_cursor(w.cursor_theme, "left_ptr")
	if cur == nil || cur.image_count == 0 do return
	img := cur.images[0]
	buf := wl_cursor_image_get_buffer(img)
	if w.cursor_surface == nil do w.cursor_surface = wl_proxy_marshal_flags(w.compositor, 0, &wl_surface_interface, ver(w.compositor), 0, rawptr(nil))
	cs := w.cursor_surface
	s := max(w.scale, 1)
	if ver(cs) >= 3 do wl_proxy_marshal_flags(cs, 8, nil, ver(cs), 0, i32(s))
	wl_proxy_marshal_flags(cs, 1, nil, ver(cs), 0, buf, i32(0), i32(0))
	wl_proxy_marshal_flags(cs, 2, nil, ver(cs), 0, i32(0), i32(0), i32(img.width), i32(img.height))
	wl_proxy_marshal_flags(cs, 6, nil, ver(cs), 0)
	wl_proxy_marshal_flags(w.pointer, 0, nil, ver(w.pointer), 0, serial, cs, i32(img.hotspot_x) / s, i32(img.hotspot_y) / s)
}

@(private = "file")
on_pointer :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	context = runtime.default_context()
	switch op {
	case 0: // enter
		w.px, w.py = f32(a[2].i) / 256, f32(a[3].i) / 256
		set_cursor(a[0].u)
		append(&events, Ev{kind = .Motion, x = w.px, y = w.py, mods = w.mods})
	case 1: // leave
		append(&events, Ev{kind = .Motion, x = -1, y = -1, mods = w.mods})
	case 2: // motion
		w.px, w.py = f32(a[1].i) / 256, f32(a[2].i) / 256
		append(&events, Ev{kind = .Motion, x = w.px, y = w.py, mods = w.mods})
	case 3: // button
		w.serial = a[0].u
		btn: u8
		switch a[2].u {
		case 0x110: btn = 1
		case 0x111: btn = 3
		case 0x112: btn = 2
		case: return 0
		}
		if a[3].u == 1 {
			now := ticks_ms()
			if btn == w.last_click_btn && now - w.last_click_ms < 400 && abs(w.px - w.last_click_x) < 5 && abs(w.py - w.last_click_y) < 5 {
				w.clicks += 1
			} else do w.clicks = 1
			w.last_click_ms, w.last_click_btn, w.last_click_x, w.last_click_y = now, btn, w.px, w.py
			append(&events, Ev{kind = .Down, x = w.px, y = w.py, button = btn, clicks = w.clicks, mods = w.mods})
		} else {
			append(&events, Ev{kind = .Up, x = w.px, y = w.py, button = btn, mods = w.mods})
		}
	case 4: // axis
		if a[1].u == 0 do w.wheel += f32(a[2].i) / 256
	case 5: // frame
		if w.wheel != 0 {
			append(&events, Ev{kind = .Wheel, x = w.px, y = w.py, wheel = -w.wheel / 10, mods = w.mods})
			w.wheel = 0
		}
	}
	return 0
}

@(private = "file")
emit_key :: proc(code: u32) {
	if w.xkb_state == nil do return
	sym := xkb_state_key_get_one_sym(w.xkb_state, code + 8)
	if sym >= 'A' && sym <= 'Z' do sym += 32
	ev := Ev{kind = .Key, key = sym, mods = w.mods}
	if w.mods & {.Ctrl, .Alt} == {} {
		buf: [16]u8
		n := xkb_state_key_get_utf8(w.xkb_state, code + 8, &buf[0], len(buf))
		if n > 0 && buf[0] >= 0x20 && buf[0] != 0x7f do ev.text = strings.clone(string(buf[:n]))
	}
	append(&events, ev)
}

@(private = "file")
on_keyboard :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	context = runtime.default_context()
	switch op {
	case 0: // keymap
		fd := posix.FD(a[1].i)
		size := uint(a[2].u)
		defer posix.close(fd)
		if a[0].u != 1 do return 0
		mem := posix.mmap(nil, size, {.READ}, {.PRIVATE}, fd, 0)
		if mem == posix.MAP_FAILED do return 0
		defer posix.munmap(mem, size)
		if w.xkb_ctx == nil do w.xkb_ctx = xkb_context_new(0)
		km := xkb_keymap_new_from_string(w.xkb_ctx, cstring(mem), 1, 0)
		if km == nil do return 0
		if w.xkb_state != nil do xkb_state_unref(w.xkb_state)
		if w.keymap != nil do xkb_keymap_unref(w.keymap)
		w.keymap, w.xkb_state = km, xkb_state_new(km)
	case 1: // enter
		append(&events, Ev{kind = .Focus})
	case 2: // leave
		w.repeat_key = 0
	case 3: // key
		w.serial = a[0].u
		code := a[2].u
		if a[3].u == 1 {
			emit_key(code)
			if w.keymap != nil && xkb_keymap_key_repeats(w.keymap, code + 8) != 0 && w.repeat_rate > 0 {
				w.repeat_key = code
				w.repeat_next = ticks_ms() + i64(w.repeat_delay)
			}
		} else if code == w.repeat_key {
			w.repeat_key = 0
		}
	case 4: // modifiers
		if w.xkb_state == nil do return 0
		xkb_state_update_mask(w.xkb_state, a[1].u, a[2].u, a[3].u, 0, 0, a[4].u)
		w.mods = {}
		EFFECTIVE :: 8
		if xkb_state_mod_name_is_active(w.xkb_state, "Control", EFFECTIVE) > 0 do w.mods += {.Ctrl}
		if xkb_state_mod_name_is_active(w.xkb_state, "Shift", EFFECTIVE) > 0 do w.mods += {.Shift}
		if xkb_state_mod_name_is_active(w.xkb_state, "Mod1", EFFECTIVE) > 0 do w.mods += {.Alt}
	case 5: // repeat_info
		w.repeat_rate, w.repeat_delay = a[0].i, a[1].i
	}
	return 0
}

@(private = "file")
on_text_input :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	context = runtime.default_context()
	switch op {
	case 0: // enter
		w.ti_entered = true
		if w.ti_on do ti_send(true)
	case 1:
		w.ti_entered = false
	case 2: // preedit_string
		delete(w.ti_pre)
		w.ti_pre = strings.clone(string(a[0].s)) if a[0].s != nil else ""
	case 3: // commit_string
		delete(w.ti_commit)
		w.ti_commit = strings.clone(string(a[0].s)) if a[0].s != nil else ""
	case 5: // done
		append(&events, Ev{kind = .Preedit, text = w.ti_pre})
		w.ti_pre = ""
		if w.ti_commit != "" do append(&events, Ev{kind = .Text, text = w.ti_commit})
		w.ti_commit = ""
	}
	return 0
}

@(private = "file")
ti_send :: proc(enable: bool) {
	t := w.ti
	if enable {
		wl_proxy_marshal_flags(t, 1, nil, ver(t), 0)
		wl_proxy_marshal_flags(t, 6, nil, ver(t), 0, w.ti_rect[0], w.ti_rect[1], w.ti_rect[2], w.ti_rect[3])
	} else {
		wl_proxy_marshal_flags(t, 2, nil, ver(t), 0)
	}
	wl_proxy_marshal_flags(t, 7, nil, ver(t), 0)
}

// ---------------------------------------------------------------------------
// Public API

plat_init :: proc(title, app_id: string, width, height: i32) -> bool {
	start_tick = time.tick_now()
	init_ifaces()
	w.display = wl_display_connect(nil)
	if w.display == nil do return false
	w.registry = wl_proxy_marshal_flags(w.display, 1, &wl_registry_interface, ver(w.display), 0, rawptr(nil))
	listen(w.registry, on_registry)
	wl_display_roundtrip(w.display)
	if w.compositor == nil || w.shm == nil || w.wm == nil do return false
	wl_display_roundtrip(w.display) // seat capabilities, keymap

	w.width, w.height, w.scale = width, height, 1
	w.surface = wl_proxy_marshal_flags(w.compositor, 0, &wl_surface_interface, ver(w.compositor), 0, rawptr(nil))
	listen(w.surface, on_surface)
	w.xsurface = wl_proxy_marshal_flags(w.wm, 2, &xdg_surface_iface, ver(w.wm), 0, rawptr(nil), w.surface)
	listen(w.xsurface, on_xsurface)
	w.toplevel = wl_proxy_marshal_flags(w.xsurface, 1, &xdg_toplevel_iface, ver(w.xsurface), 0, rawptr(nil))
	listen(w.toplevel, on_toplevel)
	plat_set_title(title)
	wl_proxy_marshal_flags(w.toplevel, 3, nil, 1, 0, strings.clone_to_cstring(app_id, context.temp_allocator))
	wl_proxy_marshal_flags(w.toplevel, 8, nil, 1, 0, i32(360), i32(300)) // min size
	wl_proxy_marshal_flags(w.surface, 6, nil, ver(w.surface), 0) // commit
	for !w.configured {
		if wl_display_roundtrip(w.display) < 0 do return false
	}

	if w.ti_mgr != nil && w.seat != nil {
		w.ti = wl_proxy_marshal_flags(w.ti_mgr, 1, &ti_iface, 1, 0, rawptr(nil), w.seat)
		listen(w.ti, on_text_input)
	}
	size: c.int = 24
	if s := posix.getenv("XCURSOR_SIZE"); s != nil {
		if v := c.int(libc_atoi(s)); v > 0 do size = v
	}
	w.cursor_theme = wl_cursor_theme_load(posix.getenv("XCURSOR_THEME"), size, w.shm)
	if w.ddm != nil && w.seat != nil {
		w.ddev = wl_proxy_marshal_flags(w.ddm, 1, &wl_data_device_interface, ver(w.ddm), 0, rawptr(nil), w.seat)
		listen(w.ddev, on_data_device)
	}
	return true
}

// ---------------------------------------------------------------------------
// Clipboard (files, interoperable with GNOME/KDE/browsers)

@(private = "file")
on_data_device :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	context = runtime.default_context()
	switch op {
	case 0: // data_offer: new wl_data_offer, its mime types follow
		if a[0].o != nil {
			w.offer_mimes[a[0].o] = 0
			listen(a[0].o, on_offer)
		}
	case 1: // enter(serial, surface, x, y, offer): a drag reached our window
		o := a[4].o
		if o == nil do return 0
		if w.offer_mimes[o] & 3 == 0 {
			drop_offer(o) // not files
			return 0
		}
		w.dnd_offer, w.dnd_action = o, 0
		mime: cstring = "text/uri-list" if w.offer_mimes[o] & 2 != 0 else "x-special/gnome-copied-files"
		wl_proxy_marshal_flags(o, 0, nil, ver(o), 0, a[0].u, mime) // accept
		if ver(o) >= 3 {
			// copy | move; moving is the natural default for drags between our own panes
			wl_proxy_marshal_flags(o, 4, nil, ver(o), 0, u32(3), u32(2) if w.drag_source != nil else u32(1))
		}
		append(&events, Ev{kind = .Dnd_Motion, x = f32(a[2].i) / 256, y = f32(a[3].i) / 256, mods = w.mods})
	case 2: // leave
		if w.dnd_offer != nil {
			drop_offer(w.dnd_offer)
			w.dnd_offer = nil
		}
		append(&events, Ev{kind = .Dnd_Leave})
	case 3: // motion(time, x, y)
		append(&events, Ev{kind = .Dnd_Motion, x = f32(a[1].i) / 256, y = f32(a[2].i) / 256, mods = w.mods})
	case 4: // drop
		o := w.dnd_offer
		if o == nil do return 0
		paths: string
		if w.drag_source != nil {
			paths = strings.clone(w.drag_paths) // our own drag: no need to go through a pipe
		} else {
			list, _, _ := receive_paths(o, context.temp_allocator)
			paths = strings.join(list[:], "\n")
		}
		action := w.dnd_action if w.dnd_action != 0 else 1
		if ver(o) >= 3 do wl_proxy_marshal_flags(o, 3, nil, ver(o), 0) // finish
		drop_offer(o)
		w.dnd_offer = nil
		append(&events, Ev{kind = .Dnd_Drop, text = paths, button = u8(action)})
	case 5: // selection
		if w.sel_offer != nil && w.sel_offer != a[0].o do drop_offer(w.sel_offer)
		w.sel_offer = a[0].o
	}
	return 0
}

@(private = "file")
drop_offer :: proc(o: Proxy) {
	delete_key(&w.offer_mimes, o)
	wl_proxy_marshal_flags(o, 2, nil, ver(o), 1) // destroy (WL_MARSHAL_FLAG_DESTROY)
}

@(private = "file")
on_offer :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	context = runtime.default_context()
	if op == 0 {
		switch string(a[0].s) {
		case "x-special/gnome-copied-files": w.offer_mimes[target] |= 1
		case "text/uri-list":                w.offer_mimes[target] |= 2
		}
	}
	if op == 2 && target == w.dnd_offer do w.dnd_action = a[0].u // action chosen by the compositor (modifiers)
	return 0
}

@(private = "file")
on_source :: proc "c" (impl, target: rawptr, op: u32, msg: ^wl_message, a: [^]wl_argument) -> c.int {
	context = runtime.default_context()
	switch op {
	case 1: // send(mime, fd)
		fd := posix.FD(a[1].i)
		pl := &w.drag_payload if target == w.drag_source else &w.source_payload
		data := pl[2]
		switch string(a[0].s) {
		case "x-special/gnome-copied-files": data = pl[0]
		case "text/uri-list":                data = pl[1]
		}
		for len(data) > 0 {
			n := posix.write(fd, raw_data(data), len(data))
			if n <= 0 do break
			data = data[n:]
		}
		posix.close(fd)
	case 2, 4: // cancelled (clipboard taken / drag aborted), dnd_finished
		if target == w.source do w.source = nil
		if target == w.drag_source {
			w.drag_source = nil
			append(&events, Ev{kind = .Drag_End})
		}
		wl_proxy_marshal_flags(target, 1, nil, ver(target), 1)
	}
	return 0
}

file_uri :: proc(path: string, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "file://")
	for i in 0 ..< len(path) {
		ch := path[i]
		switch ch {
		case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '-', '.', '_', '~', '/':
			strings.write_byte(&b, ch)
		case:
			fmt.sbprintf(&b, "%%%02X", ch)
		}
	}
	return strings.to_string(b)
}

@(private = "file")
make_payload :: proc(paths: []string, cut: bool) -> [3]string {
	gnome := strings.builder_make()
	uris := strings.builder_make()
	text := strings.builder_make()
	strings.write_string(&gnome, "cut" if cut else "copy")
	for p, i in paths {
		u := file_uri(p)
		strings.write_byte(&gnome, '\n')
		strings.write_string(&gnome, u)
		fmt.sbprintf(&uris, "%s\r\n", u)
		if i > 0 do strings.write_byte(&text, '\n')
		strings.write_string(&text, p)
	}
	return {strings.to_string(gnome), strings.to_string(uris), strings.to_string(text)}
}

@(private = "file")
new_source :: proc() -> Proxy {
	src := wl_proxy_marshal_flags(w.ddm, 0, &wl_data_source_interface, ver(w.ddm), 0, rawptr(nil))
	listen(src, on_source)
	for m in ([]cstring{"x-special/gnome-copied-files", "text/uri-list", "text/plain;charset=utf-8", "UTF8_STRING"}) {
		wl_proxy_marshal_flags(src, 0, nil, ver(src), 0, m)
	}
	return src
}

// Starts dragging files out of the window (other apps, our folders, the other pane).
plat_start_drag :: proc(paths: []string) {
	if w.ddm == nil || w.ddev == nil || w.drag_source != nil || len(paths) == 0 do return
	for s in w.drag_payload do delete(s)
	delete(w.drag_paths)
	w.drag_payload = make_payload(paths, false)
	w.drag_paths = strings.join(paths, "\n")
	src := new_source()
	if ver(src) >= 3 do wl_proxy_marshal_flags(src, 2, nil, ver(src), 0, u32(3)) // copy | move
	wl_proxy_marshal_flags(w.ddev, 0, nil, ver(w.ddev), 0, src, w.surface, rawptr(nil), w.serial)
	w.drag_source = src
}

// Publishes files to the system clipboard (copy or cut).
plat_set_clipboard_files :: proc(paths: []string, cut: bool) {
	if w.ddm == nil || w.ddev == nil do return
	for s in w.source_payload do delete(s)
	w.source_payload = make_payload(paths, cut)
	src := wl_proxy_marshal_flags(w.ddm, 0, &wl_data_source_interface, ver(w.ddm), 0, rawptr(nil))
	listen(src, on_source)
	for m in ([]cstring{"x-special/gnome-copied-files", "text/uri-list", "text/plain;charset=utf-8", "UTF8_STRING"}) {
		wl_proxy_marshal_flags(src, 0, nil, ver(src), 0, m)
	}
	wl_proxy_marshal_flags(w.ddev, 1, nil, ver(w.ddev), 0, src, w.serial)
	w.source = src
}

// True while the clipboard holds what we put there (use the in-app copy then).
plat_clipboard_is_ours :: proc() -> bool {return w.source != nil}

// Reads files from another app's clipboard. ok=false if it holds no files.
plat_get_clipboard_files :: proc(allocator := context.temp_allocator) -> (paths: [dynamic]string, cut, ok: bool) {
	o := w.sel_offer
	if o == nil || w.source != nil do return
	m := w.offer_mimes[o]
	if m == 0 do return
	return receive_paths(o, allocator)
}

// Reads file paths offered by another app (gnome-copied-files or uri-list).
@(private = "file")
receive_paths :: proc(o: Proxy, allocator: runtime.Allocator) -> (paths: [dynamic]string, cut, ok: bool) {
	m := w.offer_mimes[o]
	mime: cstring = "x-special/gnome-copied-files" if m & 1 != 0 else "text/uri-list"
	fds: [2]posix.FD
	if posix.pipe(&fds) != .OK do return
	wl_proxy_marshal_flags(o, 1, nil, ver(o), 0, mime, i32(fds[1]))
	posix.close(fds[1])
	wl_display_flush(w.display)
	data := make([dynamic]u8, context.temp_allocator)
	buf: [4096]u8
	for {
		pfd := posix.pollfd{fd = fds[0], events = {.IN}}
		if posix.poll(&pfd, 1, 1000) <= 0 do break // the other app didn't answer in time
		n := posix.read(fds[0], &buf[0], len(buf))
		if n <= 0 do break
		append(&data, ..buf[:n])
	}
	posix.close(fds[0])
	paths = make([dynamic]string, allocator)
	for line in strings.split_lines(string(data[:]), context.temp_allocator) {
		l := strings.trim_space(line)
		if l == "cut" do cut = true
		if !strings.has_prefix(l, "file://") do continue
		p := l[7:]
		if i := strings.index_byte(p, '/'); i > 0 do p = p[i:] // file://host/path
		append(&paths, url_decode(p, allocator))
	}
	return paths, cut, len(paths) > 0
}

@(private = "file")
url_decode :: proc(s: string, allocator: runtime.Allocator) -> string {
	b := strings.builder_make(allocator)
	hexv :: proc(c: u8) -> int {
		switch c {
		case '0' ..= '9': return int(c - '0')
		case 'a' ..= 'f': return int(c - 'a' + 10)
		case 'A' ..= 'F': return int(c - 'A' + 10)
		}
		return -1
	}
	for i := 0; i < len(s); i += 1 {
		if s[i] == '%' && i + 2 < len(s) && hexv(s[i + 1]) >= 0 && hexv(s[i + 2]) >= 0 {
			strings.write_byte(&b, u8(hexv(s[i + 1]) * 16 + hexv(s[i + 2])))
			i += 2
		} else do strings.write_byte(&b, s[i])
	}
	return strings.to_string(b)
}

@(private = "file")
libc_atoi :: proc(s: cstring) -> int {
	n := 0
	for ch in string(s) {
		if ch < '0' || ch > '9' do break
		n = n * 10 + int(ch - '0')
	}
	return n
}

plat_set_title :: proc(title: string) {
	wl_proxy_marshal_flags(w.toplevel, 2, nil, 1, 0, strings.clone_to_cstring(title, context.temp_allocator))
}

plat_scale :: proc() -> i32 {return max(w.scale, 1)}

plat_closed :: proc() -> bool {return w.closed}

@(private = "file")
make_pool :: proc(bw, bh: i32) -> bool {
	for &b in w.bufs {
		if b.proxy != nil do wl_proxy_marshal_flags(b.proxy, 0, nil, 1, 0) // destroy
		b = {}
	}
	if w.pool != nil {
		wl_proxy_marshal_flags(w.pool, 1, nil, 1, 0)
		posix.munmap(w.pool_mem, uint(w.pool_size))
		posix.close(w.pool_fd)
		w.pool = nil
	}
	stride := bw * 4
	one := int(stride * bh)
	w.pool_size = one * 2
	// POSIX shm (Linux + FreeBSD): create, unlink right away, keep only the fd
	name := strings.clone_to_cstring(fmt.tprintf("/ame-filemanager-%d-%d", posix.getpid(), ticks_ms()), context.temp_allocator)
	fd := posix.shm_open(name, {.RDWR, .CREAT, .EXCL, .CLOEXEC}, {.IRUSR, .IWUSR})
	if fd < 0 do return false
	posix.shm_unlink(name)
	if posix.ftruncate(fd, posix.off_t(w.pool_size)) != .OK {
		posix.close(fd)
		return false
	}
	mem := posix.mmap(nil, uint(w.pool_size), {.READ, .WRITE}, {.SHARED}, fd, 0)
	if mem == posix.MAP_FAILED {
		posix.close(fd)
		return false
	}
	w.pool_fd, w.pool_mem = fd, mem
	w.pool = wl_proxy_marshal_flags(w.shm, 0, &wl_shm_pool_interface, 1, 0, rawptr(nil), i32(fd), i32(w.pool_size))
	for &b, i in w.bufs {
		b.proxy = wl_proxy_marshal_flags(w.pool, 0, &wl_buffer_interface, 1, 0, rawptr(nil), i32(i * one), bw, bh, stride, u32(0))
		b.px = ([^]u32)(uintptr(mem) + uintptr(i * one))
		listen(b.proxy, on_buffer, &b)
	}
	w.buf_w, w.buf_h = bw, bh
	return true
}

// Returns a free buffer to draw into (nil if both are still held by the compositor).
plat_begin :: proc() -> (buf: ^Shm_Buf, bw, bh: i32) {
	s := max(w.scale, 1)
	bw, bh = w.width * s, w.height * s
	if bw != w.buf_w || bh != w.buf_h {
		if !make_pool(bw, bh) do return nil, 0, 0
	}
	for &b in w.bufs do if !b.busy do return &b, bw, bh
	return nil, bw, bh
}

plat_present :: proc(b: ^Shm_Buf) {
	s := w.surface
	if ver(s) >= 3 do wl_proxy_marshal_flags(s, 8, nil, ver(s), 0, max(w.scale, 1))
	wl_proxy_marshal_flags(s, 1, nil, ver(s), 0, b.proxy, i32(0), i32(0))
	if ver(s) >= 4 do wl_proxy_marshal_flags(s, 9, nil, ver(s), 0, i32(0), i32(0), w.buf_w, w.buf_h)
	else do wl_proxy_marshal_flags(s, 2, nil, ver(s), 0, i32(0), i32(0), w.width, w.height)
	w.frame_cb = wl_proxy_marshal_flags(s, 3, &wl_callback_interface, ver(s), 0, rawptr(nil))
	w.frame_cb_ms = ticks_ms()
	listen(w.frame_cb, on_frame_done)
	wl_proxy_marshal_flags(s, 6, nil, ver(s), 0)
	b.busy = true
}

plat_move :: proc() {
	if w.seat != nil do wl_proxy_marshal_flags(w.toplevel, 5, nil, 1, 0, w.seat, w.serial)
}

plat_resize :: proc(e: Edge) {
	if w.seat != nil do wl_proxy_marshal_flags(w.toplevel, 6, nil, 1, 0, w.seat, w.serial, u32(e))
}

// Enable the IME with the caret rectangle in logical px (or disable it).
plat_text_input :: proc(on: bool, rect: [4]i32) {
	if w.ti == nil do return
	if on == w.ti_on && (!on || rect == w.ti_rect) do return
	w.ti_on, w.ti_rect = on, rect
	if w.ti_entered do ti_send(on)
}

// Waits up to timeout_ms (-1 = forever) for input and fills `events`.
// redraw: the window was configured/rescaled; timed_out: nothing arrived in time.
// Protocol traffic like buffer releases wakes us but sets neither.
plat_wait :: proc(timeout_ms: int, extra: []posix.FD = nil) -> (alive, redraw, timed_out: bool) {
	d := w.display
	for wl_display_prepare_read(d) != 0 do wl_display_dispatch_pending(d)
	wl_display_flush(d)
	if len(events) > 0 || w.redraw {
		wl_display_cancel_read(d)
		redraw, w.redraw = w.redraw, false
		return true, redraw, false
	}
	t := timeout_ms
	if w.repeat_key != 0 {
		dt := int(max(w.repeat_next - ticks_ms(), 0))
		t = dt if t < 0 else min(t, dt)
	}
	// display fd + extra fds (directory watcher, worker wake-up pipe)
	pfds: [8]posix.pollfd
	pfds[0] = {fd = posix.FD(wl_display_get_fd(d)), events = {.IN}}
	n := 1
	for fd in extra {
		if n == len(pfds) do break
		pfds[n] = {fd = fd, events = {.IN}}
		n += 1
	}
	r := posix.poll(&pfds[0], posix.nfds_t(n), c.int(t))
	if r > 0 && .IN in pfds[0].revents {
		if wl_display_read_events(d) < 0 do return false, false, false
	} else {
		wl_display_cancel_read(d)
		timed_out = r <= 0
	}
	if wl_display_dispatch_pending(d) < 0 do return false, false, false
	if w.repeat_key != 0 && ticks_ms() >= w.repeat_next {
		emit_key(w.repeat_key)
		w.repeat_next = ticks_ms() + i64(1000 / max(w.repeat_rate, 1))
		timed_out = false
	}
	redraw, w.redraw = w.redraw, false
	return true, redraw, timed_out
}

