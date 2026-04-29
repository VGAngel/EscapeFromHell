extends Control

# Main scene: res://scenes/ui/MainMenu.tscn
# Expected scene tree:
#   MainMenu (Control) ← this script
#   ├── Background          (ColorRect or TextureRect)
#   ├── TitleLabel          (Label)
#   ├── ButtonsContainer    (VBoxContainer)
#   │   ├── BtnPlay         (Button)
#   │   ├── BtnCollection   (Button)
#   │   ├── BtnSettings     (Button)
#   │   ├── BtnNoAds        (Button)   — hidden if already purchased
#   │   └── BtnDonate       (Button)
#   ├── VersionLabel        (Label)
#   ├── CollectionScreen    (CanvasLayer)
#   ├── SettingsScreen      (CanvasLayer)
#   └── DonatePanel         (CanvasLayer)  — donate tiers overlay

# ── Constants ─────────────────────────────────────────────────────────────────
const SCENE_HUB    := "res://scenes/Hub.tscn"
const SCENE_LEVEL  := "res://scenes/levels/Level.tscn"
const FADE_DURATION := 0.5

# ── Child nodes ───────────────────────────────────────────────────────────────
@onready var _btn_play:    Button        = $ButtonsContainer/BtnPlay
@onready var _btn_collect: Button        = $ButtonsContainer/BtnCollection
@onready var _btn_settings:Button        = $ButtonsContainer/BtnSettings
@onready var _btn_no_ads:  Button        = $ButtonsContainer/BtnNoAds
@onready var _btn_donate:  Button        = $ButtonsContainer/BtnDonate
@onready var _btn_exit:    Button        = get_node_or_null("ButtonsContainer/BtnExit")
@onready var _btn_profile: Button        = get_node_or_null("ButtonsContainer/BtnProfile")
@onready var _btn_seed:    Button        = get_node_or_null("ButtonsContainer/BtnSeed")
@onready var _btn_levels:  Button        = get_node_or_null("ButtonsContainer/BtnLevels")
@onready var _seed_lbl:    Label         = get_node_or_null("SeedLabel")
@onready var _version_lbl: Label         = $VersionLabel
@onready var _collection:  CanvasLayer   = $CollectionScreen
@onready var _settings:    CanvasLayer   = $SettingsScreen
@onready var _donate:      CanvasLayer   = $DonatePanel
@onready var _profiles:    CanvasLayer   = get_node_or_null("ProfileScreen")
@onready var _seed_dlg:    CanvasLayer   = get_node_or_null("SeedDialog")
@onready var _level_debug: CanvasLayer   = get_node_or_null("LevelDebugMenu")

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_btn_play.pressed.connect(_on_play)
	_btn_collect.pressed.connect(_on_collection)
	_btn_settings.pressed.connect(_on_settings)
	_btn_no_ads.pressed.connect(_on_no_ads)
	_btn_donate.pressed.connect(_on_donate)
	if _btn_exit:
		_btn_exit.pressed.connect(_on_exit)
	if _btn_profile:
		_btn_profile.pressed.connect(_on_profile)
	if _btn_seed:
		_btn_seed.pressed.connect(_on_seed)
	if _btn_levels:
		_btn_levels.pressed.connect(_on_levels)

	_collection.closed.connect(_on_overlay_closed)
	_settings.closed.connect(_on_overlay_closed)
	_donate.closed.connect(_on_overlay_closed)
	if _profiles:
		_profiles.closed.connect(_on_overlay_closed)
	if _seed_dlg:
		_seed_dlg.closed.connect(_on_overlay_closed)
	if _level_debug:
		_level_debug.closed.connect(_on_overlay_closed)

	_ensure_seed()
	_refresh_buttons()
	_refresh_souls_counter()
	_refresh_seed_label()
	_version_lbl.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.1")

	# Atmospheric layer — embers, ash, flicker, sin-tint, parallax.
	# Built in code so the .tscn can stay slim.
	var title_node: Label = get_node_or_null("TitleLabel")
	var amb := preload("res://scripts/ui/MenuAmbient.gd").new()
	add_child(amb)
	amb.setup(self, title_node)

	# Persistent TopBar (auto-shown when an overlay is on UIRouter).
	var top_bar := preload("res://scripts/ui/TopBar.gd").new()
	add_child(top_bar)

	# Hero card — player snapshot above the button list.
	_install_hero_card()

	# Re-render dynamic labels (Play CTA, souls counter) when the
	# language changes from inside Settings.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)

	_apply_banner_space()
	var sa: Node = get_node_or_null("/root/SafeArea")
	if sa:
		sa.changed.connect(_apply_banner_space)
	elif AdsManager and AdsManager.has_signal("no_ads_purchased"):
		AdsManager.no_ads_purchased.connect(_apply_banner_space)

	# Fade in
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_DURATION)

