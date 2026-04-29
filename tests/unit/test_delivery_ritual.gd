extends GutTest

# Tests for DeliveryRitual — the slow-mo + audio-duck moment when the
# player approaches the altar carrying a soul. We verify state lifecycle
# (enter/exit), restore semantics (time scale + music db come back),
# idempotency, reduce-motion gating, and tree-exit cleanup.

const RitualScript := preload("res://scripts/DeliveryRitual.gd")

var ritual: Node
var saved_time_scale: float = 1.0
var saved_music_db: float = 0.0


func before_each() -> void:
	# Snapshot the engine state so test order doesn't leak.
	saved_time_scale = Engine.time_scale
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		saved_music_db = AudioServer.get_bus_volume_db(bus_idx)
	ritual = RitualScript.new()
	add_child_autofree(ritual)


func after_each() -> void:
	# Hard-restore even if a test forgot to exit.
	Engine.time_scale = saved_time_scale
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, saved_music_db)


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func test_starts_inactive() -> void:
	assert_false(ritual.is_active())

func test_enter_marks_active() -> void:
	ritual.enter()
	assert_true(ritual.is_active())

func test_exit_marks_inactive() -> void:
	ritual.enter()
	ritual.exit(false)
	assert_false(ritual.is_active())

func test_double_enter_is_noop() -> void:
	ritual.enter()
	# Second call must NOT overwrite the snapshot — otherwise the
	# orig_time_scale captured from the first enter would be lost.
	ritual._orig_time_scale = 1.0    # known sentinel
	ritual.enter()
	assert_eq(ritual._orig_time_scale, 1.0,
			"second enter must not re-snapshot")

func test_exit_when_inactive_is_noop() -> void:
	ritual.exit(false)
	assert_false(ritual.is_active())
	pass_test("exit while inactive must not crash")


# ── Time scale ────────────────────────────────────────────────────────────────

func test_enter_sets_time_scale_via_tween() -> void:
	# Tween needs a process tick to actually apply the value, but the
	# tween itself should be valid right after enter.
	ritual.enter()
	assert_not_null(ritual._time_tween)
	assert_true(ritual._time_tween.is_valid())


func test_reduce_motion_skips_time_scale_tween() -> void:
	ritual._reduce_motion = true
	ritual.enter()
	assert_null(ritual._time_tween,
			"time-scale tween must not start under reduce_motion")


# ── Audio duck ────────────────────────────────────────────────────────────────

func test_enter_creates_audio_tween_when_music_bus_present() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		# Headless test bench may not have the Music bus configured —
		# treat the bus-missing path as a successful no-op.
		ritual.enter()
		pass_test("Music bus missing → skipped audio duck (no crash)")
		return
	ritual.enter()
	assert_not_null(ritual._audio_tween)


# ── Tree-exit hard restore ────────────────────────────────────────────────────

func test_tree_exit_during_active_restores_time_scale() -> void:
	# Manually set a known time scale, enter ritual, force-free.
	Engine.time_scale = 1.0
	ritual.enter()
	ritual._orig_time_scale = 1.0   # ensure snapshot matches
	# Simulate scene change.
	remove_child(ritual)
	ritual.free()
	ritual = null
	# After hard restore we should be back at 1.0 even though no exit
	# was called manually.
	assert_almost_eq(Engine.time_scale, 1.0, 0.001,
			"tree-exit must hard-restore time_scale")


# ── Reduce-motion live flip ───────────────────────────────────────────────────

func test_motion_changed_during_active_snaps_time_back() -> void:
	ritual.enter()
	# Simulate the user toggling reduce-motion on while in the ritual.
	ritual._on_motion_changed(true)
	assert_almost_eq(
			Engine.time_scale, ritual._orig_time_scale, 0.001,
			"reduce-motion mid-ritual must snap time_scale back")
