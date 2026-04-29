extends GutTest

# Tests for WelcomeCard — the pre-prologue welcome moment shown the
# very first time the player enters the Hub.

const WelcomeCardScript := preload("res://scripts/ui/WelcomeCard.gd")

var card: CanvasLayer

func before_each() -> void:
	card = WelcomeCardScript.new()
	add_child_autofree(card)

# ── Build ─────────────────────────────────────────────────────────────────────

func test_builds_three_labels() -> void:
	assert_not_null(card._title_lbl)
	assert_not_null(card._tagline_lbl)
	assert_not_null(card._press_lbl)

func test_layer_above_title_card() -> void:
	# TitleCard is layer 12. Welcome must be on top so the new player
	# sees it first.
	assert_gt(card.layer, 12)

func test_title_label_has_game_name() -> void:
	# Loc fallback ships "ESCAPE FROM HELL"; check non-empty + contains
	# expected token.
	assert_string_contains(card._title_lbl.text, "ESCAPE")

func test_initial_alphas_are_zero_in_animated_mode() -> void:
	# Without reduce-motion the labels start invisible and fade in.
	# This test runs in headless test env where MotionSettings exists
	# as an autoload — set it disabled to ensure animated path.
	var ms: Node = get_node_or_null("/root/MotionSettings")
	if ms and ms.has_method("set_enabled"):
		ms.set_enabled(false)
	# Re-instantiate so _ready fires after the toggle.
	var c2: CanvasLayer = WelcomeCardScript.new()
	add_child_autofree(c2)
	assert_lt(c2._title_lbl.modulate.a, 0.05)
	assert_lt(c2._tagline_lbl.modulate.a, 0.05)
	assert_lt(c2._press_lbl.modulate.a, 0.05)

# ── Dismiss ───────────────────────────────────────────────────────────────────

func test_dismiss_marks_dismissed() -> void:
	card._dismiss()
	assert_true(card._dismissed)

func test_double_dismiss_is_noop() -> void:
	card._dismiss()
	card._dismiss()
	pass_test("repeated dismiss must not crash")

func test_dismiss_emits_signal() -> void:
	watch_signals(card)
	card._dismiss()
	# In reduce-motion path the signal fires synchronously; in animated
	# path it fires after the fade-out tween. We don't await the tween
	# in tests — instead force reduce-motion and re-run.
	var ms: Node = get_node_or_null("/root/MotionSettings")
	if ms and ms.has_method("set_enabled"):
		ms.set_enabled(true)
	var c2: CanvasLayer = WelcomeCardScript.new()
	add_child_autofree(c2)
	watch_signals(c2)
	c2._dismiss()
	assert_signal_emitted(c2, "dismissed")
	if ms:
		ms.set_enabled(false)

# ── Tap-too-early guard ───────────────────────────────────────────────────────

func test_tap_in_first_400ms_ignored() -> void:
	# Brand-new card has _t == 0 — taps must be ignored.
	card._t = 0.1
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	card._unhandled_input(ev)
	assert_false(card._dismissed,
			"tap before 400ms must not dismiss the welcome")

# ── Auto-dismiss timer ────────────────────────────────────────────────────────

func test_auto_dismiss_after_timeout() -> void:
	card._t = card.AUTO_DISMISS_S - 0.01
	card._process(0.02)
	# _process should trigger _dismiss when _t crosses AUTO_DISMISS_S.
	assert_true(card._dismissed)
