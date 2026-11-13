#+feature dynamic-literals
package main

// Programming-language and framework logos, drawn from real logo SVGs bundled into the
// binary (assets/icons, see SOURCES.md) by our own rasterizer (svg.odin): source files by
// extension or well-known name (Dockerfile, next.config.js…), and project folders by
// their manifest (package.json → React / Next.js / Vue…, Cargo.toml → Yew / Leptos…).

import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

Lang :: struct {
	icon:  string, // assets/icons/<icon>.svg
	label: string,
}

// Frameworks
FW_REACT    :: Lang{"react", "React"}
FW_NEXT     :: Lang{"nextdotjs", "Next.js"}
FW_VUE      :: Lang{"vuedotjs", "Vue"}
FW_NUXT     :: Lang{"nuxt", "Nuxt"}
FW_ANGULAR  :: Lang{"angular", "Angular"}
FW_SVELTE   :: Lang{"svelte", "Svelte"}
FW_VITE     :: Lang{"vite", "Vite"}
FW_TAILWIND :: Lang{"tailwindcss", "Tailwind"}
FW_NODE     :: Lang{"nodedotjs", "Node.js"}
FW_DJANGO   :: Lang{"django", "Django"}
FW_RAILS    :: Lang{"rubyonrails", "Rails"}
FW_LARAVEL  :: Lang{"laravel", "Laravel"}
FW_FLUTTER  :: Lang{"flutter", "Flutter"}
FW_DOTNET   :: Lang{"dotnet", ".NET"}
FW_TAURI    :: Lang{"tauri", "Tauri"}
FW_SPRING   :: Lang{"spring", "Spring"}
FW_QT       :: Lang{"qt", "Qt"}
FW_SUPABASE :: Lang{"supabase", "Supabase"}
FW_YEW      :: Lang{"yew", "Yew"}
FW_LEPTOS   :: Lang{"leptos", "Leptos"}
FW_DIOXUS   :: Lang{"dioxus", "Dioxus"}
FW_BEVY     :: Lang{"bevy", "Bevy"}
FW_ASTRO    :: Lang{"astro", "Astro"}
FW_REMIX    :: Lang{"remix", "Remix"}
FW_SOLID    :: Lang{"solid", "Solid"}
FW_ELECTRON :: Lang{"electron", "Electron"}
FW_EXPRESS  :: Lang{"express", "Express"}
FW_FLASK    :: Lang{"flask", "Flask"}
FW_FASTAPI  :: Lang{"fastapi", "FastAPI"}
FW_DENO     :: Lang{"deno", "Deno"}
// Languages (also the project fallback)
LG_RUST   :: Lang{"rust", "Rust"}
LG_PYTHON :: Lang{"python", "Python"}
LG_GO     :: Lang{"go", "Go"}
LG_DART   :: Lang{"dart", "Dart"}
LG_RUBY   :: Lang{"ruby", "Ruby"}
LG_PHP    :: Lang{"php", "PHP"}
LG_JAVA   :: Lang{"openjdk", "Java"}
LG_ZIG    :: Lang{"zig", "Zig"}