## Shift ButtonsContainer and VersionLabel up by the reserved ad-banner
## height so the bottom banner never overlaps menu content. Re-invoked
## when the player buys "no ads" so the layout expands to full height.
func _on_language_changed(_lang: String) -> void:
	# Re-render the dynamic Play CTA + souls counter so the menu
	# updates instantly when Settings switches language.
	_refresh_souls_counter()


func _apply_banner_space() -> void:
	var banner_h: int = get_banner_height()
	_version_lbl.offset_top    = -50.0 - float(banner_h)
	_version_lbl.offset_bottom = -20.0 - float(banner_h)
	# ButtonsContainer is anchored to the viewport center with symmetric
	# offsets that exactly fit its content. Shift both edges up by half the
	# banner height so the visual midpoint stays above the banner instead
	# of ballooning the container off-screen.
	if has_node("ButtonsContainer"):
		var buttons: Control = $ButtonsContainer
		var shift: float = float(banner_h) * 0.5
		buttons.offset_top    = -485.0 - shift
		buttons.offset_bottom =  485.0 - shift

## Separate helper so tests can stub without needing SafeArea fully up.
## Prefers AdsManager (always the freshest value) and falls back to
## SafeArea for projects that push insets without an AdsManager.
func get_banner_height() -> int:
	if AdsManager and AdsManager.has_method("get_banner_height"):
		return int(AdsManager.get_banner_height())
	var sa: Node = get_node_or_null("/root/SafeArea")
	if sa and "bottom_reserved" in sa:
		return int(sa.bottom_reserved)
	return 0

# ── Button state ──────────────────────────────────────────────────────────────

func _refresh_buttons() -> void:
	var no_ads_bought: bool = SaveManager.has_reward("no_ads_purchased") if SaveManager else false
	_btn_no_ads.visible = not no_ads_bought

func _refresh_souls_counter() -> void:
	var saved: int = SaveManager.get_total_souls() if SaveManager else 0
	var loc: Node = get_node_or_null("/root/Loc")
	_btn_collect.text = _loc_t(loc, "main_menu_dyn.souls_counter",
			{"saved": saved})
	_refresh_play_button()

# Dynamic label on the primary CTA — first run shows "Грати", later
# runs prefix the current level so the menu reads as "continue your
# descent". Falls back to a clean default if SaveManager is missing.
func _refresh_play_button() -> void:
	if _btn_play == null:
		return
	var loc: Node = get_node_or_null("/root/Loc")
	if SaveManager == null:
		_btn_play.text = _loc_t(loc, "main_menu_dyn.play_first")
		return
	var lvl: int = int(SaveManager.get_current_level())
	var played_before: bool = false
	if SaveManager.has_method("get_stat"):
		played_before = float(SaveManager.get_stat("total_play_seconds", 0.0)) > 0.0
	if not played_before or lvl <= 1:
		_btn_play.text = _loc_t(loc, "main_menu_dyn.play_first")
	else:
		_btn_play.text = _loc_t(loc, "main_menu_dyn.play_continue", {"n": lvl})


func _loc_t(loc: Node, key: String, params: Dictionary = {}) -> String:
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	# Fallback when Loc is missing — match previous hardcoded UA strings
	# so visuals don't regress in early-bootstrap scenarios.
	if key == "main_menu_dyn.play_first":
		return "▶  Грати"
	if key == "main_menu_dyn.play_continue":
		return "▶  Продовжити — рівень %d" % int(params.get("n", 1))
	if key == "main_menu_dyn.souls_counter":
		return "Врятовані Душі  %d/100" % int(params.get("saved", 0))
	return key

