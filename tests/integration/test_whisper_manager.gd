extends GutTest

# Integration tests for WhisperManager.
#
# Uses the actual autoload instance (registered in project.godot) for
# threshold-crossing logic, but exercises pure helpers + state via the
# public API.

var wm: Node

func before_each() -> void:
	wm = WhisperManager
	# Reset run state so each test starts from a known baseline.
	wm._shown_this_level.clear()
	wm._last_sin = 0.0

# ── Config loading ────────────────────────────────────────────────────────────

func test_phrases_loaded_for_all_three_tiers() -> void:
	for k in ["tier_30", "tier_60", "tier_85"]:
		assert_true(wm._phrases.has(k), "missing tier '%s' in whispers_config" % k)
		assert_gt(wm._phrases[k].size(), 0, "tier '%s' has zero phrases" % k)

# ── Threshold crossing ───────────────────────────────────────────────────────

func test_crossing_30_threshold_marks_shown() -> void:
	wm._on_sin_changed(35.0)
	assert_eq(wm._shown_this_level.get("tier_30"), 1)

func test_no_emit_when_already_above_threshold() -> void:
	# Player started this level at 50% sin; ticking up to 55% shouldn't
	# re-fire tier_30.
	wm._last_sin = 50.0
	wm._shown_this_level.clear()
	wm._on_sin_changed(55.0)
	assert_false(wm._shown_this_level.has("tier_30"),
		"tier_30 should not fire when already above its threshold")

func test_no_emit_when_below_all_thresholds() -> void:
	wm._on_sin_changed(15.0)
	assert_eq(wm._shown_this_level.size(), 0)

func test_higher_tier_wins_when_crossing_multiple_at_once() -> void:
	# Demon deal: jumps from 25% to 90% in one shot → expect tier_85
	# (highest) to fire, lower ones can fire on later level if needed.
	wm._last_sin = 25.0
	wm._on_sin_changed(90.0)
	assert_eq(wm._shown_this_level.get("tier_85"), 1)
	assert_false(wm._shown_this_level.has("tier_30"),
		"only the highest crossed tier should fire per delta")

# ── Per-level cap ─────────────────────────────────────────────────────────────

func test_show_whisper_caps_at_one_per_tier_per_level() -> void:
	wm.show_whisper("tier_30")
	# Calling again same level → must NOT increment.
	wm.show_whisper("tier_30")
	assert_eq(wm._shown_this_level.get("tier_30"), 1)

func test_level_started_resets_shown_list() -> void:
	wm.show_whisper("tier_30")
	wm.show_whisper("tier_60")
	wm._on_level_started(5)
	assert_eq(wm._shown_this_level.size(), 0)
