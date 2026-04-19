import sqlite3
from pathlib import Path

import pytest

from disk_cleaner.finalize import run_finalize
from disk_cleaner.scan import run_scan


def _query(db, sql, params=()):
    conn = sqlite3.connect(str(db))
    try:
        return conn.execute(sql, params).fetchall()
    finally:
        conn.close()


def _build_tree(root: Path) -> None:
    """root/
         a.txt              (10 bytes)
         sub1/
           b.bin            (100 bytes)
           sub2/
             big.bin        (10000 bytes)
         empty_dir/         (no files anywhere)
         sub3/
           c.png            (50 bytes)
    """
    (root / "a.txt").write_bytes(b"x" * 10)
    (root / "sub1" / "sub2").mkdir(parents=True)
    (root / "sub1" / "b.bin").write_bytes(b"y" * 100)
    (root / "sub1" / "sub2" / "big.bin").write_bytes(b"z" * 10000)
    (root / "empty_dir").mkdir()
    (root / "sub3").mkdir()
    (root / "sub3" / "c.png").write_bytes(b"i" * 50)


def test_finalize_computes_correct_folder_sizes(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _build_tree(root)
    db = tmp_path / "scan.db"

    run_scan(str(root), str(db), resume=False)
    run_finalize(str(db))

    sizes = dict(
        _query(
            db,
            "SELECT path, size_bytes FROM entries WHERE kind='folder'",
        )
    )
    assert sizes["sub1/sub2"] == 10000
    assert sizes["sub1"] == 10100              # 100 (b.bin) + 10000 (sub2)
    assert sizes["sub3"] == 50
    assert sizes["empty_dir"] == 0


def test_finalize_records_meta(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    db = tmp_path / "scan.db"

    run_scan(str(root), str(db), resume=False)
    run_finalize(str(db))

    meta = dict(_query(db, "SELECT key, value FROM scan_meta"))
    assert "finalized_at" in meta


def test_finalize_is_idempotent(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _build_tree(root)
    db = tmp_path / "scan.db"

    run_scan(str(root), str(db), resume=False)
    run_finalize(str(db))
    sizes_first = dict(
        _query(db, "SELECT path, size_bytes FROM entries WHERE kind='folder'")
    )
    run_finalize(str(db))
    sizes_second = dict(
        _query(db, "SELECT path, size_bytes FROM entries WHERE kind='folder'")
    )
    assert sizes_first == sizes_second


def test_finalize_refuses_incomplete_scan(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _build_tree(root)
    db = tmp_path / "scan.db"

    run_scan(str(root), str(db), resume=False)

    # Simulate an incomplete scan by removing one completion marker.
    conn = sqlite3.connect(str(db))
    conn.execute("DELETE FROM completed_dirs WHERE path='sub1/sub2'")
    conn.commit()
    conn.close()

    with pytest.raises(SystemExit, match="Scan is incomplete"):
        run_finalize(str(db))


def test_finalize_force_proceeds_on_incomplete_scan(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    _build_tree(root)
    db = tmp_path / "scan.db"

    run_scan(str(root), str(db), resume=False)

    conn = sqlite3.connect(str(db))
    conn.execute("DELETE FROM completed_dirs WHERE path='sub1/sub2'")
    conn.commit()
    conn.close()

    run_finalize(str(db), force=True)
    # Sizes still computed from whatever entries exist
    sizes = dict(
        _query(db, "SELECT path, size_bytes FROM entries WHERE kind='folder'")
    )
    assert sizes["sub1"] == 10100


def test_finalize_on_db_without_scan_raises(tmp_path):
    db = tmp_path / "empty.db"
    # Touch the file so connect() works but no scan_meta rows exist.
    sqlite3.connect(str(db)).close()
    with pytest.raises(SystemExit, match="no scan to finalize"):
        run_finalize(str(db))


def test_finalize_handles_tree_with_no_files(tmp_path):
    root = tmp_path / "tree"
    root.mkdir()
    (root / "a" / "b").mkdir(parents=True)
    db = tmp_path / "scan.db"

    run_scan(str(root), str(db), resume=False)
    run_finalize(str(db))

    sizes = dict(
        _query(db, "SELECT path, size_bytes FROM entries WHERE kind='folder'")
    )
    assert sizes == {"a": 0, "a/b": 0}