# HeroCard goes between TitleLabel and ButtonsContainer. We insert it as
# a top-anchored Control so the existing button vertical centring isn't
# disturbed.
#
# Layout math (1080×1920 portrait):
#   • TitleLabel ends around y ≈ 230 (offset_top=100, offset_bottom=230)
#   • ButtonsContainer is centred at viewport mid (y=960) with
#     offset_top=-485 → top edge ≈ y=475 (or higher when the ad-banner
#     pushes it up by banner_h/2)
#   • HeroCard is squeezed into the y=240..435 strip — leaves a 40 px
#     safety margin before the buttons start, even with a 60 px banner.
func _install_hero_card() -> void:
	if has_node("HeroCard"):
		return
	var card := preload("res://scripts/ui/HeroCard.gd").new()
	card.name = "HeroCard"
	card.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var vp := get_viewport_rect().size
	card.offset_left   = vp.x * 0.05
	card.offset_right  = -vp.x * 0.05
	card.offset_top    = vp.y * 0.125
	card.offset_bottom = vp.y * 0.227
	add_child(card)

func _ensure_seed() -> void:
	if not SaveManager or not SaveManager.get_world_seed_str().is_empty():
		return
	SaveManager.set_world_seed_str(_random_seed_str())

# 8-char alnum (≈ 1.5e12 unique values) — enough variety per save without
# overwhelming the UI label.
func _random_seed_str() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var result := ""
	for _i in 8:
		result += chars[randi() % chars.length()]
	return result

func _refresh_seed_label() -> void:
	var s: String = SaveManager.get_world_seed_str() if SaveManager else ""
	if _seed_lbl:
		_seed_lbl.text = "🌱 %s" % s if not s.is_empty() else ""
	if _btn_seed:
		_btn_seed.text = ("🌱  Seed: %s" % s) if not s.is_empty() else "🌱  Seed"

# ── Navigation ────────────────────────────────────────────────────────────────

func _on_play() -> void:
	_set_interactive(false)
	_fade_to(SCENE_HUB)

func _fade_to(scene_path: String) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file(scene_path)
	)

func _on_collection() -> void:
	_open_via_router(_collection)

func _on_settings() -> void:
	_open_via_router(_settings)

func _on_no_ads() -> void:
	if AdsManager and AdsManager.has_method("purchase_no_ads"):
		AdsManager.purchase_no_ads()

func _on_donate() -> void:
	_open_via_router(_donate)

func _on_exit() -> void:
	_set_interactive(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void: get_tree().quit())

func _on_profile() -> void:
	_open_via_router(_profiles)

func _on_levels() -> void:
	_open_via_router(_level_debug)

# Single entry point for "show overlay X" — pushes via UIRouter (so any
# observer like the upcoming TopBar reacts) and disables menu buttons
# while the overlay is up. The overlay's own `closed` signal still
# triggers `_on_overlay_closed`, which re-enables buttons.
func _open_via_router(screen: Node) -> void:
	if screen == null:
		return
	var router: Node = get_node_or_null("/root/UIRouter")
	if router and router.has_method("push"):
		router.push(screen)
	elif screen.has_method("open"):
		screen.open()
	_set_interactive(false)

func _on_seed() -> void:
	# One click = new world seed. The old SeedDialog (manual entry) is kept in
	# the scene tree but no longer opened from this button — leave it wired
	# up for a future "advanced" entry point if needed.
	if not SaveManager:
		return
	SaveManager.set_world_seed_str(_random_seed_str())
	_refresh_seed_label()
	_pulse_seed_button()

