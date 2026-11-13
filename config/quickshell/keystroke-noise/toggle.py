#!/usr/bin/env python3
"""Toggle the actual application, then show its confirmed state in Quickshell."""
import os
from pathlib import Path
import shutil
import subprocess
import time


def run(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=5)


# Serialize repeated keypresses so state changes and popup delivery stay ordered.
import fcntl
lock_path = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'galaxy-noise.lock'
lock_path.parent.mkdir(parents=True, exist_ok=True)
with lock_path.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    result = run(['keystroke-noise', 'toggle'])
    if result.returncode:
        raise SystemExit(result.stderr or 'Could not toggle KeystrokeNoise')
    enabled = 'KeystrokeNoise: ON' in result.stdout
    message = 'On · typing sounds enabled' if enabled else 'Off · typing sounds muted'
    if enabled:
        run(['systemctl', '--user', 'daemon-reload'])
        service = run(['systemctl', '--user', 'start', 'keystroke-noise.service'])
        status = run(['keystroke-noise', 'status'])
        if 'devices=0' in status.stdout:
            message = 'On · no input devices available'
        elif service.returncode:
            message = 'On · sound daemon unavailable'
    qs = shutil.which('quickshell')
    if not qs:
        fallback = Path.home() / '.config/quickshell/galaxy/runtime/bin/quickshell'
        qs = str(fallback) if fallback.exists() else None
    if not qs:
        raise SystemExit('Toggled KeystrokeNoise, but Quickshell is missing')
    call = [qs, 'ipc', '-c', 'keystroke-noise', 'call', 'noise', 'showState', 'on' if enabled else 'off', message]
    if run(call).returncode:
        subprocess.run([qs, '-c', 'keystroke-noise', '--no-duplicate', '--daemonize'], check=True, timeout=10)
        for _ in range(30):
            if not run(call).returncode:
                break
            time.sleep(0.1)
        else:
            raise SystemExit('Toggled KeystrokeNoise, but its popup did not start')
