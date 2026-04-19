extends Control

@onready var notice_label: Label = %NoticeLabel
@onready var fullscreen_btn: Button = $CenterContainer/VBoxContainer/FullscreenButton

func _ready() -> void:
	notice_label.text = ""
	_refresh_fullscreen_label()

func _apply_resolution(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	await get_tree().process_frame
	if DisplayServer.window_get_size() == win_size:
		var screen := DisplayServer.screen_get_size()
		DisplayServer.window_set_position(Vector2i(Vector2(screen - win_size) / 2.0))
		notice_label.add_theme_color_override("font_color", Color(0.4, 1, 0.4, 1))
		notice_label.text = "Applied: %d x %d" % [win_size.x, win_size.y]
	else:
		notice_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3, 1))
		notice_label.text = "Embedded mode: запусти гру окремим вікном\n(Editor Settings > Run > Window Placement)"

func _on_mobile_portrait_pressed() -> void:
	_apply_resolution(Vector2i(720, 1280))

func _on_mobile_fhd_pressed() -> void:
	_apply_resolution(Vector2i(1080, 1920))

func _on_pc_hd_pressed() -> void:
	_apply_resolution(Vector2i(1280, 720))

func _on_pc_fhd_pressed() -> void:
	_apply_resolution(Vector2i(1920, 1080))

func _on_fullscreen_pressed() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_refresh_fullscreen_label()

func _refresh_fullscreen_label() -> void:
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	fullscreen_btn.text = "Windowed" if is_fs else "Fullscreen"

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")
