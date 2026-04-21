extends Control

# Scene: res://scenes/Hub.tscn
# Shown before every level. Skippable via "Пропустити".
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
#   ├── BtnSkip          (Button)
#   ├── UpgradesScreen   (CanvasLayer) ← scripts/ui/UpgradesScreen.gd
#   └── CollectionScreen (CanvasLayer) ← scripts/ui/CollectionScreen.gd

# ── Constants ─────────────────────────────────────────────────────────────────
const MSG_AUTO_HIDE       := 8.0
const FADE_DURATION       := 0.4
const SKIP_HOLD_DURATION  := 2.0
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

# Prologue lines: [speaker, text, pause_after]
const PROLOGUE := [
	["narration", "Ти падав довго. Довше ніж здавалось можливим.\nВнизу не було нічого. Тільки тепло.\nІ голос.", 3.5],
	["god",    "Отче Данило.", 1.5],
	["god",    "Так. Я знаю що ти зробив. І знаю чому.", 0.8],
	["god",    "Ти зневірився. Це не найгірший гріх зі всіх що я бачив тут.", 0.8],
	["god",    "Але ти священник. Від тебе очікували більшого. Від тебе очікував більшого ти сам.", 1.2],
	["god",    "В пеклі є 100 душ що потрапили туди помилково. Бюрократія — навіть тут вона існує.", 0.8],
	["god",    "Я міг би виправити це сам. Але не виправлю.", 1.5],
	["god",    "Ти підеш замість мене.", 1.2],
	["player", "Я не переживу там і хвилини.", 0.8],
	["god",    "Знаю.", 1.8],
	["god",    "Тому я дам тобі те що потрібно щоб вижити. Але попереджаю — це буде боляче носити в собі.", 1.2],
	["god",    "Частина пекла тепер в тобі. Ти відчуєш це. Ти будеш хотіти використати це.", 0.8],
	["god",    "Не забувай хто ти є. Був. Хочеш бути знову.", 1.2],
	["player", "А якщо я знайду всіх 100?", 0.8],
	["god",    "Тоді подивимось що залишилось від священника Данила.", 2.0],
	["god",    "Йди. Вони чекають.", 0.8],
]

# ── Child nodes ───────────────────────────────────────────────────────────────
@onready var _bg:             Control       = $Background
@onready var _god_portrait:   Control       = $GodPortrait
@onready var _player_portrait:Control       = $PlayerPortrait
@onready var _msg_box:        PanelContainer= $MessageBox
@onready var _msg_label:      Label         = $MessageBox/Label
@onready var _msg_speaker:    Label         = $MessageBox/Speaker
@onready var _bottom_bar:     HBoxContainer = $BottomBar
@onready var _btn_upgrades:   Button        = $BottomBar/BtnUpgrades
@onready var _btn_souls:      Button        = $BottomBar/BtnSouls
@onready var _btn_continue:   Button        = $BottomBar/BtnContinue
@onready var _btn_skip:       Button        = $BtnSkip
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
	_btn_skip.pressed.connect(_on_skip)

	_upgrades.closed.connect(_on_upgrades_closed)
	_collection.closed.connect(_on_collection_closed)

	_setup_continue_label()
	_refresh_currency()
	_build_skip_indicator()

	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_DURATION)
	tw.tween_callback(_on_fade_in_done)

func _on_fade_in_done() -> void:
	if not _prologue_done and _next_level_id == 1:
		_start_prologue()
	else:
		_show_hub()

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
	_btn_skip.visible   = true
	_god_portrait.visible    = true
	_player_portrait.visible = true
	_show_god_message()

func _setup_continue_label() -> void:
	var circle: int = ceili(float(_next_level_id) / 10.0)
	_btn_continue.text = "Далі →\nКоло %d • Рівень %d" % [circle, _next_level_id]

