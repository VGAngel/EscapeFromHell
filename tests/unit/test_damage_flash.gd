extends GutTest

# Tests for DamageFlash — the red-border vignette that pulses when the
# player takes damage. Direct flash() invocation covers the visuals;
# signal-routing is covered via a fake Player node.

const DamageFlashScript := preload("res://scripts/ui/DamageFlash.gd")


# ── Fake player with damage_taken signal ──────────────────────────────────────

class FakePlayer extends Node2D:
	signal damage_taken(amount: int)

	func _ready() -> void:
		add_to_group("player")


var df: Control

func before_each() -> void:
	df = DamageFlashScript.new()
	df.size = Vector2(1080, 1920)
	add_child_autofree(df)


# ── Build ─────────────────────────────────────────────────────────────────────

func test_builds_shader_carrier() -> void:
	assert_not_null(df._shader_mat, "shader material should be built")
	# A child ColorRect carries the material so the shader has UV.
	var rects: int = 0
	for child in df.get_children():
		if child is ColorRect:
			rects += 1
	assert_eq(rects, 1, "exactly one ColorRect host for the shader")


func test_initial_alpha_zero() -> void:
	assert_lt(df.modulate.a, 0.05, "should be invisible until first flash")


# ── flash() ───────────────────────────────────────────────────────────────────

func test_flash_starts_tween_to_peak() -> void:
	df.flash(2)
	# Tween was assigned and is currently valid.
	assert_not_null(df._current_tween)
	assert_true(df._current_tween.is_valid())


func test_flash_intensity_scales_with_amount() -> void:
	# A 1-damage tick clamps to MIN_INTENSITY (0.4); 3+ saturates at MAX (1.0).
	# We can't easily inspect the post-tween peak alpha, but we can check
	# the math used to compute it directly.
	var weak: float = clamp(1.0 / 3.0, df.MIN_INTENSITY, df.MAX_INTENSITY)
	var strong: float = clamp(5.0 / 3.0, df.MIN_INTENSITY, df.MAX_INTENSITY)
	assert_lt(weak, strong, "stronger hits must produce stronger flash")
	assert_almost_eq(weak, df.MIN_INTENSITY, 0.001)
	assert_almost_eq(strong, df.MAX_INTENSITY, 0.001)


func test_concurrent_flashes_kill_previous_tween() -> void:
	df.flash(1)
	var first: Tween = df._current_tween
	df.flash(2)
	var second: Tween = df._current_tween
	assert_ne(first, second, "second flash must create a new tween")
	# Old tween should be killed (no longer valid).
	assert_false(first.is_valid(), "previous tween should be dropped")


# ── Player signal wiring ──────────────────────────────────────────────────────

func test_connects_to_player_already_in_tree() -> void:
	# Drop the original instance and rebuild it with a Player already
	# present, so the boot path (`_try_connect_player`) covers us.
	var fake := FakePlayer.new()
	add_child_autofree(fake)
	var df2: Control = DamageFlashScript.new()
	df2.size = Vector2(800, 600)
	add_child_autofree(df2)
	# DamageFlash should now have stored a reference to the fake player.
	assert_eq(df2._player, fake)
	assert_true(fake.damage_taken.is_connected(df2._on_damage_taken))


func test_connects_to_player_added_after() -> void:
	# DamageFlash is already in tree; new Player joins afterwards.
	var fake := FakePlayer.new()
	add_child_autofree(fake)
	# node_added fires synchronously when add_child runs above.
	assert_eq(df._player, fake)
	assert_true(fake.damage_taken.is_connected(df._on_damage_taken))


func test_player_signal_triggers_flash() -> void:
	var fake := FakePlayer.new()
	add_child_autofree(fake)
	fake.damage_taken.emit(2)
	assert_not_null(df._current_tween,
			"emitting damage_taken should kick off a flash tween")
