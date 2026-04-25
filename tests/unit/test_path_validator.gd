extends GutTest

# Tests for PathValidator — pure platform-layout sanity checks.
# Use small hand-crafted layouts so each scenario reads like a screenshot
# in code form. When a real shaft has a problem, paste it as a test case
# here and watch which validator flags it — that's the shared vocabulary.

const PathValidator := preload("res://scripts/levels/PathValidator.gd")

func _p(label: String, x: float, y: float, w: float) -> Dictionary:
	return {"label": label, "x": x, "y": y, "w": w}

# ── DOWN-path: walk off edge, must land within tier-0 (≤ 300 px) ──────────────

func test_down_path_clean_when_platforms_overlap() -> void:
	# Two stacked platforms with full X overlap — walking off either edge
	# of the upper lands on the lower right under the player.
	var layout: Array = [
		_p("upper", 500.0, 200.0, 220.0),  # range 390..610
		_p("lower", 500.0, 400.0, 220.0),  # range 390..610, 200 px below
	]
	var issues: Array = PathValidator.validate_down_path(layout)
	assert_eq(issues.size(), 0,
		"overlapping stacked platforms must produce zero down-path issues")

func test_down_path_flags_walk_off_into_void() -> void:
	# Upper at right side (700..900). Bottom platform sits FAR to the left
	# (range 0..200), beyond reach band even with full air control. Player
	# walking off the right edge has no tier-0 landing.
	var layout: Array = [
		_p("upper",  800.0, 100.0, 200.0),  # range 700..900
		_p("bottom", 100.0, 400.0, 200.0),  # range 0..200, 300 px below
	]
	var issues: Array = PathValidator.validate_down_path(layout)
	var right_issues: Array = issues.filter(func(i): return i.side == "right")
	assert_gt(right_issues.size(), 0,
		"walking off the right edge into void must be flagged")

func test_down_path_flags_user_real_case_row17_to_row16_unreachable() -> void:
	# User's actual case from a real dump:
	#   row 17 at (459, 507) w=330 → range 294..624, right edge 624
	#   row 16 at (900, 681) w=240 → range 780..1020 (174 px below row 17)
	#   row 15 at (666, 873) w=418 → range 457..875 (366 px below row 17)
	# Walking right off row 17, the player's tier-0 reach band at row 16's
	# Y is [624 ± 180 × sqrt(2×174/900) = ± 112] = [512, 736]. row 16
	# starts at 780 → no overlap. row 15 is too far down (366 > 300) →
	# tier-1 damage. Validator must flag right walk-off as having no
	# tier-0 landing.
	var layout: Array = [
		_p("row17", 459.0, 507.0, 330.0),
		_p("row16", 900.0, 681.0, 240.0),
		_p("row15", 666.0, 873.0, 418.0),
	]
	var issues: Array = PathValidator.validate_down_path(layout)
	var right_issues: Array = issues.filter(func(i):
		return String(i.label) == "row17" and i.side == "right")
	assert_gt(right_issues.size(), 0,
		"row17 right walk-off must be flagged — no tier-0 landing")

func test_down_path_no_issue_when_walk_off_lands_safely() -> void:
	# Same row17/row16 widths but row16 sits closer to row17 so walk-off
	# (112 px right travel) reaches row16's footprint.
	var layout: Array = [
		_p("upper", 459.0, 507.0, 330.0),  # range 294..624, right edge 624
		_p("lower", 700.0, 681.0, 240.0),  # range 580..820 — covers x=624+112=736? no, 736 in 580..820 yes
	]
	var issues: Array = PathValidator.validate_down_path(layout)
	# Right walk-off from upper: x_at_landing = 624 + 180×0.62 = 736.
	# 736 ∈ [580, 820] → catches. Fall = 174 px (no damage).
	var right_issues: Array = issues.filter(func(i): return i.side == "right")
	assert_eq(right_issues.size(), 0,
		"walk-off lands within lower's footprint → no issue")

func test_down_path_skips_lowest_platform() -> void:
	# Lowest platform has no obligation to provide a landing for itself.
	var layout: Array = [
		_p("only", 500.0, 1000.0, 220.0),
	]
	var issues: Array = PathValidator.validate_down_path(layout)
	assert_eq(issues.size(), 0)

# ── UP-path: jump platform-to-platform, must reach within MAX_JUMP_HEIGHT ─────

func test_up_path_clean_for_stacked_platforms() -> void:
	# Same X column, 180 px apart vertically, both wide → trivially climbable.
	var layout: Array = [
		_p("bot", 500.0, 400.0, 220.0),
		_p("top", 500.0, 220.0, 220.0),
	]
	var issues: Array = PathValidator.validate_up_path(layout)
	assert_eq(issues.size(), 0)

func test_up_path_flags_when_next_up_too_far_horizontally() -> void:
	# Bottom at x=100, only "up" candidate at x=900, 180 px above → centre
	# distance 800, max horizontal jump at 180 v_gap is ~125 + half-widths
	# (≤ 345). Way out of reach → flagged.
	var layout: Array = [
		_p("bot", 100.0, 400.0, 220.0),
		_p("top", 900.0, 220.0, 220.0),
	]
	var issues: Array = PathValidator.validate_up_path(layout)
	assert_eq(issues.size(), 1, "bot has no climb option → 1 issue")
	assert_eq(String(issues[0].label), "bot")

