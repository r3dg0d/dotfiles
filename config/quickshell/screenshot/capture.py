#!/usr/bin/env python3
import datetime
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time


def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=30).stdout.strip()


def capture(mode):
    args = ['grim']
    if mode == 'region':
        geometry = run(['slurp', '-b', '#07060dcc', '-c', '#b46bff', '-s', '#b46bff22', '-w', '2'])
        if not geometry:
            return
        args += ['-g', geometry]
    elif mode == 'window':
        window = json.loads(run(['niri', 'msg', '--json', 'focused-window']))
        if not window:
            return
        # Native direct-to-file capture preserves exact focused-window geometry.
        return native_window_capture()
    elif mode == 'screen':
        output = json.loads(run(['niri', 'msg', '--json', 'focused-output']))
        focused = output.get('name') if output else None
        if focused:
            args += ['-o', focused]
    path = new_path()
    run(args + [str(path)])
    return path


def new_path():
    folder = Path.home() / 'Pictures/Screenshots'
    folder.mkdir(parents=True, exist_ok=True)
    return folder / (datetime.datetime.now().strftime('%Y-%m-%d_%H-%M-%S-%f') + '.png')


def native_window_capture():
    path = new_path()
    run(['niri', 'msg', 'action', 'screenshot-window', '--path', str(path)])
    for _ in range(30):
        if path.exists():
            return path
        time.sleep(0.05)
    raise RuntimeError('Window screenshot was not saved')


if __name__ == '__main__':
    try:
        path = capture(sys.argv[1] if len(sys.argv) > 1 else 'region')
        if path:
            qs = shutil.which('quickshell') or str(Path.home() / '.config/quickshell/galaxy/runtime/bin/quickshell')
            call = [qs, 'ipc', '-c', 'screenshot', 'call', 'editor', 'openFile', str(path)]
            if subprocess.run(call, capture_output=True).returncode:
                subprocess.run([qs, '-c', 'screenshot', '--no-duplicate', '--daemonize'], check=True)
                for _ in range(40):
                    if not subprocess.run(call, capture_output=True).returncode:
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError('Screenshot saved, but editor did not open')
    except subprocess.CalledProcessError as error:
        if error.cmd[0] == 'slurp':
            sys.exit(0)  # Escape cancels capture.
        raise SystemExit(error.stderr or str(error))
