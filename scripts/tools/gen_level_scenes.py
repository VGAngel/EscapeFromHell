#!/usr/bin/env python3
"""
One-shot generator for the per-level scaffolding.

Outputs:
  scenes/levels/instances/Level_NNN.tscn          inherit from Level/Boss/VoidLevel.tscn
  vertical_layouts.json                            platform coords as data; per vertical
                                                   level: 5 variants, runtime picks one
                                                   uniformly at random per load.
  scenes/rooms/vertical_layouts/level_NNN.tscn    decoration-only scene per vertical
                                                   level. Empty Node2D + LayoutPreview
                                                   (@tool helper drawing shaft outline);
                                                   designer drops Sprite2D / lights /
                                                   particles here.

Run from repo root:
  python3 scripts/tools/gen_level_scenes.py

Idempotent for inherited scenes + JSON. SKIPS already-existing decor scenes
(scenes/rooms/vertical_layouts/level_NNN.tscn) so designer edits aren't
clobbered. Pass --force-decor to regenerate them too.
"""
import argparse
import json
import math
import os
import random
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG_PATH = os.path.join(REPO_ROOT, "levels_config.json")
INSTANCES_DIR = os.path.join(REPO_ROOT, "scenes", "levels", "instances")
LAYOUTS_DIR = os.path.join(REPO_ROOT, "scenes", "rooms", "vertical_layouts")
LAYOUTS_JSON_PATH = os.path.join(REPO_ROOT, "vertical_layouts.json")

BASE_SCENE = {
    "vertical":  ("res://scenes/levels/Level.tscn",     "uid://level1tscn01"),
    "platformer":("res://scenes/levels/Level.tscn",     "uid://level1tscn01"),
    "boss":      ("res://scenes/levels/BossLevel.tscn", "uid://bosslevel1tsc"),
    "void":      ("res://scenes/levels/VoidLevel.tscn", "uid://cdg0m4a4r0m77"),
}

LAYOUT_PREVIEW_SCRIPT = "res://scripts/tools/LayoutPreview.gd"

# ── Shaft geometry (mirrors PlaceholderRoom + LevelGenerator constants) ──────
ROOM_WIDTH = 1080.0
SIDE_WALL_W = 60.0
WALL_T = 30.0
PLATFORM_T = 30.0
VIEWPORT_HEIGHT = 1920.0
MAX_JUMP_HEIGHT = 200.0
SAME_LEVEL_REACH = 240.0

# room_count by (level_id % 10) — see scripts/levels/LevelGenerator.gd:40
ROOM_COUNT_BY_IDX = [4, 2, 3, 4, 4, 5, 6, 6, 7, 8]

# Below MAX_JUMP_HEIGHT so adjacent rows are reachable when ascending.
# Markov caps at MAX_JUMP_HEIGHT * 0.9 = 180.
ROW_SPACING = 180.0

ZONE_CENTERS_REL = [0.20, 0.40, 0.60, 0.80]
WIDTH_BUCKETS = [180.0, 220.0, 260.0]
WIDTH_WEIGHTS = [0.25, 0.50, 0.25]

# How many random variants per vertical level. Runtime picks one per load.
VARIANTS_PER_LEVEL = 5


def make_uid(prefix: str, n: int) -> str:
    return f"uid://{prefix}{n:08d}"


def make_decor_uid(level_id: int) -> str:
    return f"uid://vdec{level_id:04d}00"


def write_inherited_scene(level_id: int, base_path: str, base_uid: str) -> None:
    fname = f"Level_{level_id:03d}.tscn"
    fpath = os.path.join(INSTANCES_DIR, fname)
    uid = make_uid("lvl", level_id)
    content = f"""[gd_scene load_steps=2 format=3 uid="{uid}"]

[ext_resource type="PackedScene" uid="{base_uid}" path="{base_path}" id="1_base"]

[node name="Level" instance=ExtResource("1_base")]
level_id = {level_id}
"""
    os.makedirs(INSTANCES_DIR, exist_ok=True)
    with open(fpath, "w") as f:
        f.write(content)


def weighted_choice(rng: random.Random, items_with_weights):
    total = sum(w for _, w in items_with_weights)
    pick = rng.random() * total
    acc = 0.0
    for item, w in items_with_weights:
        acc += w
        if pick <= acc:
            return item
    return items_with_weights[-1][0]


def shaft_height_for(level_id: int) -> float:
    idx = level_id % 10
    return VIEWPORT_HEIGHT * float(ROOM_COUNT_BY_IDX[idx])


def max_horizontal_jump(v_gap_px: float) -> float:
    if v_gap_px <= 0.0:
        return SAME_LEVEL_REACH * 1.15
    t = max(0.0, min(1.0, v_gap_px / MAX_JUMP_HEIGHT))
    return (SAME_LEVEL_REACH + (120.0 - SAME_LEVEL_REACH) * t) * 1.15


