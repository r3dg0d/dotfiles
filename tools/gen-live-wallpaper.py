#!/usr/bin/env python3
"""Procedurally generate the looping live wallpaper (original artwork, MIT).
A square deep-space still is rendered with gen-wallpaper.py, then slowly rotated.
Seamless loop: frame(t) = mix(rot(w*t), rot(w*(t-T)), t/T), so frame(T) == frame(0).
Usage: gen-live-wallpaper.py OUT.mp4 [WIDTH HEIGHT SECONDS FPS]   requires numpy, pillow, ffmpeg."""
import subprocess, sys, tempfile, math
from pathlib import Path
import numpy as np
from PIL import Image

out = sys.argv[1] if len(sys.argv) > 1 else "wallpaper/deep-space-live.mp4"
W, H = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (2560, 1440)
T = float(sys.argv[4]) if len(sys.argv) > 4 else 24.0
FPS = int(sys.argv[5]) if len(sys.argv) > 5 else 24
DEG = 8.0  # degrees rotated per loop: slow drift
S = int(math.ceil(math.hypot(W, H) / 2) * 2) + 16
here = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory() as td:
    sq = f"{td}/sq.png"
    subprocess.run([sys.executable, str(here / "gen-wallpaper.py"), sq, str(S), str(S), "4242"], check=True)
    src = Image.open(sq).convert("RGB")
from PIL import ImageChops
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
vign = np.clip(1 - 0.35 * (((xx / W - .5) ** 2 + (yy / H - .5) ** 2) / .5), .6, 1)
vign = Image.fromarray((vign * 255).astype(np.uint8)).convert("RGB")
cx, cy = S / 2, S / 2
def rot(deg):
    """Rotate the square about its centre and sample only the W x H window (affine, bicubic)."""
    t = math.radians(deg); c, s_ = math.cos(t), math.sin(t)
    # output (x, y) -> input: centre-relative inverse rotation
    a, b = c, -s_; d, e = s_, c
    return src.transform((W, H), Image.AFFINE,
        (a, b, cx + a * (-W / 2) + b * (-H / 2), d, e, cy + d * (-W / 2) + e * (-H / 2)), resample=Image.BICUBIC)
n = int(T * FPS)
ff = subprocess.Popen(["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
    "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "26",
    "-tune", "grain", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", out], stdin=subprocess.PIPE)
for i in range(n):
    u = i / n
    a = DEG * u
    f = Image.blend(rot(a), rot(a - DEG), u)
    ff.stdin.write(ImageChops.multiply(f, vign).tobytes())
    if i % 48 == 0: print(f"frame {i}/{n}", flush=True)
ff.stdin.close(); ff.wait()
print("wrote", out, W, H, T, "s")
