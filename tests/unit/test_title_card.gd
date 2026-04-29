extends GutTest

# Tests for TitleCard — the brief Souls-style "CIRCLE N — NAME"
# overlay shown at the start of each level.

const TitleCardScript := preload("res://scripts/ui/TitleCard.gd")

var card: CanvasLayer

func before_each() -> void:
	card = TitleCardScript.new()
	card.setup(1, 1)
	add_child_autofree(card)

# ── Build ─────────────────────────────────────────────────────────────────────

func test_builds_three_labels() -> void:
	assert_not_null(card._t_label)
	assert_not_null(card._name_label)
	assert_not_null(card._level_label)

func test_layer_above_hud_and_topbar() -> void:
	# HUD = layer 10, TopBar = 11, TitleCard = 12+ to sit on top.
	assert_gt(card.layer, 11)

# ── Text content ──────────────────────────────────────────────────────────────

func test_circle_label_uses_circle_format() -> void:
	# Loc fallback ships the UA template "Коло %d" — the rendered
	# label must contain the number.
	assert_string_contains(card._t_label.text, "1")

func test_circle_name_for_known_circle() -> void:
	# Default fallback dict has 1=Лімб; the label is upper-cased so
	# we check the upper form.
	assert_string_contains(card._name_label.text, "ЛІМБ")

func test_setup_changes_circle_id() -> void:
	var card2: CanvasLayer = TitleCardScript.new()
	card2.setup(7, 65)
	add_child_autofree(card2)
	assert_string_contains(card2._t_label.text, "7")
	assert_string_contains(card2._level_label.text, "65")
	# Circle 7 is "Насилля" — fallback dict knows that.
	assert_string_contains(card2._name_label.text, "НАСИЛЛЯ")

# ── Auto-dismiss ──────────────────────────────────────────────────────────────

func test_process_advances_hold_timer() -> void:
	var before: float = card._hold_t
	card._process(0.5)
	assert_gt(card._hold_t, before)

func test_dismiss_marks_dismissed() -> void:
	card._dismiss()
	assert_true(card._dismissed)

func test_double_dismiss_is_noop() -> void:
	card._dismiss()
	card._dismiss()
	pass_test("repeated dismiss must not crash")

# ── Reduce-motion path ────────────────────────────────────────────────────────

func test_reduce_motion_helper_default_false() -> void:
	# In test env without MotionSettings autoload it should fall back
	# to false (graceful no-autoload).
	# If the autoload IS registered but disabled, also false.
	var ms: Node = get_node_or_null("/root/MotionSettings")
	if ms and ms.has_method("set_enabled"):
		ms.set_enabled(false)
	assert_false(card._is_reduce_motion())
