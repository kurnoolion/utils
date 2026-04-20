# disk_cleaner

A Python CLI for staging cleanup of large, near-full NAS storage. Built for an 18 TB NAS at 98% capacity, but works on any directory tree. Scans millions of files into SQLite, generates a filtered Excel review file for human triage, then moves marked items to a trash folder for later deletion.

Runs identically on Windows and Linux. Same scan can be reviewed/cleaned up from a different OS than the one that produced it.

## Why this shape

- **Two-phase: scan → human review → act.** A person decides every deletion. The tool stages moves to a trash folder; nothing is ever deleted.
- **Resumable everywhere.** Multi-TB scans take hours to days; per-directory checkpoints make Ctrl-C harmless.
- **No silent data loss.** Existing trash destinations cause a failure (no overwrites). Cross-volume moves are refused by default (would copy + delete and could fill a near-full disk).

## Requirements

- Python 3.10+ (uses `X | None` annotation syntax)
- `openpyxl` (only third-party dep; for the Excel review file)
- That's it. No install step — run from the project directory.

## Quick start

```bash
# 0. Probe the NAS environment (one-shot diagnostic, prints ~15 lines)
python -m disk_cleaner check --root /mnt/nas/subfolder --trash /mnt/nas/.trash

# 1. Scan the tree into SQLite (resumable; rerun with --resume after Ctrl-C)
python -m disk_cleaner scan --root /mnt/nas --db nas.db

# 2. Compute folder sizes (sum of descendants)
python -m disk_cleaner finalize --db nas.db

# 3. Export a filtered Excel review file
python -m disk_cleaner export-review --db nas.db --out review.xlsx \
    --min-file-size 100MB --min-folder-size 1GB

# 4. Team marks Delete?=Y on rows in review.xlsx (Y/N dropdown).

# 5. Dry-run cleanup, inspect the log, then run for real
python -m disk_cleaner cleanup --db nas.db --review review.xlsx \
    --root /mnt/nas --trash /mnt/nas/.trash --log-dir ./logs --dry-run

python -m disk_cleaner cleanup --db nas.db --review review.xlsx \
    --root /mnt/nas --trash /mnt/nas/.trash --log-dir ./logs
```

## Commands

### `check` — probe the NAS environment

```
python -m disk_cleaner check --root <subtree> --trash <dir>
                             [--max-files 5000] [--max-seconds 60]
```

Prints a compact diagnostic report. Useful before running `scan` on the full NAS to verify same-volume detection, mount type, scan throughput, atime liveness, and that root→trash moves are atomic renames.

Sample output:
```
== dc check v1 ==
env=linux py=3.12.3 enc=utf-8 tz=-0400
root=/mnt/nas/photos exists=True
trash=/mnt/nas/.trash exists=True
same_vol=True dev_root=64769 dev_trash=64769
fs total=18.0TB free=320.0GB used=98.2%
mount=cifs src=//nas/share opts=rw,vers=3.0
sample=5000f 142d 3sym 0err in 18.32s (cap_files)
rate=273f/s 7.8d/s 45.2MB/s
files_per_dir avg=35.2 max=1248
atime_eq_mtime=42/50 (noatime likely)
mtime_range=2018-03-12..2026-04-15
size_range=12.0B..2.3GB
encoding_surrogates=0 max_path_len=142
move_root_to_trash_1KB=0.42ms (rename ok) verified=True
== end ==
```

### `scan` — walk the tree into SQLite

```
python -m disk_cleaner scan --root <dir> --db <path.db> [--resume]
```

- Walks every file and folder under `--root`, recording metadata in SQLite.
- Skips symlinks/junctions (avoids loops and double-counting).
- Per-directory transaction with checkpoint, so Ctrl-C loses at most one directory's worth of work.
- `--resume` continues an interrupted scan. The DB stores POSIX-relative paths, so resuming under a *different* absolute root (e.g. you started from WSL `/mnt/y/share` and want to resume from PowerShell `\\nas\share`) is allowed — paths are re-anchored to whatever `--root` you pass. The original root is preserved in `scan_meta` for audit; the new one is recorded as `scan_root_resumed_as`.
- Logs progress every 5 seconds: `files=N dirs=N errors=N stack=N`.
- Permission errors on individual files/dirs are logged to the `scan_errors` table and the scan continues.

### `finalize` — compute folder sizes

```
python -m disk_cleaner finalize --db <path.db> [--force]
```

