# GlassFilee

**English** | [日本語](README.ja.md)

A translucent, GNOME Files–style file manager written in pure **Odin**, with Filee-style
drag-to-convert built in. It talks to Wayland directly — no GTK, no SDL, no GPU context —
so it idles at **0% CPU and ~19 MB of RAM**.

## Features

- **GNOME Files look**: sidebar (Home, Documents, Downloads, Pictures, Videos, Trash, Computer),
  back/forward, breadcrumb path bar, icon and list views, sorting, rubber-band selection,
  right-click menus, rename / new-folder dialogs. Translucent background like the ame-shell terminal.
- **Tabs, always on** like a browser: `+` button, Ctrl+T / Ctrl+W / Ctrl+Tab, middle-click a folder.
- **Convert like Filee**: Ctrl+drag files (or right-click → 変換…, Ctrl+E) and a donut of formats
  swirls open at the cursor; drop on a slice. The result is written next to the original while a
  progress ring spins on its icon. Uses whatever is installed: ffmpeg (images / video / audio),
  pandoc (documents), LibreOffice (office → PDF), ImageMagick (image → PDF), bsdtar (archives).
- **Archives**: right-click → ここに展開 for zip, tar.gz/xz/zst/bz2/lz4, 7z, rar, iso, deb, rpm…
  (via bsdtar) and single .gz/.xz/.zst/.bz2/.lz4 files; 圧縮… creates .zip / .tar.gz / .tar.xz / .7z.
  Runs in the background.
- **Quick preview** (Space): images, video frames and text zoom out of the icon; ←/→ to browse.
- **Search** filters the folder instantly and walks subfolders in the background.
- **Trash** (freedesktop spec, shared with GNOME): move, restore, empty.
- **Clipboard shared with other apps** (GNOME / KDE / browsers).
- **Thumbnails** for photos and videos (ffmpeg, shared GNOME cache, only what is on screen).
- **Split view** (F3, Tab switches panes) and **drag & drop** — between panes, onto folders,
  to and from other apps.
- **Background copy/move** with a progress panel and cancel; **undo** (Ctrl+Z, or the toast's
  元に戻す button) for trash, rename, move, copy and new folder.
- **Auto-refresh**: changes made by other programs appear immediately (inotify / kqueue).
- **Auto-convert folders** (Filee's watch): right-click a folder's background → 自動変換を設定…
  and every file that arrives is converted.
- **Donut back face**: press Tab (or scroll) on the convert donut for rotate, mirror, grayscale,
  shrink, square crop, remove audio, normalize volume, zip… The ring shows real ffmpeg progress.
- **Music player**: a folder of songs gets a player bar with cover art, seek bar and equalizer.
- **Bookmarks** (shared with GNOME), **USB drives** (mount via udisks2 / eject), **color tags**
  with a sidebar filter, **Git status** dots, **properties** (Ctrl+I), **batch rename** (F2 on
  several items: `*` = old name, `##` = number).
- **Smooth animations** (scrolling, folder-entry cascade, menus, dialogs, toasts) that only draw
  while something moves.

## Install

```bash
git clone https://github.com/TatsuyaM2667/ame-Filemanager.git
cd ame-Filemanager
./install.sh                # → ~/.local/bin/gf-gui, launcher entry, default file manager
NO_DEFAULT=1 ./install.sh   # keep your current default file manager
```

| System | Steps |
| --- | --- |
| Chimera Linux | install Odin from odin-lang.org, then `apk add wayland-devel libxkbcommon-devel freetype-devel libarchive-progs ffmpeg` → `./install.sh` |
| Arch Linux | `cd packaging/arch && makepkg -si` |
| FreeBSD | `pkg install odin wayland libxkbcommon freetype2 libarchive xdg-utils ffmpeg` → `./install.sh` |

Requirements: a Wayland compositor with xdg-shell, a recent Odin (dev-2026-08 or newer),
libwayland, libxkbcommon, FreeType, bsdtar. Fonts: Adwaita Sans, Noto Sans CJK, Symbols Nerd Font
(other fonts are found through `fc-match`).

Background opacity: `GF_OPACITY=0.85 gf-gui` (default 0.7).

## Keys

| Key | Action |
| --- | --- |
| Enter / double-click | Open |
| Space | Quick preview |
| Ctrl+drag / Ctrl+E | Convert (donut menu) |
| Alt+← / Alt+→ / Alt+↑ | Back / Forward / Parent |
| Ctrl+L / Ctrl+F | Type a path / Search (or just start typing) |
| Ctrl+C / Ctrl+X / Ctrl+V | Copy / Cut / Paste |
| F2 | Rename |
| Delete / Shift+Delete | Move to trash / Delete permanently |
| Ctrl+Shift+N | New folder |
| Ctrl+T / Ctrl+W / Ctrl+Tab | New / close / next tab |
| F3 / Tab | Split view / switch pane |
| Ctrl+Z | Undo |
| Ctrl+D / Ctrl+I | Bookmark / Properties |
| Ctrl+1 / Ctrl+2 | List / Icon view |
| Ctrl+H | Show hidden files |
| Ctrl+A, F5, Ctrl+Q | Select all, Reload, Quit |

## Layout

```
src/core/    Odin core: file operations, trash (also built as a C-ABI library for the CLI)
src/gui/     Odin GUI: Wayland client (wl.odin), renderer (draw.odin), fonts (font.odin),
             app (app.odin), conversion (convert.odin), preview, archives
src/cli/     gf-cli, a small Zig 0.13 command-line tool on top of the core (optional)
tests/       Odin trash tests; ./test.sh runs everything
```

## License

MIT
