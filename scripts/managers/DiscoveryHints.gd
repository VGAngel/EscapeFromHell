extends Node

# Proximity-triggered tutorial hints with visual highlight.
#
# Any discoverable in-world node (bonus pickup, hidden soul, faith
# platform, mimic, …) calls DiscoveryHints.register(self, type_key,
# hint_id, radius) on _ready. While the node is alive we poll the
# distance from the player every POLL_S. The first time a NEW type
# (one not yet seen by TutorialManager) comes within `radius` of
# the player:
#
#   1. TutorialManager.show_hint(hint_id) renders the explanation
#      at the top of the screen (existing pipeline).
#   2. DiscoveryHighlight is attached to the node — a pulsing gold
#      halo that draws the eye to the actual object the hint is
#      talking about. Auto-frees after HIGHLIGHT_DURATION.
#   3. The type is marked seen via TutorialManager so no re-trigger
#      ever fires again on this save.
#
# Subsequent items of the same type don't trigger anything — the
# player already knows what a Manna is.
#
# Cheap by design: poll-only-when-pending list non-empty, registry
# auto-prunes on tree_exiting, no per-frame work when the player has
# already discovered everything in the level.

signal discovered(type_key: String)

const POLL_S := 0.25
const DEFAULT_RADIUS := 150.0
const HIGHLIGHT_DURATION := 6.0


# Pending entry: { node: Node2D, type_key: String, hint_id: String,
#                  radius: float, radius_sq: float, fired: bool }
var _pending: Array[Dictionary] = []
var _poll_t: float = 0.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _pending.is_empty():
		return
	_poll_t += delta
	if _poll_t < POLL_S:
		return
	_poll_t = 0.0
	_check_proximity()


# ── Public API ────────────────────────────────────────────────────────────────

# Register a discoverable. Idempotent — re-registering the same node is
# a no-op. The radius defaults to 150 px (matches user's spec).
func register(node: Node2D, type_key: String, hint_id: String,
		radius: float = DEFAULT_RADIUS) -> void:
	if node == null or not is_instance_valid(node):
		return
	# Skip if the type was already discovered — saves polling work and
	# avoids an immediate re-fire on revisited levels.
	if is_seen(type_key):
		return
	# Skip if THIS specific node is already pending.
	for entry in _pending:
		if entry.node == node:
			return
	var registered: Dictionary = {
		"node": node,
		"type_key": type_key,
		"hint_id": hint_id,
		"radius": radius,
		"radius_sq": radius * radius,
		"fired": false,
	}
	_pending.append(registered)
	# Auto-cleanup when the node leaves the tree (picked up, level
	# unloaded, etc.). Bind the entry directly so we drop the right
	# row even if the array order shuffles.
	node.tree_exiting.connect(_on_node_freed.bind(registered))


# True if the type's hint was already shown on this save. Reads through
# TutorialManager so we share the same persistence as regular hints.
func is_seen(type_key: String) -> bool:
	var tm: Node = get_node_or_null("/root/TutorialManager")
	if tm == null:
		return false
	# Discovery types are stored under the same `seen_tutorial_hints`
	# bucket so the "show only once" guarantee covers both code paths.
	if tm.has_method("is_hint_seen"):
		return bool(tm.is_hint_seen("discovery." + type_key))
	return false


# Force-mark a type as already seen (e.g. for testing or skip flow).
func mark_seen(type_key: String) -> void:
	var tm: Node = get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("_mark_seen"):
		tm._mark_seen("discovery." + type_key)


func clear() -> void:
	_pending.clear()


# ── Internal ──────────────────────────────────────────────────────────────────

func _check_proximity() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	var p_pos: Vector2 = (player as Node2D).global_position
	# Iterate a snapshot so handlers can mutate _pending safely.
	for entry in _pending.duplicate():
		var node: Node2D = entry.node
		if node == null or not is_instance_valid(node):
			_pending.erase(entry)
			continue
		if entry.fired:
			continue
		var d_sq: float = node.global_position.distance_squared_to(p_pos)
		if d_sq <= entry.radius_sq:
			_fire(entry)


func _fire(entry: Dictionary) -> void:
	entry.fired = true
	var type_key: String = String(entry.type_key)
	# Mark first so concurrent registrations of the same type don't
	# double-fire (e.g. two MANNA pickups in the same room).
	mark_seen(type_key)
	# Show the tutorial hint if it has an id.
	var hint_id: String = String(entry.hint_id)
	var tm: Node = get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("show_hint") and not hint_id.is_empty():
		tm.show_hint(hint_id)
	# Attach the gold halo to the node so the player can see WHICH
	# object the hint refers to. Self-frees after HIGHLIGHT_DURATION.
	_attach_highlight(entry.node)
	# Drop everything else of the same type from the pending list —
	# we already explained it, no need to re-check the others.
	for other in _pending.duplicate():
		if other != entry and String(other.type_key) == type_key:
			_pending.erase(other)
	_pending.erase(entry)
	discovered.emit(type_key)


func _attach_highlight(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var hl_script: GDScript = preload("res://scripts/ui/DiscoveryHighlight.gd")
	var hl: Node2D = hl_script.new()
	hl.lifetime = HIGHLIGHT_DURATION
	node.add_child(hl)


func _on_node_freed(entry: Dictionary) -> void:
	_pending.erase(entry)
