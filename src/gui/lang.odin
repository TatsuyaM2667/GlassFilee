#+feature dynamic-literals
package main

// Programming-language and framework logos (Nerd Font glyphs + brand colors):
// source files by extension or well-known name (Dockerfile, next.config.js…), and
// project folders by their manifest (package.json → React / Next.js / Vue…,
// Cargo.toml → Yew / Leptos / Tauri…). Frameworks without a glyph get their name.

import "core:os"
import "core:path/filepath"
import "core:strings"

Lang :: struct {
	glyph: rune, // 0: draw label instead
	color: u32,
	label: string,
}

// Frameworks
FW_REACT    :: Lang{0xe7ba, 0x149eca, "React"}
FW_NEXT     :: Lang{0xe83e, 0x000000, "Next.js"}
FW_VUE      :: Lang{0xf0844, 0x41b883, "Vue"}
FW_NUXT     :: Lang{0xf1106, 0x00c16a, "Nuxt"}
FW_ANGULAR  :: Lang{0xe753, 0xdd0031, "Angular"}
FW_SVELTE   :: Lang{0xe8b7, 0xff3e00, "Svelte"}
FW_VITE     :: Lang{0xe8d7, 0x646cff, "Vite"}
FW_TAILWIND :: Lang{0xf13ff, 0x06b6d4, "Tailwind"}
FW_NODE     :: Lang{0xe718, 0x5fa04e, "Node.js"}
FW_DJANGO   :: Lang{0xe71d, 0x0c4b33, "Django"}
FW_RAILS    :: Lang{0xe73b, 0xcc0000, "Rails"}
FW_LARAVEL  :: Lang{0xe73f, 0xff2d20, "Laravel"}
FW_FLUTTER  :: Lang{0xe7dd, 0x02569b, "Flutter"}
FW_DOTNET   :: Lang{0xe7c6, 0x512bd4, ".NET"}
FW_TAURI    :: Lang{0xe8bb, 0xd99a00, "Tauri"}
FW_SPRING   :: Lang{0xe8ac, 0x6db33f, "Spring"}
FW_QT       :: Lang{0xe87d, 0x41cd52, "Qt"}
FW_SUPABASE :: Lang{0xe8b6, 0x3ecf8e, "Supabase"}
FW_YEW      :: Lang{0, 0x009a5b, "Yew"}
FW_LEPTOS   :: Lang{0, 0xef3939, "Leptos"}
FW_DIOXUS   :: Lang{0, 0xe96020, "Dioxus"}
FW_BEVY     :: Lang{0, 0x232326, "Bevy"}
FW_ASTRO    :: Lang{0, 0xbc52ee, "Astro"}
FW_REMIX    :: Lang{0, 0x121212, "Remix"}
FW_SOLID    :: Lang{0, 0x2c4f7c, "Solid"}
FW_ELECTRON :: Lang{0, 0x47848f, "Electron"}
FW_EXPRESS  :: Lang{0, 0x353535, "Express"}
FW_FLASK    :: Lang{0, 0x3b8eaa, "Flask"}
FW_FASTAPI  :: Lang{0, 0x009688, "FastAPI"}
FW_DENO     :: Lang{0, 0x111111, "Deno"}
// Languages (project fallback)
LG_RUST   :: Lang{0xf1617, 0xce422b, "Rust"}
LG_PYTHON :: Lang{0xf0320, 0x3776ab, "Python"}
LG_GO     :: Lang{0xf07d3, 0x00add8, "Go"}
LG_DART   :: Lang{0xe798, 0x0175c2, "Dart"}
LG_RUBY   :: Lang{0xf0d2d, 0xcc342d, "Ruby"}
LG_PHP    :: Lang{0xf031f, 0x777bb4, "PHP"}
LG_JAVA   :: Lang{0xf0b37, 0xe76f00, "Java"}
LG_ZIG    :: Lang{0xe6a9, 0xf7a41d, "Zig"}

