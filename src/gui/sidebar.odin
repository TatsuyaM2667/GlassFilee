package main

// Sidebar: places, bookmarks (shared with GNOME), drives, color tags.

import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"

I_EJECT :: 0xf052
I_BOOKMARK :: 0xf02e
I_USB :: 0xf287

Device :: struct {
	label, path, dev: string, // path = mount point ("" if not mounted), dev = /dev/... (Linux)
}

bookmarks: [dynamic]Place
devices: [dynamic]Device

// ---------------------------------------------------------------------------
// Bookmarks: ~/.config/gtk-3.0/bookmarks ("file:///path Optional label")

@(private = "file")
bookmarks_file :: proc() -> string {
	dir, _ := os.user_config_dir(context.temp_allocator)
	p, _ := filepath.join({dir, "gtk-3.0", "bookmarks"}, context.temp_allocator)
	return p
}

load_bookmarks :: proc() {
	for b in bookmarks {delete(b.label); delete(b.path)}
	clear(&bookmarks)
	data, err := os.read_entire_file_from_path(bookmarks_file(), context.temp_allocator)
	if err != nil do return
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		uri, _, label := strings.partition(line, " ")
		if !strings.has_prefix(uri, "file://") do continue
		path := url_decode_tmp(uri[7:])
		if label == "" do label = filepath.base(path)
		append(&bookmarks, Place{strings.clone(label), I_BOOKMARK, strings.clone(path)})
	}
}

@(private = "file")
save_bookmarks :: proc() {
	b := strings.builder_make(context.temp_allocator)
	for bm in bookmarks {
		strings.write_string(&b, file_uri(bm.path))
		if bm.label != filepath.base(bm.path) {
			strings.write_byte(&b, ' ')
			strings.write_string(&b, bm.label)
		}
		strings.write_byte(&b, '\n')
	}
	p := bookmarks_file()
	_ = os.make_directory_all(filepath.dir(p))
	_ = os.write_entire_file_from_string(p, strings.to_string(b))
}

add_bookmark :: proc(path: string) {
	for b in bookmarks do if b.path == path {
		toastf("既にブックマークにあります")
		return
	}
	append(&bookmarks, Place{strings.clone(filepath.base(path)), I_BOOKMARK, strings.clone(path)})
	save_bookmarks()
	toastf("「%s」をブックマークに追加しました", filepath.base(path))
}

remove_bookmark :: proc(path: string) {
	for b, i in bookmarks do if b.path == path {
		delete(b.label)
		delete(b.path)
		ordered_remove(&bookmarks, i)
		save_bookmarks()
		return
	}
}

url_decode_tmp :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
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

// ---------------------------------------------------------------------------
// Drives: mounted removable media (/run/media, /media, /mnt) + unmounted USB
// partitions from lsblk (Linux). Mounting needs udisks2 (udisksctl).

refresh_devices :: proc() {
	for d in devices {delete(d.label); delete(d.path); delete(d.dev)}
	clear(&devices)
	mounted := make(map[string]string, context.temp_allocator) // dev -> mount point
	if data, err := os.read_entire_file_from_path("/proc/self/mounts", context.temp_allocator); err == nil {
		text := string(data)
		for line in strings.split_lines_iterator(&text) {
			f := strings.fields(line, context.temp_allocator)
			if len(f) < 2 do continue
			mp := strings.replace_all(f[1], "\\040", " ", context.temp_allocator) or_else f[1]
			if strings.has_prefix(mp, "/run/media/") || strings.has_prefix(mp, "/media/") || strings.has_prefix(mp, "/mnt/") {
				mounted[f[0]] = mp
				append(&devices, Device{strings.clone(filepath.base(mp)), strings.clone(mp), strings.clone(f[0])})
			}
		}
	} else {
		// FreeBSD: automounted media show up as directories under /media
		if infos, err2 := os.read_all_directory_by_path("/media", context.temp_allocator); err2 == nil {
			for fi in infos do if fi.type == .Directory do append(&devices, Device{strings.clone(fi.name), strings.clone(fi.fullpath), strings.clone("")})
		}
	}
	if !have_tool("lsblk") do return
	_, out, _, err := os.process_exec({command = {"lsblk", "-J", "-o", "PATH,LABEL,SIZE,RM,HOTPLUG,MOUNTPOINT,FSTYPE,TYPE"}}, context.temp_allocator)
	if err != nil do return
	Dev :: struct {
		path, label, size, mountpoint, fstype, type: Maybe(string),
		rm, hotplug:                                 Maybe(bool),
		children:                                    []Dev,
	}
	Root :: struct {blockdevices: []Dev}
	root: Root
	if json.unmarshal(out, &root, allocator = context.temp_allocator) != nil do return
	walk :: proc(ds: []Dev, mounted: map[string]string, removable: bool) {
		for d in ds {
			rem := removable || (d.rm.? or_else false) || (d.hotplug.? or_else false)
			path := d.path.? or_else ""
			if rem && (d.fstype.? or_else "") != "" && (d.mountpoint.? or_else "") == "" && path not_in mounted {
				label := d.label.? or_else ""
				if label == "" do label = strings.concatenate({d.size.? or_else "", " のボリューム"}, context.temp_allocator)
				append(&devices, Device{strings.clone(label), strings.clone(""), strings.clone(path)})
			}
			walk(d.children, mounted, rem)
		}
	}
	walk(root.blockdevices, mounted, false)
}

