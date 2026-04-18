extends Node2D

@onready var _player1: CharacterBody2D = $Player1
@onready var _camera: Camera2D = $Camera2D
@onready var _exit_portal: Area2D = $ExitPortal
@onready var _status_label: Label = $UI/StatusLabel

var _has_soul: bool = false

func _ready() -> void:
	_camera.limit_top = -200
	_camera.limit_bottom = 3150
	_camera.limit_left = 0
	_camera.limit_right = 720
	_exit_portal.monitoring = false
	GameManager.soul_collected.connect(_on_soul_collected)

func _process(_delta: float) -> void:
	_camera.global_position = _camera.global_position.lerp(_player1.global_position, 0.08)

func _on_soul_collected(_total: int) -> void:
	_has_soul = true
	_exit_portal.monitoring = true
	_status_label.text = "Душу врятовано! Повертайтесь до виходу! ↑"
	_status_label.add_theme_color_override("font_color", Color.GOLD)

func _on_exit_portal_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and _has_soul:
		get_tree().change_scene_to_file("res://MainMenu.tscn")
