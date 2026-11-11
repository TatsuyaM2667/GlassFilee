const std = @import("std");
const core = @import("core");
const c = @cImport(@cInclude("gtk/gtk.h"));

// GlassFilee GUI: GTK4 window with a translucent "glass" background.
// Opacity of the background can be set with GF_OPACITY=0.0..1.0 (default 0.45).

const alloc = std.heap.c_allocator;

var window: *c.GtkWindow = undefined;
var listbox: *c.GtkListBox = undefined;
var path_entry: *c.GtkEntry = undefined;
var status_label: *c.GtkLabel = undefined;

var cwd: []u8 = &.{};
var history = std.ArrayList([]u8).init(alloc);
var show_hidden = false;
var shown = std.ArrayList(core.FileInfo).init(alloc);
var clip_path: ?[]u8 = null;
var clip_cut = false;

const Action = *const fn () void;
const Mode = enum { rename, mkdir };
var dlg_mode: Mode = .mkdir;

// ---------------------------------------------------------------------------
// Helpers

fn status(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const s = std.fmt.bufPrintZ(&buf, fmt, args) catch "…";
    c.gtk_label_set_text(status_label, s.ptr);
}

fn errText(err: anyerror) []const u8 {
    return switch (err) {
        error.NotFound => "見つかりません",
        error.PermissionDenied => "権限がありません",
        error.AlreadyExists => "既に存在します",
        error.InvalidPath => "不正なパスです",
        else => @errorName(err),
    };
}

fn joinZ(dir: []const u8, name: []const u8) ![:0]u8 {
    const sep: []const u8 = if (std.mem.endsWith(u8, dir, "/")) "" else "/";
    return std.fmt.allocPrintZ(alloc, "{s}{s}{s}", .{ dir, sep, name });
}

fn selected() ?*const core.FileInfo {
    const row = c.gtk_list_box_get_selected_row(listbox) orelse return null;
    const i: usize = @intCast(c.gtk_list_box_row_get_index(row));
    return if (i < shown.items.len) &shown.items[i] else null;
}

fn formatSize(buf: []u8, size: i64) []const u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var v: f64 = @floatFromInt(size);
    var u: usize = 0;
    while (v >= 1024 and u < units.len - 1) : (u += 1) v /= 1024;
    if (u == 0) return std.fmt.bufPrint(buf, "{d} B", .{size}) catch "";
    return std.fmt.bufPrint(buf, "{d:.1} {s}", .{ v, units[u] }) catch "";
}

fn lessThan(_: void, a: core.FileInfo, b: core.FileInfo) bool {
    const ad = a.file_type == .directory;
    const bd = b.file_type == .directory;
    if (ad != bd) return ad;
    return std.ascii.lessThanIgnoreCase(a.getName(), b.getName());
}

// ---------------------------------------------------------------------------
// Listing

fn navigate(path: []const u8, push: bool) void {
    const real = std.fs.realpathAlloc(alloc, path) catch |e| {
        status("開けません: {s} ({s})", .{ path, errText(e) });
        return;
    };
    const files = core.listDir(alloc, real) catch |e| {
        status("開けません: {s} ({s})", .{ real, errText(e) });
        alloc.free(real);
        return;
    };
    defer alloc.free(files);

    if (cwd.len > 0) {
        if (push) history.append(cwd) catch alloc.free(cwd) else alloc.free(cwd);
    }
    cwd = real;

    shown.clearRetainingCapacity();
    for (files) |f| {
        if (!show_hidden and f.is_hidden) continue;
        shown.append(f) catch break;
    }
    std.mem.sort(core.FileInfo, shown.items, {}, lessThan);

    c.gtk_list_box_remove_all(listbox);
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();
    for (shown.items) |*f| c.gtk_list_box_append(listbox, makeRow(a, f) catch continue);

    const cwd_z = a.dupeZ(u8, cwd) catch return;
    c.gtk_editable_set_text(@ptrCast(@alignCast(path_entry)), cwd_z.ptr);
    c.gtk_window_set_title(window, cwd_z.ptr);
    const limited: []const u8 = if (files.len >= core.max_list) " (表示上限に達しました)" else "";
    status("{d} 項目{s}", .{ shown.items.len, limited });
}

