# Disk Cleaner — Project Summary

## What we're building
A Python CLI to help clean up an 18TB NAS that is currently 98% full. The same tool runs from Windows or Linux PCs. Designed for use over many sessions across millions of files.

## Approach
A single CLI (`disk_cleaner`) with five subcommands forming a four-phase workflow plus a diagnostic probe:

1. **`check`** *(diagnostic)* — Probe the NAS environment (env, same-vol detection, fs/mount info, sample scan rate, atime liveness, root→trash move test). Prints ~15 compact lines so the output can be pasted back into chat without log files.
2. **`scan`** — Walk the tree from a given root, record per-file/folder metadata into a SQLite database. Resumable per directory.
3. **`finalize`** — Aggregate folder sizes (sum of all descendants). Separate phase so it can re-run without rescanning.
4. **`export-review`** — Generate a filtered Excel review file (only items above size thresholds). The team marks `Delete? = Y` on items to remove.
5. **`cleanup`** — Read the marked-up Excel and **move** tagged items to a trash folder on the same NAS volume. Per-move logging; resumable.

SQLite is the source of truth across all phases. The Excel file is generated and consumed but never primary storage.

## Key decisions
- **SQLite over CSV/Excel as primary store** — Excel cannot handle millions of rows; SQLite gives crash-safe writes and easy resumability.
- **POSIX-style relative paths in DB** — lets you scan on one OS and clean up on another. Cleanup re-anchors paths to its own `--root` at runtime.
- **Trash must be on the same NAS volume** — at 98% full, a cross-volume move would copy + delete and could fill the destination. Forced by default; override flag would be required to bypass.
- **Skip symlinks/junctions** — avoids loops and double-counting.
- **No hash-based duplicate detection in v1** — too slow for 18TB.
- **Resumability is mandatory** — per-directory checkpoint after each transaction; cleanup checkpoints per move.
- **Folder size = sum of contents** computed in a separate `finalize` phase after the walk completes (bottom-up aggregation in SQL).

## Categorization
Files are bucketed by extension into: `text`, `office`, `image`, `video`, `code`, `bin`, `misc`.

## Excel review file
- Filtered by `--min-file-size` (default 100 MB) and `--min-folder-size` (default 1 GB).
- Columns: relative path, size (KB), size (human-readable), kind (File/Folder), category, extension, created, modified, accessed, `Delete?` (Y/N dropdown, defaults to N).
- Sorted by size descending so worst offenders are at the top.

## Caveats flagged to the user
- `atime` (last accessed) is often unreliable — many filesystems disable atime updates for performance.
- On Linux, what we record as "creation date" is actually `ctime` (metadata change time). Best-effort proxy; true birthtime isn't portably available.
- Hardlinks would be double-counted in folder size sums (not solving in v1).

## Progress
- [x] Design discussed and approved (2026-04-18)
- [x] Project scaffold created
- [x] `scan` subcommand implemented (resumable, skips symlinks, logs errors). Resume seeds the DFS frontier from every known-incomplete folder (so deep-tree crashes are recoverable) and re-anchors paths under the current `--root`, so a WSL scan can be resumed from PowerShell with a different abs path.
- [x] `finalize` subcommand implemented (bottom-up folder size aggregation; idempotent; refuses incomplete scan unless `--force`)
- [x] `export-review` subcommand implemented (filtered Excel + Meta sheet, Y/N dropdown on `Delete?`, sorted by size desc, frozen header, autofilter)
- [x] `cleanup` subcommand implemented (reads marked xlsx → moves to trash; resumable; dry-run; refuses cross-volume by default; per-run log + errors-only log)
- [x] `check` subcommand implemented — diagnostic probe that prints ~15 compact lines (env, same-vol detection, fs/mount info, sample scan rate, atime liveness, mtime/size range, encoding sniff, root→trash move test) so the user can paste output back without log files
- [x] Test suite — **66 tests** covering scan, categorize, finalize, export, cleanup, check (all passing)
- [ ] Run `check` on the real NAS and feed output back to tune scan/cleanup defaults
- [ ] Verify the full pipeline on a real NAS subtree

