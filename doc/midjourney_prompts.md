# Midjourney Prompts — Данило (Escape from Hell)

Промпти для генерації ігрових ассетів персонажа Данило — колишній священик, напівдемон.

---

## 1. Загальний вигляд персонажа

```
chibi 2D game character, fallen priest turned half-demon, male, dark tattered priest robes
with torn edges, glowing red left eye and normal right eye, small curved horn on forehead,
ancient wooden staff with golden holy cross, pale skin with dark vein markings on hands,
white hair, soul fragments floating around him, transparent background, full body front view,
concept art, detailed, vibrant colors, fantasy dark RPG style, soft cel shading
--ar 1:1 --v 6
```

---

## 2. Аркуш анімацій (Animation Sheet)

```
2D game character sprite sheet, chibi fallen priest half-demon, white hair, torn dark robes,
glowing red eye, wooden staff with cross, 8 animation poses in row: idle standing, walking,
running, jumping up, falling down, getting hit, swinging staff forward,
carrying glowing soul above head, transparent background, flat colors, black outline,
game asset style, top quality
--ar 4:1 --v 6
```

---

## 3. Порівняння станів (без гріху vs з гріхом)

```
2D chibi game character side by side comparison, fallen priest,
left side: low sin - white glowing eyes, clean robes, soft golden aura, peaceful expression,
right side: high sin - fully red glowing eyes, cracked dark skin markings, dark purple aura,
horns more visible, torn robes darker, same character different states,
transparent background, game concept art
--ar 2:1 --v 6
```

---

## 4. Sprite Sheet для Godot (Idle анімація)

```
2D platformer sprite sheet chibi style, dark priest character with staff, white hair,
glowing red eye, 6 frames idle animation in horizontal row, soft bounce movement,
transparent PNG background, clean black outline, flat shading, game ready asset,
similar to craftpix chibi style
--ar 6:1 --v 6
```

---

## Нотатки

- Для консистентного стилю між усіма зображеннями додай однаковий `--seed XXXXX`
- Стани гріху в грі: 0–29% Чистий (golden aura) → 30–59% Скверний (red veins, dim aura) → 60–100% Корумпований (повна скверна)
- Шейдер переходу між станами: `res://shaders/player_sin.gdshader`
- Анімації в грі: idle, walk, jump, fall, wall_hang, staff_swing, pickup, carry_idle, carry_walk, hurt, death