fn refresh() void {
    const p = alloc.dupe(u8, cwd) catch return;
    defer alloc.free(p);
    navigate(p, false);
}

fn makeRow(a: std.mem.Allocator, f: *const core.FileInfo) !*c.GtkWidget {
    const name_z = try a.dupeZ(u8, f.getName());
    const box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 12);
    c.gtk_widget_set_margin_start(box, 8);
    c.gtk_widget_set_margin_end(box, 8);
    c.gtk_widget_set_margin_top(box, 4);
    c.gtk_widget_set_margin_bottom(box, 4);

    const icon = switch (f.file_type) {
        .directory => c.gtk_image_new_from_icon_name("folder"),
        else => blk: {
            const ctype = c.g_content_type_guess(name_z.ptr, null, 0, null);
            defer c.g_free(ctype);
            const gicon = c.g_content_type_get_icon(ctype);
            defer c.g_object_unref(gicon);
            break :blk c.gtk_image_new_from_gicon(gicon);
        },
    };
    c.gtk_image_set_icon_size(@ptrCast(icon), c.GTK_ICON_SIZE_LARGE);
    c.gtk_box_append(@ptrCast(box), icon);

    const name = c.gtk_label_new(name_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(name), 0);
    c.gtk_label_set_ellipsize(@ptrCast(name), c.PANGO_ELLIPSIZE_MIDDLE);
    c.gtk_widget_set_hexpand(name, 1);
    if (f.file_type == .symlink) c.gtk_widget_add_css_class(name, "link");
    c.gtk_box_append(@ptrCast(box), name);

    var tbuf: [32]u8 = undefined;
    const dt = c.g_date_time_new_from_unix_local(@divFloor(f.modified, std.time.ns_per_s));
    defer if (dt != null) c.g_date_time_unref(dt);
    const ts: [*c]u8 = if (dt != null) c.g_date_time_format(dt, "%Y-%m-%d %H:%M") else null;
    defer c.g_free(ts);
    const date = c.gtk_label_new(if (ts != null) ts else "");
    c.gtk_widget_add_css_class(date, "meta");
    c.gtk_box_append(@ptrCast(box), date);

    var sbuf: [32]u8 = undefined;
    const size_s = if (f.file_type == .directory) "—" else formatSize(&sbuf, f.size);
    const size = c.gtk_label_new((try std.fmt.bufPrintZ(&tbuf, "{s}", .{size_s})).ptr);
    c.gtk_label_set_xalign(@ptrCast(size), 1);
    c.gtk_widget_set_size_request(size, 80, -1);
    c.gtk_widget_add_css_class(size, "meta");
    c.gtk_box_append(@ptrCast(box), size);
    return box;
}

// ---------------------------------------------------------------------------
// Actions

fn goBack() void {
    const prev = history.popOrNull() orelse return;
    defer alloc.free(prev);
    navigate(prev, false);
}

fn goUp() void {
    const parent = std.fs.path.dirname(cwd) orelse return;
    const p = alloc.dupe(u8, parent) catch return;
    defer alloc.free(p);
    navigate(p, true);
}

fn goHome() void {
    navigate(std.posix.getenv("HOME") orelse "/", true);
}

fn toggleHidden() void {
    show_hidden = !show_hidden;
    refresh();
}

fn activateIndex(i: usize) void {
    if (i >= shown.items.len) return;
    const f = shown.items[i];
    const full = joinZ(cwd, f.getName()) catch return;
    defer alloc.free(full);
    // follow symlinks to dirs too
    var d = std.fs.openDirAbsolute(full, .{}) catch {
        const file = c.g_file_new_for_path(full.ptr);
        defer c.g_object_unref(file);
        const launcher = c.gtk_file_launcher_new(file);
        c.gtk_file_launcher_launch(launcher, window, null, null, null);
        c.g_object_unref(launcher);
        status("開いています: {s}", .{f.getName()});
        return;
    };
    d.close();
    navigate(full, true);
}