@(private = "file")
LANG_BY_EXT := map[string]string {
	".pdf" = "acrobat",
	".py" = "python", ".pyw" = "python", ".pyi" = "python", ".ipynb" = "jupyter",
	".js" = "javascript", ".mjs" = "javascript", ".cjs" = "javascript",
	".ts" = "typescript", ".mts" = "typescript", ".cts" = "typescript",
	".jsx" = "react", ".tsx" = "react",
	".rs" = "rust", ".go" = "go",
	".c" = "c", ".h" = "c",
	".cpp" = "cplusplus", ".cc" = "cplusplus", ".cxx" = "cplusplus", ".hpp" = "cplusplus", ".hh" = "cplusplus", ".hxx" = "cplusplus",
	".java" = "openjdk", ".kt" = "kotlin", ".kts" = "kotlin",
	".lua" = "lua", ".rb" = "ruby",
	".html" = "html5", ".htm" = "html5", ".css" = "css", ".scss" = "sass", ".sass" = "sass",
	".r" = "r", ".swift" = "swift", ".php" = "php", ".cs" = "csharp", ".hs" = "haskell",
	".md" = "markdown", ".markdown" = "markdown",
	".sh" = "gnubash", ".bash" = "gnubash", ".zsh" = "gnubash", ".fish" = "gnubash",
	".json" = "json", ".jsonc" = "json",
	".vue" = "vuedotjs", ".dart" = "dart", ".zig" = "zig", ".nix" = "nixos",
	".ex" = "elixir", ".exs" = "elixir", ".scala" = "scala", ".jl" = "julia",
	".clj" = "clojure", ".cljs" = "clojure", ".edn" = "clojure",
	".ml" = "ocaml", ".mli" = "ocaml",
	".tex" = "latex", ".sty" = "latex", ".bib" = "latex",
	".sql" = "sql",
	".yaml" = "yaml", ".yml" = "yaml", ".toml" = "toml",
	".xml" = "xml", ".xsd" = "xml", ".xsl" = "xml",
	".vim" = "vim", ".pl" = "perl", ".pm" = "perl", ".nim" = "nim", ".elm" = "elm",
	".fs" = "fsharp", ".fsx" = "fsharp", ".ps1" = "powershell", ".psm1" = "powershell",
	".cmake" = "cmake", ".mk" = "gnu", ".odin" = "odin", ".gradle" = "gradle",
	".tf" = "terraform", ".tfvars" = "terraform",
	".svelte" = "svelte", ".astro" = "astro",
	".csproj" = "dotnet", ".sln" = "dotnet", ".razor" = "dotnet",
	".gitignore" = "git", ".gitattributes" = "git", ".gitmodules" = "git",
}

@(private = "file")
LANG_BY_NAME := map[string]Lang {
	"dockerfile"         = {"docker", "Docker"},
	"containerfile"      = {"docker", "Docker"},
	"docker-compose.yml" = {"docker", "Docker"},
	"compose.yaml"       = {"docker", "Docker"},
	"makefile"           = {"gnu", "Make"},
	"gnumakefile"        = {"gnu", "Make"},
	"cmakelists.txt"     = {"cmake", "CMake"},
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
	icon: string
	icon, ok = LANG_BY_EXT[filepath.ext(base)]
	return {icon, ""}, ok
}

// ---------------------------------------------------------------------------
// Bundled icons, rasterized on first use per size

@(private = "file") ICON_FILES := #load_directory("../../assets/icons")
@(private = "file") icon_svgs: map[string]string
@(private = "file") icon_cache: map[[2]int][]u32 // (icon index, size) → pixels

@(private = "file")
icon_svg :: proc(name: string) -> (svg: string, idx: int, ok: bool) {
	if len(icon_svgs) == 0 {
		for f in ICON_FILES do if strings.has_suffix(f.name, ".svg") do icon_svgs[strings.trim_suffix(f.name, ".svg")] = string(f.data)
	}
	svg, ok = icon_svgs[name]
	if !ok do return
	for f, i in ICON_FILES do if raw_data(f.data) == raw_data(svg) do idx = i
	return
}

// Brand color of an icon: its first solid fill.
icon_color :: proc(name: string) -> u32 {
	svg, _, ok := icon_svg(name)
	if !ok do return 0x444444
	rest := svg
	for {
		i := strings.index(rest, "fill=\"#")
		if i < 0 do return 0x444444
		h := rest[i + 7:]
		end := strings.index_byte(h, '"')
		if end == 6 {
			if v, vok := strconv.parse_uint(h[:6], 16); vok do return u32(v)
		}
		rest = h
	}
}

