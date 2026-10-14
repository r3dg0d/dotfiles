#!/usr/bin/env python3
"""Render templates/ into config/ using palette/palette.json. Stdlib only.

Placeholders: {{violet}} -> #b46bff, {{violet_rgb}} -> 180, 107, 255, {{violet_nohash}} -> b46bff,
{{ansi0}}..{{ansi15}} -> hex of the ANSI slot.
"""
import json, re, sys
from pathlib import Path
root = Path(__file__).resolve().parent.parent
pal = json.loads((root / "palette/palette.json").read_text())
vals = {}
for k, v in pal["colors"].items():
    h = v["hex"]; vals[k] = h; vals[k + "_nohash"] = h[1:]
    vals[k + "_rgb"] = ", ".join(str(int(h[i:i + 2], 16)) for i in (1, 3, 5))
for i, k in enumerate(pal["ansi"]):
    vals[f"ansi{i}"] = pal["colors"][k]["hex"]
missing = set()
def sub(m):
    key = m.group(1)
    if key not in vals: missing.add(key); return m.group(0)
    return vals[key]
for src in sorted((root / "templates").rglob("*")):
    if src.is_dir(): continue
    dst = root / "config" / src.relative_to(root / "templates")
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        text = src.read_text()
    except UnicodeDecodeError:  # binary asset (e.g. preview image): copy as-is
        dst.write_bytes(src.read_bytes()); print("copied", dst.relative_to(root)); continue
    dst.write_text(re.sub(r"\{\{([a-z0-9_]+)\}\}", sub, text))
    print("rendered", dst.relative_to(root))
if missing: sys.exit(f"unknown palette keys: {sorted(missing)}")
