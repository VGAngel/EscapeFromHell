extends Control

# sin_ratio targets for each of the 4 display states
const STATE_RATIOS := [0.0, 0.33, 0.66, 1.0]
const STATE_NAMES  := ["Чистий", "Скверний", "Падений", "Демон"]
const STATE_COLORS := [
	Color(1.0, 0.92, 0.4),
	Color(1.0, 0.55, 0.2),
	Color(0.8, 0.3, 0.8),
	Color(1.0, 0.15, 0.15),
]

var _sprites: Array[Sprite2D] = []
var _slider: HSlider
var _slider_label: Label
var _state_label: Label
var _anim_toggle: CheckButton
var _anim_time: float = 0.0

func _ready() -> void:
	_slider       = $SliderRow/SinSlider
	_slider_label = $SliderRow/SliderLabel
	_state_label  = $SliderRow/StateLabel
	_anim_toggle  = $AnimToggle

	_sprites = [
		$CharactersRow/State0/Sprite0,
		$CharactersRow/State1/Sprite1,
		$CharactersRow/State2/Sprite2,
		$CharactersRow/State3/Sprite3,
	]

	var shader := load("res://shaders/player_sin.gdshader") as Shader
	for i in 4:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("sin_ratio", STATE_RATIOS[i])
		_sprites[i].material = mat

	_slider.value_changed.connect(_on_slider_changed)

func _process(delta: float) -> void:
	if _anim_toggle.button_pressed:
		_anim_time += delta * 0.18
		_slider.value = (sin(_anim_time) * 0.5 + 0.5) * 100.0

func _on_slider_changed(value: float) -> void:
	_slider_label.text = "Гріх: %d%%" % int(value)

	var ratio: float
	var state_idx: int
	if value < 30.0:
		ratio = 0.0
		state_idx = 0
	elif value < 60.0:
		ratio = (value - 30.0) / 30.0 * 0.33
		state_idx = 1
	elif value < 85.0:
		ratio = 0.33 + (value - 60.0) / 25.0 * 0.33
		state_idx = 2
	else:
		ratio = 0.66 + (value - 85.0) / 15.0 * 0.34
		state_idx = 3

	# Live sprite (State0 is used as "current sin" preview — all 4 always fixed)
	# Update all sprites slightly toward the live ratio so you can see interpolation
	for i in 4:
		var mat := _sprites[i].material as ShaderMaterial
		mat.set_shader_parameter("sin_ratio", STATE_RATIOS[i])

	_state_label.text = "Поточний стан: %s (sin_ratio = %.2f)" % [STATE_NAMES[state_idx], ratio]
	_state_label.add_theme_color_override("font_color", STATE_COLORS[state_idx])
