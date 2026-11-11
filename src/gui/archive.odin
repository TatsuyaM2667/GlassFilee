package main

// Extract / compress via bsdtar (libarchive: zip, tar.*, 7z, rar, iso, cpio, deb, rpm, ...)
// and the single-file decompressors. Runs as background processes; the UI never blocks.

import "core:c"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sys/posix"

// Longest suffixes first so ".tar.gz" wins over ".gz".
ARCHIVE_EXTS :: []string {
	".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tar.lz4", ".tar.lzma", ".tar.z",
	".tgz", ".txz", ".tbz2", ".tbz", ".tzst", ".tar", ".zip", ".7z", ".rar", ".iso", ".cpio",
	".jar", ".apk", ".deb", ".rpm", ".xpi", ".cab", ".cbz", ".cbr", ".lha", ".lzh", ".war",
}
// Compressed single files (not tarballs): ext -> tool
SINGLE_EXTS :: [][2]string{{".gz", "gzip"}, {".z", "gzip"}, {".xz", "xz"}, {".lzma", "xz"}, {".zst", "zstd"}, {".bz2", "bzip2"}, {".lz4", "lz4"}}

Job_Kind :: enum {
	Extract, Decompress, Compress, Convert, Mount, Thumb,
}

Job :: struct {
	pid:   posix.pid_t,
	kind:  Job_Kind,
	label: string, // archive / output name for messages
	dest:  string, // Extract: folder we created; Convert: output file
	src:   string, // Convert: source name (for the progress ring)
	prog_path, log_path: string, // ffmpeg -progress output and log (real progress)
	duration_us:         i64, // 0 = not known yet, -1 = none (e.g. images)
	frac:                f32,
}

free_job :: proc(j: Job) {
	if j.prog_path != "" do os.remove(j.prog_path)
	if j.log_path != "" do os.remove(j.log_path)
	delete(j.label)
	delete(j.dest)
	delete(j.src)
	delete(j.prog_path)
	delete(j.log_path)
}

jobs: [dynamic]Job

// Archive type of a file name: extension matched, tool for single files ("" = bsdtar).
archive_kind :: proc(name: string) -> (stem: string, tool: string, ok: bool) {
	lower := strings.to_lower(name, context.temp_allocator)
	for ext in ARCHIVE_EXTS {
		if strings.has_suffix(lower, ext) && len(name) > len(ext) do return name[:len(name) - len(ext)], "", true
	}
	for p in SINGLE_EXTS {
		if strings.has_suffix(lower, p[0]) && len(name) > len(p[0]) do return name[:len(name) - len(p[0])], p[1], true
	}
	return "", "", false
}

// Starts a process; returns its pid (0 on failure). The pidfd is closed: we reap with waitpid.
spawn :: proc(cmd: []string, dir := "", stderr_path := "") -> posix.pid_t {
	desc := os.Process_Desc{command = cmd, working_dir = dir}
	if stderr_path != "" {
		if f, ferr := os.create(stderr_path); ferr == nil {
			desc.stderr = f
			defer os.close(f)
		}
	}
	p, err := os.process_start(desc)
	if err != nil do return 0
	when ODIN_OS == .Linux { // os.process_start opened a pidfd
		if p.handle != 0 && p.handle != ~uintptr(0) do posix.close(posix.FD(p.handle))
	}
	return posix.pid_t(p.pid)
}

