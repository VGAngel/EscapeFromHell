extends Control

# Scene: res://scenes/Hub.tscn
# Shown before every level. Tap to advance prologue; hold 1 s to skip it.
# On first run (level_id == 1) plays the full prologue before the regular hub.
#
# Expected scene tree:
#   Hub (Node)  ← this script
#   ├── Background       (ColorRect or TextureRect)
#   ├── GodPortrait      (Control / TextureRect)
#   ├── PlayerPortrait   (Control / TextureRect)
#   ├── MessageBox       (PanelContainer)  ← god dialogue
#   ├── BottomBar        (HBoxContainer)
#   │   ├── BtnUpgrades  (Button)
#   │   ├── BtnSouls     (Button)
#   │   └── BtnContinue  (Button)

#   ├── UpgradesScreen   (CanvasLayer) ← scripts/ui/UpgradesScreen.gd
#   └── CollectionScreen (CanvasLayer) ← scripts/ui/CollectionScreen.gd

# ── Constants ─────────────────────────────────────────────────────────────────
const MSG_AUTO_HIDE       := 8.0
const FADE_DURATION       := 0.4
const SKIP_HOLD_DURATION  := 1.0
const SKIP_HINT_DELAY     := 0.25

const MSG_COLORS := {
	"calm":      Color("#FFFFFF"),
	"solemn":    Color("#DDDDFF"),
	"warning":   Color("#FFAA00"),
	"personal":  Color("#FFEECC"),
	"warm":      Color("#FFD700"),
	"observing": Color("#CCCCCC"),
	"surprised": Color("#FFFFFF"),
	"quiet":     Color("#AAAAAA"),
	"silent":    Color("#FFFFFF"),
}

# Prologue lines: [speaker, locale_key, pause_after]. Text comes from
# localization (prologue.scene_*) at display time so the dialogue stays
# in sync with the rest of the UI — earlier the text was hardcoded UA
# here AND in localization, so renaming Данило → Іларіон only fixed
# half the surface, leaving the prologue still calling the player by
# the wrong name.
const PROLOGUE := [
	["narration", "prologue.scene_fall",   3.5],
	["god",       "prologue.scene_god_1",  1.5],
	["god",       "prologue.scene_god_2",  0.8],
	["god",       "prologue.scene_god_3",  0.8],
	["god",       "prologue.scene_god_4",  1.2],
	["god",       "prologue.scene_god_5",  0.8],
	["god",       "prologue.scene_god_6",  1.5],
	["god",       "prologue.scene_god_7",  1.2],
	["player",    "prologue.scene_player_1", 0.8],
	["god",       "prologue.scene_god_8",  1.8],
	["god",       "prologue.scene_god_9",  1.2],
	["god",       "prologue.scene_god_10", 0.8],
	["god",       "prologue.scene_god_11", 1.2],
	["player",    "prologue.scene_player_2", 0.8],
	["god",       "prologue.scene_god_12", 2.0],
	["god",       "prologue.scene_god_13", 0.8],
]

# ── Child nodes ───────────────────────────────────────────────────────────────
@onready var _bg:             Control       = $Background
@onready var _god_portrait:   Control       = $GodPortrait
@onready var _player_portrait:Control       = $PlayerPortrait
@onready var _msg_box:        PanelContainer= $MessageBox
@onready var _msg_label:      Label         = $MessageBox/VBox/Label
@onready var _msg_speaker:    Label         = $MessageBox/VBox/Speaker
@onready var _bottom_bar:     HBoxContainer = $BottomBar
@onready var _btn_upgrades:   Button        = $BottomBar/BtnUpgrades
@onready var _btn_souls:      Button        = $BottomBar/BtnSouls
@onready var _btn_continue:   Button        = $BottomBar/BtnContinue

@onready var _btn_menu:       Button        = get_node_or_null("BtnMenu")
@onready var _upgrades:       CanvasLayer   = $UpgradesScreen
@onready var _collection:     CanvasLayer   = $CollectionScreen

