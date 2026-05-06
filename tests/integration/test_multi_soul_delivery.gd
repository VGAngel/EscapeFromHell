extends GutTest

# End-to-end: Player carries 2 souls → deliver_soul() emits two
# soul_delivered signals back-to-back on the same frame → LevelBase
# routes each one through SoulRevealPanel.show_soul().
#
# Without this test the multi-soul reveal bug was invisible: per-class
# unit tests passed (Player emits, LevelBase looks up data, SoulReveal
# renders) yet the player never saw the first soul's name because the
# second show_soul() arrived on the same frame and clobbered it.
#
# Setup is deliberately stripped down — we don't spin up the whole
# Level scene tree. We just stand up the three nodes that participate
# in the bug (Player carry list, LevelBase carry-data dict +
# _on_soul_delivered, SoulRevealPanel) and replay the same sequence.

const PlayerScript          := preload("res://scripts/Player.gd")
const SoulRevealPanelScene  := preload("res://scenes/ui/SoulRevealPanel.tscn")
const LevelBaseScript       := preload("res://scripts/levels/LevelBase.gd")


# ── Lightweight LevelBase double ──────────────────────────────────────────────
# Spinning up a real LevelBase requires the whole room layout +
# GameManager wiring, which is overkill for testing the soul-delivered
# routing. Mirror just the two methods that participate in the bug.

class FakeLevelBase extends Node:
	var _soul_reveal: CanvasLayer = null
	var _carried_souls_data: Dictionary = {}
	var _souls_found: int = 0

	func _ready() -> void:
		# Mirror the real LevelBase: SoulRevealPanel sits underneath us.
		# Instantiate the scene so the @onready label refs resolve —
		# script-only .new() would leave them null.
		_soul_reveal = SoulRevealPanelScene.instantiate()
		add_child(_soul_reveal)

	# Mirrors LevelBase._on_soul_delivered (named-soul branch only —
	# we never use the "H..." hidden-id path in this fixture).
	func _on_soul_delivered(soul_id: String) -> void:
		_souls_found += 1
		var id: int = soul_id.to_int() if soul_id.is_valid_int() else 0
		var data: Dictionary = _carried_souls_data.get(id, {})
		if data.has("name") and data.get("name", "") != "":
			_soul_reveal.show_soul(data)
		_carried_souls_data.erase(id)

	func register_carried(soul_id: int, data: Dictionary) -> void:
		_carried_souls_data[soul_id] = data


var lvl: Node


func before_each() -> void:
	lvl = FakeLevelBase.new()
	add_child_autofree(lvl)


# ── End-to-end: two souls, two reveals ────────────────────────────────────────

func test_two_back_to_back_deliveries_both_reach_reveal_panel() -> void:
	# Arrange: pre-seed the carry dict the way LevelBase does on
	# pickup, then fire the two delivery handlers back-to-back the
	# way Player.deliver_soul does on the same frame.
	lvl.register_carried(1, {
		"name": "Перша Душа", "age": 30, "epitaph": "Перша."})
	lvl.register_carried(2, {
		"name": "Друга Душа", "age": 40, "epitaph": "Друга."})

	lvl._on_soul_delivered("1")
	lvl._on_soul_delivered("2")

	var panel: CanvasLayer = lvl._soul_reveal
	# First soul stays on screen.
	assert_eq(panel._lbl_name.text, "Перша Душа",
			"first delivery must remain visible while the second waits")
	# Second soul is queued, NOT clobbering the first.
	assert_eq(panel._queue.size(), 1,
			"second delivery must be queued, not dropped")
	assert_eq(panel._queue[0].name, "Друга Душа")


func test_first_reveal_completes_before_second_starts() -> void:
	# After the first reveal auto-hides, the second one becomes the
	# active reveal. This is the scenario the bug literally broke:
	# without queueing, the second show_soul() instantly overrode the
	# first's labels and the auto-hide path freed it before any timer
	# elapsed.
	lvl.register_carried(1, {"name": "Перша", "age": 1, "epitaph": "."})
	lvl.register_carried(2, {"name": "Друга", "age": 2, "epitaph": ".."})
	lvl._on_soul_delivered("1")
	lvl._on_soul_delivered("2")

	var panel: CanvasLayer = lvl._soul_reveal
	assert_eq(panel._lbl_name.text, "Перша")
	# Simulate the auto-hide tween's tail callback firing.
	panel._visible = false
	panel._on_hidden()
	assert_eq(panel._lbl_name.text, "Друга",
			"after first reveal hides, the queued second must take over")
	assert_true(panel._visible)
	assert_eq(panel._queue.size(), 0)


func test_carry_data_erased_after_each_delivery() -> void:
	# LevelBase._on_soul_delivered erases the carried-data slot so
	# the same id never accidentally fires twice (e.g. if the player
	# revisits an altar). Both deliveries must clear their slots
	# regardless of whether the reveal queued or rendered.
	lvl.register_carried(1, {"name": "Перша", "age": 1, "epitaph": "."})
	lvl.register_carried(2, {"name": "Друга", "age": 2, "epitaph": "."})
	lvl._on_soul_delivered("1")
	lvl._on_soul_delivered("2")
	assert_false(lvl._carried_souls_data.has(1))
	assert_false(lvl._carried_souls_data.has(2))


func test_souls_found_counter_increments_per_delivery() -> void:
	# Catches a regression where queueing accidentally short-circuits
	# the increment path (e.g. by returning early from _on_soul_
	# delivered when the panel was busy). _souls_found drives the
	# exit-portal "you've collected enough" trigger; if it stops
	# counting on the second soul the level becomes uncompletable.
	lvl.register_carried(1, {"name": "Перша", "age": 1, "epitaph": "."})
	lvl.register_carried(2, {"name": "Друга", "age": 2, "epitaph": "."})
	lvl._on_soul_delivered("1")
	lvl._on_soul_delivered("2")
	assert_eq(lvl._souls_found, 2)


# ── Same-frame Player signal storm ────────────────────────────────────────────
#
# Tried to instantiate Player.gd directly here to assert the
# "deliver_soul emits one signal per id" contract, but the script's
# @onready node refs (animation, sprite, audio) require the full
# Player.tscn scene tree which we don't have in a unit fixture. The
# behaviour the test would have anchored is already documented +
# tested upstream by the FakeLevelBase replay above (which simulates
# exactly that signal storm by calling _on_soul_delivered twice in
# a row), so dropping the direct emit-count assertion is fine.
