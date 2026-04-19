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

## 5. Чотири стани гріху — окремі спрайти (game ready)

Система візуальних станів реалізована через **4 окремі спрайти** + crossfade шейдер.
Кожен спрайт потрібен у однаковій позі (idle front view), прозорий фон PNG.

### Стан 1 — Чистий (0–29% гріху)
```
chibi 2D game ready character sprite, fallen priest, CLEAN STATE, white hair,
soft golden aura glow around body, calm normal eyes with subtle white light,
clean dark priest robes, gentle holy light particles, peaceful expression,
transparent background, flat cel shading, black outline, craftpix chibi style
--ar 1:2 --v 6
```
Файл: `Assets/OurAssets/player_clean.png`

### Стан 2 — Скверний (30–59% гріху)
```
chibi 2D game ready character sprite, fallen priest, TAINTED STATE, white hair,
eyes slightly glowing red, faint dark purple vein markings on hands and neck,
robes slightly darker, dim flickering golden aura fading away, uneasy expression,
transparent background, flat cel shading, black outline, craftpix chibi style
--ar 1:2 --v 6
```
Файл: `Assets/OurAssets/player_tainted.png`

### Стан 3 — Падений (60–84% гріху)
```
chibi 2D game ready character sprite, fallen priest, FALLEN STATE, white hair,
LEFT eye brightly glowing red, small horn more visible on forehead,
dark robes with shadow wisps, prominent dark vein markings, dark purple aura,
right eye still normal, conflicted expression,
transparent background, flat cel shading, black outline, craftpix chibi style
--ar 1:2 --v 6
```
Файл: `Assets/OurAssets/player_fallen.png`

### Стан 4 — Демон (85–100% гріху)
```
chibi 2D game ready character sprite, fallen priest, DEMON STATE, white hair,
BOTH eyes fully glowing red, horns clearly visible, glowing cracks on skin,
very dark robes, swirling dark red aura, menacing expression,
transparent background, flat cel shading, black outline, craftpix chibi style
--ar 1:2 --v 6
```
Файл: `Assets/OurAssets/player_demon.png`

---

## Як використовується в грі

| Поріг гріху | Стан | Спрайт | Modulate |
|---|---|---|---|
| 0–29% | Чистий | `player_clean.png` | теплий золотистий |
| 30–59% | Скверний | `player_tainted.png` | злегка червонуватий |
| 60–84% | Падений | `player_fallen.png` | темний фіолетово-червоний |
| 85–100% | Демон | `player_demon.png` | темно-червоний |

**Перехід між станами:** шейдер `res://shaders/player_sin.gdshader` плавно змішує поточний і наступний спрайт через uniform `blend_t` (0→1). Одночасно `modulate` інтерполюється між кольорами станів.

**Важливо для художника:** всі 4 спрайти мають бути:
- Однакові розміри і позиція персонажа
- Прозорий фон (PNG)
- Одна поза (idle, фронтальний вигляд)
- Один стиль і рівень деталізації

---

## Нотатки

- Для консистентного стилю між промптами додай однаковий `--seed XXXXX`
- Анімації в грі: idle, walk, jump, fall, wall_hang, staff_swing, pickup, carry_idle, carry_walk, hurt, death
- Шейдер: `res://shaders/player_sin.gdshader` (crossfade між texture + texture_next)
