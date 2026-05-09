extends CanvasLayer

# Placeholder privacy policy screen — opened from Settings/MainMenu.
# Final text must be reviewed before store submission; keep the scope
# conservative (app-level saves, ad SDK, IAP) so it matches actual data
# handling at release time.
#
# UI lives in scenes/ui/PrivacyPolicy.tscn — open that file in the editor
# to tweak layout, text, colours. This script only handles open/close +
# localisation overrides.

signal closed

const FADE_DURATION := 0.25

# Hardcoded Ukrainian copy with English block underneath — both locales
# need to be visible in-app per Play Store / App Store requirements. The
# scene ships with the same strings; runtime override via Loc.t() lets
# translators swap them without re-saving the .tscn.
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

@onready var _root:    ColorRect = $Backdrop
@onready var _title:   Label     = $Backdrop/Margin/VBox/Header/Title
@onready var _close:   Button    = $Backdrop/Margin/VBox/Header/CloseButton
@onready var _body_ua: Label     = $Backdrop/Margin/VBox/Scroll/TextBox/BodyUA
@onready var _body_en: Label     = $Backdrop/Margin/VBox/Scroll/TextBox/BodyEN

func _ready() -> void:
	layer = 12
	_close.pressed.connect(close)
	_title.text   = _t("privacy_policy.title", {}, "Політика конфіденційності")
	# Body text is bilingual by design (both UA + EN visible per Play Store /
	# App Store rules), so we plant the constants directly rather than route
	# through Loc — there's no key to translate to.
	_body_ua.text = BODY_UA
	_body_en.text = BODY_EN
	visible = false
	_root.modulate.a = 0.0


# Loc.t() with fallback. Use the global `Loc` autoload symbol directly
# instead of get_node_or_null("/root/Loc") so this works from outside
# the active scene tree (unit tests, scene transitions). The absolute-
# path form errored "Can't use get_node() with absolute paths from
# outside the active scene tree" on detached instances.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	if Loc and Loc.has_method("t"):
		return String(Loc.t(key, params))
	return fallback if not fallback.is_empty() else key

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
