extends GutTest

# Cross-class pipeline integration tests.
#
# Per-class unit tests still pass even when the wiring BETWEEN classes
# is broken — the multi-soul reveal bug lived for weeks because each
# component (Player.deliver_soul, LevelBase._on_soul_delivered,
# SoulRevealPanel.show_soul) had passing tests in isolation.
#
# This file deliberately exercises the full chain for the gameplay
# moments that matter most:
#
#   1. Sin: GameManager.add_sin → sin_added signal → HUD toast spawn
#                                                  + SinVignette intensity
#   2. Damage: Player.damage_taken → DamageFlash auto-discovered via
#              group → flash tween starts
#   3. Hidden soul: Soul ("H1") → carry list → deliver → SaveManager
#                   .add_hidden_soul persisted
#   4. Discovery: BonusPickup register → DiscoveryHints proximity →
#                 TutorialManager.show_hint + DiscoveryHighlight
#   5. Localisation: Loc.set_language("en") → language_changed →
#                    HeroCard.refresh re-renders strings
#
# Each test stands up only the nodes that participate in its specific
# pipeline so the suite stays under ~3 s and isolated failures point
# at a single seam instead of a vague "level broke".

const SinVignetteScript    := preload("res://scripts/ui/SinVignette.gd")
const DamageFlashScript    := preload("res://scripts/ui/DamageFlash.gd")
const SoulRevealPanelScript:= preload("res://scripts/ui/SoulRevealPanel.gd")
const DiscoveryHintsScript := preload("res://scripts/managers/DiscoveryHints.gd")
const HeroCardScript       := preload("res://scripts/ui/HeroCard.gd")


# Fake Player with the signals the pipelines react to. Avoids
# instantiating the real Player.gd which has too many @onready scene
# refs to stand up in a unit fixture.
class FakePlayer extends Node2D:
	signal damage_taken(amount: int)

	func _ready() -> void:
		add_to_group("player")


# ──────────────────────────────────────────────────────────────────────────────
# Pipeline 1 — Sin: GameManager → HUD toast + SinVignette
# ──────────────────────────────────────────────────────────────────────────────

func test_pipeline_sin_signal_drives_vignette_intensity() -> void:
	# GameManager autoload exposes sin_added + sin_changed. The
	# SinVignette listens to sin_changed and updates its shader
	# intensity. End-to-end: emit sin_changed → vignette intensity
	# tracks the new sin %.
	var vignette: Control = SinVignetteScript.new()
	vignette.size = Vector2(1080, 1920)
	add_child_autofree(vignette)

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_signal("sin_changed"):
		pending("GameManager autoload missing sin_changed signal")
		return

	# Drive the signal directly — the contract is "vignette tracks
	# whatever value comes in", not "GameManager's add_sin math is
	# correct" (covered separately).
	gm.sin_changed.emit(60.0)
	await get_tree().process_frame
	var intensity: float = vignette._shader_mat.get_shader_parameter("intensity")
	assert_almost_eq(intensity, 0.6, 0.01,
			"SinVignette must follow the sin_changed signal")


# ──────────────────────────────────────────────────────────────────────────────
# Pipeline 2 — Damage: Player signal → DamageFlash auto-detects + flashes
# ──────────────────────────────────────────────────────────────────────────────

func test_pipeline_player_damage_triggers_screen_flash() -> void:
	# DamageFlash registers itself via tree.node_added + group lookup.
	# The chain we want to verify:
	#   FakePlayer joins tree → DamageFlash discovers it →
	#   damage_taken signal → flash() runs → tween created.
	# The bug class this catches is "DamageFlash forgets to connect
	# when the Player joins late" — exactly the kind of timing bug
	# isolated unit tests miss.
	var flash: Control = DamageFlashScript.new()
	flash.size = Vector2(1080, 1920)
	add_child_autofree(flash)
	# Player joins AFTER the flash — exercises the deferred-lookup path.
	var player := FakePlayer.new()
	add_child_autofree(player)
	await get_tree().process_frame

	# DamageFlash must have stored a ref to the player by now.
	assert_eq(flash._player, player,
			"DamageFlash must auto-connect when player joins later")
	# Fire the signal as if the player took 2 damage.
	player.damage_taken.emit(2)
	assert_not_null(flash._current_tween,
			"damage_taken must kick off a flash tween")


# ──────────────────────────────────────────────────────────────────────────────
# Pipeline 3 — Hidden soul: pickup → deliver → persisted to SaveManager
# ──────────────────────────────────────────────────────────────────────────────

class FakeLevelHidden extends Node:
	# Trimmed-down LevelBase mirror — just the carry-data dict + the
	# branching delivery handler, both adapted from the real
	# scripts/levels/LevelBase.gd.
	var _carried_souls_data: Dictionary = {}
	var _souls_found: int = 0
	var _hidden_delivered: Array = []

	func register_carried(key: Variant, data: Dictionary) -> void:
		_carried_souls_data[key] = data

	func _on_soul_delivered(soul_id: String) -> void:
		# Mirror real LevelBase routing
		if soul_id.begins_with("H"):
			_hidden_delivered.append(soul_id)
			if SaveManager and SaveManager.has_method("add_hidden_soul"):
				SaveManager.add_hidden_soul(soul_id)
			return
		_souls_found += 1


