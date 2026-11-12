package main

// Right-click menus as a radial ring (same motion as the convert donut):
// slices swirl in one after another, the hovered one pops out, the center shows
// the full label and shortcut. Tag colors sit on an outer arc below the ring.

import "core:math"
import "core:strings"
import "core:unicode/utf8"

@(private = "file") grow: [32]f32
@(private = "file") hover := -1
@(private = "file") closing: bool
@(private = "file") close_t0: f32
@(private = "file") chosen := -1

act_icon :: proc(a: Act) -> rune {
	#partial switch a {
	case .Open:            return 0xf08e
	case .New_Tab:         return 0xf0fe
	case .Extract:         return 0xf1c6
	case .Convert:         return 0xf0ec
	case .Preview:         return 0xf06e
	case .Compress:        return 0xf187
	case .Cut:             return 0xf0c4
	case .Copy:            return 0xf0c5
	case .Copy_Path:       return 0xf0c1 // link
	case .Paste:           return 0xf0ea
	case .Rename:          return 0xf040
	case .Bookmark:        return I_BOOKMARK
	case .Tag_Pick, .Tag_New, .Tag_Rename: return I_TAG
	case .Tag_Delete:      return 0xf014
	case .Remove_Bookmark: return 0xf097
	case .Props:           return 0xf05a
	case .Trash, .Empty_Trash: return I_TRASH
	case .Delete:          return 0xf014
	case .Restore:         return 0xf0e2
	case .Mkdir:           return 0xf07b
	case .Select_All:      return 0xf046
	case .Terminal:        return 0xf120
	case .Hidden:          return 0xf070
	case .Play_All, .Play_Dir: return I_PLAY
	case .Rule:            return 0xf0e7
	case .Unrule:          return 0xf05e
	case .View_Grid:       return I_GRID
	case .View_List:       return I_LIST
	case .Split:           return 0xf0db
	case .Reload:          return 0xf021
	case .Close:           return I_CLOSE
	}
	return 0xf111
}

@(private = "file")
danger :: proc(a: Act) -> bool {return a == .Delete || a == .Empty_Trash || a == .Tag_Delete}

// Slices = menu items without separators and the color row.
@(private = "file")
slices :: proc() -> (idx: [dynamic]int, colors: bool) {
	idx = make([dynamic]int, context.temp_allocator)
	for it, i in app.menu_items {
		if it.colors {colors = true; continue}
		if it.label != "" do append(&idx, i)
	}
	return
}

@(private = "file")
short :: proc(label: string) -> string {
	return strings.trim_suffix(label, "…")
}

menu_key :: proc(key: u32) {
	if closing do return
	idx, _ := slices()
	n := len(idx)
	switch key {
	case K_ESCAPE:        menu_close(-1)
	case K_LEFT, K_UP:    hover = (max(hover, 0) - 1 + n) % n
	case K_RIGHT, K_DOWN, K_TAB: hover = (hover + 1) % n
	case K_RETURN, K_KP_ENTER:
		if hover >= 0 && hover < n && app.menu_items[idx[hover]].ok {
			push(app.menu_items[idx[hover]].act, -1)
			menu_close(hover)
		}
	}
}

@(private = "file")
menu_close :: proc(i: int) {
	closing, close_t0, chosen = true, now_s(), i
}