# ── State ─────────────────────────────────────────────────────────────────────
var _next_level_id:  int   = 1
var _prologue_done:  bool  = false
var _msg_timer:      float = 0.0
var _msg_visible:    bool  = false
var _in_prologue:    bool  = false
var _prologue_step:  int   = 0
var _awaiting_tap:   bool  = false
var _skip_held:      bool  = false
var _skip_timer:     float = 0.0
var _skip_indicator: Control    = null
var _skip_progress:  ProgressBar = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_next_level_id = SaveManager.get_current_level() if SaveManager else 1
	_prologue_done = SaveManager.is_hint_seen("prologue_done") if SaveManager else false

	_btn_upgrades.pressed.connect(_on_upgrades)
	_btn_souls.pressed.connect(_on_souls)
	_btn_continue.pressed.connect(_on_continue)

	if _btn_menu:
		_btn_menu.pressed.connect(_on_menu)

	_upgrades.closed.connect(_on_upgrades_closed)
	_collection.closed.connect(_on_collection_closed)

	_setup_continue_label()
	_refresh_currency()
	_build_skip_indicator()

	# Live-refresh both labels on language switch so the bottom bar (and
	# the BtnSouls scene-default "Врятовані\nДуші") translates without
	# requiring the player to leave the hub.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)

	# Atmospheric ambient layer (lighter "hub" preset — shadows + flicker
	# + embers + sin-tint, no ash/parallax/breathing).
	var amb := preload("res://scripts/ui/MenuAmbient.gd").new()
	add_child(amb)
	amb.setup(self, null, "hub")

	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_DURATION)
	tw.tween_callback(_on_fade_in_done)

func _on_fade_in_done() -> void:
	if not _prologue_done and _next_level_id == 1:
		_show_welcome_then_prologue()
	else:
		_show_hub()


# Pre-prologue welcome moment: gives the game's name and tagline a
# proper beat before the dialogue with God starts. Only the first time
# the player ever opens the Hub. Skippable — once the welcome dismisses
# (auto or tap), the prologue picks up immediately.
func _show_welcome_then_prologue() -> void:
	var welcome := preload("res://scripts/ui/WelcomeCard.gd").new()
	add_child(welcome)
	welcome.dismissed.connect(_start_prologue)

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _msg_visible and not _in_prologue:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_hide_message()

	if _in_prologue and _skip_held:
		_skip_timer += delta
		if _skip_timer >= SKIP_HINT_DELAY and _skip_indicator and not _skip_indicator.visible:
			_skip_indicator.visible = true
		if _skip_progress:
			_skip_progress.value = _skip_timer
		if _skip_timer >= SKIP_HOLD_DURATION:
			_reset_skip_state()
			_end_prologue()

func _input(event: InputEvent) -> void:
	if not _in_prologue:
		return

	if event is InputEventKey and event.is_echo():
		return

	var is_input_event: bool = event is InputEventKey \
		or event is InputEventScreenTouch \
		or event is InputEventMouseButton
	if not is_input_event:
		return

	if event.pressed:
		if not _skip_held:
			_skip_held = true
			_skip_timer = 0.0
	else:
		var was_short_tap := _skip_held and _skip_timer < SKIP_HOLD_DURATION
		_reset_skip_state()
		if was_short_tap and _awaiting_tap:
			_awaiting_tap = false
			_advance_prologue()

func _reset_skip_state() -> void:
	_skip_held = false
	_skip_timer = 0.0
	if _skip_indicator:
		_skip_indicator.visible = false
	if _skip_progress:
		_skip_progress.value = 0.0

# ── Hub display ───────────────────────────────────────────────────────────────

func _show_hub() -> void:
	_bottom_bar.visible = true

	if _btn_menu:
		_btn_menu.visible = true
	_god_portrait.visible    = true
	_player_portrait.visible = true
	_show_god_message()

func _setup_continue_label() -> void:
	var circle: int = ceili(float(_next_level_id) / 10.0)
	var lines: Array[String] = [
		_t("hub.btn_continue_next", {}, "Далі →"),
		_t("hub.btn_continue_level",
			{"circle": circle, "level": _next_level_id},
			"Коло %d • Рівень %d" % [circle, _next_level_id]),
	]
	# If the player has played this level before, surface their best run on
	# the button so they know what they're chasing.
	if SaveManager and SaveManager.has_method("get_level_best"):
		var best: Dictionary = SaveManager.get_level_best(_next_level_id)
		if not best.is_empty():
			var t: int = int(best.get("time", 0.0))
			var stars: int = int(best.get("stars", 0))
			@warning_ignore("integer_division")
			var time_str: String = "%d:%02d" % [t / 60, t % 60]
			lines.append(_t("hub.btn_continue_best",
				{"time": time_str, "stars": _stars_str(stars)},
				"🏆 %s  %s" % [time_str, _stars_str(stars)]))
	_btn_continue.text = "\n".join(lines)

func _stars_str(n: int) -> String:
	const FULL := "★"
	const EMPTY := "☆"
	var out := ""
	for i in 3:
		out += FULL if i < n else EMPTY
	return out