func _refresh_currency() -> void:
	var light: int = SaveManager.get_light() if SaveManager else 0
	_btn_upgrades.text = "💡 %d\nАпгрейди" % light

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

	var sin: float   = SaveManager.get_sin()
	var souls: int   = SaveManager.get_total_souls()
	var level: int   = _next_level_id

	# Conditional checks (priority order)
	if SaveManager.get_demon_deals_accepted() > SaveManager.get_deals_refused():
		return {"text": "Я бачив. Нічого не кажу. Просто бачив.", "style": "quiet"}
	if sin > 70.0:
		return {"text": "Данило. Я ще тут. Але ти йдеш не в той бік.", "style": "warning"}
	if souls == 99:
		return {"text": "Одна залишилась. Остання завжди найважча. Не через пекло — через тебе.", "style": "solemn"}

	# Soul milestones
	for milestone in [99, 75, 50, 25, 10]:
		if souls >= milestone:
			var milestone_msgs := {
				10:  {"text": "Десять. Вони вже у безпеці. Продовжуй.",         "style": "warm"},
				25:  {"text": "Чверть шляху. Пам'ятаєш їхні імена?",            "style": "personal"},
				50:  {"text": "Половина. Вони чекали на тебе довго.",            "style": "solemn"},
				75:  {"text": "75 душ. Я не очікував що ти зайдеш так далеко.", "style": "surprised"},
				99:  {"text": "Одна залишилась. Остання завжди найважча.",       "style": "solemn"},
			}
			if SaveManager.is_hint_seen("soul_milestone_%d" % milestone):
				continue
			SaveManager.mark_hint_seen("soul_milestone_%d" % milestone)
			return milestone_msgs[milestone]

	# By level (exact match)
	var level_msgs := {
		1:   {"text": "Передпокій. Тут ще є тиша. Скористайся цим — далі її не буде.",                             "style": "calm"},
		2:   {"text": "Ти вже знаєш як падати. Тепер навчись зупинятись вчасно.",                                  "style": "calm"},
		5:   {"text": "Перша втеча. Не соромно тікати від того що сильніше. Соромно не повернутись.",               "style": "calm"},
		10:  {"text": "Перший охоронець позаду. Попереду гірше. Але ти вже знаєш що гірше — не значить неможливо.", "style": "solemn"},
		11:  {"text": "Болота. Тут гинуть не від болю — від непевності. Кожен крок перевіряй.",                     "style": "calm"},
		20:  {"text": "Друге Коло пройдено. Ти змінився трохи. Я бачу. Не кажу чи на краще.",                      "style": "observing"},
		25:  {"text": "Чверть шляху. Вони вже у безпеці. Данило — ти пам'ятаєш їхні імена?",                       "style": "personal"},
		30:  {"text": "Третє Коло позаду. Вогонь більше не лякає тебе так як раніше. Це добре. І погано.",          "style": "observing"},
		50:  {"text": "Половина. Подивись на себе. Пам'ятаєш яким ти був коли падав?",                             "style": "personal"},
		75:  {"text": "75 душ. Три чверті. Я не очікував що ти зайдеш так далеко.",                                "style": "surprised"},
		90:  {"text": "Дев'яте Коло позаду. Данило... я пишаюсь. Хоча й не повинен цього казати.",                 "style": "warm"},
		91:  {"text": "Трон попереду. Він знає що ти тут. Він чекав когось такого як ти.",                          "style": "warning"},
		99:  {"text": "Остання кімната перед ним. Що б не сталось далі — ти вже зробив більше ніж я просив.",       "style": "warm"},
		100: {"text": "Я більше нічого не скажу. Це твій момент. Не мій.",                                         "style": "silent"},
	}
	if level_msgs.has(level):
		return level_msgs[level]

	return {}

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
	match speaker:
		"god":    return "Бог"
		"player": return "Данило"
	return ""

# ── Prologue ──────────────────────────────────────────────────────────────────

func _start_prologue() -> void:
	_in_prologue = true
	_bottom_bar.visible   = false
	_btn_skip.visible     = false
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
	var text:    String = line[1]
	var pause:   float  = line[2]
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
	_btn_skip.disabled      = not enabled

func _on_continue() -> void:
	_fade_out_and_load()

func _on_skip() -> void:
	_fade_out_and_load()

func _fade_out_and_load() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		GameManager.load_next_level() if GameManager else \
			get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")
	)