@(private = "file")
LANG_BY_EXT := map[string]Lang {
	".py"     = {0xf0320, 0x3776ab, ""}, ".pyw" = {0xf0320, 0x3776ab, ""}, ".pyi" = {0xf0320, 0x3776ab, ""},
	".ipynb"  = {0xe678, 0xf37626, ""},
	".js"     = {0xf031e, 0xd4a300, ""}, ".mjs" = {0xf031e, 0xd4a300, ""}, ".cjs" = {0xf031e, 0xd4a300, ""},
	".ts"     = {0xf06e6, 0x3178c6, ""}, ".mts" = {0xf06e6, 0x3178c6, ""}, ".cts" = {0xf06e6, 0x3178c6, ""},
	".jsx"    = {0xf0708, 0x149eca, ""}, ".tsx" = {0xf0708, 0x149eca, ""},
	".rs"     = {0xf1617, 0xce422b, ""},
	".go"     = {0xf07d3, 0x00add8, ""},
	".c"      = {0xf0671, 0x555fbf, ""}, ".h" = {0xf0671, 0x555fbf, ""},
	".cpp"    = {0xf0672, 0x00599c, ""}, ".cc" = {0xf0672, 0x00599c, ""}, ".cxx" = {0xf0672, 0x00599c, ""},
	".hpp"    = {0xf0672, 0x00599c, ""}, ".hh" = {0xf0672, 0x00599c, ""}, ".hxx" = {0xf0672, 0x00599c, ""},
	".java"   = {0xf0b37, 0xe76f00, ""},
	".kt"     = {0xf1219, 0x7f52ff, ""}, ".kts" = {0xf1219, 0x7f52ff, ""},
	".lua"    = {0xf08b1, 0x000080, ""},
	".rb"     = {0xf0d2d, 0xcc342d, ""},
	".html"   = {0xf031d, 0xe34f26, ""}, ".htm" = {0xf031d, 0xe34f26, ""},
	".css"    = {0xf031c, 0x1572b6, ""},
	".scss"   = {0xe603, 0xcc6699, ""}, ".sass" = {0xe603, 0xcc6699, ""},
	".r"      = {0xf07d4, 0x276dc3, ""},
	".swift"  = {0xf06e5, 0xf05138, ""},
	".php"    = {0xf031f, 0x777bb4, ""},
	".cs"     = {0xf031b, 0x68217a, ""},
	".hs"     = {0xf0c92, 0x5e5086, ""},
	".md"     = {0xf0354, 0x555555, ""}, ".markdown" = {0xf0354, 0x555555, ""},
	".sh"     = {0xf1183, 0x4eaa25, ""}, ".bash" = {0xf1183, 0x4eaa25, ""}, ".zsh" = {0xf1183, 0x4eaa25, ""}, ".fish" = {0xf1183, 0x4eaa25, ""},
	".json"   = {0xf0626, 0xcb8b00, ""}, ".jsonc" = {0xf0626, 0xcb8b00, ""},
	".vue"    = {0xf0844, 0x41b883, ""},
	".dart"   = {0xe798, 0x0175c2, ""},
	".zig"    = {0xe6a9, 0xf7a41d, ""},
	".nix"    = {0xf1105, 0x5277c3, ""},
	".ex"     = {0xe62d, 0x6e4a7e, ""}, ".exs" = {0xe62d, 0x6e4a7e, ""},
	".scala"  = {0xe737, 0xdc322f, ""},
	".jl"     = {0xe624, 0x9558b2, ""},
	".clj"    = {0xe768, 0x5881d8, ""}, ".cljs" = {0xe768, 0x5881d8, ""}, ".edn" = {0xe768, 0x5881d8, ""},
	".ml"     = {0xe67a, 0xee6a1a, ""}, ".mli" = {0xe67a, 0xee6a1a, ""},
	".tex"    = {0xe69b, 0x008080, ""}, ".sty" = {0xe69b, 0x008080, ""}, ".bib" = {0xe69b, 0x008080, ""},
	".sql"    = {0xf1c0, 0xe38c00, ""},
	".yaml"   = {0xe6a8, 0xcb171e, ""}, ".yml" = {0xe6a8, 0xcb171e, ""},
	".toml"   = {0xe6b2, 0x9c4221, ""},
	".xml"    = {0xf05c0, 0xe37933, ""}, ".xsd" = {0xf05c0, 0xe37933, ""}, ".xsl" = {0xf05c0, 0xe37933, ""},
	".vim"    = {0xe62b, 0x019833, ""},
	".pl"     = {0xe769, 0x39457e, ""}, ".pm" = {0xe769, 0x39457e, ""},
	".nim"    = {0xe677, 0xc9a000, ""},
	".elm"    = {0xe62c, 0x1293d8, ""},
	".fs"     = {0xe7a7, 0x378bba, ""}, ".fsx" = {0xe7a7, 0x378bba, ""},
	".ps1"    = {0xebc7, 0x5391fe, ""}, ".psm1" = {0xebc7, 0x5391fe, ""},
	".cmake"  = {0xe794, 0x064f8c, ""},
	".mk"     = {0xe779, 0x6d8086, ""},
	".odin"   = {0xf0e7, 0x3882d2, ""},
	".gradle" = {0xe660, 0x02303a, ""},
	".tf"     = {0xf1062, 0x7b42bc, ""}, ".tfvars" = {0xf1062, 0x7b42bc, ""},
	".svelte" = FW_SVELTE, ".astro" = FW_ASTRO,
	".csproj" = FW_DOTNET, ".sln" = FW_DOTNET, ".razor" = FW_DOTNET,
	".gitignore" = {0xf02a2, 0xf05032, ""}, ".gitattributes" = {0xf02a2, 0xf05032, ""}, ".gitmodules" = {0xf02a2, 0xf05032, ""},
}

