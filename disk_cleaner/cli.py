import argparse
import logging

from .check import run_check
from .cleanup import run_cleanup
from .export import run_export
from .finalize import run_finalize
from .scan import run_scan


def main(argv: list[str] | None = None) -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    p = argparse.ArgumentParser(prog="disk_cleaner")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser(
        "scan",
        help="Walk a directory tree and record metadata into a SQLite DB.",
    )
    sp.add_argument("--root", required=True, help="Root directory to scan.")
    sp.add_argument("--db", required=True, help="Path to the SQLite DB.")
    sp.add_argument(
        "--resume",
        action="store_true",
        help="Resume an interrupted scan against the same root.",
    )

    fp = sub.add_parser(
        "finalize",
        help="Compute folder sizes (sum of descendants) after a scan.",
    )
    fp.add_argument("--db", required=True, help="Path to the SQLite DB.")
    fp.add_argument(
        "--force",
        action="store_true",
        help="Allow finalize even if the scan has incomplete folders.",
    )

    ep = sub.add_parser(
        "export-review",
        help="Generate a filtered Excel review file from the DB.",
    )
    ep.add_argument("--db", required=True, help="Path to the SQLite DB.")
    ep.add_argument("--out", required=True, help="Output .xlsx path.")
    ep.add_argument(
        "--min-file-size",
        default="100MB",
        help="Minimum file size to include (e.g. '100MB', '1GB'). Default 100MB.",
    )
    ep.add_argument(
        "--min-folder-size",
        default="1GB",
        help="Minimum folder size to include. Default 1GB.",
    )

    cp = sub.add_parser(
        "cleanup",
        help="Move items marked Delete?=Y in the review xlsx to a trash folder.",
    )
    cp.add_argument("--db", required=True, help="Path to the SQLite DB.")
    cp.add_argument("--review", required=True, help="Marked-up review .xlsx.")
    cp.add_argument(
        "--root",
        required=True,
        help="Source root (re-anchored at runtime to handle cross-OS paths).",
    )
    cp.add_argument(
        "--trash",
        required=True,
        help="Trash folder (must be on the same volume as --root by default).",
    )
    cp.add_argument(
        "--log-dir",
        required=True,
        help="Directory where cleanup_<ts>.log and cleanup_<ts>_errors.log are written.",
    )
    cp.add_argument(
        "--allow-cross-volume",
        action="store_true",
        help="Allow trash on a different volume (slow + doubles I/O).",
    )
    cp.add_argument(
        "--dry-run",
        action="store_true",
        help="Plan and log moves without actually moving anything.",
    )

    chk = sub.add_parser(
        "check",
        help="Probe NAS environment (rate, atime, same-volume, mount, etc).",
    )
    chk.add_argument("--root", required=True, help="Sample subtree of the NAS.")
    chk.add_argument("--trash", required=True, help="Intended trash folder.")
    chk.add_argument(
        "--max-files",
        type=int,
        default=5000,
        help="Cap sample scan at this many files (default 5000).",
    )
    chk.add_argument(
        "--max-seconds",
        type=int,
        default=60,
        help="Cap sample scan at this many seconds (default 60).",
    )

    args = p.parse_args(argv)

    if args.cmd == "scan":
        run_scan(args.root, args.db, args.resume)
    elif args.cmd == "finalize":
        run_finalize(args.db, args.force)
    elif args.cmd == "export-review":
        run_export(args.db, args.out, args.min_file_size, args.min_folder_size)
    elif args.cmd == "cleanup":
        run_cleanup(
            args.db,
            args.review,
            args.root,
            args.trash,
            args.log_dir,
            allow_cross_volume=args.allow_cross_volume,
            dry_run=args.dry_run,
        )
    elif args.cmd == "check":
        run_check(args.root, args.trash, args.max_files, args.max_seconds)


if __name__ == "__main__":
    main()