draw_menu :: proc() {
	@(static) opened_at: f32
	if opened_at != app.menu_t0 {
		// a fresh menu
		opened_at = app.menu_t0
		closing, chosen, hover = false, -1, -1
		grow = {}
	}
	p: f32
	if closing {
		p = 1 - progress(close_t0, 0.18)
		if p <= 0.001 {
			app.menu_open = false
			closing = false
			return
		}
	} else do p = progress(app.menu_t0, 0.32)

	idx, has_colors := slices()
	n := len(idx)
	if n == 0 {
		app.menu_open = false
		return
	}
	R1 := f32(150) if n <= 10 else 172
	r0 := px(54) * (0.6 + 0.4 * p)
	r1 := px(R1) * (0.55 + 0.45 * p)
	W, H := f32(cv.w), f32(cv.h)
	m := px(R1 + 40)
	cx := clamp(app.menu_pos.x, m, max(m, W - m))
	cy := clamp(app.menu_pos.y, m, max(m, H - m))
	step := 2 * math.PI / f32(n)
	spin := (1 - p) * -0.9

	// hover
	if !closing {
		dx, dy := app.mx - cx, app.my - cy
		d := math.sqrt(dx * dx + dy * dy)
		if d > r0 * 0.85 && d < r1 + px(16) {
			a := math.atan2(dy, dx) + math.PI / 2 - spin + step / 2
			for a < 0 do a += 2 * math.PI
			hover = int(a / step) % n
		} else if d <= r0 * 0.85 || d > r1 + px(60) {
			hover = -1
		}
	}

	draw_alpha = u32(clamp(p * 1.3, 0, 1) * 255)
	defer draw_alpha = 255
	ring_seg(cx, cy + px(3), r0 - px(2), r1 + px(4), 0, 2 * math.PI, hex(0x000000, 28))
	for k in 0 ..< n {
		it := app.menu_items[idx[k]]
		target := f32(1) if (k == hover && it.ok) || k == chosen else 0
		if d := target - grow[k]; abs(d) > 0.01 {
			grow[k] += d * (1 - math.exp(-app.dt * 20))
			app.animating = true
		} else do grow[k] = target
		g := grow[k]
		sp := clamp(p * 1.6 - f32(k) * 0.05, 0, 1)
		mid := -math.PI / 2 + f32(k) * step + spin
		gap := 0.02 + 0.02 * (1 - sp)
		ro := r0 + (r1 - r0) * sp + g * px(12)
		base := hex(0x1b2133, 245)
		hot := with_alpha(DANGER, 245) if danger(it.act) else with_alpha(ACCENT, 245)
		col := mix(base, hot, g)
		ring_seg(cx, cy, r0, ro, mid - step / 2 + gap, mid + step / 2 - gap, col)
		fg := mix(FG if it.ok else with_alpha(FG, 80), hex(0x060913), g)
		lr := (r0 + ro) / 2
		lx, ly := cx + math.cos(mid) * lr, cy + math.sin(mid) * lr
		glyph_center({lx - px(14), ly - px(22), px(28), px(24)}, act_icon(it.act), fs(15 + 2 * g), fg)
		arc := (lr * step) * 0.86
		// long labels wrap onto a second line instead of being cut ("パスを / コピー")
		l1, l2 := split_label(short(it.label), fs(11), arc)
		tw := f32(text_width(l1, fs(11)))
		dy := px(-5) if l2 != "" else 0
		text(lx - tw / 2, ly + px(16) + dy, l1, fs(11), fg, true)
		if l2 != "" {
			tw2 := f32(text_width(l2, fs(11)))
			text(lx - tw2 / 2, ly + px(29) + dy, l2, fs(11), fg, true)
		}
	}

	// tag colors on an arc under the ring
	color_hover := -1
	arc := arc_items() if has_colors else nil
	if has_colors && !closing {
		for item, c in arc {
			a := math.PI / 2 + (f32(c) - f32(len(arc) - 1) / 2) * 0.17
			rr := r1 + px(24)
			dx, dy := cx + math.cos(a) * rr, cy + math.sin(a) * rr
			sp := clamp(p * 1.6 - 0.4 - f32(c) * 0.04, 0, 1)
			hit := Rect{dx - px(11), dy - px(11), px(22), px(22)}
			if hovering(hit) {
				color_hover = c
				ring_seg(dx, dy, 0, px(12), 0, 2 * math.PI, HOVER)
			}
			draw_alpha = u32(sp * 255)
			tag_dot(dx, dy, px(7) * (0.5 + 0.5 * sp), item.color, item.on)
			draw_alpha = u32(clamp(p * 1.3, 0, 1) * 255)
			if clicked(hit) {
				arc_click(c)
				menu_close(-1)
			}
		}
	}

	// center
	ring_seg(cx, cy, 0, r0 - px(6), 0, 2 * math.PI, hex(0x10141f, 250))
	title, key := "メニュー", ""
	if hover >= 0 && hover < n {
		it := app.menu_items[idx[hover]]
		title, key = it.label, it.key
	}
	if color_hover >= 0 && color_hover < len(arc) {
		item := arc[color_hover]
		title = strings.concatenate({item.label, " ✓" if item.on else ""}, context.temp_allocator)
	}
	tsize := fs(12)
	t := ellipsize(title, tsize, (r0 - px(6)) * 1.8, true)
	tw := f32(text_width(t, tsize, true))
	text(cx - tw / 2, cy + (px(4) if key != "" else px(5)), t, tsize, FG, true)
	if key != "" {
		kw := f32(text_width(key, fs(10)))
		text(cx - kw / 2, cy + px(19), key, fs(10), DIM)
	}

	if closing do return
	if app.pressed && color_hover < 0 {
		if app.button == 1 && hover >= 0 && hover < n && app.menu_items[idx[hover]].ok {
			push(app.menu_items[idx[hover]].act, -1)
			menu_close(hover)
		} else {
			menu_close(-1)
		}
	}
}

// Two-line label for a narrow slice: split near the middle, preferably after a
// particle (を へ の に で と), so "パスをコピー" becomes "パスを / コピー".
@(private = "file")
split_label :: proc(label: string, size: i32, maxw: f32) -> (string, string) {
	if f32(text_width(label, size)) <= maxw do return label, ""
	runes := utf8.string_to_runes(label, context.temp_allocator)
	n := len(runes)
	if n < 2 do return ellipsize(label, size, maxw), ""
	mid := (n + 1) / 2
	cut := mid
	best := 99
	for i in max(1, mid - 2) ..= min(n - 1, mid + 2) {
		switch runes[i - 1] {
		case 'を', 'へ', 'の', 'に', 'で', 'と', ' ':
			if abs(i - mid) < best {best = abs(i - mid); cut = i}
		}
	}
	a := utf8.runes_to_string(runes[:cut], context.temp_allocator)
	b := utf8.runes_to_string(runes[cut:], context.temp_allocator)
	return ellipsize(strings.trim_space(a), size, maxw), ellipsize(strings.trim_space(b), size, maxw)
}
