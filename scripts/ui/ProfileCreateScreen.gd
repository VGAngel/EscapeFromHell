extends CanvasLayer

# First-launch onboarding: forces a profile to exist before MainMenu
# is reachable. Triggered when SaveManager.has_any_profiles() == false,
# either on a fresh install or after the last remaining profile has
# been deleted.
#
# Differences from ProfileScreen (which manages 3 slots in steady state):
#   * blocks Esc / hardware-back so the player can't bypass it
#   * single name input + single primary CTA — minimal cognitive load
#   * inline validation feedback as the player types
#   * always uses the first empty slot (typically slot 0)
#   * fades in from black instead of a softer overlay — reads as a
#     full-screen state, not a popup over the menu
#
# Emits `created(slot, name)` once the profile is persisted; MainMenu
# listens to that and calls _refresh_buttons() / show itself.

signal created(slot: int, name: String)

const FADE_DURATION := 0.35
const PAL := preload("res://scripts/ui/Palette.gd")


var _root: ColorRect = null
var _name_edit: LineEdit = null
var _btn_start: Button = null
var _hint_lbl: Label = null
var _name_buffer: String = ""


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 12   # above MainMenu but below router-pushed overlays in normal flow
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.modulate.a = 0.0
	visible = false
	if Loc and Loc.has_signal("language_changed"):
		Loc.language_changed.connect(func(_l: String) -> void: _refresh_labels())


# ── Public API ───────────────────────────────────────────────────────────────

func open() -> void:
	visible = true
	_name_buffer = ""
	if _name_edit:
		_name_edit.text = ""
		_name_edit.grab_focus.call_deferred()
	_refresh_validation()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)


func close() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void: visible = false)


# ── Input — block escape and hardware-back ────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Eat ui_cancel so the player can't dismiss; nothing to go back to.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		# Same logic for Android hardware back: silently swallow.
		# Without this, Godot would default to quit() — surprise exit
		# from an onboarding screen is awful UX.
		get_viewport().set_input_as_handled()


# ── Submit ────────────────────────────────────────────────────────────────────

func _on_submit() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm == null:
		push_warning("ProfileCreateScreen: SaveManager autoload missing")
		return
	if not sm.is_valid_profile_name(_name_buffer):
		_refresh_validation()
		return
	var slot: int = _first_empty_slot(sm)
	if slot < 0:
		# All slots full — caller should have routed to ProfileScreen
		# instead. Defend with a no-op rather than crashing.
		push_warning("ProfileCreateScreen: no empty slots available")
		return
	if sm.create_profile(slot, _name_buffer):
		var nm: String = _name_buffer.strip_edges()
		created.emit(slot, nm)
		close()


func _first_empty_slot(sm: Node) -> int:
	for i in sm.MAX_SLOTS:
		if not sm.has_save(i):
			return i
	return -1


# ── Validation ────────────────────────────────────────────────────────────────

func _refresh_validation() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	var ok: bool = sm != null and sm.is_valid_profile_name(_name_buffer)
	if _btn_start:
		_btn_start.disabled = not ok
	if _hint_lbl:
		var trimmed: String = _name_buffer.strip_edges()
		var min_n: int = sm.PROFILE_NAME_MIN if sm else 3
		var max_n: int = sm.PROFILE_NAME_MAX if sm else 20
		if trimmed.is_empty():
			_hint_lbl.text = _t("profile_create.hint_empty",
					{"min": min_n, "max": max_n},
					"Літери, цифри, пробіли. %d–%d символів." % [min_n, max_n])
			_hint_lbl.add_theme_color_override("font_color", PAL.TEXT_MUTED)
		elif ok:
			_hint_lbl.text = _t("profile_create.hint_ok", {}, "✓ Готово")
			_hint_lbl.add_theme_color_override("font_color", PAL.SUCCESS)
		else:
			_hint_lbl.text = _t("profile_create.hint_invalid",
					{"min": min_n, "max": max_n},
					"Тільки літери/цифри/пробіли, %d–%d символів" % [min_n, max_n])
			_hint_lbl.add_theme_color_override("font_color", PAL.DANGER)


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.02, 0.01, 0.03, 1.0)   # opaque — replaces MainMenu
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.08, 0.96)
	style.border_color = PAL.GOLD
	for side in ["left", "right", "top", "bottom"]:
		style.set("border_width_" + side, 1)
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + corner, 16)
	style.content_margin_left   = 32.0
	style.content_margin_right  = 32.0
	style.content_margin_top    = 28.0
	style.content_margin_bottom = 28.0
	style.shadow_color  = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size   = 10
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var header := Label.new()
	header.theme_type_variation = "TitleLabel"
	header.text = _t("profile_create.title", {}, "👤  Створити профіль")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var sub := Label.new()
	sub.theme_type_variation = "BodyLabel"
	sub.text = _t("profile_create.subtitle", {},
			"Введи ім'я — цей профіль збереже твій прогрес.")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = _t("profile_create.placeholder", {}, "Ваше ім'я")
	_name_edit.max_length = 20
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.text_changed.connect(func(t: String) -> void:
		_name_buffer = t
		_refresh_validation())
	_name_edit.text_submitted.connect(func(_t2: String) -> void: _on_submit())
	vbox.add_child(_name_edit)

	_hint_lbl = Label.new()
	_hint_lbl.add_theme_font_size_override("font_size", 13)
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint_lbl)

	_btn_start = Button.new()
	_btn_start.text = _t("profile_create.btn_start", {}, "▶  Почати")
	_btn_start.custom_minimum_size = Vector2(0, 70)
	_btn_start.add_theme_font_size_override("font_size", 24)
	_btn_start.pressed.connect(_on_submit)
	vbox.add_child(_btn_start)


func _refresh_labels() -> void:
	# Re-render texts that don't auto-rebuild via _refresh_validation.
	# Header / subtitle / placeholder / button label.
	if _root == null:
		return
	# Easiest: tear down and rebuild — the screen is small.
	for child in _root.get_children():
		child.queue_free()
	_build_ui()
	_refresh_validation()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	if Loc and Loc.has_method("t"):
		return String(Loc.t(key, params))
	return fallback if not fallback.is_empty() else key
