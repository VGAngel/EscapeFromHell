# Midjourney Prompts — Soul Asset

## Контекст
- Гра: Escape from Hell (2D мобільний платформер, Android)
- Душа — колектибл що плаває в рівні та з'являється над головою гравця при перенесенні
- Стиль: anime painterly, chibi, м'який glow — в дусі існуючих ассетів (`bonus_angel_feather.png`, `bonus_holy_water.png`)
- Формат: PNG з прозорим фоном, ~256×256

---

## Innocent Soul — тепло-білий дух

> Колір за GDD: "тепло-білий". Звук: тихе сопрано.

```
2D game sprite, floating soul spirit, small translucent human silhouette glowing
warm white-gold, ethereal wisp with soft inner light, gentle flowing energy wisps
around it, tiny sad face barely visible, soft particles floating upward,
dark transparent background, anime painterly style, game collectible asset,
chibi cute proportions, melancholic and pure aura, no hard outlines,
soft luminous glow, 256x256 pixel art icon style

--style raw --ar 1:1 --v 6.1 --no shadow, no background, no border
```

---

## Sleeping Soul — теплий золотий, очі закриті

> Тип: Спляча. Не знає що померла.

```
2D game sprite, floating soul spirit, small glowing golden-warm ghost silhouette,
closed eyes peaceful expression, dreamy soft haze around it, slow energy wisps,
sleeping aura, particles like fireflies, dark transparent background,
anime painterly chibi style, game collectible, serene, gentle

--style raw --ar 1:1 --v 6.1 --no background
```

---

## Mimic Soul — фіолетово-сірий, тінь неправильна

> Колір за GDD: "злегка фіолетовий". Підказка: тінь вказує не в той бік.

```
2D game sprite, soul mimic spirit, small glowing slightly purple-grey ghost
silhouette, unsettling calm expression, shadow pointing wrong direction,
faint purple inner light, irregular subtle pulse glow, dark particles,
dark transparent background, anime painterly chibi style,
eerie but subtle, almost looks normal

--style raw --ar 1:1 --v 6.1 --no background
```

---

## Workflow після генерації

1. Генеруємо базовий PNG в Midjourney
2. Видаляємо фон через [remove.bg](https://remove.bg)
3. Підставляємо в `scenes/Soul.tscn` замість `Assets/hellAssets/Collectable Object/Light.png`
4. Пульс — через tween в `scripts/Soul.gd` (не потрібен sprite sheet):

```gdscript
func _ready() -> void:
    var tween = create_tween().set_loops()
    tween.tween_property($Sprite2D, "modulate:a", 0.5, 0.8)
    tween.tween_property($Sprite2D, "modulate:a", 1.0, 0.8)
```
