import numpy as np
from PIL import Image

SRC = "/Users/james/code/jamesnewton.com/priv/static/og-default.png"
MAGENTA = np.array([255, 49, 217], dtype=np.float64)
CYAN = np.array([25, 201, 255], dtype=np.float64)

def glitch(level, out):
    rng = np.random.default_rng(7)
    im = np.array(Image.open(SRC).convert("RGB")).astype(np.float64)
    h, w, _ = im.shape

    p = {
        "subtle":  dict(ab=3, bands=4, band_shift=22, wobble=3, scan=0.07, bleed=0.10),
        "obvious": dict(ab=8, bands=9, band_shift=55, wobble=6, scan=0.12, bleed=0.20),
    }[level]

    # CRT wobble: sine displacement per row
    rows = np.arange(h)
    offs = (np.sin(rows / 34.0) * p["wobble"]).astype(int)
    for y in range(h):
        im[y] = np.roll(im[y], offs[y], axis=0)

    # chromatic aberration
    im[:, :, 0] = np.roll(im[:, :, 0], p["ab"], axis=1)
    im[:, :, 2] = np.roll(im[:, :, 2], -p["ab"], axis=1)

    # glitch bands
    for _ in range(p["bands"]):
        y0 = int(rng.integers(0, h - 40))
        bh = int(rng.integers(8, 42))
        dx = int(rng.integers(-p["band_shift"], p["band_shift"] + 1))
        band = np.roll(im[y0:y0 + bh], dx, axis=1)
        tint = MAGENTA if rng.random() < 0.5 else CYAN
        band = band * 0.92 + tint * 0.08
        im[y0:y0 + bh] = band

    # scanlines
    im[::3] *= (1.0 - p["scan"])

    # neon edge bleed: magenta left, cyan right
    x = np.arange(w, dtype=np.float64)
    lg = np.clip(1.0 - x / (w * 0.28), 0, 1)[None, :, None] ** 2 * p["bleed"]
    rg = np.clip((x - w * 0.72) / (w * 0.28), 0, 1)[None, :, None] ** 2 * p["bleed"]
    im = im * (1 - lg) + MAGENTA[None, None, :] * lg
    im = im * (1 - rg) + CYAN[None, None, :] * rg

    Image.fromarray(np.clip(im, 0, 255).astype(np.uint8)).save(out)
    print("wrote", out)

glitch("subtle", "cards/og-links-subtle.png")
glitch("obvious", "cards/og-links-obvious.png")
