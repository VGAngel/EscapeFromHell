extends "res://scripts/enemies/BossAI.gd"

# Circle 5 boss — "Гнів Втілений". dodge_and_collect mechanic —
# 3 souls near walls. Boss charges; BossAI handles charge telegraph,
# charge, and wall-stun via _begin_charge_telegraph / _check_wall_stun.

func _ready() -> void:
	boss_id = "boss_05"
	super._ready()
