"""Diagnostic probe — collects info about the NAS environment so we can tune
scan/cleanup before running them at scale.

Output is plain stdout, one short line per metric, designed to be easy to
type back into a chat. No logging framework involvement.
"""

import os
import shutil
import sys
import time
from datetime import datetime, timezone

VERSION = 1


def run_check(
    root: str,
    trash: str,
    max_files: int = 5000,
    max_seconds: int = 60,
) -> None:
    lines: list[str] = [f"== dc check v{VERSION} =="]
    lines.append(_env_line())

    root_abs = os.path.abspath(root)
    trash_abs = os.path.abspath(trash)
    root_ok = os.path.isdir(root_abs)
    trash_ok = os.path.isdir(trash_abs)

    lines.append(f"root={root_abs} exists={root_ok}")
    lines.append(f"trash={trash_abs} exists={trash_ok}")

    if not root_ok:
        lines.append("FATAL root_not_dir")
        lines.append("== end ==")
        print("\n".join(lines))
        return

    lines.append(_same_vol_line(root_abs, trash_abs))
    lines.append(_fs_line(root_abs))

    ml = _mount_line(root_abs)
    if ml:
        lines.append(ml)

    lines.extend(_sample_scan_lines(root_abs, max_files, max_seconds))

    if trash_ok:
        lines.append(_move_test_line(root_abs, trash_abs))
    else:
        lines.append("move_test=skipped (trash missing)")

    lines.append("== end ==")
    print("\n".join(lines))


def _env_line() -> str:
    tz = datetime.now(timezone.utc).astimezone().strftime("%z")
    py = ".".join(str(x) for x in sys.version_info[:3])
    enc = sys.getfilesystemencoding()
    return f"env={sys.platform} py={py} enc={enc} tz={tz}"


def _same_vol_line(root: str, trash: str) -> str:
    if os.name == "nt":
        a = os.path.splitdrive(root)[0].lower()
        b = os.path.splitdrive(trash)[0].lower()
        return f"same_vol={a == b} drv_root={a!r} drv_trash={b!r}"

    try:
        a_dev = os.stat(root).st_dev
    except OSError as e:
        return f"same_vol=ERR root_stat:errno={e.errno}"

    p = trash
    while not os.path.exists(p):
        parent = os.path.dirname(p)
        if parent == p:
            return "same_vol=False trash_parent_missing"
        p = parent

    try:
        b_dev = os.stat(p).st_dev
    except OSError as e:
        return f"same_vol=ERR trash_stat:errno={e.errno}"

    return f"same_vol={a_dev == b_dev} dev_root={a_dev} dev_trash={b_dev}"


def _fs_line(path: str) -> str:
    try:
        if hasattr(os, "statvfs"):
            sv = os.statvfs(path)
            total = sv.f_blocks * sv.f_frsize
            free = sv.f_bavail * sv.f_frsize
        else:
            import ctypes  # Windows fallback
            free_b = ctypes.c_ulonglong(0)
            total_b = ctypes.c_ulonglong(0)
            ok = ctypes.windll.kernel32.GetDiskFreeSpaceExW(  # type: ignore[attr-defined]
                ctypes.c_wchar_p(path), None,
                ctypes.byref(total_b), ctypes.byref(free_b),
            )
            if not ok:
                return "fs=ERR GetDiskFreeSpaceExW"
            total = total_b.value
            free = free_b.value
    except Exception as e:
        return f"fs=ERR {type(e).__name__}"

    used_pct = 100.0 * (total - free) / total if total else 0.0
    return f"fs total={_h(total)} free={_h(free)} used={used_pct:.1f}%"


def _mount_line(path: str) -> str | None:
    if sys.platform != "linux":
        return None
    try:
        with open("/proc/mounts") as f:
            mounts = f.readlines()
    except OSError:
        return None

    p = os.path.abspath(path)
    best = None
    best_len = -1
    for line in mounts:
        parts = line.split()
        if len(parts) < 4:
            continue
        src, mp, fstype, opts = parts[0], parts[1], parts[2], parts[3]
        if p == mp or p.startswith(mp.rstrip("/") + "/"):
            if len(mp) > best_len:
                best = (src, mp, fstype, opts)
                best_len = len(mp)

    if not best:
        return "mount=unknown"
    src, _, fstype, opts = best
    if len(opts) > 60:
        opts = opts[:57] + "..."
    return f"mount={fstype} src={src} opts={opts}"


