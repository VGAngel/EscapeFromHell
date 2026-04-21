extends "res://scripts/enemies/BossAI.gd"

# Circle 3 boss — "Вогняний Колос". lure_into_trap mechanic — 3 fire
# crystals on upper platforms. Using KeyFragment for crystal pickups.

func _ready() -> void:
	boss_id = "boss_03"
	super._ready()
