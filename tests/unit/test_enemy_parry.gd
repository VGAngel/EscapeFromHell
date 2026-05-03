extends GutTest

# Unit tests for the BaseEnemy parry-window contract.
#
# We don't drive the full physics loop — instead we set _attack_windup
# directly to simulate "deep into the windup", "inside the parry cue"
# and "cue closed" then call the public methods Player relies on.

var enemy: CharacterBody2D


func before_each() -> void:
	enemy = autofree(preload("res://scripts/enemies/BaseEnemy.gd").new())
	add_child(enemy)
	enemy.add_to_group("enemy")


# ── is_parry_window_open ──────────────────────────────────────────────────────

func test_no_active_windup_means_no_parry() -> void:
	# Default state: nothing winding up. The window is closed by
	# definition — Player should fall through to the regular knockback
	# branch instead of trying to parry.
	assert_false(enemy.is_parry_window_open())


func test_windup_active_but_telegraph_off_means_no_parry() -> void:
	# Windup is running but we haven't crossed into the parry cue yet
	# (telegraph fires only when _attack_windup <= PARRY_WINDOW). The
	# window must stay closed during this early phase so the player
	# can't pre-emptively cheese the deflect by mashing Staff.
	enemy._attack_windup    = 0.40   # 0.40s left, parry_window = 0.20s
	enemy._windup_telegraph = false
	assert_false(enemy.is_parry_window_open())


func test_windup_in_parry_cue_means_open() -> void:
	# Inside the last 0.2 s of windup → parry cue is active.
	enemy._attack_windup    = 0.15
	enemy._windup_telegraph = true
	assert_true(enemy.is_parry_window_open())


# ── cancel_attack_windup ──────────────────────────────────────────────────────

func test_cancel_clears_windup() -> void:
	enemy._attack_windup    = 0.10
	enemy._windup_telegraph = true
	enemy.cancel_attack_windup()
	assert_eq(enemy._attack_windup, 0.0)
	assert_false(enemy._windup_telegraph,
		"telegraph should be reset so the red tint disappears")


func test_cancel_extends_hit_cooldown() -> void:
	# After a parry the enemy shouldn't immediately start a new windup
	# — Player gets a fair window to follow up. cancel_attack_windup
	# refreshes _hit_cooldown to HIT_COOLDOWN_TIME (1.0 s).
	enemy._attack_windup    = 0.10
	enemy._windup_telegraph = true
	enemy._hit_cooldown     = 0.0
	enemy.cancel_attack_windup()
	assert_almost_eq(enemy._hit_cooldown, 1.0, 0.01)
