#!/usr/bin/env python3
"""Reject malformed native JSON configuration."""
import json
from pathlib import Path
import sys
for path in Path(sys.argv[1]).rglob("*.json"):
    json.loads(path.read_text())
print("Native JSON syntax passed")
