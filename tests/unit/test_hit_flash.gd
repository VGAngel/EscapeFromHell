extends GutTest

# Unit tests for HitFlash — the black edge-vignette overlay fired when
# the player's staff connects with an enemy.
#
# Mirrors the test pattern used by DamageFlash: instantiate the widget
# directly, drive flash() with both the default and was_last branches,
# and assert visible alpha changes through the tween.

var hf: Control


func before_each() -> void:
	hf = autofree(preload("res://scripts/ui/HitFlash.gd").new())
	add_child(hf)
	# Tween needs at least one frame to take effect after _ready.
	await get_tree().process_frame


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func test_initial_alpha_is_zero() -> void:
	assert_eq(hf.modulate.a, 0.0,
		"HitFlash should start fully transparent")


func test_anchors_full_rect_after_ready() -> void:
	# Edge ring uses screen UV coordinates; the carrier ColorRect must
	# fill the screen for the vignette to land on the actual edges.
	assert_eq(hf.anchor_right,  1.0)
	assert_eq(hf.anchor_bottom, 1.0)


func test_mouse_filter_is_ignore() -> void:
	# Critical: taps must pass through to gameplay even during a flash.
	assert_eq(hf.mouse_filter, Control.MOUSE_FILTER_IGNORE)


# ── flash() ───────────────────────────────────────────────────────────────────

func test_flash_brings_alpha_above_zero() -> void:
	hf.flash(false)
	# Tween peak completes after PEAK_TIME (0.04s). Wait a couple of
	# frames at typical 60fps to let it settle.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(hf.modulate.a, 0.0,
		"flash() should raise modulate.a above zero during the peak phase")


func test_flash_was_last_uses_higher_alpha_than_default() -> void:
	# Both calls should peak ABOVE zero, but was_last=true should peak
	# higher (LAST_ENEMY_BOOST adds to MAX_ALPHA). We sample shortly
	# into the tween then compare.
	hf.flash(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var peak_default: float = hf.modulate.a

	# Reset and try the boosted variant.
	hf.modulate.a = 0.0
	hf.flash(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var peak_boosted: float = hf.modulate.a

	assert_gt(peak_boosted, peak_default,
		"was_last=true should produce a thicker pulse")
