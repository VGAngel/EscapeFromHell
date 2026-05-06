#!/usr/bin/env python3
"""
One-shot generator: produces per-level inherited scenes + 5 randomized
platform-layout variants per vertical level.

Outputs:
  scenes/levels/instances/Level_NNN.tscn       (one per level in levels_config.json)
  scenes/rooms/vertical_layouts/level_NNN/layout_K.tscn   (K=1..5, vertical only)

Each layout_K is a *different* random arrangement seeded by (level_id, K),
so reruns are reproducible but the 5 variants are visibly distinct from each
other. Layouts are reachability-aware (max jump + horizontal travel) so every
stub is playable as-is without manual fixes.

Run from repo root:
  python3 scripts/tools/gen_level_scenes.py

Idempotent — overwrites existing files.
"""
import json
import math
import os
import random
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG_PATH = os.path.join(REPO_ROOT, "levels_config.json")
INSTANCES_DIR = os.path.join(REPO_ROOT, "scenes", "levels", "instances")
LAYOUTS_DIR = os.path.join(REPO_ROOT, "scenes", "rooms", "vertical_layouts")

BASE_SCENE = {
    "vertical":  ("res://scenes/levels/Level.tscn",     "uid://level1tscn01"),
    "platformer":("res://scenes/levels/Level.tscn",     "uid://level1tscn01"),
    "boss":      ("res://scenes/levels/BossLevel.tscn", "uid://bosslevel1tsc"),
    "void":      ("res://scenes/levels/VoidLevel.tscn", "uid://cdg0m4a4r0m77"),
}

BASE_PLATFORM_SCRIPT = "res://scripts/platforms/BasePlatform.gd"

# ── Shaft geometry (mirrors PlaceholderRoom + LevelGenerator constants) ──────
ROOM_WIDTH = 1080.0
SIDE_WALL_W = 60.0
WALL_T = 30.0
PLATFORM_T = 30.0
VIEWPORT_HEIGHT = 1920.0
MAX_JUMP_HEIGHT = 200.0
SAME_LEVEL_REACH = 240.0   # horizontal distance the player can clear at no rise

# room_count by (level_id % 10) — see scripts/levels/LevelGenerator.gd:40
#   idx 0 (level 10/20/...): unused in vertical (those are circle bosses).
ROOM_COUNT_BY_IDX = [4, 2, 3, 4, 4, 5, 6, 6, 7, 8]

# Row spacing per circle/difficulty — middle-of-the-road default. Real game
# uses 200..280 px depending on tier; 260 keeps every gap inside MAX_JUMP_HEIGHT
# with a small safety margin.
ROW_SPACING = 260.0

# Horizontal zones across the shaft (relative to room_width). Same anchors as
# the Markov generator — wide enough that even max-width platforms (~330 px)
# don't clip the side walls.
ZONE_CENTERS_REL = [0.20, 0.40, 0.60, 0.80]

# Width sampling — three buckets with tier-leaning weights. Sums don't have to
# be 1.0 (we normalize when sampling).
WIDTH_BUCKETS = [180.0, 220.0, 260.0]
WIDTH_WEIGHTS = [0.25, 0.50, 0.25]

# Stubs ship as pure stone — typed-platform behaviour (crumbling, moving, ice,
# bounce, …) requires the matching script (CrumblingPlatform.gd, MovingPlatform.gd,
# …), not just the BasePlatform script with a different label. Producing a stub
# that *says* "crumbling" but doesn't actually crumble would mislead the
# designer. They swap script/type in the Inspector when they want real
# behaviour — that's the whole point of editable stubs.
TYPE_OPTIONS = [
    ("stone", 1.0),
]


def make_uid(prefix: str, n: int) -> str:
    return f"uid://{prefix}{n:08d}"


def make_layout_uid(level_id: int, k: int) -> str:
    return f"uid://vlay{level_id:04d}{k}"


def write_inherited_scene(level_id: int, base_path: str, base_uid: str) -> str:
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
    return fpath


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
    rooms = ROOM_COUNT_BY_IDX[idx]
    return VIEWPORT_HEIGHT * float(rooms)


def max_horizontal_jump(v_gap_px: float) -> float:
    """Mirror of PlaceholderRoom._max_horizontal_jump — keeps stub layouts
    reachable. v_gap > 0 means rising; 0 means level/falling."""
    if v_gap_px <= 0.0:
        return SAME_LEVEL_REACH * 1.15
    t = max(0.0, min(1.0, v_gap_px / MAX_JUMP_HEIGHT))
    return (SAME_LEVEL_REACH + (120.0 - SAME_LEVEL_REACH) * t) * 1.15


