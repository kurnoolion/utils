import logging
import os
import posixpath
import time

from .categorize import categorize
from .db import connect, get_meta, init_schema, log_scan_error, set_meta

log = logging.getLogger(__name__)

PROGRESS_INTERVAL_SEC = 5


def run_scan(root: str, db_path: str, resume: bool) -> None:
    root_abs = os.path.abspath(root)
    if not os.path.isdir(root_abs):
        raise SystemExit(f"Scan root does not exist or is not a directory: {root_abs}")

    conn = connect(db_path)
    try:
        init_schema(conn)
        _record_or_verify_meta(conn, root_abs, resume)

        completed = {
            row[0] for row in conn.execute("SELECT path FROM completed_dirs")
        }
        stack = _build_initial_stack(conn, completed, root_abs, resume)
        log.info(
            "Starting scan of %s (already-complete dirs: %d, queued: %d)",
            root_abs,
            len(completed),
            len(stack),
        )

        files_seen = 0
        dirs_seen = 0
        errors_seen = 0
        last_progress = time.time()

        while stack:
            rel, abs_path = stack.pop()
            if rel in completed:
                continue

            f, d, errs, subdirs = _scan_one_dir(conn, rel, abs_path)
            files_seen += f
            dirs_seen += d
            errors_seen += errs

            # Mark this dir complete in same transaction as its child rows
            # (handled inside _scan_one_dir).
            completed.add(rel)
            for sub_rel, sub_abs in subdirs:
                if sub_rel not in completed:
                    stack.append((sub_rel, sub_abs))

            now = time.time()
            if now - last_progress >= PROGRESS_INTERVAL_SEC:
                log.info(
                    "progress: files=%d dirs=%d errors=%d stack=%d",
                    files_seen,
                    dirs_seen,
                    errors_seen,
                    len(stack),
                )
                last_progress = now

        set_meta(conn, "scan_completed_at", str(time.time()))
        log.info(
            "Scan complete. files=%d dirs=%d errors=%d",
            files_seen,
            dirs_seen,
            errors_seen,
        )
    finally:
        conn.close()


def _record_or_verify_meta(conn, root_abs: str, resume: bool) -> None:
    existing = get_meta(conn, "scan_root_original")
    if existing is None:
        set_meta(conn, "scan_root_original", root_abs)
        set_meta(conn, "scan_os", os.name)
        set_meta(conn, "scan_started_at", str(time.time()))
        return

    if not resume:
        raise SystemExit(
            f"DB already initialized for root '{existing}'. "
            f"Pass --resume to continue, or use a different --db."
        )
    if existing != root_abs:
        # Allowed: paths in DB are POSIX-relative, so re-anchoring under a
        # different absolute root (e.g. WSL → Windows UNC) just works.
        log.warning(
            "Resuming with root '%s' (originally scanned as '%s'). "
            "Re-anchoring relative paths to new root.",
            root_abs, existing,
        )
        set_meta(conn, "scan_root_resumed_as", root_abs)
        set_meta(conn, "scan_os_resumed_as", os.name)


def _build_initial_stack(
    conn, completed: set[str], root_abs: str, resume: bool
) -> list[tuple[str, str]]:
    """Initial DFS frontier.

    Fresh scan starts at root. Resume seeds the stack with every known
    folder that is not yet in completed_dirs — re-anchored to root_abs at
    runtime, so the OS path format from the original scan doesn't matter.
    """
    if not resume:
        return [("", root_abs)]

    stack: list[tuple[str, str]] = []
    if "" not in completed:
        stack.append(("", root_abs))

    rows = conn.execute(
        "SELECT path FROM entries WHERE kind='folder'"
    ).fetchall()
    for (rel,) in rows:
        if rel and rel not in completed:
            stack.append((rel, _abs_for(root_abs, rel)))
    return stack


def _abs_for(root_abs: str, rel_posix: str) -> str:
    if not rel_posix:
        return root_abs
    native = rel_posix.replace("/", os.sep) if os.sep != "/" else rel_posix
    return os.path.join(root_abs, native)


def _scan_one_dir(conn, rel: str, abs_path: str):
    """Enumerate one directory; insert child rows + completion marker atomically.

    Returns (files_count, dirs_count, errors_count, subdirs_to_visit).
    """
    rows: list[tuple] = []
    subdirs: list[tuple[str, str]] = []
    files = 0
    dirs = 0
    errors = 0

    try:
        scandir_iter = os.scandir(abs_path)
    except OSError as ex:
        # Do NOT mark this directory as completed: a transient failure
        # (e.g. network blip on SMB) would otherwise silently drop the
        # entire subtree on resume. The error is recorded for triage; the
        # dir stays in the resume frontier so the next --resume retries it.
        log_scan_error(conn, rel, f"scandir failed: {ex}")
        return 0, 0, 1, []

    with scandir_iter as it:
        for entry in it:
            child_rel = posixpath.join(rel, entry.name) if rel else entry.name
            try:
                if entry.is_symlink():
                    continue
                is_dir = entry.is_dir(follow_symlinks=False)
                stat = entry.stat(follow_symlinks=False)
            except OSError as ex:
                log_scan_error(conn, child_rel, f"stat failed: {ex}")
                errors += 1
                continue

            if is_dir:
                rows.append(
                    (
                        child_rel, rel, entry.name, "folder",
                        None, None, None,
                        stat.st_ctime, stat.st_mtime, stat.st_atime, None,
                    )
                )
                subdirs.append((child_rel, entry.path))
                dirs += 1
            else:
                ext = os.path.splitext(entry.name)[1].lower() or None
                rows.append(
                    (
                        child_rel, rel, entry.name, "file",
                        stat.st_size, ext, categorize(ext),
                        stat.st_ctime, stat.st_mtime, stat.st_atime, None,
                    )
                )
                files += 1

    with conn:
        if rows:
            conn.executemany(
                "INSERT OR REPLACE INTO entries "
                "(path, parent_path, name, kind, size_bytes, extension, category, "
                " ctime, mtime, atime, error) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                rows,
            )
        conn.execute(
            "INSERT OR IGNORE INTO completed_dirs (path) VALUES (?)", (rel,)
        )

    return files, dirs, errors, subdirs
