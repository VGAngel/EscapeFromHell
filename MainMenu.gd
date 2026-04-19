extends Control

# Main scene: res://MainMenu.tscn
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
const SCENE_LEVEL  := "res://scenes/Level.tscn"
const FADE_DURATION := 0.5
const AD_BANNER_H   := 60

# ── Child nodes ───────────────────────────────────────────────────────────────
@onready var _bg:          Control       = $Background
@onready var _title:       Label         = $TitleLabel
@onready var _btn_play:    Button        = $ButtonsContainer/BtnPlay
@onready var _btn_collect: Button        = $ButtonsContainer/BtnCollection
@onready var _btn_settings:Button        = $ButtonsContainer/BtnSettings
@onready var _btn_no_ads:  Button        = $ButtonsContainer/BtnNoAds
@onready var _btn_donate:  Button        = $ButtonsContainer/BtnDonate
@onready var _version_lbl: Label         = $VersionLabel
@onready var _collection:  CanvasLayer   = $CollectionScreen
@onready var _settings:    CanvasLayer   = $SettingsScreen
@onready var _donate:      CanvasLayer   = $DonatePanel

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_btn_play.pressed.connect(_on_play)
	_btn_collect.pressed.connect(_on_collection)
	_btn_settings.pressed.connect(_on_settings)
	_btn_no_ads.pressed.connect(_on_no_ads)
	_btn_donate.pressed.connect(_on_donate)

	_collection.closed.connect(_on_overlay_closed)
	_settings.closed.connect(_on_overlay_closed)
	_donate.closed.connect(_on_overlay_closed)

	_refresh_buttons()
	_refresh_souls_counter()
	_version_lbl.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.1")

	# Fade in
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_DURATION)

# ── Button state ──────────────────────────────────────────────────────────────

func _refresh_buttons() -> void:
	var no_ads_bought: bool = SaveManager.has_reward("no_ads_purchased") if SaveManager else false
	_btn_no_ads.visible = not no_ads_bought

func _refresh_souls_counter() -> void:
	var saved: int = SaveManager.get_total_souls() if SaveManager else 0
	_btn_collect.text = "Врятовані Душі  %d/100" % saved

# ── Navigation ────────────────────────────────────────────────────────────────

func _on_play() -> void:
	_set_interactive(false)
	if SaveManager and SaveManager.has_save():
		_fade_to(SCENE_HUB)
	else:
		# New game — reset and go to Hub (which will trigger prologue)
		if SaveManager:
			SaveManager.load_slot(0)
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

func _on_overlay_closed() -> void:
	_refresh_buttons()
	_refresh_souls_counter()
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
		["BtnCollection", "Врятовані Душі  0/100"],
		["BtnSettings",   "Налаштування"],
		["BtnNoAds",      "Без реклами"],
		["BtnDonate",     "Пожертвувати"],
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
	ver.position = Vector2(-80, -AD_BANNER_H - 22)
	add_child(ver)

	# Overlay screens (empty CanvasLayers — scripts assign themselves)
	for screen_name in ["CollectionScreen", "SettingsScreen", "DonatePanel"]:
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
