extends Node

# Autoload: TutorialManager  (res://scripts/managers/TutorialManager.gd)
# Usage: TutorialManager.show_hint("first_soul")
#
# Hints are shown once (persisted via SaveManager) unless flagged show_every_time.
# Text is read directly from tutorial_config.json — no Loc dependency.

signal hint_shown(hint_id: String)
signal hint_dismissed(hint_id: String)

const CONFIG_PATH := "res://tutorial_config.json"

# ── Config ────────────────────────────────────────────────────────────────────
var _triggers:  Dictionary = {}   # hint_id → { text, duration?, show_every_time? }
var _settings:  Dictionary = {}

# ── State ─────────────────────────────────────────────────────────────────────
var _active_id: String = ""
var _is_showing: bool  = false
var _queue:      Array = []        # Array[String] — pending hint ids

# ── UI refs ───────────────────────────────────────────────────────────────────
var _layer:    CanvasLayer = null
var _root:     Control     = null   # tweened for modulate (CanvasLayer has none)
var _panel:    PanelContainer = null   # repositioned each frame to dodge player
var _label:    Label       = null
var _tween:    Tween       = null

# Default top-zone placement (just below the level info row).
const _PANEL_HEIGHT := 120.0
const _DEFAULT_TOP    := 170.0
const _DEFAULT_BOTTOM := _DEFAULT_TOP + _PANEL_HEIGHT
# Mobile builds dock the action buttons in the bottom ~180 px of the
# viewport — keep the panel above that band when we flip it down.
const _MOBILE_HUD_BOTTOM_RESERVE := 200.0
# Vertical clearance we want around the player sprite (~64 px tall).
const _PLAYER_PAD := 70.0

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_build_ui()

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_warning("TutorialManager: tutorial_config.json not found — hints disabled")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("TutorialManager: failed to parse tutorial_config.json")
		return
	_settings  = parsed.get("settings",  {})
	_triggers  = parsed.get("triggers",  {})

# ── Public API ────────────────────────────────────────────────────────────────

func show_hint(hint_id: String) -> void:
	# Two valid hint id shapes:
	#   1. Configured trigger (in tutorial_config.json) — uses the
	#      config's text/text_key/duration/icon.
	#   2. Loc-key passthrough — hint_id starts with "tutorial." and
	#      _display() resolves it through Loc.t() + the fallback
	#      dict. Lets DiscoveryHints fire on ad-hoc keys without
	#      requiring a config entry per pickup type.
	if not _triggers.has(hint_id) and not hint_id.begins_with("tutorial."):
		return
	if _is_seen(hint_id) and not _always_show(hint_id):
		return
	if _is_showing:
		# Queue: don't interrupt a contextual hint with another
		if hint_id not in _queue:
			_queue.append(hint_id)
		return
	_display(hint_id)

func dismiss_current() -> void:
	if _is_showing:
		_do_dismiss()

func is_hint_seen(hint_id: String) -> bool:
	return _is_seen(hint_id)

func reset_all() -> void:
	if SaveManager:
		SaveManager.clear_all_hints()

# ── Input: any game action or touch dismisses ─────────────────────────────────

func _input(_event: InputEvent) -> void:
	# Tutorial hints used to dismiss on ANY key/tap, which broke the
	# flow whenever the player was mid-fight or running from enemies
	# — every gameplay input killed the hint they hadn't read yet.
	#
	# We now let hints play out their adaptive duration in full
	# (5-12 s scaled by word count). Code paths that need to force
	# an early hide call `dismiss_current()` directly (e.g. scene
	# transitions, pause overlay opening).
	pass

