extends Control

# ── State definitions ─────────────────────────────────────────────────────────
const STATES := [
	{
		"name":  "Чистий",
		"range": "0–29%",
		"desc":  "Базовий вигляд, м'яке золоте світло",
		"color": Color(1.0, 0.95, 0.5, 1),
		# modulate: легкий золотистий відтінок
		"modulate": Color(1.05, 1.0, 0.88, 1.0),
		"sin_ratio": 0.0,
	},
	{
		"name":  "Скверний",
		"range": "30–59%",
		"desc":  "Очі злегка червоніють, темні прожилки на руках",
		"color": Color(1.0, 0.55, 0.2, 1),
		# modulate: легкий червонуватий, трохи темніше
		"modulate": Color(0.95, 0.88, 0.88, 1.0),
		"sin_ratio": 0.33,
	},
	{
		"name":  "Падений",
		"range": "60–84%",
		"desc":  "Яскраво-червоне ліве око, роги помітніші, мантія темніша",
		"color": Color(0.8, 0.3, 0.9, 1),
		# modulate: темний, фіолетово-червоний
		"modulate": Color(0.80, 0.70, 0.90, 1.0),
		"sin_ratio": 0.66,
	},
	{
		"name":  "Демон",
		"range": "85–100%",
		"desc":  "Обидва ока червоні, темна аура, тріщини на шкірі світяться",
		"color": Color(1.0, 0.15, 0.15, 1),
		# modulate: темно-червоний
		"modulate": Color(0.75, 0.60, 0.65, 1.0),
		"sin_ratio": 1.0,
	},
]

var _sprite: Sprite2D
var _slider: HSlider
var _slider_label: Label
var _state_label: Label
var _desc_label: Label
var _anim_toggle: CheckButton

var _current_sin_ratio: float = 0.0
var _current_modulate: Color = Color.WHITE
var _anim_time: float = 0.0

func _ready() -> void:
	_sprite       = $PlayerSprite
	_slider       = $UI/SinSlider
	_slider_label = $UI/SliderLabel
	_state_label  = $UI/StateLabel
	_desc_label   = $UI/DescLabel
	_anim_toggle  = $UI/AnimToggle

	var shader := load("res://shaders/player_sin.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_sprite.material = mat

	_slider.value_changed.connect(_on_slider_changed)
	_on_slider_changed(0.0)

func _process(delta: float) -> void:
	if _anim_toggle.button_pressed:
		_anim_time += delta * 0.20
		_slider.value = (sin(_anim_time) * 0.5 + 0.5) * 100.0

	# Smooth interpolation for shader uniform and modulate
	var mat := _sprite.material as ShaderMaterial
	_current_sin_ratio = lerp(_current_sin_ratio, _target_sin_ratio, delta * 3.0)
	_current_modulate  = _current_modulate.lerp(_target_modulate, delta * 3.0)
	mat.set_shader_parameter("sin_ratio", _current_sin_ratio)
	_sprite.modulate = _current_modulate

var _target_sin_ratio: float = 0.0
var _target_modulate: Color  = Color.WHITE

func _on_slider_changed(value: float) -> void:
	_slider_label.text = "Гріх: %d%%" % int(value)

	var state: Dictionary
	var lerp_t: float

	if value < 30.0:
		state = STATES[0]
		lerp_t = value / 30.0
		_target_sin_ratio = lerp(0.0, 0.0, lerp_t)
		_target_modulate  = STATES[0]["modulate"]
	elif value < 60.0:
		state = STATES[1]
		lerp_t = (value - 30.0) / 30.0
		_target_sin_ratio = lerp(0.0, 0.33, lerp_t)
		_target_modulate  = (STATES[0]["modulate"] as Color).lerp(STATES[1]["modulate"], lerp_t)
	elif value < 85.0:
		state = STATES[2]
		lerp_t = (value - 60.0) / 25.0
		_target_sin_ratio = lerp(0.33, 0.66, lerp_t)
		_target_modulate  = (STATES[1]["modulate"] as Color).lerp(STATES[2]["modulate"], lerp_t)
	else:
		state = STATES[3]
		lerp_t = (value - 85.0) / 15.0
		_target_sin_ratio = lerp(0.66, 1.0, lerp_t)
		_target_modulate  = (STATES[2]["modulate"] as Color).lerp(STATES[3]["modulate"], lerp_t)

	_state_label.text = "%s  •  %s" % [state["name"], state["range"]]
	_state_label.add_theme_color_override("font_color", state["color"])
	_desc_label.text = state["desc"]
