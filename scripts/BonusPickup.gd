extends Area2D

const SIZE: float = 40.0   # diameter px; collision radius = SIZE / 2 in BonusPickup.tscn

enum BonusType {
	HOLY_WATER,    # 0 — невразливість 5с
	PRAYER_STONE,  # 1 — заморожує ворогів 8с
	ANGEL_FEATHER, # 2 — тимчасовий подвійний стрибок 30с
	MANNA,         # 3 — відновлює 1 серце
	TORCH,         # 4 — освітлення (майбутнє)
}

const NAMES: Array[String] = [
	"Свята вода",
	"Молитовний камінь",
	"Янгольське перо",
	"Манна",
	"Факел Надії",
]

const TEXTURES: Array[String] = [
	"res://Assets/OurAssets/bonus_holy_water.png",
	"res://Assets/OurAssets/bonus_prayer_stone.png",
	"res://Assets/OurAssets/bonus_angel_feather.png",
	"res://Assets/OurAssets/bonus_manna.png",
	"res://Assets/OurAssets/bonus_torch.png",
]

const ICONS: Array[String] = ["💧", "🪨", "🪶", "✨", "🔦"]

@export var bonus_type: BonusType = BonusType.MANNA:
	set(value):
		bonus_type = value
		if is_inside_tree():
			_update_sprite()

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _label:  Label    = $Label

signal bonus_collected(type: int, bonus_name: String)

func _ready() -> void:
	_apply_size()
	_update_sprite()
	if Engine.is_editor_hint():
		return
	add_to_group("bonus")
	_label.text = NAMES[bonus_type]
	body_entered.connect(_on_body_entered)

func _apply_size() -> void:
	var col := $CollisionShape2D
	if col and col.shape is CircleShape2D:
		(col.shape as CircleShape2D).radius = SIZE / 2.0

func _update_sprite() -> void:
	var path: String = TEXTURES[bonus_type]
	if ResourceLoader.exists(path):
		$Sprite2D.texture = load(path)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_sprite.position.y = sin(Time.get_ticks_msec() * 0.003) * 6.0

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	bonus_collected.emit(bonus_type, NAMES[bonus_type])
	var tw := create_tween()
	tw.parallel().tween_property(self, "scale", Vector2(1.5, 1.5), 0.15)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)
	set_deferred("monitoring", false)
