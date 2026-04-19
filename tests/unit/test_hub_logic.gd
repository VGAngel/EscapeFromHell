extends GutTest

# Tests for Hub pure logic functions.

var hub: Node

func before_each() -> void:
	hub = preload("res://scripts/Hub.gd").new()
	add_child_autofree(hub)
	if SaveManager:
		SaveManager._reset()

# ── _speaker_label ────────────────────────────────────────────────────────────

func test_speaker_label_god() -> void:
	assert_eq(hub._speaker_label("god"), "Бог")

func test_speaker_label_player() -> void:
	assert_eq(hub._speaker_label("player"), "Данило")

func test_speaker_label_narration_empty() -> void:
	assert_eq(hub._speaker_label("narration"), "")

func test_speaker_label_unknown_empty() -> void:
	assert_eq(hub._speaker_label("unknown"), "")

func test_speaker_label_empty_string() -> void:
	assert_eq(hub._speaker_label(""), "")

# ── _pick_god_message ─────────────────────────────────────────────────────────

func test_pick_god_message_level_1_without_savemanager() -> void:
	# TODO: inject SaveManager mock with get_sin / get_total_souls / get_current_level
	# so the conditional branches can be exercised deterministically.
	pass

func test_pick_god_message_high_sin_warning() -> void:
	# TODO: set SaveManager sin > 70, assert style == "warning"
	pass

func test_pick_god_message_soul_milestone_10() -> void:
	# TODO: set total_souls = 10 and hint "soul_milestone_10" not seen,
	# assert returned text contains "Десять"
	pass

func test_pick_god_message_soul_milestone_not_repeated() -> void:
	# TODO: mark "soul_milestone_10" as seen, assert milestone message NOT returned
	pass

func test_pick_god_message_99_souls() -> void:
	# TODO: set total_souls = 99, assert solemn message about last soul
	pass

func test_pick_god_message_returns_dict_or_empty() -> void:
	# TODO: assert return type is Dictionary (may be empty {})
	pass

func test_pick_god_message_more_deals_accepted_than_refused() -> void:
	# TODO: set demon_deals_accepted > deals_refused,
	# assert "quiet" style message returned
	pass
