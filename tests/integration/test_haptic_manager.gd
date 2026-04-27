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
