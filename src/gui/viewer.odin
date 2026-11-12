package main

// Content loaders for the viewer (Space / double-click), so every file shows something:
//   PDF  → poppler-glib + cairo, loaded at runtime (dlopen): no hard dependency
//   SVG  → librsvg (same), fonts → FreeType sample sheet (font.odin)
//   Word / Writer / PowerPoint / Excel / EPUB → their text, pulled out of the zip with bsdtar
//   archives → bsdtar listing, folders → their contents, anything else → hex dump

import "core:c"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// ---------------------------------------------------------------------------
// Runtime-loaded libraries

@(private = "file")
Libs :: struct {
	tried:                bool,
	pdf_ok, svg_ok:       bool,
	// gobject
	g_object_unref:       proc "c" (obj: rawptr),
	// cairo
	surface_create:       proc "c" (format: c.int, w, h: c.int) -> rawptr,
	cairo_create:         proc "c" (surface: rawptr) -> rawptr,
	cairo_scale:          proc "c" (cr: rawptr, sx, sy: f64),
	cairo_set_source_rgb: proc "c" (cr: rawptr, r, g, b: f64),
	cairo_paint:          proc "c" (cr: rawptr),
	surface_flush:        proc "c" (surface: rawptr),
	surface_data:         proc "c" (surface: rawptr) -> [^]u8,
	surface_stride:       proc "c" (surface: rawptr) -> c.int,
	cairo_destroy:        proc "c" (cr: rawptr),
	surface_destroy:      proc "c" (surface: rawptr),
	// poppler
	doc_new:              proc "c" (uri: cstring, password: cstring, err: rawptr) -> rawptr,
	doc_n_pages:          proc "c" (doc: rawptr) -> c.int,
	doc_page:             proc "c" (doc: rawptr, index: c.int) -> rawptr,
	page_size:            proc "c" (page: rawptr, w, h: ^f64),
	page_render:          proc "c" (page: rawptr, cr: rawptr),
	// rsvg
	svg_new:              proc "c" (path: cstring, err: rawptr) -> rawptr,
	svg_size:             proc "c" (h: rawptr, w, hh: ^f64) -> c.int,
	svg_render:           proc "c" (h: rawptr, cr: rawptr, viewport: ^[4]f64, err: rawptr) -> c.int,
}
@(private = "file") L: Libs

@(private = "file")
open_lib :: proc(names: []string) -> (dynlib.Library, bool) {
	for n in names {
		if lib, ok := dynlib.load_library(n); ok do return lib, true
	}
	return nil, false
}

@(private = "file")
sym :: proc(lib: dynlib.Library, name: string, dst: ^$T) -> bool {
	p, ok := dynlib.symbol_address(lib, name)
	if ok do dst^ = cast(T)p
	return ok
}

@(private = "file")
load_libs :: proc() {
	if L.tried do return
	L.tried = true
	gobj, ok1 := open_lib({"libgobject-2.0.so.0", "libgobject-2.0.so"})
	cairo, ok2 := open_lib({"libcairo.so.2", "libcairo.so"})
	if !ok1 || !ok2 do return
	base := sym(gobj, "g_object_unref", &L.g_object_unref) &&
		sym(cairo, "cairo_image_surface_create", &L.surface_create) &&
		sym(cairo, "cairo_create", &L.cairo_create) &&
		sym(cairo, "cairo_scale", &L.cairo_scale) &&
		sym(cairo, "cairo_set_source_rgb", &L.cairo_set_source_rgb) &&
		sym(cairo, "cairo_paint", &L.cairo_paint) &&
		sym(cairo, "cairo_surface_flush", &L.surface_flush) &&
		sym(cairo, "cairo_image_surface_get_data", &L.surface_data) &&
		sym(cairo, "cairo_image_surface_get_stride", &L.surface_stride) &&
		sym(cairo, "cairo_destroy", &L.cairo_destroy) &&
		sym(cairo, "cairo_surface_destroy", &L.surface_destroy)
	if !base do return
	if pop, ok := open_lib({"libpoppler-glib.so.8", "libpoppler-glib.so"}); ok {
		L.pdf_ok =
			sym(pop, "poppler_document_new_from_file", &L.doc_new) &&
			sym(pop, "poppler_document_get_n_pages", &L.doc_n_pages) &&
			sym(pop, "poppler_document_get_page", &L.doc_page) &&
			sym(pop, "poppler_page_get_size", &L.page_size) &&
			sym(pop, "poppler_page_render", &L.page_render)
	}
	if rsvg, ok := open_lib({"librsvg-2.so.2", "librsvg-2.so"}); ok {
		L.svg_ok =
			sym(rsvg, "rsvg_handle_new_from_file", &L.svg_new) &&
			sym(rsvg, "rsvg_handle_get_intrinsic_size_in_pixels", &L.svg_size) &&
			sym(rsvg, "rsvg_handle_render_document", &L.svg_render)
	}
}