@(private = "file")
LANG_BY_NAME := map[string]Lang {
	"dockerfile"         = {0xf0868, 0x2496ed, ""},
	"containerfile"      = {0xf0868, 0x2496ed, ""},
	"docker-compose.yml" = {0xf0868, 0x2496ed, ""},
	"compose.yaml"       = {0xf0868, 0x2496ed, ""},
	"makefile"           = {0xe779, 0x6d8086, ""},
	"gnumakefile"        = {0xe779, 0x6d8086, ""},
	"cmakelists.txt"     = {0xe794, 0x064f8c, ""},
	"package.json"       = FW_NODE,
	"angular.json"       = FW_ANGULAR,
	"manage.py"          = FW_DJANGO,
	"artisan"            = FW_LARAVEL,
	"pubspec.yaml"       = FW_FLUTTER,
	"tauri.conf.json"    = FW_TAURI,
	"trunk.toml"         = FW_YEW, // Trunk bundles Yew / Leptos apps
	"dioxus.toml"        = FW_DIOXUS,
	"cargo.toml"         = LG_RUST,
	"cargo.lock"         = LG_RUST,
	"gemfile"            = LG_RUBY,
	"go.mod"             = LG_GO,
	"build.zig.zon"      = LG_ZIG,
	"deno.json"          = FW_DENO,
}

// Config files named <stem>.config.<js|ts|mjs|cjs>
@(private = "file")
LANG_BY_CONFIG := map[string]Lang {
	"next"     = FW_NEXT,
	"nuxt"     = FW_NUXT,
	"vite"     = FW_VITE,
	"vitest"   = FW_VITE,
	"tailwind" = FW_TAILWIND,
	"svelte"   = FW_SVELTE,
	"astro"    = FW_ASTRO,
	"remix"    = FW_REMIX,
}

lang_of :: proc(name: string) -> (l: Lang, ok: bool) {
	base := strings.to_lower(filepath.base(name), context.temp_allocator)
	if l, ok = LANG_BY_NAME[base]; ok do return
	if i := strings.index(base, ".config."); i > 0 {
		if l, ok = LANG_BY_CONFIG[base[:i]]; ok do return
	}
	return LANG_BY_EXT[filepath.ext(base)]
}

