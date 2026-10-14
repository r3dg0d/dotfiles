#!/usr/bin/env python3
"""Procedurally generate the deep-space wallpaper (original artwork, MIT).
Usage: gen-wallpaper.py OUT.png [WIDTH HEIGHT SEED]   requires numpy + pillow."""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

out = sys.argv[1] if len(sys.argv) > 1 else "wallpaper/deep-space.png"
W = int(sys.argv[2]) if len(sys.argv) > 2 else 3840
H = int(sys.argv[3]) if len(sys.argv) > 3 else 2160
seed = int(sys.argv[4]) if len(sys.argv) > 4 else 1337
rng = np.random.default_rng(seed)
pal = json.loads((Path(__file__).resolve().parent.parent / "palette/palette.json").read_text())["colors"]
rgb = lambda k: np.array([int(pal[k]["hex"][i:i+2], 16) for i in (1, 3, 5)], np.float32) / 255

def fbm(w, h, octaves=6):
    """Fractal value noise: sum of upscaled random grids."""
    acc = np.zeros((h, w), np.float32); amp = 1.0; tot = 0
    for o in range(octaves):
        gw, gh = 3 * 2**o, max(2, int(3 * 2**o * h / w))
        g = rng.random((gh, gw)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        acc += amp * np.asarray(img, np.float32) / 255; tot += amp; amp *= 0.55
    return acc / tot

# work at quarter resolution for the clouds, then upscale smoothly
w4, h4 = W // 4, H // 4
yy, xx = np.mgrid[0:h4, 0:w4].astype(np.float32)
nx, ny = xx / w4, yy / h4
n1, n2, n3 = fbm(w4, h4), fbm(w4, h4), fbm(w4, h4, 5)
# a diagonal nebula band, warped by noise
band = np.exp(-((ny - (0.85 - 0.6 * nx) + 0.25 * (n2 - 0.5)) ** 2) / 0.035)
cloud = np.clip((n1 - 0.35) * 1.8, 0, 1) ** 1.6 * band
glow2 = np.clip((n3 - 0.45) * 2.0, 0, 1) ** 2 * np.exp(-((nx - 0.18) ** 2 + (ny - 0.78) ** 2) / 0.05)
dust = np.clip((n2 - 0.55) * 3, 0, 1) * band  # dark lanes

img = np.ones((h4, w4, 3), np.float32) * rgb("void")
img += 1.25 * cloud[..., None] * (0.55 * rgb("nebula") + 0.35 * rgb("violet"))
img += (cloud ** 3)[..., None] * 0.35 * rgb("lavender")
img += glow2[..., None] * 0.35 * rgb("green")
img *= (1 - 0.45 * dust)[..., None]
vign = 1 - 0.55 * (((nx - 0.5) ** 2 + (ny - 0.5) ** 2) / 0.5)
img *= np.clip(vign, 0.35, 1)[..., None]
base = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
base = base.filter(ImageFilter.GaussianBlur(3))
arr = np.asarray(base, np.float32) / 255

# stars: many faint, few bright with soft halos; denser inside the band
def stars(n, rmax, bright):
    s = np.zeros((H, W), np.float32)
    ys, xs = rng.integers(0, H, n), rng.integers(0, W, n)
    s[ys, xs] = rng.random(n) ** 3 * bright
    return s
band_full = np.asarray(Image.fromarray((band * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR), np.float32) / 255
field = stars(int(W * H / 900), 1, 0.9) * (0.5 + band_full)
field += stars(int(W * H / 6000), 1, 1.6)
halo = np.asarray(Image.fromarray(np.clip(field * 255, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2)), np.float32) / 255
tint = np.where(rng.random((H, W, 1)) < 0.7, np.array([0.95, 0.93, 1.0]), rgb("lavender"))
arr = arr + field[..., None] * tint + 3.5 * halo[..., None] * rgb("lavender")
# subtle grain to avoid banding
arr += (rng.random((H, W, 1)).astype(np.float32) - 0.5) / 255 * 2
Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(out, optimize=True)
print("wrote", out, W, H)
