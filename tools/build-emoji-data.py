#!/usr/bin/env python3
"""Build config/quickshell/galaxy-emoji/emoji.json from pinned upstream data.

Inputs (both verified by sha512 before use, both MIT):
  emojibase-data 18.0.0  - Unicode CLDR names, groups, keywords, skin-tone variants
  @twemoji/svg 15.0.0    - only used here to record which sequences have artwork

Usage: python3 tools/build-emoji-data.py [--cache DIR]
Network: registry.npmjs.org only. Nothing downloaded is executed.
"""
import argparse
import base64
import hashlib
import io
import json
import sys
import tarfile
import urllib.request
from pathlib import Path

PINS = {
    "emojibase-data": ("18.0.0", "https://registry.npmjs.org/emojibase-data/-/emojibase-data-18.0.0.tgz",
                       "TPPRRYv2zPd0jKI+pTpMquwWNZXYAsC3IVsCMeg2X8y8fEzKwOks4/5bz0YavF5r6d71aGPpb6oDnUEwSLLMoA=="),
    "twemoji-svg": ("15.0.0", "https://registry.npmjs.org/@twemoji/svg/-/svg-15.0.0.tgz",
                    "ZSPef2B6nBaYnfgdTbAy4jgW95o7pi2xPGwGCU+WMTxo7J6B1lMPTWwSq/wTuiMq+N0khQ90CcvYp1wFoQpo/w=="),
}
GROUPS = ["Smileys", "People", "Components", "Nature", "Food", "Travel", "Activities", "Objects", "Symbols", "Flags"]


def fetch(name: str, cache: Path) -> bytes:
    version, url, integrity = PINS[name]
    path = cache / f"{name}-{version}.tgz"
    data = path.read_bytes() if path.is_file() else urllib.request.urlopen(url, timeout=60).read()  # noqa: S310
    if base64.b64encode(hashlib.sha512(data).digest()).decode() != integrity:
        sys.exit(f"{name}: sha512 mismatch, refusing to use it")
    cache.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def asset_name(hexcode: str) -> str:
    """Twemoji file name: lower-case code points joined by '-', FE0F dropped unless the sequence has a ZWJ."""
    parts = hexcode.lower().split("-")
    if "200d" not in parts:
        parts = [p for p in parts if p != "fe0f"]
    return "-".join(p.lstrip("0") or "0" for p in parts)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", type=Path, default=Path.home() / ".cache" / "galaxy-emoji-build")
    args = ap.parse_args()
    with tarfile.open(fileobj=io.BytesIO(fetch("emojibase-data", args.cache))) as tf:
        data = json.load(tf.extractfile("package/en/data.json"))
    with tarfile.open(fileobj=io.BytesIO(fetch("twemoji-svg", args.cache))) as tf:
        art = {Path(m.name).stem for m in tf.getmembers() if m.name.endswith(".svg")}

    def art_for(hexcode: str) -> str:
        name = asset_name(hexcode)
        return name if name in art else ""

    out = []
    for e in sorted((e for e in data if "group" in e and e["group"] != 2), key=lambda e: e["order"]):
        row = {"e": e["emoji"], "n": e["label"], "g": e["group"], "k": sorted(set(e.get("tags", []))), "a": art_for(e["hexcode"])}
        skins = [{"e": s["emoji"], "n": s["label"], "t": s["tone"] if isinstance(s["tone"], list) else [s["tone"]],
                  "a": art_for(s["hexcode"])} for s in e.get("skins", [])]
        if skins:
            row["s"] = skins
        out.append(row)
    doc = {"unicode": "emojibase-data " + PINS["emojibase-data"][0], "twemoji": PINS["twemoji-svg"][0], "groups": GROUPS, "emoji": out}
    target = Path(__file__).resolve().parent.parent / "config/quickshell/galaxy-emoji/emoji.json"
    target.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    missing = [r["n"] for r in out if not r["a"]]
    print(f"{len(out)} emoji, {sum(len(r.get('s', [])) for r in out)} skin-tone variants, {len(missing)} without Twemoji art -> {target}")


if __name__ == "__main__":
    main()