## Testing
Tests live under `tests/`. Run with `python -m pytest` from the project root. Five test files:
- `tests/test_categorize.py` — extension → category mapping.
- `tests/test_scan.py` — scan integration: basic walk, POSIX paths, symlink skipping, scan_meta, completed_dirs, refuse re-init, no-op resume, partial-completion recovery, cross-root refusal, nonexistent/file roots, unreadable-subdir logging.
- `tests/test_finalize.py` — folder size aggregation correctness, idempotence, incomplete-scan refusal + `--force`.
- `tests/test_export.py` — size parsing/formatting, headers, threshold filtering, KB & human columns, default `Delete? = N`, sort by size desc, datetime cells, Meta sheet, refusal for unfinalized/empty DB.
- `tests/test_cleanup.py` — descendant-of-marked-ancestor filtering, file moves, recursive folder moves, case-insensitive Y, blank/N rows ignored, missing source → `source_missing`, dest-collision → `failed`, resume skips terminal & retries failures, dry-run is a no-op, log files written and errors-log filtered correctly, required-column validation, missing root/review refusal, cross-volume refusal + override, and a full `scan→finalize→export→mark→cleanup` round trip.

Two scan tests and one cleanup test are POSIX-only (symlinks, chmod 000, monkeypatched `_same_volume`) and skip cleanly on Windows.

## Usage
```
python -m disk_cleaner check         --root <subtree>  --trash <dir> \
                                     [--max-files 5000] [--max-seconds 60]
python -m disk_cleaner scan          --root <dir>  --db scan.db [--resume]
python -m disk_cleaner finalize      --db scan.db  [--force]
python -m disk_cleaner export-review --db scan.db  --out review.xlsx \
                                     [--min-file-size 100MB] [--min-folder-size 1GB]
python -m disk_cleaner cleanup       --db scan.db  --review review.xlsx \
                                     --root <dir>  --trash <dir>  --log-dir <dir> \
                                     [--dry-run] [--allow-cross-volume]
```

## Recommended workflow
1. **`check`** first against a small representative subtree of the NAS to verify environment (same-volume detection, atime liveness, scan throughput).
2. **`scan`** the real root (likely takes hours; resumable).
3. **`finalize`** to compute folder sizes.
4. **`export-review`** with thresholds tuned to the size distribution observed in `check`.
5. Team marks `Delete?` column.
6. **`cleanup --dry-run`** first; review log; then real run.

## Cleanup behavior details
- **Reads `Delete?` column case-insensitively** (`Y` or `y` triggers; anything else is skipped).
- **Parent/child overlap**: if a folder is marked Y and any of its descendants are also marked Y, the descendants are silently dropped from the plan — only the folder is moved.
- **Trash structure**: mirrors source (e.g. `trash/foo/bar/file.txt`). Same-volume moves are atomic renames.
- **Same-volume enforcement**: refused unless `--allow-cross-volume`. On POSIX uses `st_dev`; on Windows compares drive letters / UNC roots.
- **Resumability**: every attempt is recorded in the `moves` table with a `status` of `moved`, `source_missing`, or `failed`. On resume, terminal statuses (`moved`, `source_missing`) are skipped; `failed` rows are retried.
- **Missing source** at cleanup time → recorded as `source_missing` (treated as terminal — the desired end state already holds).
- **Existing destination** → move refused with `FileExistsError`, recorded as `failed`. No silent overwrites.
- **Dry-run**: walks the plan and logs would-move lines without touching filesystem or DB.
- **Logs**: per run, two files in `--log-dir`: `cleanup_<timestamp>.log` (full INFO-level history) and `cleanup_<timestamp>_errors.log` (WARNING+ only, for quick failure triage).

## Next steps
1. **User runs `check` on the real NAS** and pastes the output back. We use it to confirm same-volume detection, mount type, and scan throughput.
2. Based on `check` output, we may tune: per-dir transaction batching (if scan rate is slow), default review thresholds (based on observed size range), and document atime reliability for the team.
3. **Run `scan` against a small subtree first** to verify behavior end-to-end, including a deliberate Ctrl-C / `--resume` cycle.
4. **Run the full pipeline** (scan → finalize → export-review → mark → cleanup --dry-run → cleanup) on real data.

## Possible v2 enhancements (not in scope unless requested)
- Hash-based duplicate detection (separate pass — too slow for v1).
- Auto-purge of stale `entries` rows for paths that no longer exist on disk.
- Simple "undo" command that reverses a cleanup run from the `moves` table.
