package main

// Background copy/move with progress + cancel, and undo (Ctrl+Z) for file operations.

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import gf "../core"

Op :: struct {
	move:     bool,
	pairs:    [dynamic][2]string, // src, dst (absolute, heap)
	prog:     gf.Progress,
	finished: bool, // set by the worker (atomic)
	failed:   int,
	last_err: gf.OperationStatus,
	th:       ^thread.Thread,
	t0:       f32, // for the panel's slide-in
}

ops: [dynamic]^Op

// Starts copying/moving srcs into dir in a worker thread.
start_op :: proc(srcs: []string, dir: string, move: bool) {
	op := new(Op)
	op.move = move
	op.t0 = now_s()
	for src in srcs {
		if move && filepath.dir(src) == dir do continue
		if strings.has_prefix(dir, src) && (len(dir) == len(src) || dir[len(src)] == '/') {
			toastf("フォルダーをそれ自身の中には入れられません")
			continue
		}
		dst := unique_dest(dir, filepath.base(src))
		append(&op.pairs, [2]string{strings.clone(src), strings.clone(dst)})
	}
	if len(op.pairs) == 0 {
		free_op(op)
		return
	}
	op.th = thread.create_and_start_with_poly_data(op, op_worker)
	append(&ops, op)
}

@(private = "file")
op_worker :: proc(op: ^Op) {
	// moves within a filesystem are instant renames; everything else is streamed
	todo := make([dynamic]int, context.temp_allocator)
	for pr, i in op.pairs {
		if op.move && os.rename(pr[0], pr[1]) == nil do continue
		append(&todo, i)
	}
	total: i64
	for i in todo do total += gf.tree_size(op.pairs[i][0], &op.prog)
	sync.atomic_store(&op.prog.total, total)
	for i in todo {
		pr := op.pairs[i]
		st := gf.copy_tree(pr[0], pr[1], &op.prog)
		if st == .Success && op.move do st = gf.delete_path(pr[0])
		if st != .Success {
			op.failed += 1
			op.last_err = st
			if st == .Cancelled do break
		}
		free_all(context.temp_allocator)
	}
	sync.atomic_store(&op.finished, true)
	wake()
}

@(private = "file")
free_op :: proc(op: ^Op) {
	for pr in op.pairs {
		delete(pr[0])
		delete(pr[1])
	}
	delete(op.pairs)
	free(op)
}

// Collects finished operations; returns true if any finished.
reap_ops :: proc() -> bool {
	done := false
	for i := len(ops) - 1; i >= 0; i -= 1 {
		op := ops[i]
		if !sync.atomic_load(&op.finished) do continue
		thread.join(op.th)
		thread.destroy(op.th)
		ok := make([dynamic][2]string, context.temp_allocator)
		for pr in op.pairs do if os.exists(pr[1]) do append(&ok, pr)
		if op.last_err == .Cancelled {
			toastf("キャンセルしました")
		} else if op.failed > 0 {
			toastf("%d 個のアイテムを%sできませんでした: %s", op.failed, "移動" if op.move else "コピー", status_text(op.last_err))
		} else if len(ok) > 0 {
			toast_undo(fmt_items(len(ok), "移動しました" if op.move else "コピーしました"))
		}
		if len(ok) > 0 do push_undo(.Move if op.move else .Copy, ok[:])
		free_op(op)
		ordered_remove(&ops, i)
		done = true
	}
	return done
}

fmt_items :: proc(n: int, verb: string) -> string {
	return strings.concatenate({itoa_tmp(n), " 個のアイテムを", verb}, context.temp_allocator)
}

itoa_tmp :: proc(n: int) -> string {
	buf: [24]u8
	i := len(buf)
	v := n
	for {
		i -= 1
		buf[i] = u8('0' + v % 10)
		v /= 10
		if v == 0 do break
	}
	return strings.clone(string(buf[i:]), context.temp_allocator)
}

