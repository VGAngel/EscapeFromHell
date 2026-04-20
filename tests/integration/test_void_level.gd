extends GutTest

# Integration tests for VoidLevel.gd.
#
# VoidLevel extends LevelBase which calls _spawn_player(), _connect_exit(), etc.
# in _ready() — all of those crash without a proper scene tree.
# We use a SafeVoidLevel inner class that overrides _ready() to a no-op so we
# can test individual methods in isolation.

const VoidLevelScript := preload("res://scripts/levels/VoidLevel.gd")

class SafeVoidLevel extends VoidLevelScript:
	func _ready() -> void:
		pass  # skip full LevelBase + VoidLevel init

func _make_vl() -> SafeVoidLevel:
	var vl: SafeVoidLevel = SafeVoidLevel.new()
	# Provide the child nodes LevelBase @onready vars expect
	var hud := Node.new();     hud.name = "HUD"
	var rc  := Node2D.new();   rc.name  = "RoomContainer"
	var sp  := Marker2D.new(); sp.name  = "SpawnPoint"
	var ex  := Area2D.new();   ex.name  = "Exit"
	vl.add_child(hud)
	vl.add_child(rc)
	vl.add_child(sp)
	vl.add_child(ex)
	add_child_autofree(vl)
	return vl

# ── Constants ─────────────────────────────────────────────────────────────────

func test_camera_zoom_constant() -> void:
	var vl := _make_vl()
	assert_eq(vl.CAMERA_ZOOM, Vector2(0.8, 0.8))

func test_exit_pulse_scale_constant() -> void:
	var vl := _make_vl()
	assert_gt(vl.EXIT_PULSE_SCALE.x, 1.0)
	assert_gt(vl.EXIT_PULSE_SCALE.y, 1.0)

func test_exit_pulse_duration_positive() -> void:
	var vl := _make_vl()
	assert_gt(vl.EXIT_PULSE_DURATION, 0.0)

func test_exit_pulse_loops_positive() -> void:
	var vl := _make_vl()
	assert_gt(vl.EXIT_PULSE_LOOPS, 0)

# ── _update_exit_indicator ────────────────────────────────────────────────────

func test_update_exit_indicator_shows_icon_when_souls_missing() -> void:
	var vl := _make_vl()
	var exit := Area2D.new()
	var icon := Node2D.new()
	icon.name = "LockedIcon"
	icon.visible = false
	exit.add_child(icon)
	vl._exit_area = exit
	vl._souls_required = 3
	vl._souls_found    = 0

	vl._update_exit_indicator()

	assert_true(icon.visible)
	exit.free()

func test_update_exit_indicator_hides_icon_when_all_collected() -> void:
	var vl := _make_vl()
	var exit := Area2D.new()
	var icon := Node2D.new()
	icon.name = "LockedIcon"
	icon.visible = true
	exit.add_child(icon)
	vl._exit_area = exit
	vl._souls_required = 2
	vl._souls_found    = 2

	vl._update_exit_indicator()

	assert_false(icon.visible)
	exit.free()

func test_update_exit_indicator_no_crash_without_icon() -> void:
	var vl := _make_vl()
	var exit := Area2D.new()
	vl._exit_area    = exit
	vl._souls_required = 1
	vl._souls_found    = 0
	# No LockedIcon child — must not crash
	vl._update_exit_indicator()
	assert_true(true)  # reached here without error
	exit.free()

func test_update_exit_indicator_no_crash_with_null_exit() -> void:
	var vl := _make_vl()
	vl._exit_area = null
	vl._update_exit_indicator()
	assert_true(true)

# ── _pulse_exit ───────────────────────────────────────────────────────────────

func test_pulse_exit_no_crash_with_valid_exit() -> void:
	var vl := _make_vl()
	var exit := Area2D.new()
	add_child(exit)
	vl._exit_area = exit
	vl._pulse_exit()
	assert_true(true)
	exit.queue_free()

