#!/usr/bin/env python3
"""Draw the Weather mod's sheets into weather/sprites/ (fixed seed: the same
files every run).

rain.png    4 frames of 256x256, sparse to dense: thin falling streaks, bright
            at the leading end, tiling seamlessly both ways.
splash.png  6 frames of 32x32: a drop's crown splash, rising and falling.
ring.png    64x16: a soft line across, for the ring ribbons.
flat.png    8x8 white: full-view quads coloured per corner.
flake.png   3 frames of 16x16: soft round snowflakes with a cool edge.
settle.png  9x9 frames: settling snow, a pixel or a column of pixels each.
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "weather" / "sprites"
RNG = np.random.default_rng(0x5241494E)  # "RAIN"
TINT = np.array([215, 228, 255], dtype=np.float64)


def save(rgba: np.ndarray, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    img = np.clip(rgba, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(OUT / name, optimize=True)


def rgba_from_alpha(alpha: np.ndarray, tint=TINT) -> np.ndarray:
    h, w = alpha.shape
    out = np.zeros((h, w, 4))
    out[..., :3] = tint
    out[..., 3] = np.clip(alpha, 0, 1) * 255
    return out


def rain_tile(count: int, size: int = 256) -> np.ndarray:
    """`count` streaks, each wrapping round the tile's edges."""
    alpha = np.zeros((size, size))
    for _ in range(count):
        x = RNG.uniform(0, size)
        top = RNG.uniform(0, size)
        length = RNG.uniform(30, 90)
        bright = RNG.uniform(0.5, 1.0)
        width = RNG.uniform(0.7, 1.3)
        for k in range(int(length) + 1):
            # Brightest at the leading (lower) end, fading up the tail.
            t = k / length
            a = bright * (t ** 1.2)
            y = int(top + k) % size
            for dx in (-1, 0, 1):
                col = int(np.floor(x)) + dx
                cover = max(0.0, 1.0 - abs(col + 0.5 - x) / width)
                alpha[y, col % size] = max(alpha[y, col % size], a * cover)
    return rgba_from_alpha(alpha)


def rain() -> None:
    frames = [rain_tile(n) for n in (12, 20, 30, 44)]
    save(np.concatenate(frames, axis=0), "rain.png")


def splash(frames: int = 6, size: int = 32) -> None:
    """A crown: droplets thrown up and out from the bottom middle, falling
    back, with a flat spray at the foot that fades."""
    drops = [(RNG.uniform(-1.6, 1.6), RNG.uniform(2.2, 3.6), RNG.uniform(0.6, 1.0)) for _ in range(9)]
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    cx, foot = size / 2 - 0.5, size - 3.0
    out = []
    for f in range(frames):
        t = (f + 1) / frames
        alpha = np.zeros((size, size))
        # The foot: a flat ellipse widening and fading.
        rx, ry = 3 + 9 * t, 1.2 + 1.2 * t
        d = ((xx - cx) / rx) ** 2 + ((yy - foot) / ry) ** 2
        alpha = np.maximum(alpha, np.clip(1 - np.abs(d - 0.8) * 2.5, 0, 1) * (1 - t) * 0.9)
        # The crown's walls: two short sheets thrown up either side, and a
        # jet in the middle, both falling back.
        rise = 9 * np.sin(np.pi * min(1.0, t * 1.4))
        for side in (-1, 1):
            wx = cx + side * (2.5 + 5 * t)
            wall = np.clip(1 - np.abs(xx - wx) / 1.2, 0, 1) * ((yy <= foot) & (yy >= foot - rise))
            alpha = np.maximum(alpha, wall * (1 - t) * 0.85)
        jet = np.clip(1 - np.abs(xx - cx) / 1.0, 0, 1) * ((yy <= foot) & (yy >= foot - 1.4 * rise))
        alpha = np.maximum(alpha, jet * (1 - t) ** 2 * 0.9)
        # Droplets on their arcs, smaller as they fall.
        for vx, vy, bright in drops:
            step = 6 * t
            px = cx + vx * step * 1.6
            py = foot - (vy * step - 0.45 * step * step) * 2.4
            r = 1.8 * (1 - 0.5 * t)
            dd = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
            alpha = np.maximum(alpha, np.clip(1.4 - dd / max(r, 0.5), 0, 1) * bright * (1 - 0.6 * t))
        out.append(rgba_from_alpha(alpha))
    save(np.concatenate(out, axis=0), "splash.png")