lang_icon :: proc(name: string) -> (glyph: rune, color: u32, ok: bool) {
	l: Lang
	l, ok = lang_of(name)
	return l.glyph, l.color, ok
}

// Logo, or the name for frameworks without a glyph, centered in r.
draw_lang :: proc(r: Rect, l: Lang, size: f32) {
	if l.glyph != 0 {
		glyph_center(r, l.glyph, i32(size), hex(l.color))
		return
	}
	ts := i32(size * 0.55)
	for ts > 6 && f32(text_width(l.label, ts, true)) > r.w - 2 do ts -= 1
	tw := f32(text_width(l.label, ts, true))
	text(r.x + (r.w - tw) / 2, baseline(r, ts), l.label, ts, hex(l.color), true)
}

// ---------------------------------------------------------------------------
// Project folders: what framework / language a folder is, from its manifest files

@(private = "file") projects: map[string]Lang // cleared when leaving the folder
@(private = "file") no_project := Lang{}

projects_clear :: proc() {
	for k in projects do delete(k)
	clear(&projects)
}

@(private = "file")
read_small :: proc(dir, name: string) -> (s: string, ok: bool) {
	p, _ := filepath.join({dir, name}, context.temp_allocator)
	fi, err := os.stat(p, context.temp_allocator)
	if err != nil || fi.size > 256 * 1024 do return
	data, rerr := os.read_entire_file_from_path(p, context.temp_allocator)
	return string(data), rerr == nil
}

@(private = "file")
exists_in :: proc(dir, name: string) -> bool {
	p, _ := filepath.join({dir, name}, context.temp_allocator)
	return os.exists(p)
}

// A dependency named dep in a Cargo.toml: `dep = ...`, `dep.workspace = ...` or [dependencies.dep]
toml_dep :: proc(toml, dep: string) -> bool {
	text := toml
	for line in strings.split_lines_iterator(&text) {
		l := strings.trim_space(line)
		if strings.has_prefix(l, "[") && strings.has_suffix(l, strings.concatenate({".", dep, "]"}, context.temp_allocator)) do return true
		if !strings.has_prefix(l, dep) || len(l) == len(dep) do continue
		if c := l[len(dep)]; c == ' ' || c == '=' || c == '.' do return true
	}
	return false
}