// Operations panel (bottom-right), like GNOME's file operations popover.
draw_ops :: proc(W, H: f32) -> f32 {
	if len(ops) == 0 do return 0
	w := min(px(360), W - px(32))
	h := px(64)
	y := H - px(16)
	for op, k in ops {
		p := progress(op.t0, 0.25)
		r := Rect{W - w - px(16) + (1 - p) * px(40), y - h, w, h}
		draw_alpha = u32(p * 255)
		rrect(r, px(12), POP_BG)
		rrect(r, px(12), LINE, px(1))
		total := sync.atomic_load(&op.prog.total)
		done := sync.atomic_load(&op.prog.done)
		frac := f32(done) / f32(total) if total > 0 else 0
		label := fmt_items(len(op.pairs), "移動中…" if op.move else "コピー中…")
		text(r.x + px(14), r.y + px(24), label, fs(13), FG, true)
		info := strings.concatenate({format_size(done), " / ", format_size(total)}, context.temp_allocator) if total > 0 else "準備中…"
		iw := f32(text_width(info, fs(11)))
		text(r.x + r.w - px(48) - iw, r.y + px(24), info, fs(11), DIM)
		bar := Rect{r.x + px(14), r.y + px(38), r.w - px(64), px(6)}
		rrect(bar, px(3), hex(0xffffff, 26))
		if total > 0 do rrect({bar.x, bar.y, max(bar.w * frac, px(6)), bar.h}, px(3), ACCENT)
		else {
			// indeterminate shimmer while sizing
			x := bar.x + (bar.w - px(60)) * (0.5 + 0.5 * f32(sin_fast(app.now * 3)))
			rrect({x, bar.y, px(60), bar.h}, px(3), ACCENT)
		}
		cb := Rect{r.x + r.w - px(42), r.y + (r.h - px(30)) / 2, px(30), px(30)}
		if hovering(cb) do rrect(cb, px(15), HOVER)
		glyph_center(cb, I_CLOSE, fs(12), FG)
		if clicked(cb) do sync.atomic_store(&op.prog.cancel, true)
		draw_alpha = 255
		app.animating = true // progress moves on its own
		y -= h + px(8)
		_ = k
	}
	return H - y
}

@(private = "file")
sin_fast :: proc(x: f32) -> f32 {
	// cheap sine for the shimmer (no need for precision)
	t := x - 6.2831853 * f32(int(x / 6.2831853))
	if t > 3.1415927 do t -= 6.2831853
	return 1.27323954 * t - 0.405284735 * t * abs(t)
}

// ---------------------------------------------------------------------------
// Undo

Undo_Kind :: enum {
	Trash, Rename, Move, Copy, Mkdir,
}

Undo :: struct {
	kind:  Undo_Kind,
	pairs: [dynamic][2]string, // Trash: original path, trash name; Rename/Move: old, new; Copy/Mkdir: -, created path
}

undo_stack: [dynamic]Undo

push_undo :: proc(kind: Undo_Kind, pairs: [][2]string) {
	u := Undo{kind = kind}
	for pr in pairs do append(&u.pairs, [2]string{strings.clone(pr[0]), strings.clone(pr[1])})
	if len(undo_stack) >= 30 {
		free_undo(undo_stack[0])
		ordered_remove(&undo_stack, 0)
	}
	append(&undo_stack, u)
}

@(private = "file")
free_undo :: proc(u: Undo) {
	for pr in u.pairs {
		delete(pr[0])
		delete(pr[1])
	}
	delete(u.pairs)
}

// Toast with a 元に戻す button.
toast_undo :: proc(msg: string) {
	toastf("%s", msg)
	app.toast_undo = true
}

do_undo :: proc() {
	if len(undo_stack) == 0 {
		toastf("元に戻せる操作はありません")
		return
	}
	u := pop(&undo_stack)
	defer free_undo(u)
	failed := 0
	#reverse for pr in u.pairs {
		switch u.kind {
		case .Trash:
			if gf.restore_from_trash(pr[1]) != .Success do failed += 1
		case .Rename:
			if os.exists(pr[0]) || gf.rename_path(pr[1], pr[0]) != .Success do failed += 1
		case .Move:
			// back to where it came from; cross-device moves go through a background op
			if os.exists(pr[0]) {
				failed += 1
			} else if os.rename(pr[1], pr[0]) != nil {
				start_op({pr[1]}, filepath.dir(pr[0]), true)
			}
		case .Copy:
			if gf.trash_path(pr[1]) != .Success do failed += 1 // to the trash, not gone forever
		case .Mkdir:
			if os.remove(pr[1]) != nil do failed += 1 // only if still empty
		}
	}
	reload()
	if failed > 0 do toastf("%d 個は元に戻せませんでした", failed)
	else do toastf("元に戻しました")
}