## UA fallback strings used when Loc.t() returns the key itself
## (= entry missing from localization/uk.json). Keeps the tutorial
## readable even before localisation catches up — and gives the
## player a helpful first-pass explanation of every mechanic.
const _FALLBACK_TEXT := {
	"tutorial.move":          "Тримай ← / → щоб іти",
	"tutorial.jump":          "Натисни ↑ щоб стрибнути",
	"tutorial.variable_jump": "Тримай ↑ довше — стрибнеш вище",
	"tutorial.look_down":     "Затисни ↓ — камера покаже що внизу",
	"tutorial.staff":         "⚔ Натисни щоб ударити посохом. Перевіряй гріх — кожен удар його піднімає.",
	"tutorial.staff_sin":     "Кожен удар посохом додає гріх. Високий гріх змінює фінал — користуйся обережно.",
	"tutorial.sin_bar":       "Гріх — чорна частина тебе. Накопичується від ударів, смертей, угод. Високий гріх змінює кінцівку.",
	# Soul pickup is the moment players need to know about the staff
	# lockout — once a soul is in hand, ⚔ stops working until you
	# either deliver it to the altar or drop it.
	"tutorial.soul_pickup":   "Натисни E щоб підняти душу. Поки несеш душу — ⚔ посох не працює; донеси її до вівтаря або кинь, щоб знову битися.",
	"tutorial.carry_to_exit": "Неси душу до вівтаря зверху рівня. По дорозі: ⚔ посох заблоковано, тому уникай ворогів або стрибай через них.",
	"tutorial.enemy_avoid":   "Ворог поряд. Обходь, перестрибуй або бий ⚔ посохом — але удар додасть гріх.",
	"tutorial.enemy_gives_up":"Якщо тікаєш достатньо довго — ворог здається і повертається на свій маршрут.",
	"tutorial.one_way":       "Платформа однонаправлена: стрибай ↑ крізь неї знизу. Натисни ↓ щоб впасти крізь, коли стоїш зверху.",
	"tutorial.crumbling":     "Платформа розкришиться через секунду після приземлення — не затримуйся, шукай наступну точку.",
	"tutorial.faith_platform":"Тримай 🙏 щоб ця платформа стала твердою. Витрачає віру — слідкуй за лічильником.",
	"tutorial.soul_bridge":   "Душа в руках перетворюється на міст. Кинь її через прірву — пройдеш по ній.",
	"tutorial.hidden_souls":  "✦ Приховані душі — напівпрозорі, шукай у тіні платформ. Куплене вміння Чуття Душ підсвічує їх.",
	"tutorial.sleeping_soul": "Спляча душа — натисни E щоб почати мінігру. Уважно дивись на іконку, вона підкаже коли діяти.",
	"tutorial.minigame_watch_icon": "Дивись на іконку у центрі мінігри — вона показує коли і яку клавішу натиснути.",
	"tutorial.mimic_warning": "Не всі душі справжні. Деякі — міміки: вдарять, як тільки доторкнешся. Уважно дивись на форму.",
	"tutorial.mimic_exorcism":"Удар ⚔ посохом по міміку вигоняє його. Гріх це не додає — це праведна дія.",
	# Bonus pickups — fired by DiscoveryHints when one comes within
	# 150 px of the player for the first time on this save.
	"tutorial.bonus_holy_water":     "💧 Свята вода — невразливість 5 секунд",
	"tutorial.bonus_prayer_stone":   "🪨 Молитовний камінь — заморожує ворогів 8 секунд",
	"tutorial.bonus_angel_feather":  "🪶 Янгольське перо — подвійний стрибок на 30 секунд",
	"tutorial.bonus_manna":          "✨ Манна — відновлює 1 серце",
	"tutorial.bonus_torch":          "🔦 Факел Надії — освітлює темряву",
	# Discoverable platforms not already covered by the hand-tuned
	# tutorial.* set above. Triggered when one comes within ~180 px
	# of the player on first encounter.
	"tutorial.plat_bounce":     "Платформа-пружина підкине тебе високо вгору",
	"tutorial.plat_sin":        "Гріховна платформа — стояти на ній додає гріх",
	"tutorial.plat_illusory":   "Ілюзорна платформа зникає під ногами через мить",
	"tutorial.plat_ash":        "Попіл — поверхня слизька, не зупинишся одразу",
	"tutorial.plat_ice":        "Лід — ще слизькіше, інерція велика",
	"tutorial.plat_mud":        "Багно сповільнює рух",
}