fn copySel() void {
    setClip(false);
}
fn cutSel() void {
    setClip(true);
}
fn setClip(cut: bool) void {
    const f = selected() orelse return status("項目を選択してください", .{});
    if (clip_path) |p| alloc.free(p);
    clip_path = joinZ(cwd, f.getName()) catch null;
    clip_cut = cut;
    status("{s}: {s}", .{ if (cut) "切り取り" else "コピー", f.getName() });
}

fn paste() void {
    const src = clip_path orelse return status("クリップボードは空です", .{});
    const base = std.fs.path.basename(src);
    if (clip_cut and std.mem.eql(u8, std.fs.path.dirname(src) orelse "", cwd)) return;
    // refuse copying a folder into itself
    if (std.mem.startsWith(u8, cwd, src) and (cwd.len == src.len or cwd[src.len] == '/'))
        return status("フォルダを自分自身の中には貼り付けできません", .{});

    var dst = joinZ(cwd, base) catch return;
    defer alloc.free(dst);
    var n: usize = 1;
    while (core.exists(dst) catch false) : (n += 1) {
        alloc.free(dst);
        dst = std.fmt.allocPrintZ(alloc, "{s}/{s} ({d})", .{ cwd, base, n }) catch return;
    }

    const res = if (clip_cut) core.move(src, dst) else core.copy(src, dst);
    res catch |e| return status("貼り付け失敗: {s}", .{errText(e)});
    if (clip_cut) {
        alloc.free(src);
        clip_path = null;
    }
    refresh();
    status("貼り付けました: {s}", .{std.fs.path.basename(dst)});
}

fn askDelete() void {
    const f = selected() orelse return status("項目を選択してください", .{});
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "「{s}」を削除しますか？", .{f.getName()}) catch return;
    const dlg = c.gtk_alert_dialog_new("%s", msg.ptr);
    const kind: [*:0]const u8 = if (f.file_type == .directory) "フォルダの中身もすべて削除されます。元に戻せません。" else "この操作は元に戻せません。";
    c.gtk_alert_dialog_set_detail(dlg, kind);
    const buttons = [_:null]?[*:0]const u8{ "キャンセル", "削除" };
    c.gtk_alert_dialog_set_buttons(dlg, @ptrCast(&buttons));
    c.gtk_alert_dialog_set_cancel_button(dlg, 0);
    c.gtk_alert_dialog_set_default_button(dlg, 0);
    c.gtk_alert_dialog_choose(dlg, window, null, onDeleteChosen, null);
    c.g_object_unref(dlg);
}

fn onDeleteChosen(src: ?*c.GObject, res: ?*c.GAsyncResult, _: c.gpointer) callconv(.C) void {
    const choice = c.gtk_alert_dialog_choose_finish(@ptrCast(src), res, null);
    if (choice != 1) return;
    const f = selected() orelse return;
    const full = joinZ(cwd, f.getName()) catch return;
    defer alloc.free(full);
    core.delete(full) catch |e| return status("削除失敗: {s}", .{errText(e)});
    refresh();
    status("削除しました", .{});
}

fn askRename() void {
    const f = selected() orelse return status("項目を選択してください", .{});
    var buf: [257]u8 = undefined;
    const name = std.fmt.bufPrintZ(&buf, "{s}", .{f.getName()}) catch return;
    askText("名前の変更", name, .rename);
}

fn askMkdir() void {
    askText("新しいフォルダ", "新しいフォルダ", .mkdir);
}

