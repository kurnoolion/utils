import sqlite3
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS scan_meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS entries (
    path        TEXT PRIMARY KEY,
    parent_path TEXT NOT NULL,
    name        TEXT NOT NULL,
    kind        TEXT NOT NULL,
    size_bytes  INTEGER,
    extension   TEXT,
    category    TEXT,
    ctime       REAL,
    mtime       REAL,
    atime       REAL,
    error       TEXT
);
CREATE INDEX IF NOT EXISTS idx_entries_parent ON entries(parent_path);
CREATE INDEX IF NOT EXISTS idx_entries_kind   ON entries(kind);
CREATE INDEX IF NOT EXISTS idx_entries_size   ON entries(size_bytes);

CREATE TABLE IF NOT EXISTS completed_dirs (
    path TEXT PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS scan_errors (
    path        TEXT,
    error       TEXT,
    occurred_at REAL
);

CREATE TABLE IF NOT EXISTS moves (
    rel_path     TEXT PRIMARY KEY,
    kind         TEXT,
    size_bytes   INTEGER,
    dest_path    TEXT,
    attempted_at REAL,
    status       TEXT NOT NULL,   -- 'moved', 'source_missing', 'failed'
    error        TEXT
);
"""


def connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.commit()


def has_scan(conn: sqlite3.Connection) -> bool:
    """True if the DB looks like an initialized disk_cleaner DB with a scan recorded."""
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='scan_meta'"
    ).fetchone()
    if row is None:
        return False
    return get_meta(conn, "scan_root_original") is not None


def get_meta(conn: sqlite3.Connection, key: str) -> str | None:
    row = conn.execute("SELECT value FROM scan_meta WHERE key=?", (key,)).fetchone()
    return row[0] if row else None


def set_meta(conn: sqlite3.Connection, key: str, value: str) -> None:
    with conn:
        conn.execute(
            "INSERT OR REPLACE INTO scan_meta (key, value) VALUES (?, ?)",
            (key, value),
        )


def log_scan_error(conn: sqlite3.Connection, path: str, msg: str) -> None:
    with conn:
        conn.execute(
            "INSERT INTO scan_errors (path, error, occurred_at) VALUES (?, ?, ?)",
            (path, msg, time.time()),
        )
