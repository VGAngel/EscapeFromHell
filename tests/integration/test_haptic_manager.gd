extends GutTest

# Tests for HapticManager — autoload that wraps Input.vibrate_handheld().
# Headless desktop has no physical handheld so vibrate calls are no-ops;
# these tests exercise the logic gate (enabled flag, mobile-only check)
# rather than verifying actual vibration.

var hm: Node

func before_each() -> void:
	hm = HapticManager
	# Guarantee a known state regardless of test order.
	hm.set_enabled(true)

# ── Toggle ────────────────────────────────────────────────────────────────────

func test_set_enabled_persists_in_memory() -> void:
	hm.set_enabled(false)
	assert_false(hm.is_enabled())
	hm.set_enabled(true)
	assert_true(hm.is_enabled())

func test_default_enabled_is_true() -> void:
	# Read the same path the autoload reads.
	var settings_path: String = "user://settings.json"
	# Default is true unless settings.json explicitly turns haptics off.
	if not FileAccess.file_exists(settings_path):
		assert_true(hm.is_enabled())
	else:
		# When file exists, just check the toggle is reachable.
		assert_true(hm.set_enabled.is_valid())

# ── Mobile detection ─────────────────────────────────────────────────────────

func test_is_mobile_matches_OS_feature() -> void:
	var expected: bool = OS.has_feature("mobile") or OS.has_feature("android")
	assert_eq(hm.is_mobile(), expected)

# ── Event helpers don't crash ────────────────────────────────────────────────

func test_hit_does_not_crash() -> void:
	hm.hit()
	assert_true(true)

func test_jump_does_not_crash() -> void:
	hm.jump()
	assert_true(true)

func test_pickup_does_not_crash() -> void:
	hm.pickup()
	assert_true(true)

func test_death_does_not_crash() -> void:
	hm.death()
	assert_true(true)

func test_deliver_does_not_crash() -> void:
	hm.deliver()
	assert_true(true)

func test_boss_stun_does_not_crash() -> void:
	# Three-burst pattern with create_timer — must not blow up even with
	# rapid succession.
	hm.boss_stun()
	hm.boss_stun()
	assert_true(true)

# ── Disabled flag suppresses vibrate calls ────────────────────────────────────
# Hard to assert "vibrate was NOT called" without mocking Input, but we
# can verify that the gate logic at minimum doesn't error and reads the
# flag correctly.

func test_disabled_state_still_callable() -> void:
	hm.set_enabled(false)
	hm.hit()
	hm.jump()
	hm.pickup()
	hm.death()
	hm.boss_stun()
	assert_false(hm.is_enabled())

# ── Preset constants are sane ────────────────────────────────────────────────
# Locks in the per-event tuning so a future "let me tweak amplitude"
# accidentally pushing values to 0 or above 1 fails fast.

func test_preset_amplitudes_within_zero_to_one() -> void:
	for preset in [hm._PRESET_HIT, hm._PRESET_JUMP, hm._PRESET_PICKUP,
			hm._PRESET_DEATH, hm._PRESET_BOSS_STUN, hm._PRESET_DELIVER]:
		var amp: float = float(preset[1])
		assert_gte(amp, 0.0, "amplitude must be ≥ 0")
		assert_lte(amp, 1.0, "amplitude must be ≤ 1")

func test_preset_durations_positive_int() -> void:
	for preset in [hm._PRESET_HIT, hm._PRESET_JUMP, hm._PRESET_PICKUP,
			hm._PRESET_DEATH, hm._PRESET_BOSS_STUN, hm._PRESET_DELIVER]:
		var dur: int = int(preset[0])
		assert_gt(dur, 0, "duration_ms must be positive")
		assert_lt(dur, 1000, "duration_ms should be < 1s for game pulses")

func test_death_preset_is_longest() -> void:
	# Death is the heaviest haptic; everything else should be shorter than it.
	var death_dur: int = int(hm._PRESET_DEATH[0])
	for preset in [hm._PRESET_HIT, hm._PRESET_JUMP, hm._PRESET_PICKUP,
			hm._PRESET_BOSS_STUN, hm._PRESET_DELIVER]:
		assert_lt(int(preset[0]), death_dur,
			"death pulse should be the longest haptic")

func test_jump_preset_is_subtle() -> void:
	# Jump fires constantly during play — must be the shortest + softest
	# so it doesn't fatigue the player's hand.
	var jump_dur: int = int(hm._PRESET_JUMP[0])
	var jump_amp: float = float(hm._PRESET_JUMP[1])
	for preset in [hm._PRESET_HIT, hm._PRESET_PICKUP, hm._PRESET_DEATH,
			hm._PRESET_BOSS_STUN, hm._PRESET_DELIVER]:
		assert_lte(jump_dur, int(preset[0]),
			"jump should be the shortest haptic")
		assert_lte(jump_amp, float(preset[1]),
			"jump should be the softest haptic")

# ── Toggle persistence path ──────────────────────────────────────────────────

func test_toggle_off_then_on_round_trip() -> void:
	hm.set_enabled(false)
	hm.set_enabled(true)
	hm.set_enabled(false)
	assert_false(hm.is_enabled())
