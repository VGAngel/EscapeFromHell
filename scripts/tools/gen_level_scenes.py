#!/usr/bin/env python3
"""
Per-level scaffolding generator for vertical shafts.

Outputs:
  vertical_layouts.json                            ONE deterministic platform
                                                   layout per vertical level.
                                                   Edit by hand to reshape a
                                                   level — what's in the JSON
                                                   is what the player sees.
  scenes/rooms/vertical_layouts/level_NNN.tscn    THE editable scene per
                                                   vertical level. Contains a
                                                   LayoutPreview node that
                                                   renders the real shaft —
                                                   walls, backdrop, altar,
                                                   platforms — in the editor.
                                                   Designer drops Sprite2D /
                                                   lights / particles here as
                                                   children of VerticalLayout.

Run from repo root:
  python3 scripts/tools/gen_level_scenes.py

JSON is overwritten every run. SKIPS existing decor scenes by default so
designer edits aren't clobbered; pass --force-decor to overwrite them.
"""
import argparse
import json
import math
import os
import random
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG_PATH = os.path.join(REPO_ROOT, "levels_config.json")
LAYOUTS_DIR = os.path.join(REPO_ROOT, "scenes", "rooms", "vertical_layouts")
LAYOUTS_JSON_PATH = os.path.join(REPO_ROOT, "vertical_layouts.json")

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

# Type distribution for generated stubs. Each "t" string maps to real
# behaviour at runtime via PlaceholderRoom._add_typed_platform — the right
# script gets attached (CrumblingPlatform.gd, MovingPlatform.gd, IcePlatform.gd, …)
# so the platform actually crumbles/moves/slips. Designer can swap any "t"
# in vertical_layouts.json to any supported type without code changes.
#
# Supported types (see PlaceholderRoom._add_typed_platform match block):
#   stone, one_way, crumbling, bounce, mud, ash, faith, sin_platform,
#   illusory, ice, soul_bridge, moving_horizontal, moving_vertical
#
# Top + bottom rows of every level are forced to "stone" downstream so
# spawn/altar landing stays predictable.
TYPE_OPTIONS = [
    ("stone",             0.66),
    ("one_way",           0.12),
    ("crumbling",         0.07),
    ("bounce",            0.05),
    ("moving_horizontal", 0.04),
    ("ice",               0.03),
    ("mud",               0.03),
]

# Single deterministic layout per vertical level — designer edits the JSON
# entry directly and that's exactly what the player sees. No runtime random
# pick. Generator still uses a per-level seed so re-runs produce identical
# scaffolding when the designer hasn't touched a particular level.


def make_decor_uid(level_id: int) -> str:
    return f"uid://vdec{level_id:04d}00"


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

        # Top + bottom rows always stone — bottom is the player's first
        # landing after spawn, top hosts the altar; predictable footing both.
        if i == 0 or i == len(rows_y) - 1:
            ptype = "stone"
        else:
            ptype = weighted_choice(rng, TYPE_OPTIONS)
        plats.append({
            "x": round(x, 1),
            "y": round(ry_jittered, 1),
            "w": width,
            "t": ptype,
        })
        prev_zone = zone
        prev_x = x
        prev_w = width
        prev_y = ry_jittered

    return plats


def write_vertical_layouts_json(vertical_levels: list) -> None:
    """Write {level_id: [platform0, platform1, ...]} for every vertical level.
    One deterministic layout per level — what the JSON says is exactly what
    the player sees. Custom-formatted so each level's array sits on one line
    for compact diff."""
    parts: list = []
    parts.append('{')
    parts.append('  "version": 2,')
    parts.append('  "_comment": "Per-level platform layouts for vertical '
                 'shafts. ONE layout per level — designer edits this file '
                 'directly and the runtime spawns exactly these platforms. '
                 'No random selection. Regenerate scaffolding via '
                 'scripts/tools/gen_level_scenes.py. Coords are local to the '
                 'shaft origin (top-left). Keys: x, y = position; w = width; '
                 't = platform_type (stone, one_way, ice, mud, crumbling, '
                 'bounce, moving_horizontal, moving_vertical, etc).",')
    parts.append('  "levels": {')
    last_idx = len(vertical_levels) - 1
    for i, level_id in enumerate(vertical_levels):
        layout = generate_variant(level_id, 0)
        row = json.dumps(layout, separators=(',', ':'))
        trail = ',' if i < last_idx else ''
        parts.append(f'    "{level_id}": {row}{trail}')
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
level_id = {level_id}
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

    decor_written = 0
    decor_skipped = 0
    vertical_ids: list = []

    for lvl in levels:
        level_id = int(lvl["id"])
        if lvl.get("type", "platformer") != "vertical":
            continue
        vertical_ids.append(level_id)
        if write_decor_scene(level_id, args.force_decor):
            decor_written += 1
        else:
            decor_skipped += 1

    write_vertical_layouts_json(vertical_ids)

    print(f"Decor scenes:     {decor_written} written, {decor_skipped} skipped (existing)")
    print(f"Platform layouts: {len(vertical_ids)} entries → {LAYOUTS_JSON_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
