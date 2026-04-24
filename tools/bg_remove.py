#!/usr/bin/env python3
"""Remove 1-2 background colors from PNG assets (e.g. Midjourney exports).

Usage:
    python tools/bg_remove.py input.png output.png --colors "#ffffff"
    python tools/bg_remove.py input.png output.png --colors "#ffffff,#f0f0f0" --tolerance 30
    python tools/bg_remove.py input.png output.png --auto
    python tools/bg_remove.py input_dir/ output_dir/ --auto --feather 2
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def parse_hex_color(s: str) -> tuple[int, int, int]:
    s = s.strip().lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) != 6:
        raise ValueError(f"Invalid hex color: {s!r}")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def detect_corner_colors(img: Image.Image, max_colors: int = 2) -> list[tuple[int, int, int]]:
    arr = np.array(img.convert("RGB"))
    h, w, _ = arr.shape
    patch = max(2, min(h, w) // 50)
    corners = [
        arr[:patch, :patch].reshape(-1, 3),
        arr[:patch, -patch:].reshape(-1, 3),
        arr[-patch:, :patch].reshape(-1, 3),
        arr[-patch:, -patch:].reshape(-1, 3),
    ]
    samples = np.concatenate(corners, axis=0)
    # pick most common colors quantized to 8 levels per channel
    quant = (samples // 8) * 8
    uniq, counts = np.unique(quant, axis=0, return_counts=True)
    order = np.argsort(-counts)
    picked: list[tuple[int, int, int]] = []
    for idx in order:
        c = tuple(int(v) for v in uniq[idx])
        if all(color_distance(c, p) > 20 for p in picked):
            picked.append(c)
        if len(picked) >= max_colors:
            break
    return picked


def color_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    return float(np.sqrt(sum((ai - bi) ** 2 for ai, bi in zip(a, b))))


def build_alpha_mask(
    rgb: np.ndarray,
    colors: list[tuple[int, int, int]],
    tolerance: float,
) -> np.ndarray:
    """Return alpha array (0 for bg, 255 for fg, blended near edges)."""
    h, w, _ = rgb.shape
    diff = np.full((h, w), np.inf, dtype=np.float32)
    for c in colors:
        d = np.sqrt(np.sum((rgb.astype(np.float32) - np.array(c, dtype=np.float32)) ** 2, axis=2))
        diff = np.minimum(diff, d)
    # soft ramp: fully transparent below tolerance, fully opaque above tolerance*2
    lo = tolerance
    hi = tolerance * 2.0
    alpha = np.clip((diff - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    return (alpha * 255).astype(np.uint8)


def process_image(
    src: Path,
    dst: Path,
    colors: list[tuple[int, int, int]] | None,
    tolerance: float,
    feather: int,
    auto: bool,
) -> None:
    img = Image.open(src).convert("RGBA")
    rgb = np.array(img.convert("RGB"))

    resolved = colors
    if auto or not resolved:
        resolved = detect_corner_colors(img, max_colors=2)
        print(f"  auto-detected bg colors: {resolved}")

    alpha = build_alpha_mask(rgb, resolved, tolerance)

    # combine with existing alpha (keep original transparency)
    src_alpha = np.array(img)[:, :, 3]
    alpha = np.minimum(alpha, src_alpha)

    alpha_img = Image.fromarray(alpha)
    if feather > 0:
        alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(radius=feather))

    out = img.copy()
    out.putalpha(alpha_img)
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, "PNG")


def iter_targets(src: Path, dst: Path) -> list[tuple[Path, Path]]:
    if src.is_dir():
        if dst.exists() and not dst.is_dir():
            raise SystemExit(f"{dst} exists and is not a directory")
        pairs = []
        for p in sorted(src.rglob("*.png")):
            rel = p.relative_to(src)
            pairs.append((p, dst / rel))
        return pairs
    return [(src, dst)]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=Path, help="Input PNG file or directory")
    ap.add_argument("output", type=Path, help="Output PNG file or directory")
    ap.add_argument("--colors", type=str, default="", help="Comma-separated hex colors, e.g. '#ffffff,#f0f0f0'")
    ap.add_argument("--auto", action="store_true", help="Auto-detect bg colors from image corners")
    ap.add_argument("--tolerance", type=float, default=25.0, help="RGB distance tolerance (default 25)")
    ap.add_argument("--feather", type=int, default=0, help="Gaussian blur radius for edge softening (default 0)")
    args = ap.parse_args()

    colors: list[tuple[int, int, int]] = []
    if args.colors:
        colors = [parse_hex_color(c) for c in args.colors.split(",") if c.strip()]
    if not colors and not args.auto:
        print("error: provide --colors or --auto", file=sys.stderr)
        return 2

    if not args.input.exists():
        print(f"error: input not found: {args.input}", file=sys.stderr)
        return 1

    pairs = iter_targets(args.input, args.output)
    if not pairs:
        print("no PNG files found", file=sys.stderr)
        return 1

    for src, dst in pairs:
        print(f"{src} -> {dst}")
        process_image(src, dst, colors or None, args.tolerance, args.feather, args.auto)
    return 0


if __name__ == "__main__":
    sys.exit(main())
