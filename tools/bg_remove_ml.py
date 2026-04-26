#!/usr/bin/env python3
"""ML-based background removal using rembg (U²-Net).

For assets where the background is not a flat color (gradient skies, cloud
backdrops, painted scenery) — bg_remove.py with chroma keying can't help
because there is no single dominant background colour. rembg runs a
salient-object segmentation network and returns a clean alpha mask.

Usage:
    python3 tools/bg_remove_ml.py input.png output.png
    python3 tools/bg_remove_ml.py in_dir/ out_dir/

Requires the `rembg` package (one-time install):
    pip3 install rembg
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image
from rembg import remove


def iter_targets(src: Path, dst: Path) -> list[tuple[Path, Path]]:
    if src.is_dir():
        if dst.exists() and not dst.is_dir():
            raise SystemExit(f"{dst} exists and is not a directory")
        return [(p, dst / p.relative_to(src)) for p in sorted(src.rglob("*.png"))]
    return [(src, dst)]


def process(src: Path, dst: Path) -> None:
    with src.open("rb") as f:
        data = f.read()
    out_bytes = remove(data)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(out_bytes)
    # Sanity check the result
    im = Image.open(dst)
    print(f"{src} -> {dst}  ({im.size[0]}x{im.size[1]} {im.mode})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()

    if not args.input.exists():
        print(f"error: input not found: {args.input}", file=sys.stderr)
        return 1

    pairs = iter_targets(args.input, args.output)
    if not pairs:
        print("no PNG files found", file=sys.stderr)
        return 1

    for src, dst in pairs:
        process(src, dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
