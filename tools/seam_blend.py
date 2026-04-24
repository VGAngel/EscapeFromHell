#!/usr/bin/env python3
"""Make a PNG seamlessly tileable vertically (or horizontally).

Strategy: blend the top N pixels of the image with the bottom N pixels using a
feathered alpha ramp. After this pass, the image can be stacked against itself
without a visible seam — the top matches the bottom because they are literally
a crossfade of each other.

Usage:
    python3 tools/seam_blend.py wall.png wall_tiled.png --band 64
    python3 tools/seam_blend.py wall.png wall_tiled.png --band 64 --axis y
    python3 tools/seam_blend.py wall.png wall_tiled.png --band 64 --axis x
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def blend_vertical(arr: np.ndarray, band: int) -> np.ndarray:
    """Crossfade top `band` rows with bottom `band` rows so the image tiles in Y."""
    h = arr.shape[0]
    band = min(band, h // 2)
    if band <= 0:
        return arr

    top = arr[:band].astype(np.float32)
    bot = arr[h - band:].astype(np.float32)

    # Ramp: at the very top/bottom edge → 50/50 mix. Interior of band → keep original.
    ramp = np.linspace(0.5, 0.0, band, dtype=np.float32)[:, None, None]

    new_top = top * (1.0 - ramp) + bot * ramp
    new_bot = bot * (1.0 - ramp[::-1]) + top * ramp[::-1]

    out = arr.copy()
    out[:band] = np.clip(new_top, 0, 255).astype(arr.dtype)
    out[h - band:] = np.clip(new_bot, 0, 255).astype(arr.dtype)
    return out


def blend_horizontal(arr: np.ndarray, band: int) -> np.ndarray:
    """Crossfade left `band` cols with right `band` cols so the image tiles in X."""
    return blend_vertical(arr.transpose(1, 0, 2), band).transpose(1, 0, 2)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--band", type=int, default=64, help="Blend band size in pixels (default 64)")
    ap.add_argument("--axis", choices=("y", "x", "both"), default="y",
                    help="Axis to make seamless (default y — vertical tile)")
    args = ap.parse_args()

    img = Image.open(args.input).convert("RGBA")
    arr = np.array(img)

    if args.axis in ("y", "both"):
        arr = blend_vertical(arr, args.band)
    if args.axis in ("x", "both"):
        arr = blend_horizontal(arr, args.band)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr, mode="RGBA").save(args.output, "PNG")
    print(f"{args.input} -> {args.output}  (band={args.band}, axis={args.axis})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
