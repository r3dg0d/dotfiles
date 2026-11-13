#!/usr/bin/env python3
"""Hands requests from the AI Media widget to the `ai-media` CLI.

The widget passes one percent-encoded JSON argument so prompts are never interpolated into a command line;
this script decodes it and sends parameters to `ai-media` on stdin. It adds no logic of its own:
the CLI, the widget and MCP all use the same runner and the same job state.

  bridge.py run  <encoded {"model", "params", "output"?, "allow_hosted"?}>   -> ai-media run ... --json
  bridge.py chat <encoded {"model", "messages", "options"}>                  -> ai-media chat ... --stream-json
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.parse


def ai_media() -> str:
    exe = os.environ.get("AI_MEDIA_BIN") or shutil.which("ai-media") or os.path.expanduser("~/.local/bin/ai-media")
    if not os.path.exists(exe):
        print(json.dumps({"error": {"code": "not_installed", "message": "the ai-media command was not found",
                                    "hint": "install ai-media-cli: scripts/install_qwen_wrappers.sh or scripts/install_music_wrappers.sh"}}))
        sys.exit(127)
    return exe


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("run", "chat"):
        sys.exit(__doc__)
    try:
        req = json.loads(urllib.parse.unquote(sys.argv[2], errors="strict"))
        if not isinstance(req, dict):
            raise ValueError
    except (ValueError, TypeError):
        print(json.dumps({"error": {"code": "invalid_request", "message": "bridge: malformed request"}}))
        return 2
    model = str(req.get("model", ""))
    if not model or model.startswith("-"):
        print(json.dumps({"error": {"code": "invalid_request", "message": "bridge: no model"}}))
        return 2
    if sys.argv[1] == "run":
        argv = [ai_media(), "run", model, "--params-json", "-", "--json"]
        if req.get("output"):
            argv += ["-o", str(req["output"])]
        if req.get("allow_hosted"):
            argv.append("--allow-hosted")
        payload = json.dumps(req.get("params") or {})
    else:
        argv = [ai_media(), "chat", model, "--stdin-json", "--stream-json"]
        payload = json.dumps({"messages": req.get("messages") or [], "options": req.get("options") or {}})
    proc = subprocess.Popen(argv, stdin=subprocess.PIPE)
    try:
        proc.communicate(payload.encode("utf-8"))
    except KeyboardInterrupt:
        proc.terminate()
    return proc.returncode or 0


if __name__ == "__main__":
    sys.exit(main())
