#!/usr/bin/env python3
"""Crop fully-transparent rows/columns from PNG borders.

After bg_remove (chroma or ML) the asset is isolated, but the original canvas
is preserved — there's usually a fat transparent margin around the actual
sprite. When the game later scales such a sprite to a target width, that
margin scales with it and shows up as a phantom gap (e.g. character standing
"above" a platform because the platform asset has 150 px of empty pixels
above the actual stone).

This tool trims those transparent borders so pixel (0, 0) of the output is
the first opaque pixel.

Usage:
    python3 tools/trim_alpha.py in.png out.png
    python3 tools/trim_alpha.py in_dir/ out_dir/
    python3 tools/trim_alpha.py asset.png asset.png  # in-place
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def trim(arr: np.ndarray, threshold: int) -> np.ndarray:
    if arr.shape[-1] != 4:
        return arr  # no alpha channel — nothing to trim
    alpha = arr[:, :, 3]
    rows = np.where(alpha.max(axis=1) > threshold)[0]
    cols = np.where(alpha.max(axis=0) > threshold)[0]
    if len(rows) == 0 or len(cols) == 0:
        return arr  # fully transparent — return as-is
    top, bot = rows[0], rows[-1] + 1
    left, right = cols[0], cols[-1] + 1
    return arr[top:bot, left:right]


def iter_targets(src: Path, dst: Path) -> list[tuple[Path, Path]]:
    if src.is_dir():
        if dst.exists() and not dst.is_dir():
            raise SystemExit(f"{dst} exists and is not a directory")
        return [(p, dst / p.relative_to(src)) for p in sorted(src.rglob("*.png"))]
    return [(src, dst)]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--threshold", type=int, default=32,
                    help="Alpha values <= this count as transparent (default 32)")
    args = ap.parse_args()

    if not args.input.exists():
        print(f"error: input not found: {args.input}", file=sys.stderr)
        return 1

    pairs = iter_targets(args.input, args.output)
    if not pairs:
        print("no PNG files found", file=sys.stderr)
        return 1

    for src, dst in pairs:
        im = Image.open(src).convert("RGBA")
        arr = np.array(im)
        out = trim(arr, args.threshold)
        dst.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(out).save(dst, "PNG")
        h0, w0 = arr.shape[:2]
        h1, w1 = out.shape[:2]
        print(f"{src} -> {dst}  {w0}x{h0} -> {w1}x{h1}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
