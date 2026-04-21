extends "res://scripts/enemies/BaseEnemy.gd"

# Circle 1 enemy — faster wanderer with longer patrol route + wider detection.
# Stats from enemies_config.json.

const ENEMY_ID := "pale_wanderer"

func _ready() -> void:
	_apply_enemy_config(ENEMY_ID)
	super._ready()
