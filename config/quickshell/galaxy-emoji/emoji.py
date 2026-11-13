#!/usr/bin/env python3
"""Backend for the Galaxy emoji picker: Twemoji assets, recents, clipboard.

  emoji.py status            JSON: asset directory, whether it is ready, recents
  emoji.py assets            fetch the pinned Twemoji SVG set once (sha512-checked), then status
  emoji.py pick HEX-HEX-...  copy that exact Unicode sequence with wl-copy and remember it
  emoji.py forget            clear recents

A sequence is passed as hyphen-joined code points so that ZWJ, variation selectors, skin-tone
modifiers, regional indicators and tag characters all survive argv unchanged.
Nothing is logged and nothing leaves the machine except the one pinned download from registry.npmjs.org.
"""
import base64
import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

TWEMOJI_VERSION = "15.0.0"
TWEMOJI_URL = "https://registry.npmjs.org/@twemoji/svg/-/svg-15.0.0.tgz"
TWEMOJI_SHA512 = "ZSPef2B6nBaYnfgdTbAy4jgW95o7pi2xPGwGCU+WMTxo7J6B1lMPTWwSq/wTuiMq+N0khQ90CcvYp1wFoQpo/w=="
MAX_RECENTS = 40
ALLOWED = (  # code point ranges that occur in emoji sequences
    (0x23, 0x23), (0x2A, 0x2A), (0x30, 0x39), (0xA9, 0xA9), (0xAE, 0xAE), (0x200D, 0x200D), (0x203C, 0x3299),
    (0xFE0F, 0xFE0F), (0x1F000, 0x1FAFF), (0x1FC00, 0x1FFFD), (0xE0020, 0xE007F),
)


def data_dir() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "galaxy-emoji"


def state_file() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "galaxy-emoji" / "recents.json"


def assets_dir() -> Path:
    return data_dir() / f"twemoji-{TWEMOJI_VERSION}"


def assets_ready() -> bool:
    return (assets_dir() / ".complete").is_file()


def decode(arg: str) -> str:
    try:
        points = [int(p, 16) for p in arg.split("-")]
    except ValueError:
        sys.exit("pick: expected hyphen-joined hexadecimal code points")
    if not 1 <= len(points) <= 16 or not all(any(lo <= p <= hi for lo, hi in ALLOWED) for p in points):
        sys.exit("pick: not an emoji sequence")
    return "".join(map(chr, points))


def recents() -> list[str]:
    try:
        data = json.loads(state_file().read_text(encoding="utf-8"))
        return [e for e in data if isinstance(e, str)][:MAX_RECENTS]
    except (OSError, ValueError):
        return []


def remember(emoji: str) -> None:
    items = [emoji] + [e for e in recents() if e != emoji]
    path = state_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(items[:MAX_RECENTS], ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


def fetch_assets() -> None:
    if assets_ready():
        return
    with urllib.request.urlopen(TWEMOJI_URL, timeout=60) as resp:  # noqa: S310 - fixed https URL
        blob = resp.read(64 * 1024 * 1024)
    if base64.b64encode(hashlib.sha512(blob).digest()).decode() != TWEMOJI_SHA512:
        sys.exit("twemoji: sha512 mismatch; nothing was installed")
    target = assets_dir()
    target.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(blob)) as tf:
        for member in tf.getmembers():
            name = Path(member.name).name
            if not member.isfile() or not (name.endswith(".svg") or name in ("LICENSE", "license", "package.json")):
                continue
            src = tf.extractfile(member)
            if src is not None:  # written by basename only: no paths from the archive are trusted
                (target / name).write_bytes(src.read())
    (target / ".complete").write_text(TWEMOJI_VERSION, encoding="utf-8")


def status() -> dict:
    return {"assets": str(assets_dir()), "ready": assets_ready(), "twemoji": TWEMOJI_VERSION, "recents": recents()}


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd == "assets":
        fetch_assets()
    elif cmd == "pick":
        if len(argv) != 3:
            sys.exit("usage: emoji.py pick HEX-HEX-...")
        emoji = decode(argv[2])
        try:
            subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"], input=emoji.encode("utf-8"), check=True, timeout=5)
        except (OSError, subprocess.SubprocessError) as exc:
            print(json.dumps({"ok": False, "error": f"wl-copy failed: {exc}"}))
            return 1
        remember(emoji)
        print(json.dumps({"ok": True}))
        return 0
    elif cmd == "forget":
        state_file().unlink(missing_ok=True)
    elif cmd != "status":
        sys.exit(__doc__)
    print(json.dumps(status(), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
