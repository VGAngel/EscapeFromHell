extends "res://scripts/enemies/BossAI.gd"

# Circle 1 boss — "Воротар" (Gatekeeper). Placeholder sprite and all
# mechanics come straight from BossAI + bosses_config.json entry
# "boss_01". This file exists so the scene's script is easy to grep for.

func _ready() -> void:
	boss_id = "boss_01"
	super._ready()