// Draws into a fresh cairo surface (white for documents) and returns its pixels.
@(private = "file")
with_surface :: proc(w, h: int, white: bool, draw: proc(cr: rawptr, data: rawptr), data: rawptr) -> []u32 {
	surf := L.surface_create(0, c.int(w), c.int(h)) // CAIRO_FORMAT_ARGB32: premultiplied, like ours
	cr := L.cairo_create(surf)
	if white {
		L.cairo_set_source_rgb(cr, 1, 1, 1)
		L.cairo_paint(cr)
	}
	draw(cr, data)
	L.surface_flush(surf)
	src := L.surface_data(surf)
	stride := int(L.surface_stride(surf))
	out := make([]u32, w * h)
	for y in 0 ..< h do copy(out[y * w:][:w], slice.reinterpret([]u32, src[y * stride:][:w * 4]))
	L.cairo_destroy(cr)
	L.surface_destroy(surf)
	return out
}

// ---------------------------------------------------------------------------
// PDF

pdf_open :: proc(path: string) -> (doc: rawptr, pages: int) {
	load_libs()
	if !L.pdf_ok do return nil, 0
	uri := strings.clone_to_cstring(file_uri(path), context.temp_allocator)
	doc = L.doc_new(uri, nil, nil)
	if doc == nil do return nil, 0
	return doc, int(L.doc_n_pages(doc))
}

pdf_close :: proc(doc: rawptr) {
	if doc != nil do L.g_object_unref(doc)
}

// Renders page `index` at `width` pixels wide.
pdf_render :: proc(doc: rawptr, index, width: int) -> (img: []u32, w, h: int) {
	page := L.doc_page(doc, c.int(index))
	if page == nil do return
	defer L.g_object_unref(page)
	pw, ph: f64
	L.page_size(page, &pw, &ph)
	if pw <= 0 || ph <= 0 do return
	w = max(width, 16)
	h = int(f64(w) * ph / pw)
	Ctx :: struct {page: rawptr, s: f64}
	ctx := Ctx{page, f64(w) / pw}
	img = with_surface(w, h, true, proc(cr: rawptr, data: rawptr) {
		x := (^Ctx)(data)
		L.cairo_scale(cr, x.s, x.s)
		L.page_render(x.page, cr)
	}, &ctx)
	return
}

// ---------------------------------------------------------------------------
// SVG

svg_render_file :: proc(path: string, max_side: int) -> (img: []u32, w, h: int) {
	load_libs()
	if !L.svg_ok do return
	handle := L.svg_new(strings.clone_to_cstring(path, context.temp_allocator), nil)
	if handle == nil do return
	defer L.g_object_unref(handle)
	iw, ih: f64
	if L.svg_size(handle, &iw, &ih) == 0 || iw <= 0 || ih <= 0 do iw, ih = 512, 512
	s := f64(max_side) / max(iw, ih)
	w, h = max(int(iw * s), 1), max(int(ih * s), 1)
	Ctx :: struct {handle: rawptr, vp: [4]f64}
	ctx := Ctx{handle, {0, 0, f64(w), f64(h)}}
	img = with_surface(w, h, false, proc(cr: rawptr, data: rawptr) {
		x := (^Ctx)(data)
		L.svg_render(x.handle, cr, &x.vp, nil)
	}, &ctx)
	return
}

// ---------------------------------------------------------------------------
// Office documents / EPUB: their text

@(private = "file")
unzip_member :: proc(path, member: string) -> string {
	_, out, _, err := os.process_exec({command = {"bsdtar", "-xOf", path, member}}, context.temp_allocator)
	return string(out) if err == nil else ""
}

@(private = "file")
zip_members :: proc(path: string) -> []string {
	_, out, _, err := os.process_exec({command = {"bsdtar", "-tf", path}}, context.temp_allocator)
	if err != nil do return nil
	return strings.split_lines(strings.trim_space(string(out)), context.temp_allocator)
}