func _fallback_for(key: String) -> String:
	return String(_FALLBACK_TEXT.get(key, key))


# ── Display ───────────────────────────────────────────────────────────────────

func _display(hint_id: String) -> void:
	var cfg: Dictionary = _triggers.get(hint_id, {})
	# Ad-hoc passthrough: if no trigger config exists but the id is
	# a Loc key (starts with "tutorial."), treat the id itself as
	# the text_key so DiscoveryHints / arbitrary callers can show a
	# hint without registering a config entry.
	if cfg.is_empty() and hint_id.begins_with("tutorial."):
		cfg = {"text_key": hint_id}
	# Resolve display text. The config supports two shapes:
	#   • "text"      → direct Ukrainian fallback (legacy)
	#   • "text_key"  → dot-notation Loc key, e.g. "tutorial.move"
	# When a `text_key` is given we MUST call Loc.t() — otherwise the
	# UI ends up rendering the literal key string ("tutorial.move")
	# which is what the player was complaining about (no readable
	# tutorial text at all).
	var text: String = ""
	if cfg.has("text") and not String(cfg["text"]).is_empty():
		text = String(cfg["text"])
	elif cfg.has("text_key") and not String(cfg["text_key"]).is_empty():
		var key: String = String(cfg["text_key"])
		var loc: Node = get_node_or_null("/root/Loc")
		if loc and loc.has_method("t"):
			var resolved: String = String(loc.t(key))
			# Loc.t() returns the key itself when the entry is missing —
			# fall through to a clearer fallback in that case so the
			# player sees something readable instead of a path.
			text = resolved if resolved != key else _fallback_for(key)
		else:
			text = _fallback_for(key)
	else:
		text = hint_id

	# Adaptive duration: longer hints get more reading time. Average
	# reader does ~3 words/sec including comprehension, so a 16-word
	# sin-bar hint needs ~5-6 s, not the legacy 4 s default. Min 5 s
	# even for very short hints so the player has time to look up.
	var base_dur: float = float(cfg.get("duration",
		_settings.get("hint_display_duration", 5.0)))
	var word_count: int = text.split(" ", false).size()
	var reading_dur: float = clamp(float(word_count) * 0.45, 5.0, 12.0)
	var dur: float = maxf(base_dur, reading_dur)
	var fade_in: float  = float(_settings.get("hint_fade_in",  0.3))
	var fade_out: float = float(_settings.get("hint_fade_out", 0.5))

	_active_id  = hint_id
	_is_showing = true
	_label.text = text
	_root.modulate.a = 0.0
	_layer.visible   = true
	_reposition_panel()

	_mark_seen(hint_id)
	hint_shown.emit(hint_id)

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, fade_in)
	_tween.tween_interval(dur)
	_tween.tween_property(_root, "modulate:a", 0.0, fade_out)
	_tween.tween_callback(_on_finished)

func _do_dismiss() -> void:
	if not _is_showing:
		return
	var fade_out: float = float(_settings.get("hint_fade_out", 0.5))
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, fade_out * 0.5)
	_tween.tween_callback(_on_finished)

# Per-frame nudge so the panel keeps dodging the player as they move
# (e.g. hint shows mid-jump → player lands inside the top band).
func _process(_delta: float) -> void:
	if _is_showing:
		_reposition_panel()