- Aggregates each folder's `size_bytes` as the sum of all descendant files.
- Bottom-up via parent-chain propagation; O(n_files × avg_depth).
- Refuses to run if any folder in `entries` is missing from `completed_dirs` (incomplete scan). Override with `--force`.
- Idempotent — safe to re-run.

### `export-review` — generate the Excel review file

```
python -m disk_cleaner export-review --db <path.db> --out <review.xlsx>
                                     [--min-file-size 100MB]
                                     [--min-folder-size 1GB]
```

Two sheets:

- **`Review`** — one row per file/folder above the size thresholds, sorted by size descending.
- **`Meta`** — scan root, OS, timestamps, the thresholds used, and row count. Audit trail.

`Review` columns:

| # | Column         | Notes                                              |
|---|----------------|----------------------------------------------------|
| 1 | Path           | POSIX-style, relative to scan root                  |
| 2 | Size (KB)      | Numeric                                             |
| 3 | Size (Human)   | "1.4 GB", "350.0 MB", etc.                          |
| 4 | Type           | `File` or `Folder`                                  |
| 5 | Category       | text / office / image / video / code / bin / misc   |
| 6 | Extension      | Lowercased, with leading dot                        |
| 7 | Created        | datetime — `ctime` (best-effort, see Caveats)       |
| 8 | Modified       | datetime                                            |
| 9 | Accessed       | datetime — see Caveats re: noatime                  |
|10 | Delete?        | Y/N dropdown, defaults to N                         |

Header row is bold + frozen; an autofilter is applied; column widths are pre-set.

Size thresholds accept `B`, `KB`, `MB`, `GB`, `TB` (binary, 1024-based). Bare numbers are bytes.

### `cleanup` — move marked items to trash

```
python -m disk_cleaner cleanup --db <path.db> --review <review.xlsx>
                               --root <dir> --trash <dir> --log-dir <dir>
                               [--dry-run] [--allow-cross-volume]
```

- Reads `Delete?` case-insensitively (`Y` or `y` triggers; anything else is skipped).
- **Parent/child overlap**: if a folder is marked `Y` and any of its descendants are also marked `Y`, the descendants are silently dropped from the plan — only the folder is moved.
- **Trash structure mirrors source** (e.g. `trash/foo/bar/file.txt`). Same-volume moves are atomic renames.
- **Same-volume enforcement** is on by default; refused unless `--allow-cross-volume`. On POSIX compares `st_dev`; on Windows compares drive letters / UNC roots.
- **Resumable**: every attempt is recorded in the `moves` table with `status` ∈ {`moved`, `source_missing`, `failed`}. On resume, terminal statuses are skipped; `failed` rows are retried.
- **Missing source** at cleanup time → recorded as `source_missing` (terminal — desired end state already holds).
- **Existing destination** → move refused (no silent overwrites), recorded as `failed`.
- `--dry-run` plans and logs would-move lines without touching filesystem or DB.

Two log files per run, in `--log-dir`:

- `cleanup_<timestamp>.log` — full INFO-level history of attempts.
- `cleanup_<timestamp>_errors.log` — WARNING+ only, for quick failure triage.

## Cross-OS path handling

The DB stores paths as **POSIX-style and relative to the scan root**. The scan also records the original root and OS in a `scan_meta` table for audit. At cleanup time the tool re-anchors paths to whatever `--root` you pass at runtime.

So you can scan from Linux (`/mnt/nas/share`) and clean up from Windows (`\\nas\share`) — the relative paths in the Excel are the same; only the `--root` differs.

## Caveats

- **`atime` is often unreliable.** Many filesystems (and NFS/SMB mount options) suppress access-time updates for performance. Run `check` first; if it reports `noatime likely`, treat the "Accessed" column as untrustworthy.
- **"Created" date on Linux is `ctime`** (metadata change time), not true birth time. `st_birthtime` isn't portably available. On Windows it's the actual creation time.
- **Hardlinks are double-counted** in folder size sums. Not solving in v1.
- **No hash-based dedup in v1** — too slow for 18 TB. Could be added as a separate pass later.
- **Re-scanning after cleanup** is not the intended workflow. Cleanup is a one-shot. If you need to re-scan, use a fresh DB.

## Troubleshooting

The DB is plain SQLite — when something looks off, query it directly. All recipes assume `nas.db` in the current directory.

### Verify a scan covered every folder

