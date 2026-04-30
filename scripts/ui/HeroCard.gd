extends PanelContainer

# Hero card on the main menu — shows the player's snapshot at a glance
# so the menu feels like "continue your descent" rather than a cold list
# of buttons.
#
# Layout:
#   ┌────────────────────────────────────────┐
#   │ <profile name>                  Коло X │
#   │                                Рівень Y│
#   │ 👻 Souls 23/100 · ✦ 4/20 · 💡 120      │
#   │ 🏆 Найкращий: 0:42 ★★★ (рівень 7)      │
#   │ 😈 Гріх 18%                            │
#   └────────────────────────────────────────┘
#
# Pure-code (no .tscn) so MainMenu can drop it in via add_child + setup.
# Refresh is cheap — call .refresh() after returning from any overlay.

const PAL := preload("res://scripts/ui/Palette.gd")

const REFRESH_INTERVAL := 1.0   # poll-based refresh while visible

var _name_lbl: Label = null
var _circle_lbl: Label = null
var _level_lbl: Label = null
var _souls_lbl: Label = null
var _best_lbl: Label = null
var _sin_lbl: Label = null
var _poll_t: float = 0.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Custom card styling — flat DarkPanel was a black-on-black box
	# that disappeared into the menu background. We replace it with a
	# layered look: drop shadow underneath, gold-rim StyleBoxFlat,
	# vertical gradient inside, and a soft top-edge glow that gives
	# the card its "elevated reliquary" feel.
	custom_minimum_size = Vector2(0, 0)
	_apply_card_style()
	_build()
	refresh()
	# Re-render labels when the player switches language live.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)


func _on_language_changed(_new_lang: String) -> void:
	refresh()


func _process(delta: float) -> void:
	# Cheap to refresh — saves don't change every frame, but this keeps
	# the card live if the player buys an upgrade from a deep overlay.
	_poll_t += delta
	if _poll_t >= REFRESH_INTERVAL:
		_poll_t = 0.0
		refresh()


# ── Public ────────────────────────────────────────────────────────────────────

func refresh() -> void:
	var loc: Node = get_node_or_null("/root/Loc")
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm == null:
		_set_text(_name_lbl,   "—")
		_set_text(_circle_lbl, "")
		_set_text(_level_lbl,  "")
		_set_text(_souls_lbl,  "SaveManager не доступний")
		_set_text(_best_lbl,   "")
		_set_text(_sin_lbl,    "")
		return

	# Name
	var name_text: String = _t(loc, "hero_card.name_unknown")
	if sm.has_method("get_profile_name"):
		var pn: String = String(sm.get_profile_name())
		if not pn.is_empty():
			name_text = pn
	_set_text(_name_lbl, name_text)

	# Progress
	var current_level: int = int(sm.get_current_level()) if sm.has_method("get_current_level") else 1
	var current_circle: int = int(sm.get_current_circle()) if sm.has_method("get_current_circle") else 1
	_set_text(_circle_lbl, _t(loc, "hero_card.circle_format", {"n": current_circle}))
	_set_text(_level_lbl,  _t(loc, "hero_card.level_format",  {"n": current_level}))

	# Souls / hidden / light
	var souls: int = int(sm.get_total_souls()) if sm.has_method("get_total_souls") else 0
	var hidden_count: int = int(sm.get_total_hidden_souls()) if sm.has_method("get_total_hidden_souls") else 0
	var light: int = int(sm.get_light()) if sm.has_method("get_light") else 0
	_set_text(_souls_lbl, _t(loc, "hero_card.stats_format",
			{"souls": souls, "hidden": hidden_count, "light": light}))

	# Best level — search 1..100, max stars then min time tiebreaker.
	_set_text(_best_lbl, _format_best(sm, loc))

	# Sin
	if sm.has_method("get_sin"):
		var sin_pct: int = int(sm.get_sin())
		_sin_lbl.add_theme_color_override("font_color", _sin_color(sin_pct))
		_set_text(_sin_lbl, _t(loc, "hero_card.sin_format", {"pct": sin_pct}))


# Loc.t() with hardcoded fallback so unit tests without Loc autoload
# don't crash. Returns the key itself if Loc is missing — test asserts
# can still match by key prefix.
func _t(loc: Node, key: String, params: Dictionary = {}) -> String:
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	return key


# ── Helpers ───────────────────────────────────────────────────────────────────

func _format_best(sm: Node, loc: Node) -> String:
	if not sm.has_method("get_level_best"):
		return ""
	var best_id: int = -1
	var best_time: float = INF
	var best_stars: int = 0
	for lid in range(1, 101):
		var b: Dictionary = sm.get_level_best(lid)
		if b.is_empty():
			continue
		var s: int = int(b.get("stars", 0))
		var t: float = float(b.get("time", INF))
		if s > best_stars or (s == best_stars and t < best_time):
			best_stars = s
			best_time = t
			best_id = lid
	if best_id < 0:
		return _t(loc, "hero_card.best_none")
	return _t(loc, "hero_card.best_format", {
		"time":  _format_time(best_time),
		"stars": _stars(best_stars),
		"level": best_id,
	})


