#+feature dynamic-literals
package main

// Programming-language logos for source files (Nerd Font glyphs + brand colors),
// chosen by extension or by well-known file names (Dockerfile, Makefile…).

import "core:path/filepath"
import "core:strings"

@(private = "file")
Lang :: struct {
	glyph: rune,
	color: u32,
}

@(private = "file")
LANG_BY_EXT := map[string]Lang {
	".py"     = {0xf0320, 0x3776ab}, ".pyw" = {0xf0320, 0x3776ab}, ".pyi" = {0xf0320, 0x3776ab},
	".ipynb"  = {0xe678, 0xf37626},
	".js"     = {0xf031e, 0xd4a300}, ".mjs" = {0xf031e, 0xd4a300}, ".cjs" = {0xf031e, 0xd4a300},
	".ts"     = {0xf06e6, 0x3178c6}, ".mts" = {0xf06e6, 0x3178c6}, ".cts" = {0xf06e6, 0x3178c6},
	".jsx"    = {0xf0708, 0x149eca}, ".tsx" = {0xf0708, 0x149eca},
	".rs"     = {0xf1617, 0xce422b},
	".go"     = {0xf07d3, 0x00add8},
	".c"      = {0xf0671, 0x555fbf}, ".h" = {0xf0671, 0x555fbf},
	".cpp"    = {0xf0672, 0x00599c}, ".cc" = {0xf0672, 0x00599c}, ".cxx" = {0xf0672, 0x00599c},
	".hpp"    = {0xf0672, 0x00599c}, ".hh" = {0xf0672, 0x00599c}, ".hxx" = {0xf0672, 0x00599c},
	".java"   = {0xf0b37, 0xe76f00},
	".kt"     = {0xf1219, 0x7f52ff}, ".kts" = {0xf1219, 0x7f52ff},
	".lua"    = {0xf08b1, 0x000080},
	".rb"     = {0xf0d2d, 0xcc342d},
	".html"   = {0xf031d, 0xe34f26}, ".htm" = {0xf031d, 0xe34f26},
	".css"    = {0xf031c, 0x1572b6},
	".scss"   = {0xe603, 0xcc6699}, ".sass" = {0xe603, 0xcc6699},
	".r"      = {0xf07d4, 0x276dc3},
	".swift"  = {0xf06e5, 0xf05138},
	".php"    = {0xf031f, 0x777bb4},
	".cs"     = {0xf031b, 0x68217a},
	".hs"     = {0xf0c92, 0x5e5086},
	".md"     = {0xf0354, 0x555555}, ".markdown" = {0xf0354, 0x555555},
	".sh"     = {0xf1183, 0x4eaa25}, ".bash" = {0xf1183, 0x4eaa25}, ".zsh" = {0xf1183, 0x4eaa25}, ".fish" = {0xf1183, 0x4eaa25},
	".json"   = {0xf0626, 0xcb8b00}, ".jsonc" = {0xf0626, 0xcb8b00},
	".vue"    = {0xf0844, 0x41b883},
	".dart"   = {0xe798, 0x0175c2},
	".zig"    = {0xe6a9, 0xf7a41d},
	".nix"    = {0xf1105, 0x5277c3},
	".ex"     = {0xe62d, 0x6e4a7e}, ".exs" = {0xe62d, 0x6e4a7e},
	".scala"  = {0xe737, 0xdc322f},
	".jl"     = {0xe624, 0x9558b2},
	".clj"    = {0xe768, 0x5881d8}, ".cljs" = {0xe768, 0x5881d8}, ".edn" = {0xe768, 0x5881d8},
	".ml"     = {0xe67a, 0xee6a1a}, ".mli" = {0xe67a, 0xee6a1a},
	".tex"    = {0xe69b, 0x008080}, ".sty" = {0xe69b, 0x008080}, ".bib" = {0xe69b, 0x008080},
	".sql"    = {0xf1c0, 0xe38c00},
	".yaml"   = {0xe6a8, 0xcb171e}, ".yml" = {0xe6a8, 0xcb171e},
	".toml"   = {0xe6b2, 0x9c4221},
	".xml"    = {0xf05c0, 0xe37933}, ".xsd" = {0xf05c0, 0xe37933}, ".xsl" = {0xf05c0, 0xe37933},
	".vim"    = {0xe62b, 0x019833},
	".pl"     = {0xe769, 0x39457e}, ".pm" = {0xe769, 0x39457e},
	".nim"    = {0xe677, 0xc9a000},
	".elm"    = {0xe62c, 0x1293d8},
	".fs"     = {0xe7a7, 0x378bba}, ".fsx" = {0xe7a7, 0x378bba},
	".ps1"    = {0xebc7, 0x5391fe}, ".psm1" = {0xebc7, 0x5391fe},
	".cmake"  = {0xe794, 0x064f8c},
	".mk"     = {0xe779, 0x6d8086},
	".odin"   = {0xf0e7, 0x3882d2},
	".gradle" = {0xe660, 0x02303a},
	".tf"     = {0xf1062, 0x7b42bc}, ".tfvars" = {0xf1062, 0x7b42bc},
	".gitignore" = {0xf02a2, 0xf05032}, ".gitattributes" = {0xf02a2, 0xf05032}, ".gitmodules" = {0xf02a2, 0xf05032},
}

@(private = "file")
LANG_BY_NAME := map[string]Lang {
	"dockerfile"         = {0xf0868, 0x2496ed},
	"containerfile"      = {0xf0868, 0x2496ed},
	"docker-compose.yml" = {0xf0868, 0x2496ed},
	"compose.yaml"       = {0xf0868, 0x2496ed},
	"makefile"           = {0xe779, 0x6d8086},
	"gnumakefile"        = {0xe779, 0x6d8086},
	"cmakelists.txt"     = {0xe794, 0x064f8c},
}

lang_icon :: proc(name: string) -> (glyph: rune, color: u32, ok: bool) {
	base := strings.to_lower(filepath.base(name), context.temp_allocator)
	l: Lang
	if l, ok = LANG_BY_NAME[base]; !ok do l, ok = LANG_BY_EXT[filepath.ext(base)]
	return l.glyph, l.color, ok
}