def generate_variant(level_id: int, variant_k: int) -> list:
    """Return list of {x,y,w,t} platform dicts for one variant. Reachability-
    aware: every adjacent row is jumpable upward."""
    rng = random.Random(hash((level_id, variant_k, "layout-v2")))
    height = shaft_height_for(level_id)
    floor_y = height - WALL_T
    # Reserve clearance above the topmost platform so the 220 px altar sprite
    # doesn't clip into the ceiling wall.
    ALTAR_CLEARANCE = 280.0
    min_top_y = WALL_T + ALTAR_CLEARANCE

    rows_y = []
    y = floor_y - ROW_SPACING
    while y >= min_top_y:
        rows_y.append(y)
        y -= ROW_SPACING

    zone_centers = [ROOM_WIDTH * r for r in ZONE_CENTERS_REL]
    zone_count = len(zone_centers)

    plats = []
    prev_zone = rng.randint(0, zone_count - 1)
    prev_x = None
    prev_w = 0.0
    prev_y = None

    for i, ry in enumerate(rows_y):
        deltas = [-2, -1, 0, 1, 2]
        weights = [0.10, 0.40, 0.10, 0.40, 0.10] if i > 0 else [0.25] * 5
        jitter = 0.0 if (i == 0 or i == len(rows_y) - 1) else rng.uniform(
            -ROW_SPACING * 0.05, ROW_SPACING * 0.05)
        zone = prev_zone
        for _attempt in range(8):
            d = weighted_choice(rng, list(zip(deltas, weights)))
            cand = max(0, min(zone_count - 1, prev_zone + d))
            if cand != prev_zone or i == 0:
                zone = cand
                break

        x = zone_centers[zone] + rng.uniform(-ROOM_WIDTH * 0.03, ROOM_WIDTH * 0.03)
        width = weighted_choice(rng, list(zip(WIDTH_BUCKETS, WIDTH_WEIGHTS)))
        ry_jittered = ry + jitter

        if prev_x is not None:
            v_gap = prev_y - ry_jittered
            max_dx = (max_horizontal_jump(v_gap) + (prev_w + width) * 0.5) * 0.85
            dx = x - prev_x
            if abs(dx) > max_dx:
                x = prev_x + math.copysign(max_dx, dx)

        min_x = SIDE_WALL_W + width * 0.5
        max_x = ROOM_WIDTH - SIDE_WALL_W - width * 0.5
        x = max(min_x, min(max_x, x))

        plats.append({
            "x": round(x, 1),
            "y": round(ry_jittered, 1),
            "w": width,
            "t": "stone",
        })
        prev_zone = zone
        prev_x = x
        prev_w = width
        prev_y = ry_jittered

    return plats


def write_vertical_layouts_json(vertical_levels: list) -> None:
    """Write {level_id: [variant_0, variant_1, ..., variant_4]} for every
    vertical level. Custom-formatted: outer structure pretty-printed for
    diff readability, each variant collapsed to one line so the file
    stays under ~500 KB instead of 2.5 MB."""
    parts: list = []
    parts.append('{')
    parts.append('  "version": 1,')
    parts.append('  "_comment": "Per-level platform variants for vertical '
                 'shafts. Runtime picks one variant uniformly at random per '
                 'level load. Edit by hand or regenerate via '
                 'scripts/tools/gen_level_scenes.py. Coords are local to the '
                 'shaft origin (top-left). Keys: x, y = position; w = width; '
                 't = platform_type (stone, one_way, ice, mud, crumbling, '
                 'bounce, moving_horizontal, moving_vertical, etc).",')
    parts.append('  "levels": {')
    last_idx = len(vertical_levels) - 1
    for i, level_id in enumerate(vertical_levels):
        variants = [generate_variant(level_id, k)
                    for k in range(VARIANTS_PER_LEVEL)]
        parts.append(f'    "{level_id}": [')
        for j, variant in enumerate(variants):
            row = json.dumps(variant, separators=(',', ':'))
            comma = ',' if j < len(variants) - 1 else ''
            parts.append(f'      {row}{comma}')
        trail = ',' if i < last_idx else ''
        parts.append(f'    ]{trail}')
    parts.append('  }')
    parts.append('}')
    with open(LAYOUTS_JSON_PATH, "w") as f:
        f.write("\n".join(parts) + "\n")


def write_decor_scene(level_id: int, force: bool) -> bool:
    """Write a stub decoration scene per vertical level. Returns True if
    written, False if skipped because the file exists and force=False."""
    fpath = os.path.join(LAYOUTS_DIR, f"level_{level_id:03d}.tscn")
    if os.path.exists(fpath) and not force:
        return False
    os.makedirs(LAYOUTS_DIR, exist_ok=True)
    uid = make_decor_uid(level_id)
    shaft_h = shaft_height_for(level_id)
    content = f"""[gd_scene load_steps=2 format=3 uid="{uid}"]

[ext_resource type="Script" path="{LAYOUT_PREVIEW_SCRIPT}" id="1_preview"]

[node name="VerticalLayout" type="Node2D"]

[node name="LayoutPreview" type="Node2D" parent="."]
script = ExtResource("1_preview")
shaft_height = {shaft_h}
"""
    with open(fpath, "w") as f:
        f.write(content)
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force-decor", action="store_true",
                    help="Overwrite existing per-level decoration scenes "
                         "(default: skip to preserve designer edits).")
    args = ap.parse_args()

    with open(CONFIG_PATH) as f:
        cfg = json.load(f)
    levels = cfg.get("levels", [])

    inherit_count = 0
    decor_written = 0
    decor_skipped = 0
    vertical_ids: list = []

    for lvl in levels:
        level_id = int(lvl["id"])
        ltype = lvl.get("type", "platformer")
        base = BASE_SCENE.get(ltype, BASE_SCENE["platformer"])
        write_inherited_scene(level_id, base[0], base[1])
        inherit_count += 1
        if ltype == "vertical":
            vertical_ids.append(level_id)
            if write_decor_scene(level_id, args.force_decor):
                decor_written += 1
            else:
                decor_skipped += 1

    write_vertical_layouts_json(vertical_ids)

    print(f"Inherited level scenes:    {inherit_count} written → {INSTANCES_DIR}")
    print(f"Decor scenes:              {decor_written} written, {decor_skipped} skipped (existing)")
    print(f"Platform variants:         {len(vertical_ids) * VARIANTS_PER_LEVEL} entries → {LAYOUTS_JSON_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
