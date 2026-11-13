#!/usr/bin/env python3
"""Galaxy clipboard history: one watcher, a bounded local store, no logging of contents.

  clip.py watch              run the single watcher (wl-paste --watch); exits at once if one is running
  clip.py store              called by the watcher on every clipboard change (reads the clipboard itself)
  clip.py list [--query Q] [--limit N]     JSON rows, newest first (text is a preview, never the full blob)
  clip.py restore ID         put an entry back on the clipboard
  clip.py delete ID | clear  remove one entry / all history
  clip.py pause on|off       stop / resume capturing
  clip.py status             JSON: backend, watcher, paused, counts, limits

Backends
  own       SQLite in ~/.local/state/galaxy-clip (mode 0600), images as PNG files beside it. Default.
  cliphist  used automatically when a `wl-paste --watch cliphist store` watcher is already running, so
            there is never a second watcher or a second history. Then this script only reads and edits
            cliphist's store.

Privacy: entries offered with a password-manager hint (x-kde-passwordManagerHint = secret) or flagged
sensitive by wl-clipboard (CLIPBOARD_STATE=sensitive) are never stored. Contents are never printed to logs
and nothing is sent anywhere.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

MAX_ENTRIES = 300
MAX_AGE_DAYS = 14
MAX_TEXT_BYTES = 1024 * 1024
MAX_IMAGE_BYTES = 16 * 1024 * 1024
MAX_IMAGE_TOTAL = 256 * 1024 * 1024
PREVIEW_CHARS = 400
IMAGE_TYPES = ("image/png", "image/jpeg", "image/webp", "image/bmp", "image/gif")
TEXT_TYPES = ("text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "STRING", "TEXT")
SECRET_HINT = "x-kde-passwordManagerHint"


def state_dir() -> Path:
    path = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "galaxy-clip"
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, 0o700)
    return path


def run(argv: list[str], *, data: bytes | None = None, timeout: float = 5.0) -> tuple[int, bytes]:
    try:
        res = subprocess.run(argv, input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return 127, b""
    return res.returncode, res.stdout


# --------------------------------------------------------------------------- watcher
def external_cliphist_watcher() -> bool:
    """True when some other process already feeds cliphist from wl-paste."""
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            argv = (proc / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        # the process itself must be wl-paste (not a shell or editor whose arguments mention it)
        if os.path.basename(argv[0]) == b"wl-paste" and b"--watch" in argv and any(b"cliphist" in a for a in argv[1:]):
            return True
    return False


def watcher_lock():
    fh = open(state_dir() / "watcher.lock", "a+")  # noqa: SIM115 - held for the life of the watcher
    try:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        fh.close()
        return None
    return fh


def watcher_running() -> bool:
    fh = watcher_lock()
    if fh is None:
        return True
    fh.close()
    return False


def cmd_watch() -> int:
    if external_cliphist_watcher():
        print("galaxy-clip: a cliphist watcher is already running; using its history instead of starting another", file=sys.stderr)
        return 0
    lock = watcher_lock()
    if lock is None:
        print("galaxy-clip: watcher already running", file=sys.stderr)
        return 0
    os.set_inheritable(lock.fileno(), True)  # the lock lives as long as wl-paste does
    os.execvp("wl-paste", ["wl-paste", "--watch", sys.executable, os.path.abspath(__file__), "store"])
    return 127


# --------------------------------------------------------------------------- own store
class Store:
    def __init__(self) -> None:
        self.dir = state_dir()
        self.images = self.dir / "images"
        self.images.mkdir(mode=0o700, exist_ok=True)
        path = self.dir / "history.db"
        self.db = sqlite3.connect(path, timeout=5)
        os.chmod(path, 0o600)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("CREATE TABLE IF NOT EXISTS entries (id INTEGER PRIMARY KEY AUTOINCREMENT, ts REAL NOT NULL, kind TEXT NOT NULL, "
                        "mime TEXT NOT NULL, sha TEXT NOT NULL UNIQUE, size INTEGER NOT NULL, preview TEXT NOT NULL, body BLOB, file TEXT)")
        self.db.execute("CREATE INDEX IF NOT EXISTS entries_ts ON entries (ts DESC)")
        self.db.commit()

    def add(self, kind: str, mime: str, data: bytes) -> str:
        sha = hashlib.sha256(mime.split(";")[0].encode() + b"\0" + data).hexdigest()
        now = time.time()
        if self.db.execute("UPDATE entries SET ts = ? WHERE sha = ?", (now, sha)).rowcount:
            self.db.commit()
            return "duplicate"  # same content again: move it to the top, keep one row
        if kind == "image":
            path = self.images / f"{sha[:32]}.{mime.split('/')[1]}"
            path.write_bytes(data)
            os.chmod(path, 0o600)
            self.db.execute("INSERT INTO entries (ts, kind, mime, sha, size, preview, file) VALUES (?, 'image', ?, ?, ?, ?, ?)",
                            (now, mime, sha, len(data), f"image · {len(data) // 1024 or 1} KB", str(path)))
        else:
            text = data.decode("utf-8", "replace")
            self.db.execute("INSERT INTO entries (ts, kind, mime, sha, size, preview, body) VALUES (?, 'text', ?, ?, ?, ?, ?)",
                            (now, mime, sha, len(data), text[:PREVIEW_CHARS], data))
        self.db.commit()
        self.prune()
        return "stored"

    def prune(self) -> None:
        cutoff = time.time() - MAX_AGE_DAYS * 86400
        doomed = [r[0] for r in self.db.execute("SELECT id FROM entries WHERE ts < ?", (cutoff,))]
        doomed += [r[0] for r in self.db.execute("SELECT id FROM entries ORDER BY ts DESC LIMIT -1 OFFSET ?", (MAX_ENTRIES,))]
        total = 0
        for row_id, size in self.db.execute("SELECT id, size FROM entries WHERE kind = 'image' ORDER BY ts DESC"):
            total += size
            if total > MAX_IMAGE_TOTAL:
                doomed.append(row_id)
        for row_id in set(doomed):
            self.delete(row_id, commit=False)
        self.db.commit()

    def delete(self, row_id: int, *, commit: bool = True) -> bool:
        row = self.db.execute("SELECT file FROM entries WHERE id = ?", (row_id,)).fetchone()
        if row is None:
            return False
        if row[0]:
            Path(row[0]).unlink(missing_ok=True)
        self.db.execute("DELETE FROM entries WHERE id = ?", (row_id,))
        if commit:
            self.db.commit()
        return True

    def clear(self) -> int:
        n = self.db.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
        for (path,) in self.db.execute("SELECT file FROM entries WHERE file IS NOT NULL"):
            Path(path).unlink(missing_ok=True)
        self.db.execute("DELETE FROM entries")
        self.db.commit()
        self.db.execute("VACUUM")  # deleted text must not linger in free pages
        return n

    def list(self, query: str = "", limit: int = 100) -> list[dict]:
        sql = "SELECT id, ts, kind, mime, size, preview, file FROM entries"
        args: list = []
        if query:
            # search the full text, not only the preview
            sql += " WHERE kind = 'text' AND instr(lower(CAST(body AS TEXT)), lower(?)) > 0"
            args.append(query)
        sql += " ORDER BY ts DESC LIMIT ?"
        args.append(max(1, min(limit, MAX_ENTRIES)))
        return [{"id": str(r[0]), "ts": r[1], "kind": r[2], "mime": r[3], "size": r[4], "preview": r[5], "file": r[6] or "",
                 "lines": r[5].count("\n") + 1 if r[2] == "text" else 0} for r in self.db.execute(sql, args)]

    def get(self, row_id: int) -> tuple[str, bytes] | None:
        row = self.db.execute("SELECT mime, body, file FROM entries WHERE id = ?", (row_id,)).fetchone()
        if row is None:
            return None
        try:
            return row[0], (Path(row[2]).read_bytes() if row[2] else bytes(row[1]))
        except OSError:
            return None

    def count(self) -> int:
        return self.db.execute("SELECT COUNT(*) FROM entries").fetchone()[0]


# --------------------------------------------------------------------------- cliphist backend (only when its watcher exists)
class Cliphist:
    def list(self, query: str = "", limit: int = 100) -> list[dict]:
        _, out = run(["cliphist", "list"])
        rows = []
        for line in out.decode("utf-8", "replace").splitlines():
            ident, _, preview = line.partition("\t")
            is_image = preview.startswith("[[ binary data") and any(t in preview for t in ("png", "jpeg", "jpg", "webp", "bmp"))
            if query and (is_image or query.lower() not in preview.lower()):
                continue
            rows.append({"id": ident, "ts": 0, "kind": "image" if is_image else "text", "mime": "", "size": 0,
                         "preview": preview[:PREVIEW_CHARS], "file": "", "lines": 1})
            if len(rows) >= limit:
                break
        return rows

    def get(self, ident: str) -> tuple[str, bytes] | None:
        code, out = run(["cliphist", "decode", ident])
        if code != 0:
            return None
        return ("image/png" if out[:8] == b"\x89PNG\r\n\x1a\n" else "text/plain;charset=utf-8"), out

    def delete(self, ident: str) -> bool:
        return run(["cliphist", "delete-query", ident])[0] == 0 if not ident.isdigit() else run(["cliphist", "delete"], data=f"{ident}\t\n".encode())[0] == 0

    def clear(self) -> int:
        n = len(self.list(limit=100000))
        run(["cliphist", "wipe"])
        return n

    def count(self) -> int:
        return len(self.list(limit=100000))


def backend():
    return ("cliphist", Cliphist()) if external_cliphist_watcher() else ("own", Store())


# --------------------------------------------------------------------------- commands
def paused() -> bool:
    return (state_dir() / "paused").exists()


def cmd_store() -> int:
    """Runs once per clipboard change. Decides what, if anything, to keep. Prints nothing about the content."""
    state = os.environ.get("CLIPBOARD_STATE", "data")
    if state in ("sensitive", "clear", "nil"):
        return 0
    skip = state_dir() / "skipped"
    if paused():
        # Remember (as a hash only) what was on the clipboard while paused, so that it is not
        # captured later when the watcher restarts and sees the same selection again.
        _, held = run(["wl-paste", "--no-newline"])
        skip.write_text(hashlib.sha256(held).hexdigest(), encoding="ascii")
        os.chmod(skip, 0o600)
        return 0
    if skip.exists():
        _, held = run(["wl-paste", "--no-newline"])
        if hashlib.sha256(held).hexdigest() == skip.read_text(encoding="ascii").strip():
            return 0
        skip.unlink(missing_ok=True)
    code, out = run(["wl-paste", "--list-types"])
    if code != 0:
        return 0
    types = out.decode("utf-8", "replace").split()
    if SECRET_HINT in types:
        _, hint = run(["wl-paste", "--no-newline", "--type", SECRET_HINT])
        if hint.strip() == b"secret":
            return 0
    text_type = next((t for t in TEXT_TYPES if t in types), None)
    image_type = next((t for t in IMAGE_TYPES if t in types), None)
    if image_type and not text_type:  # a copied image; browsers add text/html but not text/plain for these
        code, data = run(["wl-paste", "--type", image_type], timeout=10)
        if code == 0 and 0 < len(data) <= MAX_IMAGE_BYTES:
            Store().add("image", image_type, data)
    elif text_type:
        code, data = run(["wl-paste", "--no-newline", "--type", text_type])
        if code == 0 and data.strip() and len(data) <= MAX_TEXT_BYTES:
            Store().add("text", "text/plain;charset=utf-8", data)
    return 0


def cmd_restore(ident: str) -> int:
    name, be = backend()
    got = be.get(int(ident) if name == "own" else ident) if (name != "own" or ident.isdigit()) else None
    if got is None:
        print(json.dumps({"ok": False, "error": "no such entry"}))
        return 1
    mime, data = got
    code, _ = run(["wl-copy", "--type", mime], data=data, timeout=10)
    print(json.dumps({"ok": code == 0, **({} if code == 0 else {"error": "wl-copy failed"})}))
    return 0 if code == 0 else 1


def status() -> dict:
    name, be = backend()
    return {"backend": name, "watcher": "external cliphist" if name == "cliphist" else ("running" if watcher_running() else "stopped"),
            "paused": paused(), "count": be.count(),
            "limits": {"entries": MAX_ENTRIES, "days": MAX_AGE_DAYS, "text_kb": MAX_TEXT_BYTES // 1024, "image_mb": MAX_IMAGE_BYTES // 1024**2},
            "pause_applies": name == "own"}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="clip.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("watch")
    sub.add_parser("store")
    ls = sub.add_parser("list")
    ls.add_argument("--query", default="")
    ls.add_argument("--limit", type=int, default=120)
    sub.add_parser("restore").add_argument("id")
    sub.add_parser("delete").add_argument("id")
    sub.add_parser("clear")
    sub.add_parser("pause").add_argument("state", choices=["on", "off", "toggle"])
    sub.add_parser("status")
    args = ap.parse_args(argv)
    if args.cmd == "watch":
        return cmd_watch()
    if args.cmd == "store":
        return cmd_store()
    if args.cmd == "restore":
        return cmd_restore(args.id)
    name, be = backend()
    if args.cmd == "list":
        print(json.dumps({"entries": be.list(args.query, args.limit), **status()}, ensure_ascii=False))
    elif args.cmd == "delete":
        ok = be.delete(int(args.id)) if name == "own" and args.id.isdigit() else (be.delete(args.id) if name != "own" else False)
        print(json.dumps({"ok": bool(ok)}))
        return 0 if ok else 1
    elif args.cmd == "clear":
        print(json.dumps({"ok": True, "removed": be.clear()}))
    elif args.cmd == "pause":
        flag = state_dir() / "paused"
        on = (not flag.exists()) if args.state == "toggle" else args.state == "on"
        flag.touch() if on else flag.unlink(missing_ok=True)
        print(json.dumps(status()))
    else:
        print(json.dumps(status()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
