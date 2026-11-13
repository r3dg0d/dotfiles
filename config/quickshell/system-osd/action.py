#!/usr/bin/env python3
"""Niri hardware key actions with confirmed-state Quickshell feedback."""
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def run(args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=12)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or 'Command failed')
    return result.stdout.strip()


def tool(name):
    found = shutil.which(name)
    fallback = Path.home() / '.config/quickshell/galaxy/runtime/bin' / name
    if found:
        return found
    if fallback.exists():
        return str(fallback)
    raise RuntimeError(name + ' is not installed')


def volume(node):
    status = run(['wpctl', 'get-volume', str(node)])
    match = re.search(r'Volume:\s*([\d.]+)', status)
    if not match:
        raise RuntimeError('Could not read audio level')
    return round(float(match[1]) * 100), '[MUTED]' in status


def microphones(nodes):
    return [node['id'] for node in nodes if node.get('type') == 'PipeWire:Interface:Node'
            and node.get('info', {}).get('props', {}).get('media.class') == 'Audio/Source']


def action(name):
    if name.startswith('volume') or name == 'mute':
        sink = '@DEFAULT_AUDIO_SINK@'
        if name == 'mute':
            run(['wpctl', 'set-mute', sink, 'toggle'])
        else:
            run(['wpctl', 'set-volume', sink, '0.05+' if name == 'volume-up' else '0.05-', '-l', '1.0'])
        value, muted = volume(sink)
        return ('Speakers muted' if muted else f'Volume · {value}%', '󰝟' if muted else '󰕾', value, muted)
    if name == 'microphones':
        nodes = microphones(json.loads(run(['pw-dump'])))
        if not nodes:
            raise RuntimeError('No microphones found')
        mute = not all(volume(node)[1] for node in nodes)
        for node in nodes:
            run(['wpctl', 'set-mute', str(node), '1' if mute else '0'])
        states = [volume(node)[1] for node in nodes]
        if not all(state == mute for state in states):
            raise RuntimeError('Some microphones did not change state')
        return (f'All microphones {"muted" if mute else "on"} · {len(nodes)}', '󰍭' if mute else '󰍬', 0 if mute else 100, mute)
    if name.startswith('brightness'):
        up = name == 'brightness-up'
        if any(Path('/sys/class/backlight').iterdir()):
            run(['brightnessctl', '-c', 'backlight', '--min-value=1', 'set', '+5%' if up else '5%-'])
            value = round(100 * int(run(['brightnessctl', '-c', 'backlight', 'get'])) / int(run(['brightnessctl', '-c', 'backlight', 'max'])))
        else:
            ddc = tool('ddcutil')
            # DDC controls the first detected external monitor; never keyboard LEDs.
            parts = run([ddc, '--display', '1', '--terse', 'getvcp', '10']).split()
            current, maximum = int(parts[-2]), int(parts[-1])
            target = max(1, min(maximum, current + (1 if up else -1) * max(1, round(maximum * 0.05))))
            run([ddc, '--display', '1', 'setvcp', '10', str(target)])
            parts = run([ddc, '--display', '1', '--terse', 'getvcp', '10']).split()
            value = round(100 * int(parts[-2]) / int(parts[-1]))
        return (f'Brightness · {value}%', '󰃠', value, False)
    if name in ('previous', 'play-pause', 'next'):
        playerctl = tool('playerctl')
        players = run([playerctl, '-l']).splitlines()
        player = next((p for p in players if 'kopuz' in p.lower()), players[0] if players else None)
        if not player:
            raise RuntimeError('No media player is running')
        def metadata():
            try:
                fields = run([playerctl, '-p', player, 'metadata', '--format',
                              '{{mpris:trackid}}\x1f{{xesam:url}}\x1f{{xesam:title}}\x1f{{xesam:artist}}']).split('\x1f')
                return (fields + [''] * 4)[:4]
            except (RuntimeError, OSError, subprocess.SubprocessError):
                return ['', '', '', '']
        before = metadata() if name != 'play-pause' else None
        run([playerctl, '-p', player, name])
        track = metadata()
        if before is not None:
            # MPRIS metadata may arrive shortly after the command returns.
            for _ in range(8):
                if track[:3] != before[:3] and track[2]:
                    break
                time.sleep(0.075)
                track = metadata()
        status = run([playerctl, '-p', player, 'status'])
        heading = {'previous': 'Previous track', 'next': 'Next track', 'play-pause': status}[name]
        title = track[2].replace('\n', ' ').strip() or 'Unknown song'
        artist = track[3].replace('\n', ' ').strip()
        label = heading + '\n' + title + ('\n' + artist if artist else '')
        icon = {'previous': '⏮', 'next': '⏭', 'play-pause': '⏸' if status == 'Paused' else '▶'}[name]
        return (label, icon, -1, False)
    raise RuntimeError('Unknown action')


def show(data):
    label, icon, value, muted = data
    qs = tool('quickshell')
    call = [qs, 'ipc', '-c', 'system-osd', 'call', 'system', 'showState', label, icon, str(value), str(muted).lower()]
    if subprocess.run(call, capture_output=True, timeout=3).returncode:
        subprocess.run([qs, '-c', 'system-osd', '--no-duplicate', '--daemonize'], check=True, timeout=10)
        for _ in range(30):
            if not subprocess.run(call, capture_output=True, timeout=3).returncode:
                return
            time.sleep(0.1)
        raise RuntimeError('System popup could not start')


if __name__ == '__main__':
    lock_path = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'galaxy-system-osd.lock'
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            try:
                result = action(sys.argv[1])
            except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
                print(str(error), file=sys.stderr)
                result = ('Control unavailable · check device access', '!', -1, True)
            show(result)
        except (RuntimeError, OSError, subprocess.SubprocessError) as error:
            raise SystemExit(str(error))