func test_up_path_flags_when_vertical_gap_exceeds_max_jump() -> void:
	# 250 px gap > MAX_JUMP_HEIGHT (200) → unreachable regardless of X.
	var layout: Array = [
		_p("bot", 500.0, 400.0, 220.0),
		_p("top", 500.0, 150.0, 220.0),  # 250 px above
	]
	var issues: Array = PathValidator.validate_up_path(layout)
	assert_eq(issues.size(), 1)
	assert_eq(String(issues[0].label), "bot")

func test_up_path_skips_topmost_platform() -> void:
	# Highest platform has no obligation to have anything above it.
	var layout: Array = [
		_p("only", 500.0, 100.0, 220.0),
	]
	var issues: Array = PathValidator.validate_up_path(layout)
	assert_eq(issues.size(), 0)

# ── Combined: validate_all ──────────────────────────────────────────────────

func test_user_real_dump_row9_isolated_from_row10() -> void:
	# Real dump (level 1, room 1#1), user reports "10th platform from the
	# altar" — the altar sits at the top, so 10th from top = dump's row 9
	# (indexed from bottom). Row 9 sits FAR right (x=877), row 10 above
	# sits FAR left (x=421). Centre delta = 456 px, vertical gap = 185 px.
	#
	#   Walk-off from row 10 (range 256..586) — no band reaches row 9
	#     (range 734..1019).
	#   Jump UP from row 9 → row 10 — max_center ≈ 437 (< 456 by 19 px).
	#
	# Row 9 is effectively isolated from row 10: reachable only from below
	# via bridge row 8. Validator must flag it on the up-path.
	var layout: Array = [
		_p("row8",  864.0, 2126.0, 330.0),
		_p("row9",  877.0, 1956.0, 285.0),
		_p("row10", 421.0, 1771.0, 330.0),
	]
	var up: Array = PathValidator.validate_up_path(layout)
	var row9_up: Array = up.filter(func(i): return String(i.label) == "row9")
	assert_eq(row9_up.size(), 1,
		"row9 must be flagged — too far from row10 to jump up")

func test_user_real_dump_row10_is_stuck_both_directions() -> void:
	# Real dump (level 1, room 1#1), user reports row 10 as problematic:
	#   row 10: y=1771, x=421, w=330  → range 256..586
	#   row 9:  y=1956, x=877, w=285  → range 734..1019  (185 px below row 10)
	#   row 8:  y=2126, bridge x=864  → bridge L 106..326, R 754..974 (355 px below)
	#   row 11: y=1581, x=811, w=160  → range 731..891  (190 px above row 10)
	#
	# Walking off either edge of row 10 has no tier-0 landing — row 9 sits
	# 456 px to the right (horizontal mismatch). Player drops past row 9
	# to row 8's bridge → 355 px fall → tier-1 (-1 HP).
	# Climbing back UP from row 10 to row 11 also fails: dx=390, v_gap=190,
	# max_h ≈ 134, half-widths (330+160)/2 = 245 → max_center ≈ 379 < 390.
	#
	# Validator must flag BOTH down-path edges of row 10 and the up-path.
	var layout: Array = [
		_p("row8",  864.0, 2126.0, 330.0),  # bridge anchor — treat as single
		_p("row9",  877.0, 1956.0, 285.0),
		_p("row10", 421.0, 1771.0, 330.0),
		_p("row11", 811.0, 1581.0, 160.0),
	]
	var down: Array = PathValidator.validate_down_path(layout)
	var row10_down: Array = down.filter(func(i): return String(i.label) == "row10")
	assert_eq(row10_down.size(), 2,
		"row10 must have BOTH walk-off edges flagged (no tier-0 landing on either side)")
	var sides: Array = row10_down.map(func(i): return String(i.side))
	assert_true("left"  in sides, "row10 left walk-off must be flagged")
	assert_true("right" in sides, "row10 right walk-off must be flagged")

	var up: Array = PathValidator.validate_up_path(layout)
	var row10_up: Array = up.filter(func(i): return String(i.label) == "row10")
	assert_eq(row10_up.size(), 1,
		"row10 must be flagged as having no reachable platform UP")

func test_validate_all_combines_both_path_issues() -> void:
	# A layout that breaks BOTH paths in different rows.
	var layout: Array = [
		_p("a", 100.0, 100.0, 200.0),  # left edge 0 walk-off into void
		_p("b", 900.0, 250.0, 200.0),  # too far right of "a" to climb back
	]
	var issues: Array = PathValidator.validate_all(layout)
	var down_count: int = issues.filter(func(i): return i.path == "down").size()
	var up_count:   int = issues.filter(func(i): return i.path == "up").size()
	assert_gt(down_count, 0, "down-path should flag at least one walk-off problem")
	assert_gt(up_count,   0, "up-path should flag the broken climb from b → a")