func _on_language_changed(_lang: String) -> void:
	_setup_continue_label()
	_refresh_currency()


func _refresh_currency() -> void:
	var light: int = SaveManager.get_light() if SaveManager else 0
	_btn_upgrades.text = _t("hub.btn_upgrades",
		{"light": light}, "💡 %d\nАпгрейди" % light)
	# BtnSouls text comes from a static scene default ("Врятовані\nДуші")
	# that isn't translated when the player switches language. Re-apply
	# from Loc on every refresh so the EN/UA toggle reaches it.
	if _btn_souls:
		_btn_souls.text = _t("hub.btn_souls", {}, "Врятовані\nДуші")

# ── God message selection ─────────────────────────────────────────────────────

func _show_god_message() -> void:
	var msg := _pick_god_message()
	if msg.is_empty():
		_hide_message()
		return
	_display_message("", msg.get("text", ""), msg.get("style", "calm"))

func _pick_god_message() -> Dictionary:
	if not SaveManager:
		return {}

	var sin_val: float = SaveManager.get_sin()
	var souls: int     = SaveManager.get_total_souls()
	var level: int     = _next_level_id

	# Conditional checks (priority order). Text comes from
	# god_messages.* locale keys; style stays code-side because it drives
	# colour/animation, not copy.
	if SaveManager.get_demon_deals_accepted() > SaveManager.get_deals_refused():
		return _msg("god_messages.demon_deal_accepted", "quiet")
	if sin_val > 70.0:
		return _msg("god_messages.sin_critical", "warning")
	if souls == 99:
		return _msg("god_messages.last_soul", "solemn")

	# Soul-count milestones — fired once each via SaveManager hint flags.
	# Only the milestones that actually have a god_messages.souls_X key
	# in localization are listed; adding a new tier = adding two lines.
	const MILESTONE_STYLES := {
		10: "warm",  25: "personal", 50: "solemn",
		75: "surprised", 99: "solemn",
	}
	for milestone in [99, 75, 50, 25, 10]:
		if souls >= milestone:
			if SaveManager.is_hint_seen("soul_milestone_%d" % milestone):
				continue
			SaveManager.mark_hint_seen("soul_milestone_%d" % milestone)
			return _msg("god_messages.souls_%d" % milestone,
				String(MILESTONE_STYLES.get(milestone, "calm")))

	# Per-level lines. Style table mirrors the previous hardcoded dict.
	const LEVEL_STYLES := {
		1: "calm",   2: "calm",  5: "calm",
		10: "solemn", 11: "calm",
		20: "observing", 25: "personal",
		30: "observing", 50: "personal",
		75: "surprised", 90: "warm",
		91: "warning", 99: "warm",
		100: "silent",
	}
	if LEVEL_STYLES.has(level):
		return _msg("god_messages.level_%d" % level,
			String(LEVEL_STYLES[level]))

	return {}


# Build a {text, style} dict by resolving the given Loc key with the
# named-soul target as a {total} param (used by milestone wording).
func _msg(loc_key: String, style: String) -> Dictionary:
	var n_target: int = SaveManager.get_named_souls_target() if SaveManager else 100
	return {"text": _t(loc_key, {"total": n_target}), "style": style}

# ── Message display ───────────────────────────────────────────────────────────

func _display_message(speaker: String, text: String, style: String) -> void:
	_msg_box.visible   = true
	_msg_label.text    = text
	_msg_label.add_theme_color_override("font_color", MSG_COLORS.get(style, Color.WHITE))
	_msg_speaker.text    = _speaker_label(speaker)
	_msg_speaker.visible = speaker != "" and speaker != "narration"

	_msg_box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_msg_box, "modulate:a", 1.0, 0.5)
	_msg_visible = true
	_msg_timer   = MSG_AUTO_HIDE

func _hide_message() -> void:
	if not _msg_visible:
		return
	_msg_visible = false
	var tw := create_tween()
	tw.tween_property(_msg_box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: _msg_box.visible = false)

func _speaker_label(speaker: String) -> String:
	# Speaker labels live in localization too, so the player name (Іларіон
	# in canon) updates everywhere from one place.
	match speaker:
		"god":    return _t("prologue.speaker_god",    {}, "Бог")
		"player": return _t("prologue.speaker_player", {}, "Іларіон")
	return ""


# Loc.t() with fallback so the hub still renders if Loc isn't loaded
# (early boot, headless tests).
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	return fallback if not fallback.is_empty() else key

