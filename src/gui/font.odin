package main

// Minimal FreeType binding + glyph cache. Fonts are mmap'd by FreeType, so
// large CJK fonts only cost the pages actually touched.

import "core:c"
import "core:os"
import "core:strings"

foreign import ft "system:freetype"

FT_Library :: distinct rawptr
FT_Generic :: struct {
	data:      rawptr,
	finalizer: rawptr,
}
FT_Bitmap :: struct {
	rows, width:  c.uint,
	pitch:        c.int,
	buffer:       [^]u8,
	num_grays:    u16,
	pixel_mode:   u8,
	palette_mode: u8,
	palette:      rawptr,
}
FT_GlyphSlotRec :: struct {
	library:            FT_Library,
	face:               rawptr,
	next:               rawptr,
	glyph_index:        c.uint,
	generic:            FT_Generic,
	metrics:            [8]c.long,
	linear_hori_advance: c.long,
	linear_vert_advance: c.long,
	advance:            [2]c.long,
	format:             c.uint,
	bitmap:             FT_Bitmap,
	bitmap_left:        c.int,
	bitmap_top:         c.int,
}
FT_Size_Metrics :: struct {
	x_ppem, y_ppem:                          u16,
	x_scale, y_scale:                        c.long,
	ascender, descender, height, max_advance: c.long,
}
FT_SizeRec :: struct {
	face:    rawptr,
	generic: FT_Generic,
	metrics: FT_Size_Metrics,
}
FT_FaceRec :: struct {
	num_faces, face_index, face_flags, style_flags, num_glyphs: c.long,
	family_name, style_name: cstring,
	num_fixed_sizes:         c.int,
	available_sizes:         rawptr,
	num_charmaps:            c.int,
	charmaps:                rawptr,
	generic:                 FT_Generic,
	bbox:                    [4]c.long,
	units_per_EM:            u16,
	ascender, descender, height, max_advance_width, max_advance_height, underline_position, underline_thickness: i16,
	glyph:                   ^FT_GlyphSlotRec,
	size:                    ^FT_SizeRec,
	charmap:                 rawptr,
}
FT_Face :: ^FT_FaceRec

FT_LOAD_RENDER :: 1 << 2
FT_LOAD_TARGET_LIGHT :: 1 << 16

@(default_calling_convention = "c")
foreign ft {
	FT_Init_FreeType :: proc(lib: ^FT_Library) -> c.int ---
	FT_New_Face :: proc(lib: FT_Library, path: cstring, index: c.long, face: ^FT_Face) -> c.int ---
	FT_Set_Pixel_Sizes :: proc(face: FT_Face, w, h: c.uint) -> c.int ---
	FT_Get_Char_Index :: proc(face: FT_Face, code: c.ulong) -> c.uint ---
	FT_Load_Glyph :: proc(face: FT_Face, index: c.uint, flags: i32) -> c.int ---
	FT_Done_Face :: proc(face: FT_Face) -> c.int ---
	FT_Set_Var_Design_Coordinates :: proc(face: FT_Face, num: c.uint, coords: [^]c.long) -> c.int ---
}

Glyph :: struct {
	w, h, left, top, adv: i32,
	px:                   []u8,
}

// chain[0] = regular, chain[1] = bold; each: UI font, CJK fallback, icon font
@(private = "file") lib: FT_Library
@(private = "file") chain: [2][3]FT_Face
@(private = "file") face_size: map[FT_Face]i32
@(private = "file") cache: map[u64]Glyph