# Brief visual confirmation: scale + tween back so the click reads as
# "something happened" without a popup.
func _pulse_seed_button() -> void:
	if not _btn_seed:
		return
	_btn_seed.scale = Vector2(1.15, 1.15)
	var tw := create_tween()
	tw.tween_property(_btn_seed, "scale", Vector2.ONE, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_overlay_closed() -> void:
	_refresh_buttons()
	_refresh_souls_counter()
	_refresh_seed_label()
	_set_interactive(true)

func _set_interactive(enabled: bool) -> void:
	for btn in $ButtonsContainer.get_children():
		if btn is Button:
			btn.disabled = not enabled
	$ButtonsContainer.modulate.a = 1.0 if enabled else 0.5

# ── Build UI in code (fallback if scene has no nodes yet) ─────────────────────
# If MainMenu.tscn already has proper nodes this section is skipped.

func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		if not has_node("Background"):
			_build_fallback_ui()

func _build_fallback_ui() -> void:
	# Full-screen dark background
	var bg := ColorRect.new()
	bg.name  = "Background"
	bg.color = Color(0.04, 0.03, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)

	# Atmospheric gradient overlay
	var grad := ColorRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.color = Color(0.06, 0.04, 0.10, 0.6)
	bg.add_child(grad)

	# Title
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "ESCAPE\nFROM HELL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 63)
	title.add_theme_color_override("font_color", Color("#CC3322"))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var vp_size := get_viewport().get_visible_rect().size
	title.position = Vector2(0, vp_size.y * 0.083)
	title.size     = Vector2(vp_size.x, vp_size.y * 0.073)
	add_child(title)

	# Seed label — always visible below title
	var seed_lbl := Label.new()
	seed_lbl.name = "SeedLabel"
	seed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_lbl.add_theme_font_size_override("font_size", 20)
	seed_lbl.add_theme_color_override("font_color", Color(0.50, 0.72, 0.42))
	seed_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	seed_lbl.position = Vector2(0, vp_size.y * 0.161)
	seed_lbl.size     = Vector2(vp_size.x, 28)
	add_child(seed_lbl)

	# Buttons container
	var vbox := VBoxContainer.new()
	vbox.name = "ButtonsContainer"
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(vp_size.x * 0.15, vp_size.y * 0.27)
	vbox.size     = Vector2(vp_size.x * 0.70, 0)
	add_child(vbox)

	var btn_defs := [
		["BtnPlay",       "Грати"],
		["BtnProfile",    "Профіль"],
		["BtnCollection", "Врятовані Душі  0/100"],
		["BtnSettings",   "Налаштування"],
		["BtnLevels",     "Levels (debug)"],
		["BtnSeed",       "🌱  Seed"],
		["BtnNoAds",      "Без реклами"],
		["BtnDonate",     "Пожертвувати"],
		["BtnExit",       "Вихід"],
	]
	for pair in btn_defs:
		var btn := _make_menu_btn(pair[1], pair[0] == "BtnPlay")
		btn.name = pair[0]
		vbox.add_child(btn)

	# Version label
	var ver := Label.new()
	ver.name = "VersionLabel"
	ver.text = "v0.1"
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.add_theme_font_size_override("font_size", 16)
	ver.add_theme_color_override("font_color", Color(0.35, 0.33, 0.40))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Banner-aware position is applied in _apply_banner_space; default
	# uses a 60 px banner so the version label is visible before that
	# runs (mainly matters for tests that skip the full _ready flow).
	ver.position = Vector2(-80, -82)
	add_child(ver)

	# Overlay screens (empty CanvasLayers — scripts assign themselves)
	var screen_names := [
		"CollectionScreen", "SettingsScreen", "DonatePanel",
		"ProfileScreen", "SeedDialog", "LevelDebugMenu",
	]
	for screen_name in screen_names:
		var cl := CanvasLayer.new()
		cl.name  = screen_name
		cl.layer = 10
		add_child(cl)
	# Attach debug overlay script so a code-only fallback wires up too.
	var debug_node: CanvasLayer = get_node_or_null("LevelDebugMenu") as CanvasLayer
	if debug_node and debug_node.get_script() == null:
		debug_node.set_script(load("res://scripts/ui/LevelDebugMenu.gd"))

func _make_menu_btn(text: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 50)
	btn.add_theme_font_size_override("font_size", 24)

	var n := StyleBoxFlat.new()
	var h := StyleBoxFlat.new()
	var p := StyleBoxFlat.new()
	if primary:
		n.bg_color = Color(0.30, 0.08, 0.08)
		h.bg_color = Color(0.44, 0.12, 0.12)
		p.bg_color = Color(0.22, 0.05, 0.05)
		btn.add_theme_color_override("font_color", Color("#FF8866"))
	else:
		n.bg_color = Color(0.12, 0.11, 0.16)
		h.bg_color = Color(0.20, 0.18, 0.24)
		p.bg_color = Color(0.09, 0.08, 0.12)
		btn.add_theme_color_override("font_color", Color(0.78, 0.76, 0.82))
	for s in [n, h, p]:
		s.corner_radius_top_left    = 10
		s.corner_radius_top_right   = 10
		s.corner_radius_bottom_left = 10
		s.corner_radius_bottom_right = 10
		s.border_width_left   = 1; s.border_width_right  = 1
		s.border_width_top    = 1; s.border_width_bottom = 1
	n.border_color = Color(0.45, 0.15, 0.15) if primary else Color(0.24, 0.22, 0.30)
	h.border_color = Color(0.65, 0.22, 0.22) if primary else Color(0.38, 0.35, 0.46)
	p.border_color = n.border_color
	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus",   n)
	return btn
