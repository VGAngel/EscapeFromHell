extends "res://scripts/enemies/BossAI.gd"

# Circle 10 boss — "Люцифер". Three phases defined in bosses_config.json:
#   Phase 1: stationary_observer — player navigates and collects 5 souls.
#   Phase 2: slow_patrol with sin_aura — triggered at 3 souls.
#   Phase 3: stationary_final + prayer_ritual — triggered at 5 souls.
#
# All three are handled by BossAI:
#   * advance_phase / on_collectible_picked drives 2 + 3
#   * _tick_sin_aura ticks during phase 2
#   * tick_prayer / reset_prayer handles phase 3 from BossLevel._process

func _ready() -> void:
	boss_id = "boss_10"
	super._ready()