# ── Prologue ──────────────────────────────────────────────────────────────────

func _start_prologue() -> void:
	_in_prologue = true
	_bottom_bar.visible   = false

	if _btn_menu:
		_btn_menu.visible = false
	_prologue_step        = 0
	_bg.modulate          = Color.BLACK
	_god_portrait.visible = false
	_player_portrait.visible = false
	_advance_prologue()

func _advance_prologue() -> void:
	if _prologue_step >= PROLOGUE.size():
		_end_prologue()
		return

	var line: Array = PROLOGUE[_prologue_step]
	var speaker: String = line[0]
	var loc_key: String = line[1]
	var pause:   float  = line[2]
	# {total} resolves to the named-soul pool size so the prologue scales
	# automatically when souls_collection.json grows. Lines that don't
	# use the placeholder simply ignore it.
	var n_target: int = SaveManager.get_named_souls_target() if SaveManager else 100
	var text: String  = _t(loc_key, {"total": n_target})
	_prologue_step += 1

	# Fade in background on second line
	if _prologue_step == 2:
		var tw := create_tween()
		tw.tween_property(_bg, "modulate", Color.WHITE, 1.2)
		tw.tween_callback(func() -> void:
			_god_portrait.visible = true
			_player_portrait.visible = true
		)

	_display_message(speaker, text, "calm")
	_awaiting_tap = false
	await get_tree().create_timer(pause).timeout
	if _in_prologue:
		_awaiting_tap = true

func _end_prologue() -> void:
	_in_prologue    = false
	_prologue_done  = true
	_reset_skip_state()
	if SaveManager:
		SaveManager.mark_hint_seen("prologue_done")
	_hide_message()
	await get_tree().create_timer(0.6).timeout
	_show_hub()

# ── Skip indicator ────────────────────────────────────────────────────────────

func _build_skip_indicator() -> void:
	var panel := PanelContainer.new()
	panel.name = "SkipIndicator"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -130
	panel.offset_right = 130
	# Y offsets come from SafeArea so the panel never slides under the
	# ad banner. Re-applied whenever the banner expands or collapses.
	panel.offset_top = -80
	panel.offset_bottom = -30

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var label := Label.new()
	label.text = "Тримай щоб пропустити"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("#DDDDDD"))
	vbox.add_child(label)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = SKIP_HOLD_DURATION
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(240, 6)
	vbox.add_child(bar)

	add_child(panel)
	_skip_indicator = panel
	_skip_progress  = bar

	_apply_safe_area()
	var sa: Node = get_node_or_null("/root/SafeArea")
	if sa:
		sa.changed.connect(_apply_safe_area)

## Pull the skip indicator and the prologue BottomBar above the ad
## banner. Delegated to SafeArea so "no_ads" purchase reclaims the
## reserved strip automatically.
func _apply_safe_area() -> void:
	var sa: Node = get_node_or_null("/root/SafeArea")
	var banner: int = int(sa.bottom_reserved) if sa else 0

	if _skip_indicator:
		_skip_indicator.offset_bottom = -30.0 - float(banner)
		_skip_indicator.offset_top    = -80.0 - float(banner)

	# BottomBar is bottom-anchored; push it up when the ad banner is present.
	if _bottom_bar:
		_bottom_bar.offset_bottom = -float(banner)
		_bottom_bar.offset_top    = -70.0 - float(banner)

# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_upgrades() -> void:
	if _upgrades and _upgrades.has_method("open"):
		_upgrades.open()
		_set_hub_interactive(false)

func _on_upgrades_closed() -> void:
	_refresh_currency()
	_setup_continue_label()
	_set_hub_interactive(true)

func _on_souls() -> void:
	if _collection and _collection.has_method("open"):
		_collection.open()
		_set_hub_interactive(false)

func _on_collection_closed() -> void:
	_set_hub_interactive(true)

func _set_hub_interactive(enabled: bool) -> void:
	_bottom_bar.modulate.a = 1.0 if enabled else 0.4
	_btn_upgrades.disabled  = not enabled
	_btn_souls.disabled     = not enabled
	_btn_continue.disabled  = not enabled


func _on_continue() -> void:
	_fade_out_and_load()


func _on_menu() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		if GameManager and GameManager.has_method("load_main_menu"):
			GameManager.load_main_menu()
		else:
			get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn"))

func _fade_out_and_load() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		if GameManager and GameManager.has_method("start_level"):
			GameManager.start_level(_next_level_id)
		else:
			get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")
	)
