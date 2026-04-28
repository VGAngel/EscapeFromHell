extends Node

# Centralised modal-overlay stack.
#
# Lets the rest of the codebase ask "is anything open?" / "close the
# topmost screen" without needing to know which overlay is on top.
# Provides a single signal (`stack_changed`) that the upcoming
# persistent TopBar (U10) and other observers can subscribe to.
#
# Design principle: do NOT take over input handling. Existing overlays
# already consume `ui_cancel` correctly per-instance (they check
# `visible` and call `set_input_as_handled`). Router only listens to
# the overlay's existing `closed` signal to keep the stack in sync.
#
# The one input the router DOES handle is the Android hardware-back
# request (`NOTIFICATION_WM_GO_BACK_REQUEST`), which Godot otherwise
# routes to `quit()` — not what you want when a settings overlay is up.
#
# Overlay contract (duck-typed — no formal interface):
#   • Has `signal closed`
#   • Has `func open()` and `func close()`
#   • Optional: `func router_title() -> String` (for TopBar header)
#
# Usage:
#   UIRouter.push(_settings)   # MainMenu replaces direct .open() call
#   UIRouter.pop()             # close topmost
#   UIRouter.pop_all()         # collapse everything (e.g. before scene change)

signal stack_changed(depth: int)
signal screen_pushed(screen: Node)
signal screen_popped(screen: Node)

var _stack: Array[Node] = []
# Track which screens we've already wired so reopening is idempotent.
var _wired: Dictionary = {}


# ── Public API ────────────────────────────────────────────────────────────────

# Push an overlay onto the stack and call its open(). If the screen is
# already in the stack it's a no-op (returns false). Returns true if a
# new entry was pushed.
func push(screen: Node) -> bool:
	if screen == null:
		return false
	if _stack.has(screen):
		# Already top? Just refresh by re-opening (handles re-entry from
		# different MainMenu buttons gracefully).
		if screen.has_method("open"):
			screen.open()
		return false
	_wire(screen)
	_stack.append(screen)
	if screen.has_method("open"):
		screen.open()
	screen_pushed.emit(screen)
	stack_changed.emit(_stack.size())
	return true


# Close the topmost screen. Returns true if something was popped.
func pop() -> bool:
	if _stack.is_empty():
		return false
	var top_screen: Node = _stack.back()
	# We don't remove from the stack here — the screen's `closed` signal
	# fires after its fade-out and our handler removes it cleanly.
	# This keeps depth correct during the fade animation.
	if top_screen.has_method("close"):
		top_screen.close()
	else:
		_remove(top_screen)
	return true


# Close everything in reverse order (top-most first). Useful before
# scene changes or when entering Pause from a deep stack.
func pop_all() -> void:
	# Iterate a copy because handlers may mutate _stack.
	for screen in _stack.duplicate():
		if is_instance_valid(screen) and screen.has_method("close"):
			screen.close()
		else:
			_remove(screen)


func top() -> Node:
	return _stack.back() if not _stack.is_empty() else null


func depth() -> int:
	return _stack.size()


func is_open() -> bool:
	return not _stack.is_empty()


func contains(screen: Node) -> bool:
	return _stack.has(screen)


# ── Wiring ────────────────────────────────────────────────────────────────────

func _wire(screen: Node) -> void:
	if _wired.has(screen):
		return
	_wired[screen] = true
	# Keep stack in sync with overlays that close themselves (Esc, ✕, etc.)
	if screen.has_signal("closed"):
		screen.closed.connect(_on_screen_closed.bind(screen))
	# Drop from stack if the overlay is freed (scene change, etc.)
	screen.tree_exiting.connect(_on_screen_tree_exiting.bind(screen))


func _on_screen_closed(screen: Node) -> void:
	_remove(screen)


func _on_screen_tree_exiting(screen: Node) -> void:
	_wired.erase(screen)
	_remove(screen)


# Internal — pull a screen out of the stack and emit signals. Safe to
# call when the screen isn't in the stack (no-op).
func _remove(screen: Node) -> void:
	var idx: int = _stack.find(screen)
	if idx < 0:
		return
	_stack.remove_at(idx)
	screen_popped.emit(screen)
	stack_changed.emit(_stack.size())


# ── Android hardware-back ─────────────────────────────────────────────────────

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not _stack.is_empty():
		pop()
		# Don't let Godot's default quit-on-back fire while an overlay is up.
		var tree := get_tree()
		if tree:
			tree.set_input_as_handled()
