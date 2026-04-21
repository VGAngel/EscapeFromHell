extends CanvasLayer

# Placeholder privacy policy screen — opened from Settings/MainMenu.
# Final text must be reviewed before store submission; keep the scope
# conservative (app-level saves, ad SDK, IAP) so it matches actual data
# handling at release time.

signal closed

const FADE_DURATION := 0.25

# Hardcoded Ukrainian copy with English block underneath — both locales
# need to be visible in-app per Play Store / App Store requirements.
const BODY_UA := """Остання редакція: 2026-04-21

1. Які дані збираємо
Ігровий прогрес зберігається локально на пристрої (current_level, sin, light, upgrades, saved_soul_ids). Жодні персональні дані ми не передаємо на сервер.

2. Реклама
Інтерстиціальні та reward-ролики надаються стороннім SDK. Може передаватись анонімний ідентифікатор пристрою для таргетингу.

3. IAP
Покупки обробляються Google Play / App Store. Ми не зберігаємо платіжних даних.

4. Контакт
valentin.polischuk@dreamplay.games"""

const BODY_EN := """Last updated: 2026-04-21

1. Data we collect
Game progress is stored locally (current_level, sin, light, upgrades, saved_soul_ids). No personal data is sent to our servers.

2. Ads
Interstitial and reward videos are served by a third-party SDK. An anonymous device id may be shared for targeting.

3. In-app purchases
Handled by Google Play / App Store. We do not store payment data.

4. Contact
valentin.polischuk@dreamplay.games"""

var _root: ColorRect = null

func _ready() -> void:
	layer = 12
	_build_ui()
	visible = false
	_root.modulate.a = 0.0

func open() -> void:
	visible = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func close() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit())

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.04, 0.03, 0.06, 0.97)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",  24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top",   24)
	margin.add_theme_constant_override("margin_bottom", 80)
	_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)

	var title := Label.new()
	title.text = "Політика конфіденційності"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.95))
	hdr.add_child(title)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(40, 40)
	btn_close.add_theme_font_size_override("font_size", 18)
	var empty := StyleBoxEmpty.new()
	for state in ["normal","hover","pressed","focus"]:
		btn_close.add_theme_stylebox_override(state, empty)
	btn_close.add_theme_color_override("font_color", Color(0.55, 0.52, 0.62))
	btn_close.pressed.connect(close)
	hdr.add_child(btn_close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 18)
	scroll.add_child(text_box)

	for body in [BODY_UA, BODY_EN]:
		var lbl := Label.new()
		lbl.text = body
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.82, 0.80, 0.86))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size.x = 640
		text_box.add_child(lbl)
