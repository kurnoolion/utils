import os
import sqlite3
import sys
from pathlib import Path

import pytest

from disk_cleaner.scan import run_scan


def _make_tree(root: Path) -> None:
    """Build:
        root/
          a.txt              (12 bytes)
          sub1/
            b.docx           (4 bytes)
            sub2/
              big.bin        (10240 bytes)
          sub3/
            c.PNG            (4 bytes — uppercase extension on purpose)
    """
    (root / "a.txt").write_text("hello world\n")
    (root / "sub1" / "sub2").mkdir(parents=True)
    (root / "sub1" / "b.docx").write_text("doc\n")
    (root / "sub1" / "sub2" / "big.bin").write_bytes(b"\0" * 10240)
    (root / "sub3").mkdir()
    (root / "sub3" / "c.PNG").write_text("img\n")


def _query(db_path, sql, params=()):
    conn = sqlite3.connect(str(db_path))
    try:
        return conn.execute(sql, params).fetchall()
    finally:
        conn.close()


def test_basic_scan_records_files_and_folders(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _make_tree(root)
    db = tmp_path / "scan.db"

    run_scan(str(root), str(db), resume=False)

    rows = _query(
        db,
        "SELECT path, kind, size_bytes, extension, category FROM entries",
    )
    by_path = {r[0]: r[1:] for r in rows}

    assert by_path["a.txt"] == ("file", 12, ".txt", "text")
    assert by_path["sub1/b.docx"] == ("file", 4, ".docx", "office")
    assert by_path["sub1/sub2/big.bin"] == ("file", 10240, ".bin", "bin")
    # extension is lowercased even though file on disk is .PNG
    assert by_path["sub3/c.PNG"] == ("file", 4, ".png", "image")

    # folders have NULL size until finalize phase
    assert by_path["sub1"] == ("folder", None, None, None)
    assert by_path["sub3"] == ("folder", None, None, None)
    assert by_path["sub1/sub2"] == ("folder", None, None, None)


def test_parent_paths_are_correct(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _make_tree(root)
    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    parents = dict(_query(db, "SELECT path, parent_path FROM entries"))
    assert parents["a.txt"] == ""
    assert parents["sub1"] == ""
    assert parents["sub1/b.docx"] == "sub1"
    assert parents["sub1/sub2"] == "sub1"
    assert parents["sub1/sub2/big.bin"] == "sub1/sub2"


def test_paths_use_forward_slashes(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _make_tree(root)
    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    for (p,) in _query(db, "SELECT path FROM entries"):
        assert "\\" not in p, f"backslash leaked into stored path: {p!r}"


@pytest.mark.skipif(sys.platform == "win32", reason="POSIX symlink test")
def test_symlinks_are_skipped(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    (root / "real.txt").write_text("ok")
    os.symlink("/tmp", root / "link_to_tmp")

    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    paths = {p for (p,) in _query(db, "SELECT path FROM entries")}
    assert "real.txt" in paths
    assert "link_to_tmp" not in paths


def test_scan_meta_recorded(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    meta = dict(_query(db, "SELECT key, value FROM scan_meta"))
    assert meta["scan_root_original"] == os.path.abspath(str(root))
    assert "scan_started_at" in meta
    assert "scan_completed_at" in meta
    assert meta["scan_os"] == os.name


def test_completed_dirs_covers_root_and_all_subdirs(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _make_tree(root)
    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    completed = {p for (p,) in _query(db, "SELECT path FROM completed_dirs")}
    assert completed == {"", "sub1", "sub1/sub2", "sub3"}


def test_rerun_without_resume_refuses(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    with pytest.raises(SystemExit, match="already initialized"):
        run_scan(str(root), str(db), resume=False)


def test_resume_on_complete_db_is_noop(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _make_tree(root)
    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    before = _query(db, "SELECT COUNT(*) FROM entries")[0][0]
    run_scan(str(root), str(db), resume=True)
    after = _query(db, "SELECT COUNT(*) FROM entries")[0][0]
    assert before == after == 7


def test_resume_after_partial_completion_picks_up_new_files(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _make_tree(root)
    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    # Simulate crash mid-sub1: drop its completion marker + one of its entries.
    conn = sqlite3.connect(str(db))
    conn.execute("DELETE FROM completed_dirs WHERE path='sub1'")
    conn.execute("DELETE FROM entries WHERE path='sub1/b.docx'")
    conn.commit()
    conn.close()

    # A new file appears in sub1 before resume.
    (root / "sub1" / "new_after_crash.md").write_text("new\n")

    run_scan(str(root), str(db), resume=True)

    sub1_children = {
        p for (p,) in _query(
            db, "SELECT path FROM entries WHERE parent_path='sub1'"
        )
    }
    assert "sub1/b.docx" in sub1_children            # re-discovered
    assert "sub1/new_after_crash.md" in sub1_children  # newly seen on resume
    assert "sub1/sub2" in sub1_children              # still recorded as folder

    # sub1/sub2 was already complete and should NOT have been re-enumerated
    # (it was not deleted from completed_dirs).
    completed = {p for (p,) in _query(db, "SELECT path FROM completed_dirs")}
    assert "sub1/sub2" in completed
    assert "sub1" in completed  # re-completed during resume


def test_resume_with_different_root_succeeds_and_reanchors(tmp_path):
    """Cross-OS resume case: scan from root1, resume from root2 (different
    abs path) — should pick up the same logical tree and finish the work."""
    root1 = tmp_path / "a"
    root2 = tmp_path / "b"
    root1.mkdir()
    _make_tree(root1)
    db = tmp_path / "scan.db"
    run_scan(str(root1), str(db), resume=False)

    # Build an identical tree under a different root and resume there.
    root2.mkdir()
    _make_tree(root2)
    run_scan(str(root2), str(db), resume=True)

    meta = dict(_query(db, "SELECT key, value FROM scan_meta"))
    assert meta["scan_root_original"] == os.path.abspath(str(root1))
    assert meta["scan_root_resumed_as"] == os.path.abspath(str(root2))


def test_resume_recovers_deep_subtree(tmp_path):
    """Crash deep in the tree must not leave incomplete work behind on resume.

    Regression: previously, resume only descended one level into already-
    completed dirs, so an incomplete grandchild was unreachable.
    """
    root = tmp_path / "tree"
    deep = root / "A" / "X" / "Y" / "Z"
    deep.mkdir(parents=True)
    (deep / "leaf.txt").write_text("deep")
    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    # Simulate crash *inside* Z: drop Z's completion marker + its leaf.
    conn = sqlite3.connect(str(db))
    conn.execute("DELETE FROM completed_dirs WHERE path='A/X/Y/Z'")
    conn.execute("DELETE FROM entries WHERE path='A/X/Y/Z/leaf.txt'")
    conn.commit()
    conn.close()

    run_scan(str(root), str(db), resume=True)

    paths = {p for (p,) in _query(db, "SELECT path FROM entries")}
    assert "A/X/Y/Z/leaf.txt" in paths

    completed = {p for (p,) in _query(db, "SELECT path FROM completed_dirs")}
    assert "A/X/Y/Z" in completed


def test_nonexistent_root_raises(tmp_path):
    db = tmp_path / "scan.db"
    with pytest.raises(SystemExit, match="does not exist"):
        run_scan(str(tmp_path / "no_such_dir"), str(db), resume=False)


def test_root_that_is_a_file_raises(tmp_path):
    f = tmp_path / "file.txt"
    f.write_text("x")
    db = tmp_path / "scan.db"
    with pytest.raises(SystemExit, match="not a directory"):
        run_scan(str(f), str(db), resume=False)


@pytest.mark.skipif(sys.platform == "win32", reason="POSIX permission test")
def test_unreadable_subdir_logs_error_and_continues(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    (root / "good.txt").write_text("ok")
    bad = root / "bad_dir"
    bad.mkdir()
    (bad / "hidden.txt").write_text("nope")
    os.chmod(bad, 0o000)

    db = tmp_path / "scan.db"
    try:
        run_scan(str(root), str(db), resume=False)
    finally:
        os.chmod(bad, 0o755)  # restore so tmp_path cleanup works

    paths = {p for (p,) in _query(db, "SELECT path FROM entries")}
    assert "good.txt" in paths
    assert "bad_dir" in paths               # listed by parent's scandir
    assert "bad_dir/hidden.txt" not in paths  # could not enumerate

    errors = _query(db, "SELECT path, error FROM scan_errors")
    assert any(p == "bad_dir" for p, _ in errors)


def test_scandir_failure_does_not_mark_dir_complete(tmp_path, monkeypatch):
    """Regression: a transient OSError from os.scandir (e.g. SMB network
    blip) used to mark the directory complete, silently dropping its
    entire subtree on resume. It must now leave the dir in the frontier.
    """
    import disk_cleaner.scan as scan_mod

    root = tmp_path / "tree"
    sub = root / "flaky"
    sub.mkdir(parents=True)
    (sub / "child.txt").write_text("hi")
    (root / "ok.txt").write_text("ok")

    real_scandir = os.scandir
    failed = {"flaky": False}

    def flaky_scandir(path):
        if os.path.basename(str(path)) == "flaky" and not failed["flaky"]:
            failed["flaky"] = True
            raise OSError("simulated network blip")
        return real_scandir(path)

    monkeypatch.setattr(scan_mod.os, "scandir", flaky_scandir)

    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    completed = {p for (p,) in _query(db, "SELECT path FROM completed_dirs")}
    assert "flaky" not in completed, "transient scandir failure must not mark dir complete"

    errors = {p for (p, _e) in _query(db, "SELECT path, error FROM scan_errors")}
    assert "flaky" in errors

    # After the blip is gone, --resume picks the dir back up.
    monkeypatch.setattr(scan_mod.os, "scandir", real_scandir)
    run_scan(str(root), str(db), resume=True)

    paths = {p for (p,) in _query(db, "SELECT path FROM entries")}
    assert "flaky/child.txt" in paths
    completed = {p for (p,) in _query(db, "SELECT path FROM completed_dirs")}
    assert "flaky" in completed


def test_file_with_no_extension_is_misc(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    (root / "Makefile").write_text("all:\n")
    db = tmp_path / "scan.db"
    run_scan(str(root), str(db), resume=False)

    rows = _query(
        db,
        "SELECT extension, category FROM entries WHERE path='Makefile'",
    )
    assert rows == [(None, "misc")]