def ring(width: int = 64, height: int = 16) -> None:
    """Across the strip (v), a thin bright line with a soft edge."""
    v = (np.arange(height) + 0.5) / height - 0.5
    profile = np.exp(-(v / 0.12) ** 2) * 0.9 + np.exp(-(v / 0.3) ** 2) * 0.25
    alpha = np.tile(profile[:, None], (1, width))
    save(rgba_from_alpha(alpha, np.array([235, 242, 255.0])), "ring.png")


def oval(width: int = 64, height: int = 16) -> None:
    """A whole ring seen flat: an ellipse outline with the line's soft profile."""
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float64)
    u = (xx + 0.5) / width * 2 - 1
    v = (yy + 0.5) / height * 2 - 1
    d = np.sqrt(u * u + v * v) - 0.84
    # Thinner across the ends, where the ellipse is seen edge on.
    alpha = np.exp(-(d / 0.07) ** 2) * 0.9 + np.exp(-(d / 0.16) ** 2) * 0.25
    save(rgba_from_alpha(np.clip(alpha, 0, 1), np.array([235, 242, 255.0])), "oval.png")


def flat(size: int = 8) -> None:
    save(np.full((size, size, 4), 255.0), "flat.png")


def flake(size: int = 16) -> None:
    """A soft disc, a smaller crisp one, and a faint wide one, white in the
    middle and cooler towards the edge."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    c = size / 2 - 0.5
    d = np.sqrt((xx - c) ** 2 + (yy - c) ** 2)
    out = []
    for core, soft, peak in ((2.6, 2.2, 1.0), (1.6, 1.2, 1.0), (3.4, 3.0, 0.75)):
        alpha = np.clip(1 - np.maximum(d - core, 0) / soft, 0, 1) ** 1.5 * peak
        t = np.clip(d / (core + soft), 0, 1)[..., None]
        tint = (1 - t) * np.array([255, 255, 255.0]) + t * np.array([200, 218, 255.0])
        rgba = np.zeros((size, size, 4))
        rgba[..., :3] = tint
        rgba[..., 3] = alpha * 255
        out.append(rgba)
    save(np.concatenate(out, axis=0), "flake.png")


def settle(size: int = 9) -> None:
    """lib/settle.lua's sheet, everything on the middle column from the bottom
    row up: four single pixels of snow in slightly different whites, then
    columns of 1..9 pixels, white on top and cooler underneath. All opaque."""
    shades = [(250, 252, 255), (242, 246, 252), (236, 241, 250), (246, 249, 255)]
    out = []
    for rgb in shades:
        rgba = np.zeros((size, size, 4))
        rgba[size - 1, size // 2] = [*rgb, 255]
        out.append(rgba)
    for h in range(1, size + 1):
        rgba = np.zeros((size, size, 4))
        for k in range(h):
            t = k / max(h - 1, 1)
            rgb = (1 - t) * np.array([226, 234, 248.0]) + t * np.array([250, 252, 255.0])
            rgba[size - 1 - k, size // 2] = [*rgb, 255]
        out.append(rgba)
    save(np.concatenate(out, axis=0), "settle.png")


if __name__ == "__main__":
    rain()
    splash()
    ring()
    oval()
    flat()
    flake()
    settle()
    for p in sorted(OUT.glob("*.png")):
        with Image.open(p) as img:
            print(p.name, img.size)
