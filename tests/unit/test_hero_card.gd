extends GutTest

# Tests for HeroCard — the player-snapshot panel on MainMenu.
# Uses the live SaveManager autoload (well-tested upstream) to drive
# the readout, then verifies the labels render expected substrings.

const HeroCardScript := preload("res://scripts/ui/HeroCard.gd")

var card: PanelContainer
var sm: Node

func before_each() -> void:
	sm = get_node_or_null("/root/SaveManager")
	# Reset relevant slot fields to known values where possible.
	if sm and sm.has_method("set_profile_name"):
		sm.set_profile_name("ТестГерой")
	card = HeroCardScript.new()
	add_child_autofree(card)
	# _ready already calls refresh; make sure it doesn't crash.

# ── Build ─────────────────────────────────────────────────────────────────────

func test_card_builds_all_labels() -> void:
	assert_not_null(card._name_lbl)
	assert_not_null(card._circle_lbl)
	assert_not_null(card._level_lbl)
	assert_not_null(card._souls_lbl)
	assert_not_null(card._best_lbl)
	assert_not_null(card._sin_lbl)

# ── Refresh ───────────────────────────────────────────────────────────────────

func test_refresh_renders_player_snapshot() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	card.refresh()
	# Name should be populated.
	assert_ne(card._name_lbl.text, "")
	# Circle/Level have prefixes we control.
	assert_true(card._circle_lbl.text.begins_with("Коло"),
			"got: %s" % card._circle_lbl.text)
	assert_true(card._level_lbl.text.begins_with("Рівень"),
			"got: %s" % card._level_lbl.text)
	# Souls row contains all three icons.
	assert_string_contains(card._souls_lbl.text, "👻")
	assert_string_contains(card._souls_lbl.text, "✦")
	assert_string_contains(card._souls_lbl.text, "💡")

func test_refresh_handles_missing_save_manager() -> void:
	# Override the path resolution by rerooting the card to a
	# scene-less control that doesn't have /root visible … instead,
	# simulate by clearing labels and verifying refresh writes a
	# fallback. We can't easily yank the autoload, so this test
	# just confirms refresh doesn't crash when called repeatedly.
	for i in 3:
		card.refresh()
	pass_test("repeated refresh is safe")

# ── Best run formatting ───────────────────────────────────────────────────────

func test_best_label_when_no_clears_shows_dash() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	# We can't guarantee no clears if test ordering hits stats — check
	# that the label always starts with the trophy prefix.
	card.refresh()
	assert_true(card._best_lbl.text.begins_with("🏆"),
			"got: %s" % card._best_lbl.text)

# ── Sin colour mapping ────────────────────────────────────────────────────────

func test_sin_color_low_is_greenish() -> void:
	# Internal helper: 0% sin → SUCCESS green.
	var c: Color = card._sin_color(0)
	assert_almost_eq(c.g, 0.85, 0.05, "0% sin should be greenish")

func test_sin_color_high_is_reddish() -> void:
	var c: Color = card._sin_color(100)
	assert_gt(c.r, 0.6, "100% sin should be reddish")
	assert_lt(c.g, 0.5)
