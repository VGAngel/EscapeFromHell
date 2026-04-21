extends "res://scripts/enemies/BossAI.gd"

# Circle 7 boss — "Зрадник". identify_and_evade mechanic — real boss +
# 3 copies. The level calls spawn_copies() after the scene is in the
# tree; BossAI handles the copy behaviour (_do_copy_behavior) and the
# copy destruction on stun.

func _ready() -> void:
	boss_id = "boss_07"
	super._ready()
