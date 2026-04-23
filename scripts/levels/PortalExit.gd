class_name PortalExit
extends Node2D

## Portal vortex at the bottom of each level.
## Inactive (dark, slow spin, physics blocker) until activate() is called.
## On activation: glows gold-white, spins up, blocker removed.
## Emits player_entered when an active portal detects the player.

signal player_entered

const RADIUS_OUTER := 72.0
const RADIUS_MID   := 52.0
const RADIUS_INNER := 30.0

var _is_active:  bool  = false
var _activation: float = 0.0   # 0 = fully inactive … 1 = fully active
var _spin_speed: float = 0.35  # rad/s; tweened up on activation
var _pulse:      float = 0.0   # drives inner pulsing when active

var _area:    Area2D       = null
var _blocker: StaticBody2D = null

# ── Init ───────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_area()
	_build_blocker()

func _build_area() -> void:
	_area = Area2D.new()
	_area.name            = "Area2D"
	_area.collision_layer = 0
	_area.collision_mask  = 1
	_area.monitoring      = true
	_area.monitorable     = false
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = RADIUS_OUTER + 8.0
	col.shape = shape
	_area.add_child(col)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)

func _build_blocker() -> void:
	_blocker = StaticBody2D.new()
	_blocker.name            = "Blocker"
	_blocker.collision_layer = 1
	_blocker.collision_mask  = 0
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	# Wide flat wall sealing the funnel mouth.
	shape.size = Vector2(RADIUS_OUTER * 2.0 + 40.0, 24.0)
	col.shape = shape
	_blocker.add_child(col)
	add_child(_blocker)

# ── Loop ───────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	rotation += _spin_speed * delta
	if _is_active:
		_pulse = fmod(_pulse + delta * 2.5, TAU)
	queue_redraw()

# ── Drawing ────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var t := _activation

	# ── Palette (inactive = dark purple → active = gold-white) ──────────────
	var c_outer := Color(0.30 + 0.60 * t,  0.0  + 0.80 * t,  0.50 + 0.30 * t,
						  0.25 + 0.55 * t)
	var c_mid   := Color(0.15 + 0.80 * t,  0.0  + 0.85 * t,  0.40 + 0.40 * t,
						  0.35 + 0.45 * t)
	var c_inner := Color(0.05 + 0.95 * t,  0.0  + 0.90 * t,  0.20 + 0.50 * t,
						  0.55 + 0.35 * t)
	var c_arms  := Color(0.50 * t,          0.80 * t,          0.30 + 0.50 * t,
						  0.15 + 0.55 * t)
	var c_glow  := Color(1.0, 0.92, 0.45, 0.12 * t * (1.0 + 0.3 * sin(_pulse)))

	# ── Outer halo (active only) ─────────────────────────────────────────────
	if t > 0.05:
		draw_circle(Vector2.ZERO, RADIUS_OUTER + 16.0, c_glow)

	# ── Broken outer ring — gap creates natural swirl feel via rotation ──────
	draw_arc(Vector2.ZERO, RADIUS_OUTER, 0.0,         TAU * 0.68, 52, c_outer, 7.0)
	draw_arc(Vector2.ZERO, RADIUS_OUTER, TAU * 0.72,  TAU * 0.94, 22, c_outer, 4.5)

	# ── Mid ring ─────────────────────────────────────────────────────────────
	draw_arc(Vector2.ZERO, RADIUS_MID,   TAU * 0.04,  TAU * 0.76, 40, c_mid,   5.5)
	draw_arc(Vector2.ZERO, RADIUS_MID,   TAU * 0.80,  TAU * 0.97, 14, c_mid,   3.0)

	# ── Inner filled circle (pulsing when active) ────────────────────────────
	var pulse_r := RADIUS_INNER * (1.0 + 0.08 * sin(_pulse) * t)
	draw_circle(Vector2.ZERO, pulse_r, c_inner)

	# ── Three swirl arms (blades) ────────────────────────────────────────────
	for i in 3:
		var angle := float(i) * TAU / 3.0
		var p1 := Vector2(cos(angle), sin(angle)) * 7.0
		var p2 := Vector2(cos(angle + 1.15), sin(angle + 1.15)) * (RADIUS_OUTER * 0.82)
		var ca  := c_arms
		ca.a   *= 0.75
		draw_line(p1, p2, ca, 3.5)

# ── Activation ─────────────────────────────────────────────────────────────────

func activate() -> void:
	if _is_active:
		return
	_is_active = true

	if is_instance_valid(_blocker):
		_blocker.queue_free()
		_blocker = null

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "_activation", 1.0, 1.4).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_spin_speed", 2.2, 1.8).set_ease(Tween.EASE_IN_OUT)

# ── Area callback ───────────────────────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if _is_active and body.is_in_group("player"):
		player_entered.emit()