fn askText(title: [*:0]const u8, initial: [*:0]const u8, mode: Mode) void {
    dlg_mode = mode;
    const win = c.gtk_window_new();
    c.gtk_window_set_transient_for(@ptrCast(win), window);
    c.gtk_window_set_modal(@ptrCast(win), 1);
    c.gtk_window_set_title(@ptrCast(win), title);
    c.gtk_window_set_default_size(@ptrCast(win), 380, -1);
    c.gtk_widget_add_css_class(win, "glass");

    const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 12);
    for ([_]*const fn (?*c.GtkWidget, c_int) callconv(.C) void{ c.gtk_widget_set_margin_start, c.gtk_widget_set_margin_end, c.gtk_widget_set_margin_top, c.gtk_widget_set_margin_bottom }) |set| set(box, 16);

    const entry = c.gtk_entry_new();
    c.gtk_editable_set_text(@ptrCast(entry), initial);
    c.gtk_box_append(@ptrCast(box), entry);
    c.g_object_set_data(@ptrCast(win), "entry", entry);
    connect(entry, "activate", &onDialogOk, win);

    const btns = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_set_halign(btns, c.GTK_ALIGN_END);
    const cancel = c.gtk_button_new_with_label("キャンセル");
    connect(cancel, "clicked", &onDialogCancel, win);
    const ok = c.gtk_button_new_with_label("OK");
    c.gtk_widget_add_css_class(ok, "suggested-action");
    connect(ok, "clicked", &onDialogOk, win);
    c.gtk_box_append(@ptrCast(btns), cancel);
    c.gtk_box_append(@ptrCast(btns), ok);
    c.gtk_box_append(@ptrCast(box), btns);

    const sc = c.gtk_shortcut_controller_new();
    c.gtk_shortcut_controller_add_shortcut(@ptrCast(@alignCast(sc)), c.gtk_shortcut_new(c.gtk_shortcut_trigger_parse_string("Escape"), c.gtk_named_action_new("window.close")));
    c.gtk_widget_add_controller(win, sc);

    c.gtk_window_set_child(@ptrCast(win), box);
    c.gtk_window_present(@ptrCast(win));
    _ = c.gtk_widget_grab_focus(entry);
    // select name without extension for rename
    const dot = std.mem.lastIndexOfScalar(u8, std.mem.span(initial), '.');
    c.gtk_editable_select_region(@ptrCast(entry), 0, if (mode == .rename and dot != null and dot.? > 0) @intCast(dot.?) else -1);
}

fn onDialogCancel(_: ?*c.GtkWidget, win: c.gpointer) callconv(.C) void {
    c.gtk_window_destroy(@ptrCast(@alignCast(win)));
}

fn onDialogOk(_: ?*c.GtkWidget, win: c.gpointer) callconv(.C) void {
    const entry: *c.GtkEditable = @ptrCast(@alignCast(c.g_object_get_data(@ptrCast(@alignCast(win)), "entry")));
    const text = std.mem.span(c.gtk_editable_get_text(entry));
    if (text.len == 0 or std.mem.indexOfScalar(u8, text, '/') != null or std.mem.eql(u8, text, ".") or std.mem.eql(u8, text, "..")) {
        status("その名前は使えません", .{});
        return;
    }
    const dst = joinZ(cwd, text) catch return;
    defer alloc.free(dst);
    const res = switch (dlg_mode) {
        .mkdir => core.mkdir(dst),
        .rename => blk: {
            const f = selected() orelse break :blk error.NotFound;
            const src = joinZ(cwd, f.getName()) catch break :blk error.Unknown;
            defer alloc.free(src);
            if (std.mem.eql(u8, src, dst)) break :blk {};
            if (core.exists(dst) catch false) break :blk error.AlreadyExists;
            break :blk core.rename(src, dst);
        },
    };
    res catch |e| {
        status("失敗: {s}", .{errText(e)});
        return;
    };
    c.gtk_window_destroy(@ptrCast(@alignCast(win)));
    refresh();
}

// ---------------------------------------------------------------------------
// GTK glue

fn connect(obj: anytype, sig: [*:0]const u8, cb: anytype, data: ?*anyopaque) void {
    _ = c.g_signal_connect_data(@ptrCast(obj), sig, @ptrCast(cb), data, null, 0);
}

fn onClicked(_: ?*c.GtkWidget, data: c.gpointer) callconv(.C) void {
    const f: Action = @ptrCast(data);
    f();
}

fn onShortcut(_: ?*c.GtkWidget, _: ?*c.GVariant, data: c.gpointer) callconv(.C) c.gboolean {
    const f: Action = @ptrCast(data);
    f();
    return 1;
}