mount_device :: proc(d: Device) {
	if !have_tool("udisksctl") {
		toastf("マウントには udisks2（udisksctl）が必要です")
		return
	}
	if pid := spawn({"udisksctl", "mount", "-b", d.dev}); pid != 0 {
		append(&jobs, Job{pid = pid, kind = .Mount, label = strings.clone(d.label)})
		toastf("「%s」をマウントしています…", d.label)
	}
}

eject_device :: proc(d: Device) {
	cmd := []string{"udisksctl", "unmount", "-b", d.dev} if have_tool("udisksctl") && d.dev != "" else []string{"umount", d.path}
	if strings.has_prefix(app.cwd, d.path) do go_to(app.home) // don't keep the drive busy
	if pid := spawn(cmd); pid != 0 {
		append(&jobs, Job{pid = pid, kind = .Mount, label = strings.clone(d.label), dest = strings.clone("eject")})
	}
}

// ---------------------------------------------------------------------------

side_row :: proc(y: ^f32, w: f32, icon: rune, label: string, active: bool, dim := false) -> Rect {
	r := Rect{px(6), y^, w - px(12), px(36)}
	if active do rrect(r, px(6), ACTIVE)
	else if hovering(r) do rrect(r, px(6), HOVER)
	col := with_alpha(FG, 120) if dim else FG
	if icon != 0 do glyph_center({r.x + px(6), r.y, px(28), r.h}, icon, fs(15), col)
	text(r.x + px(42), baseline(r, fs(14)), ellipsize(label, fs(14), r.w - px(80)), fs(14), col, active)
	y^ += px(38)
	return r
}

side_section :: proc(y: ^f32, w: f32, title: string) {
	y^ += px(6)
	fill({px(12), y^, w - px(24), 1}, LINE)
	y^ += px(6)
	if title != "" {
		text(px(18), y^ + px(14), title, fs(12), DIM, true)
		y^ += px(22)
	}
}

side_menu_path: string // sidebar row that opened the context menu

draw_sidebar :: proc(w, H: f32) {
	fill({0, 0, w, H}, hex(0xffffff, 8))
	fill({w, 0, 1, H}, LINE)
	hh := app.header_h
	size := fs(15)
	title := "Ame-FileManager"
	tw := f32(text_width(title, size, true))
	text((w - px(40) - tw) / 2 + px(4), baseline({0, 0, w, hh}, size), title, size, FG, true)
	mb := Rect{w - px(40), px(6.5), px(34), px(34)}
	if icon_button(mb, I_MENU, app.menu_open && app.menu_main) do push(.Main_Menu)

	set_clip({0, hh, w, H - hh})
	defer reset_clip()
	y := hh + px(6)
	nav :: proc(r: Rect, path: string) {
		if clicked(r) do push(.Navigate, 0, path)
		if hovering(r) && app.pressed && app.button == 2 do push(.New_Tab, 0, path)
		if hovering(r) && app.pressed && app.button == 3 {
			menu_tag_id = -1
			delete(side_menu_path)
			side_menu_path = strings.clone(path)
			push(.Side_Menu)
		}
	}
	for p in app.places {
		if p.icon == I_TRASH || p.icon == I_DRIVE do continue
		nav(side_row(&y, w, p.icon, p.label, app.cwd == p.path), p.path)
	}
	if len(bookmarks) > 0 {
		side_section(&y, w, "ブックマーク")
		for b in bookmarks do nav(side_row(&y, w, I_BOOKMARK, b.label, app.cwd == b.path), b.path)
	}
	side_section(&y, w, "")
	for p in app.places {
		if p.icon != I_TRASH && p.icon != I_DRIVE do continue
		nav(side_row(&y, w, p.icon, p.label, app.cwd == p.path), p.path)
	}
	for d in devices {
		r := side_row(&y, w, I_USB, d.label, d.path != "" && app.cwd == d.path, d.path == "")
		if d.path == "" {
			if clicked(r) do mount_device(d)
			continue
		}
		er := Rect{r.x + r.w - px(32), r.y + px(4), px(28), r.h - px(8)}
		if hovering(er) do rrect(er, px(6), HOVER)
		glyph_center(er, I_EJECT, fs(13), DIM)
		if clicked(er) do eject_device(d)
		else do nav(r, d.path)
	}
	draw_sidebar_tags(&y, w)
}

