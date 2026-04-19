extends GutTest

# Tests for Hub pure logic functions.

var hub: Node

func before_each() -> void:
	hub = autofree(preload("res://scripts/Hub.gd").new())
	# autofree() skips _ready() — avoids crash on missing $Background etc.
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

func test_pick_god_message_level_1_returns_calm_message() -> void:
	# Default SaveManager state: sin=0, souls=0, deals=0, level_id=1
	hub._next_level_id = 1
	var msg: Dictionary = hub._pick_god_message()
	assert_eq(msg.get("style"), "calm")
	assert_true(msg.get("text", "").length() > 0)

func test_pick_god_message_high_sin_warning() -> void:
	SaveManager.set_sin(75.0)
	hub._next_level_id = 1
	var msg: Dictionary = hub._pick_god_message()
	assert_eq(msg.get("style"), "warning")

func test_pick_god_message_soul_milestone_10() -> void:
	for i in 10:
		SaveManager.add_soul(i)
	hub._next_level_id = 3  # no level-specific message for level 3
	var msg: Dictionary = hub._pick_god_message()
	assert_true(msg.get("text", "").contains("Десять"))
	assert_eq(msg.get("style"), "warm")

func test_pick_god_message_soul_milestone_not_repeated() -> void:
	for i in 10:
		SaveManager.add_soul(i)
	SaveManager.mark_hint_seen("soul_milestone_10")
	hub._next_level_id = 3
	var msg: Dictionary = hub._pick_god_message()
	assert_false(msg.get("text", "").contains("Десять"), "milestone should not repeat")

func test_pick_god_message_99_souls() -> void:
	for i in 99:
		SaveManager.add_soul(i)
	hub._next_level_id = 3
	var msg: Dictionary = hub._pick_god_message()
	assert_eq(msg.get("style"), "solemn")
	assert_true(msg.get("text", "").contains("Одна"))

func test_pick_god_message_returns_dict_or_empty() -> void:
	hub._next_level_id = 3  # no level message, no souls, default state
	var msg: Variant = hub._pick_god_message()
	assert_true(msg is Dictionary)

func test_pick_god_message_more_deals_accepted_than_refused() -> void:
	SaveManager.increment_demon_deals()
	SaveManager.increment_demon_deals()
	# deals_refused stays 0 → accepted(2) > refused(0)
	hub._next_level_id = 1
	var msg: Dictionary = hub._pick_god_message()
	assert_eq(msg.get("style"), "quiet")