fn onRowActivated(_: ?*c.GtkListBox, row: ?*c.GtkListBoxRow, _: c.gpointer) callconv(.C) void {
    activateIndex(@intCast(c.gtk_list_box_row_get_index(row)));
}

fn onPathActivate(entry: ?*c.GtkWidget, _: c.gpointer) callconv(.C) void {
    navigate(std.mem.span(c.gtk_editable_get_text(@ptrCast(entry))), true);
}

fn button(bar: *c.GtkHeaderBar, end: bool, icon: [*:0]const u8, tip: [*:0]const u8, f: Action) void {
    const b = c.gtk_button_new_from_icon_name(icon);
    c.gtk_widget_set_tooltip_text(b, tip);
    connect(b, "clicked", &onClicked, @constCast(@ptrCast(f)));
    if (end) c.gtk_header_bar_pack_end(bar, b) else c.gtk_header_bar_pack_start(bar, b);
}

fn shortcut(ctrl: *c.GtkShortcutController, trigger: [*:0]const u8, f: Action) void {
    const action = c.gtk_callback_action_new(@ptrCast(&onShortcut), @constCast(@ptrCast(f)), null);
    c.gtk_shortcut_controller_add_shortcut(ctrl, c.gtk_shortcut_new(c.gtk_shortcut_trigger_parse_string(trigger), action));
}

