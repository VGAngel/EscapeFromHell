extends GutTest

# Tests for SoulRevealPanel's queueing behaviour. Player.deliver_soul
# emits one soul_delivered signal per carried soul on the same frame
# (with the soul_echo upgrade you can deliver 2+ at once), so the
# panel has to render each one in turn — without the queue the second
# show_soul() instantly clobbered the first and the player only saw
# the last delivered name.

const SoulRevealPanelScene := preload("res://scenes/ui/SoulRevealPanel.tscn")

var panel: CanvasLayer

func before_each() -> void:
	# The panel's UI hierarchy lives in the .tscn (script @onready vars
	# point at named children), so the scene must be instantiated — a bare
	# `Script.new()` instance has no Backdrop/VBox children and show_soul
	# would crash writing to null labels.
	panel = SoulRevealPanelScene.instantiate()
	add_child_autofree(panel)


# ── Single show ───────────────────────────────────────────────────────────────

func test_show_soul_renders_name() -> void:
	panel.show_soul({"name": "Іван", "age": 47, "epitaph": "Tест."})
	assert_eq(panel._lbl_name.text, "Іван")
	assert_true(panel._visible)

func test_empty_name_is_ignored() -> void:
	panel.show_soul({"name": "", "age": 30, "epitaph": "..."})
	assert_false(panel._visible)

# ── Queue ─────────────────────────────────────────────────────────────────────

func test_second_show_while_visible_queues() -> void:
	panel.show_soul({"name": "Перша", "age": 30, "epitaph": "."})
	panel.show_soul({"name": "Друга", "age": 40, "epitaph": ".."})
	# First is still on screen; second waits in queue.
	assert_eq(panel._lbl_name.text, "Перша",
			"second show_soul must NOT override the first")
	assert_eq(panel._queue.size(), 1)
	assert_eq(panel._queue[0].name, "Друга")

func test_queue_pops_after_hide() -> void:
	panel.show_soul({"name": "Перша", "age": 30, "epitaph": "."})
	panel.show_soul({"name": "Друга", "age": 40, "epitaph": ".."})
	# Simulate the fade-out finishing: call _on_hidden directly so
	# we don't depend on tween timing in tests.
	panel._visible = false
	panel._on_hidden()
	assert_eq(panel._lbl_name.text, "Друга")
	assert_true(panel._visible)
	assert_eq(panel._queue.size(), 0)

func test_three_in_a_row_shows_each_in_order() -> void:
	panel.show_soul({"name": "Один",  "age": 10, "epitaph": "1"})
	panel.show_soul({"name": "Два",   "age": 20, "epitaph": "2"})
	panel.show_soul({"name": "Три",   "age": 30, "epitaph": "3"})
	# Now: showing "Один", queue = ["Два", "Три"]
	assert_eq(panel._lbl_name.text, "Один")
	assert_eq(panel._queue.size(), 2)
	# Play out the queue.
	panel._visible = false
	panel._on_hidden()
	assert_eq(panel._lbl_name.text, "Два")
	panel._visible = false
	panel._on_hidden()
	assert_eq(panel._lbl_name.text, "Три")
	# After the last reveal hides, queue is empty + panel goes invisible.
	panel._visible = false
	panel._on_hidden()
	assert_false(panel.visible)

func test_empty_queue_hide_makes_panel_invisible() -> void:
	panel.show_soul({"name": "Solo", "age": 5, "epitaph": "."})
	panel._visible = false
	panel._on_hidden()
	assert_false(panel.visible)
