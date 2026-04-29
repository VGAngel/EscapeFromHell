extends GutTest

# Tests for MotionSettings — the reduce-motion preference broadcaster.
# Covers: signal emission, no-op on same value, and that subscribers
# get the right boolean.

const MotionScript := preload("res://scripts/managers/MotionSettings.gd")
const MenuAmbientScript := preload("res://scripts/ui/MenuAmbient.gd")
const SinVignetteScript := preload("res://scripts/ui/SinVignette.gd")

var ms: Node

func before_each() -> void:
	ms = MotionScript.new()
	add_child_autofree(ms)

# ── Public API ────────────────────────────────────────────────────────────────

func test_default_is_disabled() -> void:
	assert_false(ms.is_enabled())

func test_set_enabled_emits_changed_with_value() -> void:
	watch_signals(ms)
	ms.set_enabled(true)
	assert_signal_emitted_with_parameters(ms, "changed", [true])
	assert_true(ms.is_enabled())

func test_set_same_value_does_not_emit() -> void:
	# Already false by default — flipping to false again should be a no-op.
	watch_signals(ms)
	ms.set_enabled(false)
	assert_signal_not_emitted(ms, "changed")

func test_round_trip_emits_each_flip() -> void:
	watch_signals(ms)
	ms.set_enabled(true)
	ms.set_enabled(false)
	# Two emissions total — one per actual flip.
	assert_signal_emit_count(ms, "changed", 2)

# ── Subscribers ───────────────────────────────────────────────────────────────

func test_menu_ambient_subscribes_and_freezes_emitters() -> void:
	# Build an ambient layer, then flip the toggle and verify particles stop.
	var root := Control.new()
	root.size = Vector2(1080, 1920)
	add_child_autofree(root)
	var amb: Node = MenuAmbientScript.new()
	root.add_child(amb)
	amb.setup(root, null)
	# Look up the live MotionSettings autoload (root /root/MotionSettings).
	var live_ms: Node = get_node_or_null("/root/MotionSettings")
	if live_ms == null:
		pending("MotionSettings autoload not registered yet")
		return
	live_ms.set_enabled(true)
	var embers: CPUParticles2D = root.get_node("Embers")
	assert_false(embers.emitting,
			"embers must stop emitting under reduce_motion")
	live_ms.set_enabled(false)   # restore so other tests aren't affected
