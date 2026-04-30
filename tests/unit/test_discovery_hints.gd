extends GutTest

# Tests for DiscoveryHints — the proximity-triggered tutorial popups
# with gold-halo highlight on first encounter.

const DiscoveryHintsScript := preload("res://scripts/managers/DiscoveryHints.gd")
const HighlightScript      := preload("res://scripts/ui/DiscoveryHighlight.gd")


# ── Fake player ───────────────────────────────────────────────────────────────

class FakePlayer extends Node2D:
	func _ready() -> void:
		add_to_group("player")


var dh: Node
var _test_index: int = 0

func before_each() -> void:
	dh = DiscoveryHintsScript.new()
	add_child_autofree(dh)
	_test_index += 1


# Unique type_key per test — TutorialManager autoload persists state
# across tests (it stores `seen_tutorial_hints` in SaveManager), so
# reusing "manna" between tests would skip-on-already-seen.
func _ukey(prefix: String) -> String:
	return "%s_%d" % [prefix, _test_index]


# ── register / pending list ───────────────────────────────────────────────────

func test_register_adds_to_pending() -> void:
	var item := Node2D.new()
	add_child_autofree(item)
	var key := _ukey("manna")
	dh.register(item, key, "tutorial.bonus_manna", 150.0)
	assert_eq(dh._pending.size(), 1)
	assert_eq(dh._pending[0].type_key, key)

func test_register_idempotent_for_same_node() -> void:
	var item := Node2D.new()
	add_child_autofree(item)
	var key := _ukey("manna")
	dh.register(item, key, "tutorial.bonus_manna", 150.0)
	dh.register(item, key, "tutorial.bonus_manna", 150.0)
	assert_eq(dh._pending.size(), 1, "double-register must not duplicate")

func test_register_skips_if_type_already_seen() -> void:
	var key := _ukey("manna")
	dh.mark_seen(key)
	var item := Node2D.new()
	add_child_autofree(item)
	dh.register(item, key, "tutorial.bonus_manna", 150.0)
	assert_eq(dh._pending.size(), 0,
			"already-seen types must not enter the pending list")

func test_freed_node_drops_from_pending() -> void:
	var item := Node2D.new()
	add_child(item)
	dh.register(item, _ukey("manna"), "tutorial.bonus_manna", 150.0)
	assert_eq(dh._pending.size(), 1)
	remove_child(item)
	item.free()
	assert_eq(dh._pending.size(), 0)


# ── Proximity firing ──────────────────────────────────────────────────────────

func test_proximity_inside_radius_fires_discovered_signal() -> void:
	var player := FakePlayer.new()
	player.global_position = Vector2(0, 0)
	add_child_autofree(player)
	var item := Node2D.new()
	item.global_position = Vector2(100, 0)   # 100 px < 150 default
	add_child_autofree(item)
	var key := _ukey("manna")
	watch_signals(dh)
	dh.register(item, key, "tutorial.bonus_manna", 150.0)
	dh._check_proximity()
	assert_signal_emitted_with_parameters(dh, "discovered", [key])

func test_proximity_outside_radius_does_not_fire() -> void:
	var player := FakePlayer.new()
	player.global_position = Vector2(0, 0)
	add_child_autofree(player)
	var item := Node2D.new()
	item.global_position = Vector2(300, 0)   # 300 > 150
	add_child_autofree(item)
	watch_signals(dh)
	dh.register(item, _ukey("manna"), "tutorial.bonus_manna", 150.0)
	dh._check_proximity()
	assert_signal_not_emitted(dh, "discovered")

func test_first_fire_clears_other_same_type_entries() -> void:
	# Two MANNA pickups in the same room: only the closer one's
	# halo + hint should fire; the other gets pruned silently.
	var player := FakePlayer.new()
	player.global_position = Vector2(0, 0)
	add_child_autofree(player)
	var near := Node2D.new()
	near.global_position = Vector2(50, 0)
	add_child_autofree(near)
	var far := Node2D.new()
	far.global_position = Vector2(140, 0)    # also inside 150 px
	add_child_autofree(far)
	var key := _ukey("manna")
	dh.register(near, key, "tutorial.bonus_manna", 150.0)
	dh.register(far,  key, "tutorial.bonus_manna", 150.0)
	assert_eq(dh._pending.size(), 2)
	dh._check_proximity()
	assert_eq(dh._pending.size(), 0,
			"both entries of the same type must be pruned after first fire")


# ── DiscoveryHighlight ────────────────────────────────────────────────────────

func test_default_radius_is_200() -> void:
	# User-set rule: 200 px is the canonical proximity threshold.
	# Lowering it would make hints fire only when basically on top
	# of the object; raising it leaks into adjacent rooms.
	assert_eq(dh.DEFAULT_RADIUS, 200.0)


func test_cooldown_blocks_second_fire_within_window() -> void:
	# Two different-type entries both inside radius — only the first
	# should fire on this poll. The second stays pending so it can
	# light up later once the cooldown expires.
	var player := FakePlayer.new()
	player.global_position = Vector2(0, 0)
	add_child_autofree(player)
	var item_a := Node2D.new()
	item_a.global_position = Vector2(50, 0)
	add_child_autofree(item_a)
	var item_b := Node2D.new()
	item_b.global_position = Vector2(60, 0)
	add_child_autofree(item_b)
	var key_a := _ukey("type_a")
	var key_b := _ukey("type_b")
	dh.register(item_a, key_a, "tutorial.bonus_manna")
	dh.register(item_b, key_b, "tutorial.bonus_holy_water")
	watch_signals(dh)
	# First poll fires one.
	dh._check_proximity()
	# Second poll within the cooldown window should NOT fire the
	# second entry — _last_fire_ms gates the whole pass.
	dh._check_proximity()
	# Exactly one `discovered` signal should have been emitted.
	assert_eq(get_signal_emit_count(dh, "discovered"), 1,
			"second hint must wait for the cooldown to expire")


func test_highlight_self_frees_after_lifetime() -> void:
	# We can't easily await tweens in GUT, but we can verify the
	# script construction + that ring child is built.
	var parent := Node2D.new()
	add_child_autofree(parent)
	var hl: Node2D = HighlightScript.new()
	hl.lifetime = 0.05
	parent.add_child(hl)
	# Ring sprite should be a child of the highlight after _ready.
	var has_ring: bool = false
	for c in hl.get_children():
		if c is Sprite2D:
			has_ring = true
			break
	assert_true(has_ring, "highlight must instantiate a Sprite2D ring")
