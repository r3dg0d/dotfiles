#!/usr/bin/env python3
"""Waybar JSON and controls for Kopuz only."""
import html
import json
import subprocess
import sys


def ctl(*args):
    return subprocess.run(['playerctl', *args], capture_output=True, text=True, timeout=3)


try:
    players = ctl('-l').stdout.splitlines()
    player = next((p for p in players if 'kopuz' in p.lower()), None)
    if not player:
        print(json.dumps({'text': '󰝚  Kopuz', 'class': 'idle', 'tooltip': 'Open Kopuz and play a song'}))
        sys.exit(0)
    if len(sys.argv) > 1:
        action = sys.argv[1]
        if action in ('play-pause', 'next', 'previous'):
            ctl('-p', player, action)
        sys.exit(0)
    status = ctl('-p', player, 'status').stdout.strip()
    title = ctl('-p', player, 'metadata', 'xesam:title').stdout.strip() or 'Kopuz'
    artist = ctl('-p', player, 'metadata', 'xesam:artist').stdout.strip()
    icon = '󰎈' if status == 'Playing' else '󰏤'
    print(json.dumps({'text': html.escape(f'{icon}  {title}'),
                      'class': status.lower(),
                      'tooltip': html.escape(f'{title}\n{artist}\n\nClick: music player · Right-click: play/pause\nMiddle-click: lyrics · Scroll: next/previous')}))
except (OSError, subprocess.TimeoutExpired):
    print(json.dumps({'text': '󰝚  Kopuz', 'class': 'idle', 'tooltip': 'Kopuz media controls unavailable'}))