// Known paths first (no fontconfig startup cost); fc-match is the fallback.
UI_FONTS :: []string {
	"/usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf",
	"/usr/share/fonts/adwaita-sans-fonts/AdwaitaSans-Regular.ttf",
	"/usr/share/fonts/cantarell/Cantarell-VF.otf",
	"/usr/share/fonts/noto/NotoSans-Regular.ttf",
	"/usr/share/fonts/TTF/DejaVuSans.ttf",
	"/usr/share/fonts/dejavu/DejaVuSans.ttf",
	"/usr/local/share/fonts/adwaita/AdwaitaSans-Regular.ttf",
	"/usr/local/share/fonts/noto/NotoSans-Regular.ttf",
	"/usr/local/share/fonts/dejavu/DejaVuSans.ttf",
}
CJK_FONTS :: []string {
	"/usr/share/fonts/noto/NotoSansCJKjp-Regular.otf",
	"/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
	"/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
	"/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc",
	"/usr/local/share/fonts/noto/NotoSansCJK-Regular.ttc",
	"/usr/local/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
}
CJK_BOLD_FONTS :: []string {
	"/usr/share/fonts/noto/NotoSansCJKjp-Bold.otf",
	"/usr/share/fonts/noto-cjk/NotoSansCJK-Bold.ttc",
	"/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
}
ICON_FONTS :: []string {
	"/usr/share/fonts/nerd-symbols-only/SymbolsNerdFont-Regular.ttf",
	"/usr/share/fonts/TTF/SymbolsNerdFont-Regular.ttf",
	"/usr/share/fonts/nerd-fonts/SymbolsNerdFont-Regular.ttf",
	"/usr/share/fonts/TTF/SymbolsNerdFontMono-Regular.ttf",
	"/usr/local/share/fonts/nerd-fonts-symbols/SymbolsNerdFont-Regular.ttf",
}

@(private = "file")
open_first :: proc(paths: []string) -> FT_Face {
	for p in paths {
		if !os.exists(p) do continue
		face: FT_Face
		if FT_New_Face(lib, strings.clone_to_cstring(p, context.temp_allocator), 0, &face) == 0 do return face
	}
	return nil
}

font_init :: proc() -> bool {
	if FT_Init_FreeType(&lib) != 0 do return false
	chain[0] = {open_first(UI_FONTS), open_first(CJK_FONTS), open_first(ICON_FONTS)}
	if chain[0][0] == nil do chain[0][0] = fc_match("sans-serif")
	if chain[0][1] == nil do chain[0][1] = fc_match("sans-serif:lang=ja")
	if chain[0][2] == nil do chain[0][2] = fc_match("Symbols Nerd Font")
	bold_ui := open_first(UI_FONTS)
	if bold_ui != nil {
		// variable font: wght axis -> 700 (ignored by static fonts)
		coord := [1]c.long{700 << 16}
		FT_Set_Var_Design_Coordinates(bold_ui, 1, &coord[0])
	}
	bold_cjk := open_first(CJK_BOLD_FONTS)
	chain[1] = {bold_ui, bold_cjk if bold_cjk != nil else chain[0][1], chain[0][2]}
	return chain[0][0] != nil || chain[0][1] != nil
}

@(private = "file")
fc_match :: proc(pattern: string) -> FT_Face {
	_, out, _, err := os.process_exec({command = {"fc-match", "-f", "%{file}", pattern}}, context.temp_allocator)
	if err != nil || len(out) == 0 do return nil
	return open_first({string(out)})
}

@(private = "file")
set_size :: proc(face: FT_Face, size: i32) {
	if face_size[face] != size {
		FT_Set_Pixel_Sizes(face, 0, c.uint(size))
		face_size[face] = size
	}
}

