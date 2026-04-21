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
@onready var _version_lbl: Label         = $VersionLabel
@onready var _collection:  CanvasLayer   = $CollectionScreen
@onready var _settings:    CanvasLayer   = $SettingsScreen
@onready var _donate:      CanvasLayer   = $DonatePanel
@onready var _profiles:    CanvasLayer   = get_node_or_null("ProfileScreen")
@onready var _seed_dlg:    CanvasLayer   = get_node_or_null("SeedDialog")

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

	_collection.closed.connect(_on_overlay_closed)
	_settings.closed.connect(_on_overlay_closed)
	_donate.closed.connect(_on_overlay_closed)
	if _profiles:
		_profiles.closed.connect(_on_overlay_closed)
	if _seed_dlg:
		_seed_dlg.closed.connect(_on_overlay_closed)

	_refresh_buttons()
	_refresh_souls_counter()
	_refresh_seed_label()
	_version_lbl.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.1")

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
func _apply_banner_space() -> void:
	var banner_h: int = get_banner_height()
	_version_lbl.offset_top    = 1210.0 - banner_h
	_version_lbl.offset_bottom = 1240.0 - banner_h
	if has_node("ButtonsContainer"):
		var buttons: Control = $ButtonsContainer
		buttons.offset_bottom = 900.0 - banner_h

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
	_btn_collect.text = "Врятовані Душі  %d/100" % saved

func _refresh_seed_label() -> void:
	if not _btn_seed:
		return
	var s: String = SaveManager.get_world_seed_str() if SaveManager else ""
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
	_collection.open()
	_set_interactive(false)

func _on_settings() -> void:
	_settings.open()
	_set_interactive(false)

func _on_no_ads() -> void:
	if AdsManager and AdsManager.has_method("purchase_no_ads"):
		AdsManager.purchase_no_ads()

func _on_donate() -> void:
	_donate.open()
	_set_interactive(false)

func _on_exit() -> void:
	_set_interactive(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void: get_tree().quit())

func _on_profile() -> void:
	if _profiles:
		_profiles.open()
		_set_interactive(false)

func _on_seed() -> void:
	if _seed_dlg:
		_seed_dlg.open()
		_set_interactive(false)

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
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("#CC3322"))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position = Vector2(0, 160)
	title.size     = Vector2(720, 140)
	add_child(title)

	# Buttons container
	var vbox := VBoxContainer.new()
	vbox.name = "ButtonsContainer"
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(360 - 160, 520)
	vbox.size     = Vector2(320, 0)
	add_child(vbox)

	var btn_defs := [
		["BtnPlay",       "Грати"],
		["BtnProfile",    "Профіль"],
		["BtnCollection", "Врятовані Душі  0/100"],
		["BtnSettings",   "Налаштування"],
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
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(0.35, 0.33, 0.40))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Banner-aware position is applied in _apply_banner_space; default
	# uses a 60 px banner so the version label is visible before that
	# runs (mainly matters for tests that skip the full _ready flow).
	ver.position = Vector2(-80, -82)
	add_child(ver)

	# Overlay screens (empty CanvasLayers — scripts assign themselves)
	for screen_name in ["CollectionScreen", "SettingsScreen", "DonatePanel", "ProfileScreen", "SeedDialog"]:
		var cl := CanvasLayer.new()
		cl.name  = screen_name
		cl.layer = 10
		add_child(cl)

func _make_menu_btn(text: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 50)
	btn.add_theme_font_size_override("font_size", 16)

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