// Draws the logo into a square of side size centered in r. Renders at a fixed step
// size (16, 24, 32, 48, 64, 96, 128) and scales, so animated sizes don't fill the cache.
draw_icon :: proc(r: Rect, name: string, size: f32) -> bool {
	_, idx, ok := icon_svg(name)
	if !ok do return false
	step := 128
	for st in ([]int{16, 24, 32, 48, 64, 96}) do if f32(st) >= size {step = st; break}
	key := [2]int{idx, step}
	img, cached := icon_cache[key]
	if !cached {
		svg, _, _ := icon_svg(name)
		img = svg_rasterize(svg, step)
		icon_cache[key] = img
	}
	blit_scaled({r.x + (r.w - size) / 2, r.y + (r.h - size) / 2, size, size}, img, step, step)
	return true
}

// Logo centered in r (size: its side), or the name if the icon is missing.
draw_lang :: proc(r: Rect, l: Lang, size: f32) {
	if draw_icon(r, l.icon, size) do return
	ts := i32(size * 0.55)
	for ts > 6 && f32(text_width(l.label, ts, true)) > r.w - 2 do ts -= 1
	tw := f32(text_width(l.label, ts, true))
	text(r.x + (r.w - tw) / 2, baseline(r, ts), l.label, ts, hex(0x444444), true)
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

// A framework found in the manifest wins (React, Yew, Django…); otherwise the language
// with the most source code (by bytes) — so a mostly-Odin repo with a small build.zig
// is Odin, not Zig. Folders with no manifest, build file or .git get no badge.
project_detect :: proc(dir: string) -> (Lang, bool) {
	marker: Lang // language a manifest implies, used when no source files are found
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
		marker = FW_NODE
	}
	if cargo, ok := read_small(dir, "Cargo.toml"); ok {
		switch {
		case toml_dep(cargo, "yew"):    return FW_YEW, true
		case toml_dep(cargo, "leptos"): return FW_LEPTOS, true
		case toml_dep(cargo, "dioxus"): return FW_DIOXUS, true
		case toml_dep(cargo, "bevy"):   return FW_BEVY, true
		case toml_dep(cargo, "tauri"):  return FW_TAURI, true
		}
		marker = LG_RUST
	}
	if pub, ok := read_small(dir, "pubspec.yaml"); ok {
		if strings.contains(pub, "flutter") do return FW_FLUTTER, true
		marker = LG_DART
	}
	if exists_in(dir, "manage.py") do return FW_DJANGO, true
	if exists_in(dir, "artisan") do return FW_LARAVEL, true
	for f in ([]string{"pyproject.toml", "requirements.txt", "setup.py"}) {
		if py, ok := read_small(dir, f); ok {
			low := strings.to_lower(py, context.temp_allocator)
			switch {
			case strings.contains(low, "django"):  return FW_DJANGO, true
			case strings.contains(low, "fastapi"): return FW_FASTAPI, true
			case strings.contains(low, "flask"):   return FW_FLASK, true
			}
			marker = LG_PYTHON
		}
	}
	if gem, ok := read_small(dir, "Gemfile"); ok {
		if strings.contains(gem, "rails") do return FW_RAILS, true
		marker = LG_RUBY
	}
	if comp, ok := read_small(dir, "composer.json"); ok {
		if strings.contains(comp, "laravel/") do return FW_LARAVEL, true
		marker = LG_PHP
	}
	for f in ([]string{"pom.xml", "build.gradle", "build.gradle.kts"}) {
		if j, ok := read_small(dir, f); ok {
			if strings.contains(j, "springframework") do return FW_SPRING, true
			marker = LG_JAVA
		}
	}
	if exists_in(dir, "deno.json") || exists_in(dir, "deno.jsonc") do return FW_DENO, true
	if cm, ok := read_small(dir, "CMakeLists.txt"); ok && (strings.contains(cm, "Qt6") || strings.contains(cm, "Qt5")) do return FW_QT, true
	if exists_in(dir, "supabase/config.toml") do return FW_SUPABASE, true
	if exists_in(dir, "go.mod") do marker = LG_GO
	if exists_in(dir, "build.zig") do marker = LG_ZIG

	is_project := marker.icon != ""
	if !is_project {
		for f in ([]string{".git", "Makefile", "CMakeLists.txt", "meson.build", "build.sh", "flake.nix"}) do if exists_in(dir, f) do is_project = true
	}
	if !is_project do return {}, false
	if l, ok := main_language(dir); ok do return l, true
	return marker, marker.icon != ""
}