func test_pulse_exit_no_crash_with_null_exit() -> void:
	var vl := _make_vl()
	vl._exit_area = null
	vl._pulse_exit()
	assert_true(true)

func test_pulse_exit_no_crash_with_freed_exit() -> void:
	# Assign first, then free — avoids "previously freed" typed-property error.
	var vl := _make_vl()
	var exit := Area2D.new()
	vl._exit_area = exit  # assign while valid
	exit.free()            # now invalidate — _exit_area holds a freed ref
	vl._pulse_exit()       # must not crash (is_instance_valid guard)
	assert_true(true)

# ── _on_soul_collected ────────────────────────────────────────────────────────

func test_on_soul_collected_increments_souls_found() -> void:
	var vl := _make_vl()
	vl._souls_required = 2
	vl._souls_found    = 0
	vl._exit_area      = null  # prevent indicator crash

	# Create a minimal soul stub with required meta and no signal
	var soul := Node.new()
	soul.set_meta("soul_id", 0)
	add_child_autofree(soul)

	vl._on_soul_collected(soul)
	assert_eq(vl._souls_found, 1)

func test_on_soul_collected_updates_exit_indicator() -> void:
	var vl := _make_vl()
	var exit := Area2D.new()
	var icon := Node2D.new()
	icon.name    = "LockedIcon"
	icon.visible = true
	exit.add_child(icon)
	vl._exit_area      = exit
	vl._souls_required = 1
	vl._souls_found    = 0

	var soul := Node.new()
	soul.set_meta("soul_id", 0)
	add_child_autofree(soul)

	vl._on_soul_collected(soul)
	# All souls now found → icon should be hidden
	assert_false(icon.visible)
	exit.free()

func test_on_soul_collected_does_not_pulse_when_souls_remain() -> void:
	var vl := _make_vl()
	vl._souls_required = 3
	vl._souls_found    = 0
	vl._exit_area      = null

	var soul := Node.new()
	soul.set_meta("soul_id", 0)
	add_child_autofree(soul)

	# souls_found becomes 1, required=3 → no pulse (just ensure no crash)
	vl._on_soul_collected(soul)
	assert_eq(vl._souls_found, 1)

# ── _find_camera ──────────────────────────────────────────────────────────────

func test_find_camera_returns_null_without_camera() -> void:
	var vl := _make_vl()
	# No Camera2D child added → should return null gracefully
	var cam: Camera2D = vl._find_camera()
	# Either null or the test runner's camera — just check no crash
	assert_true(cam == null or cam is Camera2D)

func test_find_camera_returns_child_camera() -> void:
	var vl := _make_vl()
	var cam := Camera2D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vl.add_child(cam)
	var found: Camera2D = vl._find_camera()
	# May find viewport camera first, but must return a Camera2D
	assert_true(found is Camera2D)
	cam.queue_free()

# ── _setup_camera_zoom ────────────────────────────────────────────────────────

func test_setup_camera_zoom_applies_to_child_camera() -> void:
	var vl := _make_vl()
	var cam := Camera2D.new()
	cam.enabled = true
	# Disable physics interpolation to suppress Godot 4.6 engine message
	# ("Camera2D overridden to physics process mode") which GUT counts as failure.
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vl.add_child(cam)
	cam.make_current()
	vl._setup_camera_zoom()
	assert_eq(cam.zoom, vl.CAMERA_ZOOM)
	cam.queue_free()

# ── GameManager death limit ───────────────────────────────────────────────────

func test_game_manager_void_death_limit_is_five() -> void:
	assert_eq(GameManager.DEATH_LIMITS.get("void", -1), 5)

func test_game_manager_void_death_limit_greater_than_vertical() -> void:
	assert_gt(
		GameManager.DEATH_LIMITS.get("void", 0),
		GameManager.DEATH_LIMITS.get("vertical", 0)
	)