project_detect :: proc(dir: string) -> (Lang, bool) {
	if pkg, ok := read_small(dir, "package.json"); ok {
		has :: proc(pkg, dep: string) -> bool {return strings.contains(pkg, strings.concatenate({"\"", dep}, context.temp_allocator))}
		switch {
		case exists_in(dir, "src-tauri"):   return FW_TAURI, true
		case has(pkg, "next\""):            return FW_NEXT, true
		case has(pkg, "nuxt\""):            return FW_NUXT, true
		case has(pkg, "astro\""):           return FW_ASTRO, true
		case has(pkg, "@remix-run/"):       return FW_REMIX, true
		case has(pkg, "@angular/core\""):   return FW_ANGULAR, true
		case has(pkg, "svelte\"") || has(pkg, "@sveltejs/kit\""): return FW_SVELTE, true
		case has(pkg, "solid-js\""):        return FW_SOLID, true
		case has(pkg, "vue\""):             return FW_VUE, true
		case has(pkg, "electron\""):        return FW_ELECTRON, true
		case has(pkg, "react\""):           return FW_REACT, true
		case has(pkg, "express\""):         return FW_EXPRESS, true
		case has(pkg, "vite\""):            return FW_VITE, true
		}
		return FW_NODE, true
	}
	if cargo, ok := read_small(dir, "Cargo.toml"); ok {
		switch {
		case toml_dep(cargo, "yew"):    return FW_YEW, true
		case toml_dep(cargo, "leptos"): return FW_LEPTOS, true
		case toml_dep(cargo, "dioxus"): return FW_DIOXUS, true
		case toml_dep(cargo, "bevy"):   return FW_BEVY, true
		case toml_dep(cargo, "tauri"):  return FW_TAURI, true
		}
		return LG_RUST, true
	}
	if pub, ok := read_small(dir, "pubspec.yaml"); ok do return (FW_FLUTTER if strings.contains(pub, "flutter") else LG_DART), true
	if exists_in(dir, "manage.py") do return FW_DJANGO, true
	if exists_in(dir, "artisan") do return FW_LARAVEL, true
	for f in ([]string{"pyproject.toml", "requirements.txt"}) {
		if py, ok := read_small(dir, f); ok {
			low := strings.to_lower(py, context.temp_allocator)
			switch {
			case strings.contains(low, "django"):  return FW_DJANGO, true
			case strings.contains(low, "fastapi"): return FW_FASTAPI, true
			case strings.contains(low, "flask"):   return FW_FLASK, true
			}
			return LG_PYTHON, true
		}
	}
	if gem, ok := read_small(dir, "Gemfile"); ok do return (FW_RAILS if strings.contains(gem, "rails") else LG_RUBY), true
	if comp, ok := read_small(dir, "composer.json"); ok do return (FW_LARAVEL if strings.contains(comp, "laravel/") else LG_PHP), true
	for f in ([]string{"pom.xml", "build.gradle", "build.gradle.kts"}) {
		if j, ok := read_small(dir, f); ok do return (FW_SPRING if strings.contains(j, "springframework") else LG_JAVA), true
	}
	if exists_in(dir, "go.mod") do return LG_GO, true
	if exists_in(dir, "build.zig") do return LG_ZIG, true
	if exists_in(dir, "deno.json") || exists_in(dir, "deno.jsonc") do return FW_DENO, true
	if cm, ok := read_small(dir, "CMakeLists.txt"); ok && (strings.contains(cm, "Qt6") || strings.contains(cm, "Qt5")) do return FW_QT, true
	if exists_in(dir, "supabase") && exists_in(dir, "supabase/config.toml") do return FW_SUPABASE, true
	return {}, false
}

// Cached per folder; only folders actually drawn are looked at.
project_of :: proc(dir: string) -> (Lang, bool) {
	if l, ok := projects[dir]; ok do return l, l != no_project
	l, ok := project_detect(dir)
	projects[strings.clone(dir)] = l if ok else no_project
	return l, ok
}

// White badge with the project's logo in the folder's lower right corner.
project_badge :: proc(x, y, s: f32, dir: string) {
	l, ok := project_of(dir)
	if !ok do return
	b := s * 0.46
	r := Rect{x + s - b * 0.92, y + s - b * 0.98, b, b}
	if l.glyph == 0 { // a name: a wider pill
		r.w = max(b, f32(text_width(l.label, i32(b * 0.42), true)) + b * 0.3)
		r.x = x + s - r.w * 0.92
	}
	rrect({r.x, r.y + s * 0.02, r.w, r.h}, b * 0.28, hex(0x000000, 60))
	rrect(r, b * 0.28, hex(0xffffff, 245))
	draw_lang(r, l, b * 0.68)
}

// List rows: a "logo + name" chip after the folder name (a badge would be too small there).
project_chip :: proc(x, cy: f32, dir: string) {
	l, ok := project_of(dir)
	if !ok do return
	size := fs(11)
	h := px(18)
	tw := f32(text_width(l.label, size, true))
	gw := px(16) if l.glyph != 0 else 0
	r := Rect{x, cy - h / 2, tw + gw + px(12), h}
	rrect(r, h / 2, hex(0xffffff, 235))
	if l.glyph != 0 do glyph_center({r.x + px(4), r.y, px(14), h}, l.glyph, fs(11), hex(l.color))
	text(r.x + px(6) + gw, baseline(r, size), l.label, size, hex(l.color), true)
}
