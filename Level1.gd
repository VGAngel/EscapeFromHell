extends Node2D

@onready var _player1:      CharacterBody2D = $Player1
@onready var _camera:       Camera2D        = $Camera2D
@onready var _exit_portal:  Area2D          = $ExitPortal
@onready var _status_label: Label           = $UI/StatusLabel
@onready var _bonus_label:  Label           = $UI/BonusLabel
@onready var _dark_rect:    ColorRect       = $DarkOverlay/DarkRect
@onready var _heart1: Label = $UI/Hearts/Heart1
@onready var _heart2: Label = $UI/Hearts/Heart2
@onready var _heart3: Label = $UI/Hearts/Heart3

var _has_soul: bool = false

func _ready() -> void:
	_camera.limit_top    = -200
	_camera.limit_bottom = 3150
	_camera.limit_left   = 0
	_camera.limit_right  = 720
	_exit_portal.monitoring = false
	GameManager.soul_collected.connect(_on_soul_collected)
	_player1.life_lost.connect(_on_life_lost)
	_player1.all_lives_lost.connect(_on_all_lives_lost)
	_player1.heart_restored.connect(_on_heart_restored)
	for bonus in get_tree().get_nodes_in_group("bonus"):
		bonus.bonus_collected.connect(_on_bonus_collected)

func _process(_delta: float) -> void:
	_camera.global_position = _camera.global_position.lerp(_player1.global_position, 0.08)
	if not _player1.is_dead and _player1.global_position.y > 2990.0:
		_player1.die()

func _on_soul_collected(_total: int) -> void:
	_has_soul = true
	_exit_portal.monitoring = true
	_status_label.text = "Душу врятовано! Повертайтесь до виходу! ↑"
	_status_label.add_theme_color_override("font_color", Color.GOLD)

func _on_exit_portal_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and _has_soul:
		get_tree().change_scene_to_file.call_deferred("res://MainMenu.tscn")

func _refresh_hearts() -> void:
	var hearts := [_heart1, _heart2, _heart3]
	for i in range(3):
		hearts[i].modulate = Color.WHITE if i < _player1.lives else Color(0.2, 0.2, 0.2, 1.0)

func _on_life_lost(_remaining: int) -> void:
	_refresh_hearts()

func _on_heart_restored(_current: int) -> void:
	_refresh_hearts()

func _on_all_lives_lost() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func _on_bonus_collected(type: int, bonus_name: String) -> void:
	if type == 4:  # TORCH
		_dark_rect.hide()
	else:
		_player1.apply_bonus(type)
	_show_bonus_text(bonus_name)

func _show_bonus_text(text: String) -> void:
	_bonus_label.text = text
	await get_tree().create_timer(2.0).timeout
	if _bonus_label.text == text:
		_bonus_label.text = ""