// Languages that count as "the project's language" (not data / docs / config).
@(private = "file")
LANGUAGE_NAMES := map[string]string {
	"python" = "Python", "javascript" = "JavaScript", "typescript" = "TypeScript", "react" = "React",
	"rust" = "Rust", "go" = "Go", "c" = "C", "cplusplus" = "C++", "openjdk" = "Java", "kotlin" = "Kotlin",
	"lua" = "Lua", "ruby" = "Ruby", "html5" = "HTML", "css" = "CSS", "sass" = "Sass", "r" = "R",
	"swift" = "Swift", "php" = "PHP", "csharp" = "C#", "haskell" = "Haskell", "gnubash" = "Shell",
	"vuedotjs" = "Vue", "dart" = "Dart", "zig" = "Zig", "nixos" = "Nix", "elixir" = "Elixir",
	"scala" = "Scala", "julia" = "Julia", "clojure" = "Clojure", "ocaml" = "OCaml", "perl" = "Perl",
	"nim" = "Nim", "elm" = "Elm", "fsharp" = "F#", "powershell" = "PowerShell", "odin" = "Odin",
	"svelte" = "Svelte", "astro" = "Astro", "jupyter" = "Jupyter", "latex" = "LaTeX",
}

// Build output, dependencies and caches are not the project's own code.
@(private = "file")
SKIP_DIRS :: []string {"node_modules", "target", "zig-cache", "zig-out", "build", "dist", "out", "vendor", "third_party", "venv", "__pycache__", "Pods", "bin", "obj"}

// The language with the most bytes of source, looking up to 3 levels deep (at most ~4000 entries).
main_language :: proc(dir: string) -> (Lang, bool) {
	bytes := make(map[string]i64, 16, context.temp_allocator)
	budget := 4000
	walk :: proc(dir: string, depth: int, bytes: ^map[string]i64, budget: ^int) {
		infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if err != nil do return
		for fi in infos {
			if budget^ <= 0 do return
			budget^ -= 1
			if strings.has_prefix(fi.name, ".") do continue
			if fi.type == .Directory {
				if depth < 3 && !slice.contains(SKIP_DIRS, fi.name) do walk(fi.fullpath, depth + 1, bytes, budget)
				continue
			}
			ext := strings.to_lower(filepath.ext(fi.name), context.temp_allocator)
			if icon, ok := LANG_BY_EXT[ext]; ok && icon in LANGUAGE_NAMES do bytes[icon] += max(fi.size, 1)
		}
	}
	walk(dir, 0, &bytes, &budget)
	best, most := "", i64(0)
	for icon, n in bytes do if n > most || n == most && icon < best {best, most = icon, n}
	if best == "" do return {}, false
	return {best, LANGUAGE_NAMES[best]}, true
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
	rrect({r.x, r.y + s * 0.02, r.w, r.h}, b * 0.28, hex(0x000000, 60))
	rrect(r, b * 0.28, hex(0xffffff, 245))
	draw_lang(r, l, b * 0.72)
}

// List rows: a "logo + name" chip after the folder name (a badge would be too small there).
project_chip :: proc(x, cy: f32, dir: string) {
	l, ok := project_of(dir)
	if !ok do return
	size := fs(11)
	h := px(18)
	tw := f32(text_width(l.label, size, true))
	gw := px(16)
	r := Rect{x, cy - h / 2, tw + gw + px(12), h}
	rrect(r, h / 2, hex(0xffffff, 235))
	draw_icon({r.x + px(4), r.y, px(14), h}, l.icon, px(12))
	text(r.x + px(6) + gw, baseline(r, size), l.label, size, hex(icon_color(l.icon)), true)
}