// XML/HTML → text: paragraphs and rows become new lines, tabs stay, tags vanish.
xml_text :: proc(xml: string, b: ^strings.Builder) {
	in_body := !strings.contains(xml, "<body")
	for i := 0; i < len(xml); {
		ch := xml[i]
		if ch == '<' {
			end := strings.index_byte(xml[i:], '>')
			if end < 0 do break
			tag := xml[i + 1:i + end]
			i += end + 1
			name := strings.trim_left(tag, "/")
			if k := strings.index_any(name, " /\t\n"); k >= 0 do name = name[:k]
			if colon := strings.index_byte(name, ':'); colon >= 0 do name = name[colon + 1:]
			switch name {
			case "body": in_body = true
			case "script", "style":
				if !strings.has_prefix(tag, "/") { // skip their contents
					close := strings.concatenate({"</", name}, context.temp_allocator)
					if k := strings.index(xml[i:], close); k >= 0 do i += k
				}
			case "p", "h", "h1", "h2", "h3", "h4", "h5", "h6", "li", "tr", "row", "si", "br", "line-break", "div":
				if in_body && (strings.has_prefix(tag, "/") || strings.has_suffix(tag, "/") || name == "br") do strings.write_byte(b, '\n')
			case "tab", "td", "c":
				if in_body && (strings.has_prefix(tag, "/") || strings.has_suffix(tag, "/")) do strings.write_byte(b, '\t')
			}
			continue
		}
		if !in_body {
			i += 1
			continue
		}
		if ch == '&' {
			ents := [?][2]string{{"&amp;", "&"}, {"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&apos;", "'"}, {"&nbsp;", " "}}
			matched := false
			for e in ents do if strings.has_prefix(xml[i:], e[0]) {
				strings.write_string(b, e[1])
				i += len(e[0])
				matched = true
				break
			}
			if matched do continue
		}
		strings.write_byte(b, ch)
		i += 1
	}
}

// Returns the readable text of an office document / EPUB ("" if not one).
document_text :: proc(path: string) -> string {
	if !have_tool("bsdtar") do return ""
	b := strings.builder_make(context.temp_allocator)
	switch strings.to_lower(filepath.ext(path), context.temp_allocator) {
	case ".docx": xml_text(unzip_member(path, "word/document.xml"), &b)
	case ".xlsx": xml_text(unzip_member(path, "xl/sharedStrings.xml"), &b)
	case ".odt", ".ods", ".odp": xml_text(unzip_member(path, "content.xml"), &b)
	case ".pptx":
		slides := make([dynamic]string, context.temp_allocator)
		for m in zip_members(path) do if strings.has_prefix(m, "ppt/slides/slide") && strings.has_suffix(m, ".xml") do append(&slides, m)
		slice.sort_by(slides[:], natural_less)
		for m, i in slides {
			fmt.sbprintf(&b, "── スライド %d ──\n", i + 1)
			xml_text(unzip_member(path, m), &b)
			strings.write_string(&b, "\n\n")
		}
	case ".epub":
		for m in zip_members(path) {
			lm := strings.to_lower(m, context.temp_allocator)
			if strings.has_suffix(lm, ".xhtml") || strings.has_suffix(lm, ".html") || strings.has_suffix(lm, ".htm") {
				xml_text(unzip_member(path, m), &b)
				strings.write_string(&b, "\n")
			}
		}
	case:
		return ""
	}
	// squeeze runs of blank lines
	out := strings.builder_make(context.temp_allocator)
	blank := 0
	for line in strings.split_lines(strings.to_string(b), context.temp_allocator) {
		l := strings.trim_right_space(line)
		if l == "" {
			blank += 1
			if blank > 1 do continue
		} else do blank = 0
		strings.write_string(&out, l)
		strings.write_byte(&out, '\n')
	}
	return strings.to_string(out)
}

// ---------------------------------------------------------------------------
// Archives, folders, binaries

archive_listing :: proc(path: string) -> string {
	if !have_tool("bsdtar") do return ""
	_, out, _, err := os.process_exec({command = {"bsdtar", "-tvf", path}}, context.temp_allocator)
	return string(out) if err == nil else ""
}

folder_listing :: proc(path: string) -> string {
	infos, err := os.read_all_directory_by_path(path, context.temp_allocator)
	if err != nil do return ""
	slice.sort_by(infos, proc(a, b: os.File_Info) -> bool {
		if (a.type == .Directory) != (b.type == .Directory) do return a.type == .Directory
		return natural_less(a.name, b.name)
	})
	b := strings.builder_make(context.temp_allocator)
	for fi in infos {
		if fi.type == .Directory do fmt.sbprintf(&b, "▸ %s/\n", fi.name)
		else do fmt.sbprintf(&b, "   %s    %s\n", fi.name, format_size(fi.size))
	}
	return strings.to_string(b)
}

hex_dump :: proc(data: []u8) -> string {
	b := strings.builder_make(context.temp_allocator)
	for off := 0; off < len(data); off += 16 {
		row := data[off:min(off + 16, len(data))]
		fmt.sbprintf(&b, "%08x  ", off)
		for i in 0 ..< 16 {
			if i < len(row) do fmt.sbprintf(&b, "%02x ", row[i])
			else do strings.write_string(&b, "   ")
			if i == 7 do strings.write_byte(&b, ' ')
		}
		strings.write_string(&b, " |")
		for x in row do strings.write_byte(&b, x if x >= 0x20 && x < 0x7f else '.')
		strings.write_string(&b, "|\n")
	}
	return strings.to_string(b)
}