def _sample_scan_lines(root: str, max_files: int, max_seconds: int) -> list[str]:
    files = 0
    dirs = 0
    syms = 0
    errors = 0
    total_bytes = 0
    surrogate = 0
    max_path_len = 0
    files_per_dir: list[int] = []

    atime_samples = 0
    atime_eq_mtime = 0

    min_mtime: float | None = None
    max_mtime: float | None = None
    min_size: int | None = None
    max_size: int | None = None
    first_error: str | None = None

    deadline = time.time() + max_seconds
    start = time.time()
    stop_reason = "exhausted"

    stack = [root]
    while stack:
        if files >= max_files:
            stop_reason = "cap_files"
            break
        if time.time() >= deadline:
            stop_reason = "cap_time"
            break

        d = stack.pop()
        in_this_dir = 0
        try:
            it = os.scandir(d)
        except OSError as e:
            errors += 1
            if first_error is None:
                first_error = f"{type(e).__name__}:errno={e.errno}"
            continue

        with it:
            for entry in it:
                if files >= max_files:
                    stop_reason = "cap_files"
                    break
                if time.time() >= deadline:
                    stop_reason = "cap_time"
                    break

                try:
                    entry.path.encode("utf-8")
                except UnicodeEncodeError:
                    surrogate += 1

                pl = len(entry.path)
                if pl > max_path_len:
                    max_path_len = pl

                try:
                    if entry.is_symlink():
                        syms += 1
                        continue
                    is_dir = entry.is_dir(follow_symlinks=False)
                    stat = entry.stat(follow_symlinks=False)
                except OSError as e:
                    errors += 1
                    if first_error is None:
                        first_error = f"{type(e).__name__}:errno={e.errno}"
                    continue

                if is_dir:
                    dirs += 1
                    stack.append(entry.path)
                else:
                    files += 1
                    in_this_dir += 1
                    sz = stat.st_size
                    total_bytes += sz

                    if min_size is None or sz < min_size:
                        min_size = sz
                    if max_size is None or sz > max_size:
                        max_size = sz

                    mt = stat.st_mtime
                    if min_mtime is None or mt < min_mtime:
                        min_mtime = mt
                    if max_mtime is None or mt > max_mtime:
                        max_mtime = mt

                    if atime_samples < 50:
                        atime_samples += 1
                        if abs(stat.st_atime - mt) <= 1:
                            atime_eq_mtime += 1

        files_per_dir.append(in_this_dir)

    elapsed = max(time.time() - start, 1e-6)
    cap_note = "" if stop_reason == "exhausted" else f" ({stop_reason})"

    out: list[str] = [
        f"sample={files}f {dirs}d {syms}sym {errors}err in {elapsed:.2f}s{cap_note}",
        f"rate={files/elapsed:.0f}f/s {dirs/elapsed:.1f}d/s "
        f"{(total_bytes/(1024*1024))/elapsed:.1f}MB/s",
    ]

    if files_per_dir:
        avg_fpd = sum(files_per_dir) / len(files_per_dir)
        out.append(f"files_per_dir avg={avg_fpd:.1f} max={max(files_per_dir)}")

    if atime_samples:
        eq_pct = 100 * atime_eq_mtime / atime_samples
        note = "noatime likely" if eq_pct >= 80 else "atime live"
        out.append(f"atime_eq_mtime={atime_eq_mtime}/{atime_samples} ({note})")

    if min_mtime is not None:
        oldest = datetime.fromtimestamp(min_mtime).strftime("%Y-%m-%d")
        newest = datetime.fromtimestamp(max_mtime).strftime("%Y-%m-%d")
        out.append(f"mtime_range={oldest}..{newest}")

    if min_size is not None:
        out.append(f"size_range={_h(min_size)}..{_h(max_size)}")

    out.append(f"encoding_surrogates={surrogate} max_path_len={max_path_len}")

    if first_error:
        out.append(f"first_err={first_error}")

    return out


def _move_test_line(root: str, trash: str) -> str:
    name = f"_disk_cleaner_check_{os.getpid()}_{int(time.time())}.tmp"
    src = os.path.join(root, name)
    dst = os.path.join(trash, name)

    try:
        with open(src, "wb") as f:
            f.write(b"x" * 1024)
    except OSError as e:
        return f"move_test=ERR write_root:errno={e.errno}"

    try:
        t0 = time.time()
        shutil.move(src, dst)
        dt_ms = (time.time() - t0) * 1000
    except Exception as e:
        if os.path.exists(src):
            try:
                os.remove(src)
            except OSError:
                pass
        return f"move_test=ERR move:{type(e).__name__}"

    ok = os.path.exists(dst) and not os.path.exists(src)

    if os.path.exists(dst):
        try:
            os.remove(dst)
        except OSError:
            pass

    note = "rename ok" if dt_ms < 100 else "slow (probably cross-volume copy)"
    return f"move_root_to_trash_1KB={dt_ms:.2f}ms ({note}) verified={ok}"


def _h(n) -> str:
    v = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(v) < 1024:
            return f"{v:.1f}{unit}"
        v /= 1024
    return f"{v:.1f}PB"
