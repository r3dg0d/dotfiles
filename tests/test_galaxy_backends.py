"""Backends of the Galaxy emoji picker and clipboard manager, with wl-copy / wl-paste replaced by fakes.

    python3 -m pytest tests/ -q

The same behaviour is checked against a real Wayland clipboard by tools/qs-harness/check.sh.
"""
import importlib.util
import json
import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
QS = ROOT / "config" / "quickshell"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def env(tmp_path, monkeypatch):
    """A fake clipboard: wl-copy writes files, wl-paste reads them. CLIP_TYPES lists the offered types."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    clip = tmp_path / "clipboard"
    clip.mkdir()
    (bindir / "wl-copy").write_text(f"""#!/bin/sh
type="text/plain;charset=utf-8"
while [ $# -gt 0 ]; do case "$1" in --type|-t) type="$2"; shift 2;; *) shift;; esac; done
cat > "{clip}/data"; printf '%s\\n' "$type" > "{clip}/types"
""")
    (bindir / "wl-paste").write_text(f"""#!/bin/sh
[ -f "{clip}/data" ] || exit 1
case " $* " in *" --list-types "*) cat "{clip}/types"; exit 0;; esac
want=""
while [ $# -gt 0 ]; do case "$1" in --type|-t) want="$2"; shift 2;; *) shift;; esac; done
[ -n "$want" ] && [ -f "{clip}/alt-$want" ] && {{ cat "{clip}/alt-$want"; exit 0; }}
cat "{clip}/data"
""")
    for f in bindir.iterdir():
        f.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bindir}:{os.environ['PATH']}")
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.delenv("CLIPBOARD_STATE", raising=False)
    return clip


def offer(clip: Path, data: bytes, types: str = "text/plain;charset=utf-8\ntext/plain\nUTF8_STRING", **alts: bytes):
    (clip / "data").write_bytes(data)
    (clip / "types").write_text(types + "\n")
    for name, value in alts.items():
        (clip / f"alt-{name}").write_bytes(value)


# --------------------------------------------------------------------------- emoji
EMOJI = load(QS / "galaxy-emoji" / "emoji.py", "galaxy_emoji")
DATA = json.loads((QS / "galaxy-emoji" / "emoji.json").read_text(encoding="utf-8"))
BY_NAME = {e["n"]: e for e in DATA["emoji"]}


def hexes(s: str) -> str:
    return "-".join(f"{ord(c):x}" for c in s)


@pytest.mark.parametrize("name,codepoints", [
    ("grinning face", "1f600"),
    ("flag: Portugal", "1f1f5-1f1f9"),                                         # regional indicator pair
    ("flag: Scotland", "1f3f4-e0067-e0062-e0073-e0063-e0074-e007f"),           # tag sequence
    ("red heart", "2764-fe0f"),                                                # variation selector kept
    ("keycap: 1", "31-fe0f-20e3"),
    ("rainbow flag", "1f3f3-fe0f-200d-1f308"),                                 # VS16 + ZWJ
    ("family: man, woman, girl, boy", "1f468-200d-1f469-200d-1f467-200d-1f466"),
])
def test_data_keeps_complete_sequences(name, codepoints):
    assert hexes(BY_NAME[name]["e"]) == codepoints


def test_skin_tone_variants_are_complete_sequences():
    wave = BY_NAME["waving hand"]
    assert [hexes(s["e"]) for s in wave["s"]] == [f"1f44b-{t}" for t in ("1f3fb", "1f3fc", "1f3fd", "1f3fe", "1f3ff")]
    assert [s["t"] for s in wave["s"]] == [[1], [2], [3], [4], [5]]
    pair = next(s for s in BY_NAME["people holding hands"]["s"] if s["t"] == [2, 5])
    assert hexes(pair["e"]) == "1f9d1-1f3fc-200d-1f91d-200d-1f9d1-1f3ff"


def test_every_row_has_a_name_group_keywords_and_mostly_art():
    rows = DATA["emoji"]
    assert len(rows) > 1800 and all(r["n"] and isinstance(r["k"], list) and 0 <= r["g"] <= 9 for r in rows)
    assert sum(1 for r in rows if not r["a"]) < 80          # newer Unicode than the pinned Twemoji
    assert BY_NAME["red heart"]["a"] == "2764"               # Twemoji drops FE0F in file names...
    assert BY_NAME["rainbow flag"]["a"] == "1f3f3-fe0f-200d-1f308"  # ...except in ZWJ sequences
    assert "hello" in BY_NAME["waving hand"]["k"]


@pytest.mark.parametrize("name", ["rocket", "flag: Portugal", "flag: Scotland", "red heart", "family: man, woman, girl, boy", "rainbow flag"])
def test_pick_copies_the_exact_bytes_and_records_recents(env, name):
    emoji = BY_NAME[name]["e"]
    res = subprocess.run([sys.executable, str(QS / "galaxy-emoji" / "emoji.py"), "pick", hexes(emoji)], capture_output=True, text=True)
    assert json.loads(res.stdout) == {"ok": True}
    assert (env / "data").read_bytes() == emoji.encode("utf-8")
    assert EMOJI.recents()[0] == emoji


def test_recents_are_bounded_deduplicated_and_most_recent_first(env):
    for cp in range(0x1F600, 0x1F600 + 50):
        EMOJI.remember(chr(cp))
    EMOJI.remember(chr(0x1F605))
    rec = EMOJI.recents()
    assert len(rec) == EMOJI.MAX_RECENTS and rec[0] == chr(0x1F605) and rec.count(chr(0x1F605)) == 1


@pytest.mark.parametrize("bad", ["41-42", "zz", "1f600;rm -rf", "", "-".join(["1f600"] * 17), "d83d-de00"])
def test_pick_refuses_anything_that_is_not_an_emoji_sequence(env, bad):
    res = subprocess.run([sys.executable, str(QS / "galaxy-emoji" / "emoji.py"), "pick", bad], capture_output=True, text=True)
    assert res.returncode != 0 and not (env / "data").exists()


def test_asset_names_follow_the_twemoji_rule():
    build = load(ROOT / "tools" / "build-emoji-data.py", "build_emoji")
    assert build.asset_name("2764-FE0F") == "2764"
    assert build.asset_name("1F3F3-FE0F-200D-1F308") == "1f3f3-fe0f-200d-1f308"
    assert build.asset_name("0031-FE0F-20E3") == "31-20e3"


# --------------------------------------------------------------------------- clipboard
CLIP = load(QS / "galaxy-clip" / "clip.py", "galaxy_clip")
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


def capture(clip, data, **kw):
    offer(clip, data, **kw)
    assert CLIP.cmd_store() == 0


def test_multiline_and_unicode_text_round_trip(env):
    multi = "line one\nline two\n\ttabbed three\n".encode()
    uni = "Ünïcödé 日本語 🧑🏼‍🤝‍🧑🏿 مرحبا".encode()
    capture(env, multi)
    capture(env, uni)
    rows = CLIP.Store().list()
    assert [r["kind"] for r in rows] == ["text", "text"] and rows[1]["lines"] == 4
    assert rows[0]["preview"] == uni.decode()
    for row, want in zip(rows, (uni, multi)):
        assert CLIP.cmd_restore(row["id"]) == 0
        assert (env / "data").read_bytes() == want


def test_images_are_kept_as_files_and_restore_with_their_type(env):
    capture(env, PNG, types="image/png")
    row = CLIP.Store().list()[0]
    assert row["kind"] == "image" and Path(row["file"]).read_bytes() == PNG
    assert stat.S_IMODE(Path(row["file"]).stat().st_mode) == 0o600
    assert CLIP.cmd_restore(row["id"]) == 0
    assert (env / "data").read_bytes() == PNG and (env / "types").read_text().strip() == "image/png"


def test_duplicates_move_to_the_top_instead_of_adding_rows(env):
    capture(env, b"alpha")
    capture(env, b"beta")
    capture(env, b"alpha")
    store = CLIP.Store()
    assert [r["preview"] for r in store.list()] == ["alpha", "beta"] and store.count() == 2
    CLIP.cmd_restore(store.list()[1]["id"])       # restoring is seen by the watcher as a copy
    CLIP.cmd_store()
    assert [r["preview"] for r in CLIP.Store().list()] == ["beta", "alpha"]


def test_search_is_case_insensitive_and_covers_text_beyond_the_preview(env):
    capture(env, ("x" * 600 + " NEEDLE at the end").encode())
    capture(env, b"something else")
    hits = CLIP.Store().list("needle")
    assert len(hits) == 1 and "NEEDLE" not in hits[0]["preview"]
    assert CLIP.Store().list("nothing-here") == []


def test_delete_and_clear(env):
    capture(env, b"keep")
    capture(env, b"drop")
    capture(env, PNG, types="image/png")
    store = CLIP.Store()
    image = next(r for r in store.list() if r["kind"] == "image")
    drop = next(r for r in store.list() if r["preview"] == "drop")
    assert store.delete(int(drop["id"])) and not store.delete(999999)
    assert store.delete(int(image["id"])) and not Path(image["file"]).exists()
    assert [r["preview"] for r in store.list()] == ["keep"]
    assert store.clear() == 1 and store.count() == 0
    assert b"keep" not in (Path(os.environ["XDG_STATE_HOME"]) / "galaxy-clip" / "history.db").read_bytes()


def test_history_survives_a_restart_and_is_private(env):
    capture(env, b"persist me")
    state = Path(os.environ["XDG_STATE_HOME"]) / "galaxy-clip"
    assert stat.S_IMODE(state.stat().st_mode) == 0o700 and stat.S_IMODE((state / "history.db").stat().st_mode) == 0o600
    res = subprocess.run([sys.executable, str(QS / "galaxy-clip" / "clip.py"), "list"], capture_output=True, text=True)
    out = json.loads(res.stdout)
    assert out["entries"][0]["preview"] == "persist me" and out["backend"] == "own" and out["count"] == 1
    assert res.stderr == ""


def test_sensitive_content_is_never_stored(env, monkeypatch):
    offer(env, b"hunter2", types="text/plain\nx-kde-passwordManagerHint", **{"x-kde-passwordManagerHint": b"secret"})
    CLIP.cmd_store()
    monkeypatch.setenv("CLIPBOARD_STATE", "sensitive")
    offer(env, b"also secret")
    CLIP.cmd_store()
    monkeypatch.setenv("CLIPBOARD_STATE", "clear")
    CLIP.cmd_store()
    assert CLIP.Store().count() == 0


def test_pause_stops_capture_and_what_was_copied_meanwhile_is_not_picked_up_later(env):
    (CLIP.state_dir() / "paused").touch()
    capture(env, b"copied while paused")
    (CLIP.state_dir() / "paused").unlink()
    CLIP.cmd_store()                               # watcher restart sees the same selection again
    assert CLIP.Store().count() == 0
    capture(env, b"copied after resuming")
    assert [r["preview"] for r in CLIP.Store().list()] == ["copied after resuming"]


def test_retention_is_bounded(env, monkeypatch):
    monkeypatch.setattr(CLIP, "MAX_ENTRIES", 5)
    store = CLIP.Store()
    for i in range(9):
        store.add("text", "text/plain;charset=utf-8", f"entry {i}".encode())
    assert store.count() == 5 and store.list()[0]["preview"] == "entry 8"
    store.db.execute("UPDATE entries SET ts = ts - ?", ((CLIP.MAX_AGE_DAYS + 1) * 86400,))
    store.db.commit()
    store.add("text", "text/plain;charset=utf-8", b"fresh")
    assert [r["preview"] for r in store.list()] == ["fresh"]
    offer(env, b"x" * (CLIP.MAX_TEXT_BYTES + 1))
    CLIP.cmd_store()
    assert CLIP.Store().count() == 1               # oversized text is skipped, not truncated


def test_only_a_real_wl_paste_cliphist_process_counts_as_an_external_watcher(env):
    assert CLIP.external_cliphist_watcher() is False   # this test process mentions the words but is not wl-paste
    assert CLIP.watcher_running() is False
    lock = CLIP.watcher_lock()
    assert lock is not None and CLIP.watcher_lock() is None   # a second watcher cannot take the lock
    lock.close()


# --------------------------------------------------------------------------- config
def test_niri_binds_do_not_collide():
    for path in (ROOT / "config/niri/config.kdl", ROOT / "templates/niri/config.kdl"):
        keys = []
        for line in path.read_text(encoding="utf-8").splitlines():
            s = line.strip()
            if s.startswith("//") or "{" not in s or not s.split()[0].replace("+", "").replace("_", "").isalnum():
                continue
            head = s.split()[0]
            if "+" in head or head in ("Print",):
                keys.append(head)
        dupes = {k for k in keys if keys.count(k) > 1}
        assert not dupes, f"{path.name}: bound twice: {dupes}"
        assert "Mod+E" in keys and "Mod+Shift+Period" in keys and "Mod+Alt+I" in keys
        assert keys.count("Mod+Period") == 1          # still niri's own expel-window-from-column


def test_widgets_ship_what_their_shells_reference():
    for widget, files in {"galaxy-emoji": ["shell.qml", "emoji.py", "emoji.json", "start.sh", "Nebula.qml", "Galaxy.qml", "ATTRIBUTION.md"],
                          "galaxy-clip": ["shell.qml", "clip.py", "start.sh", "Nebula.qml", "Galaxy.qml"],
                          "galaxy-ai-media": ["shell.qml", "bridge.py", "start.sh", "Nebula.qml", "Galaxy.qml", "GalaxyButton.qml"]}.items():
        for name in files:
            assert (QS / widget / name).is_file(), f"{widget}/{name}"
        for script in (QS / widget).glob("*.sh"):
            assert os.access(script, os.X_OK)
