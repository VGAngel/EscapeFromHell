@tool
extends Area2D

enum BonusType {
	HOLY_WATER,    # 0 — невразливість 5с
	PRAYER_STONE,  # 1 — заморозка ворогів (placeholder)
	ANGEL_FEATHER, # 2 — подвійний стрибок
	MANNA,         # 3 — відновлює 1 серце
	TORCH,         # 4 — освітлює темну локацію
}

@export var bonus_type: BonusType = BonusType.MANNA:
	set(value):
		bonus_type = value
		if is_inside_tree():
			_update_sprite()

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label:  Label    = $Label

const NAMES: Array[String] = [
	"Свята вода",
	"Молитовний камінь",
	"Янгольське перо",
	"Манна",
	"Факел Надії",
]

const TEXTURES: Array[String] = [
	"res://Assets/MyAssets/bonus_holy_water.png",
	"res://Assets/MyAssets/bonus_prayer_stone.png",
	"res://Assets/MyAssets/bonus_angel_feather.png",
	"res://Assets/MyAssets/bonus_manna.png",
	"res://Assets/MyAssets/bonus_torch.png",
]

signal bonus_collected(type: int, bonus_name: String)

func _ready() -> void:
	_update_sprite()
	if Engine.is_editor_hint():
		return
	add_to_group("bonus")
	_label.text = NAMES[bonus_type]
	body_entered.connect(_on_body_entered)

func _update_sprite() -> void:
	var sprite := $Sprite2D as Sprite2D
	if sprite:
		sprite.texture = load(TEXTURES[bonus_type])

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_sprite.position.y = sin(Time.get_ticks_msec() * 0.003) * 6.0

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		bonus_collected.emit(bonus_type, NAMES[bonus_type])
		queue_free()