func _format_time(seconds: float) -> String:
	if seconds == INF:
		return "—"
	var s: int = int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]


func _stars(n: int) -> String:
	const FULL := "★"
	const EMPTY := "☆"
	var out := ""
	for i in 3:
		out += FULL if i < n else EMPTY
	return out


# Sin color goes from green → yellow → red as % climbs. Keeps the
# card readable: 0% green, 50% yellow, 100% red.
func _sin_color(pct: int) -> Color:
	var p: float = clamp(float(pct) / 100.0, 0.0, 1.0)
	if p < 0.5:
		return PAL.SUCCESS.lerp(PAL.WARNING, p * 2.0)
	return PAL.WARNING.lerp(PAL.SIN_RED, (p - 0.5) * 2.0)


func _set_text(lbl: Label, text: String) -> void:
	if lbl != null:
		lbl.text = text


# ── Card chrome ───────────────────────────────────────────────────────────────

# Override the default DarkPanel theme variation with a custom
# StyleBoxFlat: deep purple-black bg, thin gold rim at alpha 0.35,
# 14 px corner radius, drop shadow underneath. The vertical gradient
# itself rides on a separate ColorRect inserted below the layout
# (StyleBoxFlat doesn't support gradients natively).
func _apply_card_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.03, 0.07, 0.92)
	style.border_color = Color(1.0, 0.84, 0.30, 0.40)   # gold rim
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left     = 14
	style.corner_radius_top_right    = 14
	style.corner_radius_bottom_left  = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left   = 18.0
	style.content_margin_right  = 18.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	# Drop shadow — gives the card its "elevated" feel without
	# leaking into the Play button below. Earlier values (size 14,
	# offset y=4) extended ~18 px beneath the card edge and ate the
	# 9-30 px gap to ButtonsContainer (worse with the ad banner
	# active). Tighter values keep the lift but stay within the
	# rect's natural footprint.
	style.shadow_color  = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size   = 6
	style.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", style)


# Adds a top-edge inner glow + procedural noise overlay so the
# rectangle reads as a piece of weathered material instead of a
# flat shape. Invoked from _build() AFTER the children exist so
# we can move it to the bottom of the z-order.
func _install_gradient_layer() -> void:
	# Top inner glow — soft gold band fading down ~80 px. Sits inside
	# the panel, BELOW the text layout so labels stay legible.
	var glow := ColorRect.new()
	glow.name = "TopGlow"
	glow.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glow.offset_top    = 0.0
	glow.offset_bottom = 80.0
	glow.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var glow_sh := Shader.new()
	glow_sh.code = """
shader_type canvas_item;
void fragment() {
	float v = pow(1.0 - UV.y, 2.5) * 0.18;
	COLOR = vec4(1.0, 0.85, 0.40, v);
}
"""
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = glow_sh
	glow.material = glow_mat
	add_child(glow)
	move_child(glow, 0)

	# Subtle parchment noise overlay — covers the whole card. Very
	# low alpha (3-5%) so it just adds tactile texture, not pattern.
	var noise := ColorRect.new()
	noise.name = "ParchmentNoise"
	noise.set_anchors_preset(Control.PRESET_FULL_RECT)
	noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var noise_sh := Shader.new()
	noise_sh.code = """
shader_type canvas_item;
// Hash-based pseudo-noise — no texture asset needed.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	float n = hash(floor(UV * 240.0));
	// Vignette: stronger at the edges so the centre reads cleanly.
	vec2 d = UV - vec2(0.5);
	float vign = smoothstep(0.30, 0.85, length(d));
	float a = (n - 0.5) * 0.06 + vign * 0.05;
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""
	var noise_mat := ShaderMaterial.new()
	noise_mat.shader = noise_sh
	noise.material = noise_mat
	add_child(noise)
	move_child(noise, 1)


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	# Decorative layers go in first so MarginContainer ends up on top.
	_install_gradient_layer()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	# Tighter top/bottom + row separation so the card fits in the
	# 196 px strip between TitleLabel and ButtonsContainer.
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	margin.add_child(v)

	# Top row: profile name | Circle/Level (right-aligned)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)

	_name_lbl = Label.new()
	_name_lbl.theme_type_variation = "TitleLabel"
	_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name_lbl)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(stack)

	_circle_lbl = Label.new()
	_circle_lbl.theme_type_variation = "BodyLabel"
	_circle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(_circle_lbl)

	_level_lbl = Label.new()
	_level_lbl.theme_type_variation = "BodyLabel"
	_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(_level_lbl)

	# Separator
	var sep := HSeparator.new()
	sep.theme_type_variation = "GoldSeparator"
	v.add_child(sep)

	# Souls / hidden / light row
	_souls_lbl = Label.new()
	_souls_lbl.theme_type_variation = "ValueLabel"
	v.add_child(_souls_lbl)

	# Best run
	_best_lbl = Label.new()
	_best_lbl.theme_type_variation = "BodyLabel"
	v.add_child(_best_lbl)

	# Sin
	_sin_lbl = Label.new()
	_sin_lbl.theme_type_variation = "BodyLabel"
	v.add_child(_sin_lbl)
