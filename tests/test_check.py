import os
import sys
from pathlib import Path

import pytest

from disk_cleaner.check import VERSION, _h, _move_test_line, run_check


def _build_tree(root: Path) -> None:
    (root / "a.txt").write_bytes(b"x" * 100)
    (root / "sub").mkdir()
    (root / "sub" / "b.bin").write_bytes(b"y" * 5000)
    (root / "sub" / "c.bin").write_bytes(b"z" * 200)


def _run(tmp_path, capsys, **kwargs) -> str:
    root = tmp_path / "src"
    trash = tmp_path / "trash"
    root.mkdir()
    trash.mkdir()
    _build_tree(root)
    run_check(str(root), str(trash), **kwargs)
    return capsys.readouterr().out


def test_check_outputs_expected_sections(tmp_path, capsys):
    out = _run(tmp_path, capsys)
    assert f"== dc check v{VERSION} ==" in out
    assert "== end ==" in out
    assert "env=" in out
    assert "root=" in out
    assert "trash=" in out
    assert "same_vol=" in out
    assert "fs total=" in out
    assert "sample=" in out
    assert "rate=" in out
    assert "files_per_dir avg=" in out
    assert "size_range=" in out
    assert "mtime_range=" in out
    assert "encoding_surrogates=" in out
    assert "move_root_to_trash_1KB=" in out


def test_check_same_volume_true_for_sibling_paths(tmp_path, capsys):
    out = _run(tmp_path, capsys)
    # Both root and trash are siblings under tmp_path -> same st_dev
    assert "same_vol=True" in out


def test_check_fatal_when_root_missing(tmp_path, capsys):
    trash = tmp_path / "trash"
    trash.mkdir()
    run_check(str(tmp_path / "no_such"), str(trash))
    out = capsys.readouterr().out
    assert "FATAL root_not_dir" in out
    assert "== end ==" in out
    # Should not have crashed before printing footer
    assert "sample=" not in out


def test_check_respects_file_cap(tmp_path, capsys):
    root = tmp_path / "src"
    trash = tmp_path / "trash"
    root.mkdir()
    trash.mkdir()
    for i in range(20):
        (root / f"f{i}.bin").write_bytes(b"x")

    run_check(str(root), str(trash), max_files=5)
    out = capsys.readouterr().out
    # We capped at 5
    assert "sample=5f " in out
    assert "(cap_files)" in out


def test_check_move_test_cleans_up_test_files(tmp_path):
    root = tmp_path / "src"
    trash = tmp_path / "trash"
    root.mkdir()
    trash.mkdir()
    _move_test_line(str(root), str(trash))

    # No leftover _disk_cleaner_check files in either location
    leftovers = list(root.glob("_disk_cleaner_check_*")) + list(
        trash.glob("_disk_cleaner_check_*")
    )
    assert leftovers == []


def test_check_move_test_reports_verified_true(tmp_path):
    root = tmp_path / "src"
    trash = tmp_path / "trash"
    root.mkdir()
    trash.mkdir()
    line = _move_test_line(str(root), str(trash))
    assert "verified=True" in line
    assert line.startswith("move_root_to_trash_1KB=")


def test_check_move_test_handles_unwritable_root(tmp_path):
    if sys.platform == "win32":
        pytest.skip("chmod test for posix")
    root = tmp_path / "src"
    trash = tmp_path / "trash"
    root.mkdir()
    trash.mkdir()
    os.chmod(root, 0o500)  # read+execute only — no write
    try:
        line = _move_test_line(str(root), str(trash))
    finally:
        os.chmod(root, 0o755)
    assert line.startswith("move_test=ERR write_root:")


def test_h_formats_human_sizes():
    assert _h(0) == "0.0B"
    assert _h(1024) == "1.0KB"
    assert _h(1024 * 1024) == "1.0MB"
    assert _h(int(2.5 * 1024**3)) == "2.5GB"


def test_check_skips_move_test_if_trash_missing(tmp_path, capsys):
    root = tmp_path / "src"
    root.mkdir()
    _build_tree(root)
    run_check(str(root), str(tmp_path / "no_trash"))
    out = capsys.readouterr().out
    assert "move_test=skipped" in out
    assert "trash missing" in out


def test_check_output_is_compact(tmp_path, capsys):
    """Each line should be short enough to comfortably type back into chat."""
    out = _run(tmp_path, capsys)
    lines = out.strip().splitlines()
    # The whole report should fit in a screen
    assert len(lines) <= 20, f"too many lines ({len(lines)}): {lines}"
    # No single line should be obscenely long
    for line in lines:
        assert len(line) <= 200, f"line too long ({len(line)} chars): {line!r}"