# Choose a top-zone or bottom-zone Y for the hint panel based on the
# player's current screen position. Default is the existing top band
# (170-290 px below the level info row). If the player's screen-Y
# enters that band ± _PLAYER_PAD, slide the panel BELOW the player.
# If even the below-player slot would overlap the mobile control HUD
# at the bottom, fall back to a position ABOVE the player. Worst case
# (player fills the whole viewport — shouldn't happen in normal play)
# we keep the default and accept the overlap rather than hide off-screen.
func _reposition_panel() -> void:
	if _panel == null or _root == null or not _root.is_inside_tree():
		return
	var top := _DEFAULT_TOP
	var bottom := _DEFAULT_BOTTOM
	var player := _find_player()
	if player != null:
		var vp_size: Vector2 = _root.get_viewport_rect().size
		var player_y: float = player.get_global_transform_with_canvas().origin.y
		var collides_top := player_y > (top - _PLAYER_PAD) \
				and player_y < (bottom + _PLAYER_PAD)
		if collides_top:
			# Try below-player first.
			var below_top: float = player_y + _PLAYER_PAD
			var below_bottom: float = below_top + _PANEL_HEIGHT
			if below_bottom <= vp_size.y - _MOBILE_HUD_BOTTOM_RESERVE:
				top = below_top
				bottom = below_bottom
			else:
				# Below would clip into the mobile controls — go above.
				bottom = max(player_y - _PLAYER_PAD, _PANEL_HEIGHT + 20.0)
				top = bottom - _PANEL_HEIGHT
				if top < 20.0:
					top = _DEFAULT_TOP
					bottom = _DEFAULT_BOTTOM
	_panel.offset_top    = top
	_panel.offset_bottom = bottom


func _find_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes: Array = tree.get_nodes_in_group("player")
	for n in nodes:
		if n is Node2D:
			return n as Node2D
	return null


func _on_finished() -> void:
	_layer.visible = false
	_root.modulate.a = 0.0
	var finished_id := _active_id
	_active_id  = ""
	_is_showing = false
	hint_dismissed.emit(finished_id)

	# Show next queued hint after a short gap
	if _queue.size() > 0:
		var next: String = _queue.pop_front()
		get_tree().create_timer(0.3).timeout.connect(
			func() -> void: show_hint(next), CONNECT_ONE_SHOT
		)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _is_seen(hint_id: String) -> bool:
	return SaveManager.is_hint_seen(hint_id) if SaveManager else false

func _always_show(hint_id: String) -> bool:
	return bool(_triggers.get(hint_id, {}).get("show_every_time", false))

func _mark_seen(hint_id: String) -> void:
	if _always_show(hint_id):
		return
	if SaveManager:
		SaveManager.mark_hint_seen(hint_id)

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer   = 12
	_layer.visible = false
	add_child(_layer)

	# Full-screen root control — this is what we tween for modulate
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a   = 0.0
	_layer.add_child(_root)

	# Pill panel — TOP-center, just below the level info row.
	# Bottom placement was hidden behind mobile controls (←↑→) and
	# the sin bar on portrait phones, so the player never read the
	# tutorial. Top-center is the same eye-line they already use for
	# soul/level info, so the hint actually lands.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top    = 170.0     # below the level info (~y=70-100)
	panel.offset_bottom = 290.0     # ~120 px tall fits 2-3 lines
	panel.offset_left   = 60.0
	panel.offset_right  = -60.0
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.06, 0.90)
	style.corner_radius_top_left     = 18
	style.corner_radius_top_right    = 18
	style.corner_radius_bottom_left  = 18
	style.corner_radius_bottom_right = 18
	style.border_color = Color(0.30, 0.28, 0.40, 0.80)
	for side in ["left","right","top","bottom"]:
		style.set("border_width_" + side, 1)
	style.content_margin_left   = 24.0
	style.content_margin_right  = 24.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)
	_panel = panel

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	# Bumped from 15 → 22 px. The previous size was illegible on the
	# 1080×1920 portrait builds — players literally couldn't read the
	# hint even when they noticed the panel.
	_label.custom_minimum_size  = Vector2(720, 0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.86))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	panel.add_child(_label)