fn loadCss() void {
    const opacity = blk: {
        const s = std.posix.getenv("GF_OPACITY") orelse break :blk 0.45;
        break :blk std.math.clamp(std.fmt.parseFloat(f64, s) catch 0.45, 0.0, 1.0);
    };
    var buf: [2048]u8 = undefined;
    const css = std.fmt.bufPrintZ(&buf,
        \\window.glass {{ background-color: rgba(16, 20, 30, {d:.2}); color: #eef1f8; }}
        \\window.glass.csd {{ border-radius: 14px; }}
        \\window.glass headerbar {{ background: rgba(255,255,255,0.06); box-shadow: none;
        \\  border-bottom: 1px solid rgba(255,255,255,0.12); color: inherit; }}
        \\window.glass scrolledwindow, window.glass viewport, window.glass list {{ background: transparent; }}
        \\window.glass row {{ border-radius: 10px; margin: 1px 6px; }}
        \\window.glass row:hover {{ background: rgba(255,255,255,0.08); }}
        \\window.glass row:selected {{ background: rgba(120,170,255,0.32); }}
        \\window.glass entry {{ background: rgba(255,255,255,0.08); color: inherit; }}
        \\window.glass .meta {{ opacity: 0.65; font-feature-settings: "tnum"; }}
        \\window.glass .link {{ font-style: italic; }}
        \\window.glass .status {{ padding: 4px 12px; opacity: 0.75; font-size: smaller;
        \\  border-top: 1px solid rgba(255,255,255,0.10); }}
    , .{opacity}) catch unreachable;
    const provider = c.gtk_css_provider_new();
    c.gtk_css_provider_load_from_string(provider, css.ptr);
    c.gtk_style_context_add_provider_for_display(c.gdk_display_get_default(), @ptrCast(@alignCast(provider)), c.GTK_STYLE_PROVIDER_PRIORITY_USER);
}

var start_path: []const u8 = ".";

fn onActivate(app: ?*c.GtkApplication, _: c.gpointer) callconv(.C) void {
    loadCss();
    const settings = c.gtk_settings_get_default();
    c.g_object_set(settings, "gtk-interface-color-scheme", @as(c_int, c.GTK_INTERFACE_COLOR_SCHEME_DARK), @as(?*anyopaque, null));

    window = @ptrCast(c.gtk_application_window_new(app));
    c.gtk_window_set_default_size(window, 900, 600);
    c.gtk_widget_add_css_class(@ptrCast(@alignCast(window)), "glass");

    const bar: *c.GtkHeaderBar = @ptrCast(@alignCast(c.gtk_header_bar_new()));
    button(bar, false, "go-previous-symbolic", "戻る (Alt+←)", &goBack);
    button(bar, false, "go-up-symbolic", "上へ (Backspace)", &goUp);
    button(bar, false, "go-home-symbolic", "ホーム (Alt+Home)", &goHome);
    path_entry = @ptrCast(c.gtk_entry_new());
    c.gtk_widget_set_hexpand(@ptrCast(@alignCast(path_entry)), 1);
    connect(path_entry, "activate", &onPathActivate, null);
    c.gtk_header_bar_set_title_widget(bar, @ptrCast(@alignCast(path_entry)));
    button(bar, true, "user-trash-symbolic", "削除 (Delete)", &askDelete);
    button(bar, true, "edit-paste-symbolic", "貼り付け (Ctrl+V)", &paste);
    button(bar, true, "edit-cut-symbolic", "切り取り (Ctrl+X)", &cutSel);
    button(bar, true, "edit-copy-symbolic", "コピー (Ctrl+C)", &copySel);
    button(bar, true, "document-edit-symbolic", "名前の変更 (F2)", &askRename);
    button(bar, true, "folder-new-symbolic", "新しいフォルダ (Ctrl+Shift+N)", &askMkdir);
    button(bar, true, "view-reveal-symbolic", "隠しファイル (Ctrl+H)", &toggleHidden);
    button(bar, true, "view-refresh-symbolic", "更新 (F5)", &refresh);
    c.gtk_window_set_titlebar(window, @ptrCast(@alignCast(bar)));

    listbox = @ptrCast(c.gtk_list_box_new());
    c.gtk_list_box_set_activate_on_single_click(listbox, 0);
    connect(listbox, "row-activated", &onRowActivated, null);
    const scroll = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_child(@ptrCast(scroll), @ptrCast(@alignCast(listbox)));
    c.gtk_widget_set_vexpand(scroll, 1);

    status_label = @ptrCast(c.gtk_label_new(""));
    c.gtk_label_set_xalign(status_label, 0);
    c.gtk_widget_add_css_class(@ptrCast(@alignCast(status_label)), "status");

    const vbox = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_box_append(@ptrCast(vbox), scroll);
    c.gtk_box_append(@ptrCast(vbox), @ptrCast(@alignCast(status_label)));
    c.gtk_window_set_child(window, vbox);

    const sc: *c.GtkShortcutController = @ptrCast(c.gtk_shortcut_controller_new());
    shortcut(sc, "<Control>c", &copySel);
    shortcut(sc, "<Control>x", &cutSel);
    shortcut(sc, "<Control>v", &paste);
    shortcut(sc, "Delete", &askDelete);
    shortcut(sc, "F2", &askRename);
    shortcut(sc, "F5", &refresh);
    shortcut(sc, "<Control>h", &toggleHidden);
    shortcut(sc, "<Control><Shift>n", &askMkdir);
    shortcut(sc, "BackSpace", &goUp);
    shortcut(sc, "<Alt>Up", &goUp);
    shortcut(sc, "<Alt>Left", &goBack);
    shortcut(sc, "<Alt>Home", &goHome);
    c.gtk_widget_add_controller(@ptrCast(@alignCast(window)), @ptrCast(@alignCast(sc)));

    navigate(start_path, false);
    if (cwd.len == 0) navigate(std.posix.getenv("HOME") orelse "/", false);
    c.gtk_window_present(window);
    _ = c.gtk_widget_grab_focus(@ptrCast(@alignCast(listbox)));
}

pub fn main() !void {
    core.init();
    defer core.cleanup();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();
    if (args.next()) |p| start_path = p;

    const app = c.gtk_application_new("dev.glassfilee.GlassFilee", c.G_APPLICATION_NON_UNIQUE);
    defer c.g_object_unref(app);
    connect(app, "activate", &onActivate, null);
    // argv is handled above; GTK gets none so it doesn't treat the path as a file to open
    const rc = c.g_application_run(@ptrCast(app), 0, null);
    if (rc != 0) std.process.exit(@intCast(rc));
}
