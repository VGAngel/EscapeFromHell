extends "res://scripts/enemies/BossAI.gd"

# Circle 2 boss — "Хранитель Вітрів". activate_in_sequence mechanic
# (three wind totems). flight=true is read from bosses_config.json so
# BossAI skips gravity for this boss.

func _ready() -> void:
	boss_id = "boss_02"
	super._ready()