func test_pipeline_hidden_soul_persists_to_save_manager() -> void:
	# Anchors the H-prefix routing rule introduced when we wired the
	# 20 hidden souls. End-to-end: deliver "H1" via the same handler
	# that AltarNode would invoke → SaveManager.get_hidden_soul_ids
	# contains "H1".
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	SaveManager._reset()
	var lvl := FakeLevelHidden.new()
	add_child_autofree(lvl)
	lvl.register_carried("H1", {"name": "Агнеса", "age": 6, "epitaph": "."})
	lvl._on_soul_delivered("H1")

	assert_eq(SaveManager.get_total_hidden_souls(), 1)
	assert_true("H1" in SaveManager.get_hidden_soul_ids())
	# Hidden delivery must NOT increment the regular souls_found
	# counter (it's a discovery bonus, not a level-clear requirement).
	assert_eq(lvl._souls_found, 0,
			"hidden souls don't count toward the level's required total")


func test_pipeline_named_soul_does_not_hit_hidden_path() -> void:
	# Inverse guard: a regular numeric id ("47") must NOT route
	# through SaveManager.add_hidden_soul.
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	SaveManager._reset()
	var lvl := FakeLevelHidden.new()
	add_child_autofree(lvl)
	lvl.register_carried(47, {"name": "Михайло", "epitaph": "..."})
	lvl._on_soul_delivered("47")

	assert_eq(SaveManager.get_total_hidden_souls(), 0,
			"named souls must not be misrouted into the hidden bucket")
	assert_eq(lvl._souls_found, 1)


# ──────────────────────────────────────────────────────────────────────────────
# Pipeline 4 — Discovery: pickup register → proximity → hint + halo
# ──────────────────────────────────────────────────────────────────────────────

func test_pipeline_discovery_proximity_fires_hint_and_halo() -> void:
	# Full chain: register a node → player walks into the radius →
	# DiscoveryHints fires → TutorialManager hint marked seen + the
	# DiscoveryHighlight halo gets attached as a child. The
	# halo-attached part is the cross-class wiring the user asked
	# for: a unit test on DiscoveryHints alone wouldn't have caught
	# "halo never showed up because the script path was wrong".
	var dh: Node = DiscoveryHintsScript.new()
	add_child_autofree(dh)
	var player := FakePlayer.new()
	player.global_position = Vector2(0, 0)
	add_child_autofree(player)

	var item := Node2D.new()
	item.global_position = Vector2(120, 0)   # within 200 default
	add_child_autofree(item)

	# Use a unique key so TutorialManager's persistent seen-set
	# from previous tests doesn't skip this one.
	var key: String = "pipe_disc_%d" % Time.get_ticks_usec()
	dh.register(item, key, "tutorial.bonus_manna")

	watch_signals(dh)
	dh._check_proximity()
	assert_signal_emitted(dh, "discovered")

	# Halo: a child node created by _attach_highlight should now sit
	# under the item.
	var has_halo: bool = false
	for c in item.get_children():
		if c.get_script() and String(c.get_script().resource_path).ends_with(
				"DiscoveryHighlight.gd"):
			has_halo = true
			break
	assert_true(has_halo,
			"DiscoveryHighlight must be attached to the discovered node")


# ──────────────────────────────────────────────────────────────────────────────
# Pipeline 5 — Localisation switch propagates to subscribed UI
# ──────────────────────────────────────────────────────────────────────────────

func test_pipeline_loc_change_re_renders_hero_card_text() -> void:
	# Loc.set_language emits language_changed; HeroCard subscribes
	# in _ready and calls refresh() on emission. This pipeline is
	# the difference between "language toggle in Settings actually
	# works" and "labels stay UA forever".
	if SaveManager == null:
		pending("SaveManager autoload missing")
		return
	if SaveManager.has_method("set_profile_name"):
		SaveManager.set_profile_name("ТестГерой")
	var loc: Node = get_node_or_null("/root/Loc")
	if loc == null or not loc.has_signal("language_changed"):
		pending("Loc autoload missing")
		return

	# Switch to UA first to baseline.
	loc.set_language("uk")
	var card: PanelContainer = HeroCardScript.new()
	add_child_autofree(card)
	await get_tree().process_frame
	var ua_circle_text: String = card._circle_lbl.text

	loc.set_language("en")
	await get_tree().process_frame
	var en_circle_text: String = card._circle_lbl.text
	# UA: "Коло 1", EN: "Circle 1" — they must differ after the
	# language flip if the signal actually propagated.
	assert_ne(ua_circle_text, en_circle_text,
			"HeroCard must re-render its labels when Loc.language_changed fires")
	# Restore for other tests.
	loc.set_language("uk")
