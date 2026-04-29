extends GutTest

# Tests for the upgraded HUD._pulse_node — the satisfying "pop"
# animation on counter changes (souls, light, capacity).
#
# We can't easily await tween completion in GUT without flakiness, so
# the tests verify the pre/post-state contracts: pivot centred, tween
# stashed in meta, previous tween killed on rapid re-call, and that
# the function tolerates non-Label nodes.

const HUDScript := preload("res://scripts/ui/HUD.gd")

var hud: CanvasLayer

func before_each() -> void:
	hud = HUDScript.new()
	add_child_autofree(hud)
	# _ready builds the UI; we just need the helper to be available.

# ── Pivot ─────────────────────────────────────────────────────────────────────

func test_pivot_centred_on_call() -> void:
	var lbl := Label.new()
	lbl.size = Vector2(120, 40)
	lbl.pivot_offset = Vector2.ZERO
	add_child_autofree(lbl)
	hud._pulse_node(lbl, 0.3)
	assert_eq(lbl.pivot_offset, lbl.size * 0.5,
			"pivot must be centred so the bounce expands symmetrically")

# ── Tween stash ───────────────────────────────────────────────────────────────

func test_meta_tween_is_stashed() -> void:
	var lbl := Label.new()
	lbl.size = Vector2(80, 30)
	add_child_autofree(lbl)
	hud._pulse_node(lbl, 0.3)
	assert_true(lbl.has_meta("hud_pop_tween"),
			"a hud_pop_tween reference must be stashed on the node")

# ── Re-pulse cancels previous tween ───────────────────────────────────────────

func test_rapid_repulse_kills_previous_tween() -> void:
	var lbl := Label.new()
	lbl.size = Vector2(80, 30)
	add_child_autofree(lbl)
	hud._pulse_node(lbl, 0.3)
	var first: Tween = lbl.get_meta("hud_pop_tween")
	hud._pulse_node(lbl, 0.3)
	var second: Tween = lbl.get_meta("hud_pop_tween")
	assert_ne(first, second, "second pulse must create a fresh tween")
	assert_false(first.is_valid(), "previous tween must be killed")

# ── Non-Label tolerance ───────────────────────────────────────────────────────

func test_non_label_does_not_crash() -> void:
	# A plain Control has no font_color theme entry — the helper has
	# to noop the colour-flash branch and only run the scale tween.
	var ctrl := Control.new()
	ctrl.size = Vector2(60, 60)
	add_child_autofree(ctrl)
	hud._pulse_node(ctrl, 0.25)
	assert_true(ctrl.has_meta("hud_pop_tween"))

# ── Null safety ───────────────────────────────────────────────────────────────

func test_null_node_is_noop() -> void:
	hud._pulse_node(null, 0.3)
	pass_test("null node must not crash")

# ── Constants sanity ──────────────────────────────────────────────────────────

func test_peak_scale_overshoots_one() -> void:
	# The pop only reads as "satisfying" if scale > 1.0 — guard against
	# accidentally lowering it below the bounce threshold.
	assert_gt(hud._POP_SCALE_PEAK.x, 1.15)
	assert_eq(hud._POP_SCALE_PEAK.x, hud._POP_SCALE_PEAK.y,
			"scale must be uniform")