```powershell
python -c "import sqlite3; c=sqlite3.connect('nas.db'); folders=c.execute(\"SELECT COUNT(*) FROM entries WHERE kind='folder'\").fetchone()[0]; done=c.execute('SELECT COUNT(*) FROM completed_dirs').fetchone()[0]; missing=c.execute(\"SELECT path FROM entries WHERE kind='folder' AND path NOT IN (SELECT path FROM completed_dirs)\").fetchall(); print(f'folders={folders} completed={done+1} (incl. root)'); print('incomplete:', missing if missing else 'none')"
```

`incomplete: none` means every known folder was fully enumerated. `+1` accounts for the empty-string root path which is in `completed_dirs` but not in `entries`.

### Inspect scan errors

```powershell
python -c "import sqlite3; c=sqlite3.connect('nas.db'); rows=c.execute('SELECT path, error FROM scan_errors').fetchall(); print(f'{len(rows)} errors:'); [print(' ', p, '-', e) for p,e in rows]"
```

`scandir failed: ...` rows are directories the tool couldn't enumerate — usually a transient network blip on SMB. Permission-denied on individual files appears as `stat failed: ...`.

### Recover from a network blip mid-scan

If `scan_errors` shows `scandir failed: ...` rows, the tool now leaves those folders in the resume frontier — just rerun with `--resume` and they'll be retried:

```powershell
python -m disk_cleaner scan --root <root> --db nas.db --resume
```

If you have an **older DB** scanned before this fix (where failed folders were incorrectly marked complete), re-queue them once before resuming:

```powershell
python -c "import sqlite3; c=sqlite3.connect('nas.db'); n=c.execute(\"DELETE FROM completed_dirs WHERE path IN (SELECT path FROM scan_errors WHERE error LIKE 'scandir failed:%')\").rowcount; c.commit(); print(f'requeued {n} folders')"

python -m disk_cleaner scan --root <root> --db nas.db --resume
```

### Resume across OSes (WSL → PowerShell, etc.)

Just point `--root` at the new path. The DB stores POSIX-relative paths and re-anchors automatically. You'll see a one-line warning on resume; the original root is preserved in `scan_meta` and the new one is recorded as `scan_root_resumed_as`.

```powershell
python -m disk_cleaner scan --root \\nas\share --db nas.db --resume
```

### Check cleanup state

```powershell
python -c "import sqlite3; c=sqlite3.connect('nas.db'); rows=c.execute('SELECT status, COUNT(*) FROM moves GROUP BY status').fetchall(); [print(f'  {s}: {n}') for s,n in rows]"
```

Failed rows can be inspected with `SELECT rel_path, error FROM moves WHERE status='failed'`. Re-running `cleanup` retries them automatically.

## Project layout

```
utils/
├── README_DISK_CLEANER.md
├── DISK_CLEANER_SUMMARY.md     # project state, decisions, progress
├── pyproject.toml              # pytest config only
├── disk_cleaner/
│   ├── __init__.py
│   ├── __main__.py             # `python -m disk_cleaner` entry
│   ├── cli.py                  # argparse, subcommand dispatch
│   ├── db.py                   # SQLite schema + helpers
│   ├── categorize.py           # extension → category map
│   ├── check.py                # diagnostic probe
│   ├── scan.py                 # tree walker (resumable)
│   ├── finalize.py             # folder size aggregation
│   ├── export.py               # SQLite → Excel
│   └── cleanup.py              # Excel → moves
└── tests/
    ├── test_categorize.py
    ├── test_check.py
    ├── test_cleanup.py
    ├── test_export.py
    ├── test_finalize.py
    └── test_scan.py
```

## SQLite schema

The DB is the source of truth across all phases.

- **`scan_meta(key, value)`** — scan root, OS, started/completed/finalized timestamps.
- **`entries(path PK, parent_path, name, kind, size_bytes, extension, category, ctime, mtime, atime, error)`** — one row per file or folder. `path` is POSIX-relative. For folders, `size_bytes` is `NULL` until `finalize` runs.
- **`completed_dirs(path PK)`** — directories whose immediate children have been written. Drives scan resumability.
- **`scan_errors(path, error, occurred_at)`** — non-fatal errors during scan.
- **`moves(rel_path PK, kind, size_bytes, dest_path, attempted_at, status, error)`** — cleanup attempts. `status` ∈ {`moved`, `source_missing`, `failed`}.

## Testing

```bash
python -m pytest          # 66 tests, ~3 seconds
```

Three POSIX-only tests (symlinks, `chmod 000`, monkeypatched same-volume) skip cleanly on Windows.

## License

Internal tool — no license attached.