def generate_layout(level_id: int, variant_k: int) -> list:
    """Return list of {x, y, width, type} platform dicts for one variant."""
    rng = random.Random(hash((level_id, variant_k, "layout-v1")))

    height = shaft_height_for(level_id)
    floor_y = height - WALL_T
    ceiling_y = WALL_T + 120.0  # leave headroom for player

    # Y rows from floor walking upward. First row is one spacing above floor;
    # last row is the closest to ceiling that still leaves player headroom.
    rows_y = []
    y = floor_y - ROW_SPACING
    while y >= ceiling_y:
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
        # Anti-clustering: avoid sticking to the same zone two rows in a row.
        # Bias toward neighbour zones (delta ±1) — mirrors the Markov chain.
        deltas = [-2, -1, 0, 1, 2]
        weights = [0.10, 0.40, 0.10, 0.40, 0.10] if i > 0 else [0.25, 0.25, 0.25, 0.25, 0.25]
        # Y jitter so rows don't form a perfect grid.
        jitter = rng.uniform(-ROW_SPACING * 0.05, ROW_SPACING * 0.05)
        if i == 0 or i == len(rows_y) - 1:
            jitter = 0.0
        zone = prev_zone
        for _attempt in range(8):
            d = weighted_choice(rng, list(zip(deltas, weights)))
            cand = max(0, min(zone_count - 1, prev_zone + d))
            if cand != prev_zone or i == 0:
                zone = cand
                break

        x = zone_centers[zone] + rng.uniform(-ROOM_WIDTH * 0.03, ROOM_WIDTH * 0.03)
        width = weighted_choice(rng, list(zip(WIDTH_BUCKETS, WIDTH_WEIGHTS)))
        ptype = weighted_choice(rng, TYPE_OPTIONS)
        # Top + bottom rows always stone for safe entry/exit.
        if i == 0 or i == len(rows_y) - 1:
            ptype = "stone"

        # Reachability snap: keep horizontal jump from previous platform within
        # physical reach + 15% margin. Same formula PlaceholderRoom uses.
        ry_jittered = ry + jitter
        if prev_x is not None:
            v_gap = prev_y - ry_jittered  # positive = current row is higher
            max_dx = (max_horizontal_jump(v_gap) + (prev_w + width) * 0.5) * 0.85
            dx = x - prev_x
            if abs(dx) > max_dx:
                x = prev_x + math.copysign(max_dx, dx)

        # Final clamp inside playable interior (don't sink half the platform
        # into the side wall).
        min_x = SIDE_WALL_W + width * 0.5
        max_x = ROOM_WIDTH - SIDE_WALL_W - width * 0.5
        x = max(min_x, min(max_x, x))

        plats.append({"x": round(x, 1), "y": round(ry_jittered, 1),
                      "width": width, "type": ptype})

        prev_zone = zone
        prev_x = x
        prev_w = width
        prev_y = ry_jittered

    return plats


def write_layout_scene(level_id: int, k: int) -> str:
    layout_dir = os.path.join(LAYOUTS_DIR, f"level_{level_id:03d}")
    os.makedirs(layout_dir, exist_ok=True)
    fpath = os.path.join(layout_dir, f"layout_{k}.tscn")

    plats = generate_layout(level_id, k)

    uid = make_layout_uid(level_id, k)
    lines = [
        f'[gd_scene load_steps=2 format=3 uid="{uid}"]',
        '',
        f'[ext_resource type="Script" path="{BASE_PLATFORM_SCRIPT}" id="1_plat"]',
        '',
        '[node name="VerticalLayout" type="Node2D"]',
        '',
    ]
    for i, p in enumerate(plats):
        node_name = f"Platform_{i+1}"
        lines.append(f'[node name="{node_name}" type="StaticBody2D" parent="."]')
        lines.append(f'position = Vector2({p["x"]}, {p["y"]})')
        lines.append('collision_layer = 1')
        lines.append('script = ExtResource("1_plat")')
        lines.append(f'platform_type = "{p["type"]}"')
        lines.append(f'size = Vector2({p["width"]}, {PLATFORM_T})')
        lines.append('')
    with open(fpath, "w") as f:
        f.write("\n".join(lines))
    return fpath


def main() -> int:
    with open(CONFIG_PATH) as f:
        cfg = json.load(f)
    levels = cfg.get("levels", [])

    inherit_count = 0
    layout_count = 0

    for lvl in levels:
        level_id = int(lvl["id"])
        ltype = lvl.get("type", "platformer")
        base = BASE_SCENE.get(ltype, BASE_SCENE["platformer"])
        write_inherited_scene(level_id, base[0], base[1])
        inherit_count += 1

        if ltype == "vertical":
            for k in range(1, 6):
                write_layout_scene(level_id, k)
                layout_count += 1

    print(f"Generated {inherit_count} inherited level scenes → {INSTANCES_DIR}")
    print(f"Generated {layout_count} layout variants → {LAYOUTS_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
