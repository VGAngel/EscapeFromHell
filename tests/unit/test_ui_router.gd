extends GutTest

# Tests for UIRouter — the centralised modal-overlay stack.
# We use a fake overlay (CanvasLayer with `signal closed`, open() and
# close()) so the test stays decoupled from any real screen.

const RouterScript := preload("res://scripts/managers/UIRouter.gd")

# ── Fake overlay ──────────────────────────────────────────────────────────────

class FakeScreen extends CanvasLayer:
	signal closed
	var open_calls: int = 0
	var close_calls: int = 0

	func open() -> void:
		open_calls += 1
		visible = true

	func close() -> void:
		close_calls += 1
		visible = false
		closed.emit()


var router: Node

func before_each() -> void:
	router = RouterScript.new()
	add_child_autofree(router)

func _make_screen() -> FakeScreen:
	var s := FakeScreen.new()
	add_child_autofree(s)
	return s

# ── Push ──────────────────────────────────────────────────────────────────────

func test_push_calls_open_and_increments_depth() -> void:
	var s := _make_screen()
	var pushed: bool = router.push(s)
	assert_true(pushed)
	assert_eq(s.open_calls, 1)
	assert_eq(router.depth(), 1)
	assert_eq(router.top(), s)
	assert_true(router.is_open())

func test_push_null_is_noop() -> void:
	var pushed: bool = router.push(null)
	assert_false(pushed)
	assert_eq(router.depth(), 0)

func test_push_already_in_stack_returns_false_and_reopens() -> void:
	var s := _make_screen()
	router.push(s)
	var second_push: bool = router.push(s)
	assert_false(second_push)
	# But open() should be re-called so the screen refreshes content.
	assert_eq(s.open_calls, 2)
	assert_eq(router.depth(), 1)

func test_push_multiple_screens_stacks_in_order() -> void:
	var a := _make_screen()
	var b := _make_screen()
	router.push(a)
	router.push(b)
	assert_eq(router.depth(), 2)
	assert_eq(router.top(), b)
	assert_true(router.contains(a))

# ── Pop ───────────────────────────────────────────────────────────────────────

func test_pop_calls_close_on_top() -> void:
	var s := _make_screen()
	router.push(s)
	var popped: bool = router.pop()
	assert_true(popped)
	assert_eq(s.close_calls, 1)
	# Stack drops to 0 once the close() emits `closed`.
	assert_eq(router.depth(), 0)
	assert_false(router.is_open())

func test_pop_when_empty_returns_false() -> void:
	assert_false(router.pop())

func test_pop_only_pops_topmost() -> void:
	var a := _make_screen()
	var b := _make_screen()
	router.push(a)
	router.push(b)
	router.pop()
	assert_eq(b.close_calls, 1)
	assert_eq(a.close_calls, 0, "lower screen should remain")
	assert_eq(router.top(), a)

# ── Pop all ───────────────────────────────────────────────────────────────────

func test_pop_all_closes_each_screen() -> void:
	var a := _make_screen()
	var b := _make_screen()
	var c := _make_screen()
	router.push(a)
	router.push(b)
	router.push(c)
	router.pop_all()
	assert_eq(a.close_calls, 1)
	assert_eq(b.close_calls, 1)
	assert_eq(c.close_calls, 1)
	assert_eq(router.depth(), 0)

# ── Closed signal sync ────────────────────────────────────────────────────────

func test_screen_self_closing_drops_from_stack() -> void:
	var s := _make_screen()
	router.push(s)
	# Simulate Esc/✕ — overlay handles it and emits `closed` itself.
	s.closed.emit()
	assert_eq(router.depth(), 0)
	assert_false(router.is_open())

func test_tree_exit_drops_from_stack() -> void:
	var s := _make_screen()
	router.push(s)
	# Simulate scene change / queue_free.
	remove_child(s)
	s.free()
	assert_eq(router.depth(), 0)

# ── Stack-changed signal ──────────────────────────────────────────────────────

func test_stack_changed_emits_with_depth() -> void:
	var s := _make_screen()
	watch_signals(router)
	router.push(s)
	assert_signal_emitted_with_parameters(router, "stack_changed", [1])
	router.pop()
	assert_signal_emitted_with_parameters(router, "stack_changed", [0])

# ── screen_pushed / screen_popped ─────────────────────────────────────────────

func test_pushed_and_popped_signals_fire() -> void:
	var s := _make_screen()
	watch_signals(router)
	router.push(s)
	assert_signal_emitted(router, "screen_pushed")
	router.pop()
	assert_signal_emitted(router, "screen_popped")