extract :: proc(vi: int) {
	name := app.entries[vi].name
	stem, tool, ok := archive_kind(name)
	if !ok do return
	src := full_path(name)
	job := Job{label = strings.clone(name)}
	if tool != "" {
		// gzip/xz/... -d -k writes the file next to the archive and keeps the original
		if os.exists(full_path(stem)) {
			toastf("「%s」は既にあります", stem)
			delete(job.label)
			return
		}
		job.kind = .Decompress
		job.pid = spawn({tool, "-d", "-k", src}, app.cwd)
	} else {
		dest := unique_dest(app.cwd, stem)
		if os.make_directory(dest) != nil {
			toastf("展開先フォルダーを作成できません")
			delete(job.label)
			return
		}
		job.kind, job.dest = .Extract, strings.clone(dest)
		job.pid = spawn({"bsdtar", "-xf", src, "-C", dest})
	}
	if job.pid == 0 {
		toastf("展開ツールを起動できません（bsdtar / %s が必要です）", tool if tool != "" else "libarchive")
		delete(job.label)
		delete(job.dest)
		if job.dest != "" do os.remove(job.dest)
		return
	}
	append(&jobs, job)
	toastf("「%s」を展開しています…", name)
}

compress :: proc(out_name: string) {
	names := make([dynamic]string, context.temp_allocator)
	append(&names, "bsdtar", "-a", "-cf", full_path(out_name), "--")
	for vi in selection() do append(&names, app.entries[vi].name)
	if len(names) == 5 do return
	pid := spawn(names[:], app.cwd) // -a: format from the extension (.zip, .tar.gz, .tar.xz, .7z ...)
	if pid == 0 {
		toastf("bsdtar を起動できません")
		return
	}
	append(&jobs, Job{pid = pid, kind = .Compress, label = strings.clone(out_name)})
	toastf("「%s」を作成しています…", out_name)
}

// After extracting into "<stem>/", a lone top-level entry is moved up so
// "project.zip" containing "project/" doesn't end up as "project/project".
flatten :: proc(dest: string) {
	infos, err := os.read_all_directory_by_path(dest, context.temp_allocator)
	if err != nil || len(infos) != 1 do return
	parent := filepath.dir(dest)
	tmp := strings.concatenate({dest, ".gf-extract"}, context.temp_allocator)
	if os.exists(tmp) || os.rename(dest, tmp) != nil do return
	inner, _ := filepath.join({tmp, infos[0].name}, context.temp_allocator)
	target := unique_dest(parent, infos[0].name)
	if os.rename(inner, target) == nil {
		os.remove(tmp)
	} else {
		os.rename(tmp, dest) // put it back as it was
	}
}

// Reaps finished children (jobs and fire-and-forget apps). Returns true if a job finished.
reap_jobs :: proc() -> bool {
	done := false
	for {
		status: c.int
		pid := posix.waitpid(-1, &status, {.NOHANG})
		if pid <= 0 do break
		if music_child_exited(pid) do continue
		for j, i in jobs {
			if j.pid != pid do continue
			ok := posix.WIFEXITED(status) && posix.WEXITSTATUS(status) == 0
			switch j.kind {
			case .Extract:
				if ok do flatten(j.dest)
				else do os.remove(j.dest) // only removes it if nothing was extracted
				if ok do toastf("「%s」を展開しました", j.label)
				else do toastf("「%s」を展開できませんでした", j.label)
			case .Decompress:
				if ok do toastf("「%s」を展開しました", j.label)
				else do toastf("「%s」を展開できませんでした", j.label)
			case .Mount:
				if !ok do toastf("「%s」を%sできませんでした", j.label, "取り出し" if j.dest == "eject" else "マウント")
				else if j.dest == "eject" do toastf("「%s」を取り外せます", j.label)
				refresh_devices()
			case .Thumb:
				thumb_done(j, ok)
			case .Compress, .Convert:
				// the output name was new (unique_dest), so a failed run's leftover is ours to remove
				if !ok && j.kind == .Convert do os.remove(j.dest)
				if ok do toastf("「%s」を作成しました", j.label)
				else do toastf("「%s」を作成できませんでした", j.label)
			}
			if j.kind != .Thumb && j.kind != .Mount do done = true // these don't change the listing
			free_job(j)
			ordered_remove(&jobs, i)
			break
		}
	}
	return done
}


visible_jobs :: proc() -> bool {
	for j in jobs do if j.kind != .Thumb do return true
	return false
}
