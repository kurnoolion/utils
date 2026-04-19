import logging
import time
from collections import defaultdict

from .db import connect, has_scan, set_meta

log = logging.getLogger(__name__)


def run_finalize(db_path: str, force: bool = False) -> None:
    """Aggregate folder sizes (sum of all descendant file sizes) into entries.size_bytes.

    Walks files once, propagating each file's size up its parent chain via the
    folder->parent map. O(n_files * avg_depth).
    """
    conn = connect(db_path)
    try:
        if not has_scan(conn):
            raise SystemExit(f"DB has no scan to finalize: {db_path}")

        incomplete = conn.execute(
            "SELECT COUNT(*) FROM entries "
            "WHERE kind='folder' AND path NOT IN (SELECT path FROM completed_dirs)"
        ).fetchone()[0]
        if incomplete and not force:
            raise SystemExit(
                f"Scan is incomplete: {incomplete} folders not yet enumerated. "
                f"Resume the scan first, or pass --force to finalize anyway."
            )

        log.info("Loading folder parent map...")
        parent_of_folder = dict(
            conn.execute(
                "SELECT path, parent_path FROM entries WHERE kind='folder'"
            )
        )
        log.info("  %d folders", len(parent_of_folder))

        log.info("Aggregating file sizes up parent chains...")
        sizes: dict[str, int] = defaultdict(int)
        n_files = 0
        for parent, size in conn.execute(
            "SELECT parent_path, size_bytes FROM entries WHERE kind='file'"
        ):
            n_files += 1
            if size is None:
                continue
            p = parent
            while p:  # '' (root) is not an entry — terminate cleanly
                sizes[p] += size
                p = parent_of_folder.get(p, "")
        log.info("  %d files contributed", n_files)

        # Folders with no descendant files get size 0.
        for folder in parent_of_folder:
            sizes.setdefault(folder, 0)

        log.info("Writing folder sizes...")
        with conn:
            conn.executemany(
                "UPDATE entries SET size_bytes=? WHERE path=? AND kind='folder'",
                [(s, p) for p, s in sizes.items()],
            )

        set_meta(conn, "finalized_at", str(time.time()))
        log.info("Finalize complete. %d folder sizes computed.", len(sizes))
    finally:
        conn.close()