get_glyph :: proc(r: rune, size: i32, bold := false) -> Glyph {
	key := u64(r) | u64(size) << 32 | (u64(1) << 63 if bold else 0)
	if g, ok := cache[key]; ok do return g

	g: Glyph
	faces := &chain[1 if bold else 0]
	pick: FT_Face
	idx: c.uint
	for f in faces {
		if f == nil do continue
		if i := FT_Get_Char_Index(f, c.ulong(r)); i != 0 {
			pick, idx = f, i
			break
		}
	}
	if pick == nil do pick = faces[0] if faces[0] != nil else faces[1] // .notdef box
	if pick != nil {
		set_size(pick, size)
		if FT_Load_Glyph(pick, idx, FT_LOAD_RENDER | FT_LOAD_TARGET_LIGHT) == 0 {
			slot := pick.glyph
			bm := slot.bitmap
			g.w, g.h = i32(bm.width), i32(bm.rows)
			g.left, g.top = i32(slot.bitmap_left), i32(slot.bitmap_top)
			g.adv = i32((slot.advance[0] + 32) >> 6)
			if g.w > 0 && g.h > 0 && bm.buffer != nil {
				g.px = make([]u8, int(g.w * g.h))
				for y in 0 ..< int(g.h) {
					copy(g.px[y * int(g.w):][:g.w], bm.buffer[y * int(bm.pitch):][:g.w])
				}
			}
		}
	}
	cache[key] = g
	return g
}

// Ascent/descent of the UI font at this pixel size.
font_metrics :: proc(size: i32) -> (asc, desc: i32) {
	f := chain[0][0] if chain[0][0] != nil else chain[0][1]
	if f == nil do return size, size / 4
	set_size(f, size)
	return i32(f.size.metrics.ascender >> 6), i32(-f.size.metrics.descender >> 6)
}

text_width :: proc(s: string, size: i32, bold := false) -> i32 {
	w: i32
	for r in s do w += get_glyph(r, size, bold).adv
	return w
}

// A sample sheet for a font file (viewer): its name, then text at a few sizes.
font_sample :: proc(path: string, width: int, col: Color) -> (img: []u32, w, h: int, ok: bool) {
	face: FT_Face
	if FT_New_Face(lib, strings.clone_to_cstring(path, context.temp_allocator), 0, &face) != 0 do return
	defer FT_Done_Face(face)
	Line :: struct {s: string, size: i32}
	name := strings.concatenate({string(face.family_name), " ", string(face.style_name)}, context.temp_allocator)
	lines := []Line {
		{name, 22},
		{"Aa Bb Cc Dd Ee Ff Gg 0123456789", 44},
		{"あいうえお アイウエオ 漢字 かな", 40},
		{"The quick brown fox jumps over the lazy dog.", 28},
		{"いろはにほへと ちりぬるを わかよたれそ つねならむ", 24},
		{"!@#$%^&*()_+-=[]{};:'\",.<>/?", 20},
	}
	w = width
	pad := 24
	for l in lines do h += int(l.size) * 2
	h += pad * 2
	img = make([]u32, w * h)
	y := pad
	for l in lines {
		// skip lines the font can't show (e.g. Japanese in a Latin-only font) instead of boxes
		missing, total := 0, 0
		for r in l.s do if r != ' ' {
			total += 1
			if FT_Get_Char_Index(face, c.ulong(r)) == 0 do missing += 1
		}
		if missing * 2 > total do continue
		FT_Set_Pixel_Sizes(face, 0, c.uint(l.size))
		base := y + int(l.size)
		x := pad
		for r in l.s {
			idx := FT_Get_Char_Index(face, c.ulong(r))
			if FT_Load_Glyph(face, idx, FT_LOAD_RENDER | FT_LOAD_TARGET_LIGHT) != 0 do continue
			slot := face.glyph
			bm := slot.bitmap
			gx, gy := x + int(slot.bitmap_left), base - int(slot.bitmap_top)
			for j in 0 ..< int(bm.rows) {
				py := gy + j
				if py < 0 || py >= h do continue
				for i in 0 ..< int(bm.width) {
					px_ := gx + i
					if px_ < 0 || px_ >= w do continue
					a := u32(bm.buffer[j * int(bm.pitch) + i]) * u32(col.a) / 255
					if a == 0 do continue
					img[py * w + px_] = a << 24 | (u32(col.r) * a / 255) << 16 | (u32(col.g) * a / 255) << 8 | u32(col.b) * a / 255
				}
			}
			x += int((slot.advance[0] + 32) >> 6)
			if x > w - pad do break
		}
		y += int(l.size) * 2
	}
	ok = true
	return
}
