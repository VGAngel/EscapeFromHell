extends "res://scripts/enemies/BaseEnemy.gd"

# Circle 1 enemy — slow basic patroller. Stats from enemies_config.json.

const ENEMY_ID := "shadow_lost"

func _ready() -> void:
	_apply_enemy_config(ENEMY_ID)
	super._ready()
