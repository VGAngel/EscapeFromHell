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

## 4. MainMenu Parallax Background

`scripts/ui/MenuBackground.gd` будує 3-шарову паралакс-сцену за головним меню.
Перший шар (sky) — procedural shader, без ассету. Другий і третій — це
**опційні TextureRect** які підвантажуються якщо файл існує (в іншому випадку
шар тихо пропускається).

### 4.1 Mid-distance silhouette — `Assets/menu_bg_mid.png`

Дальній план — кафедральні шпилі / готичні арки на тлі червоного неба.
Силуетна графіка, переважно чорна із кривавими акцентами.

```
silhouette parallax background layer for a 2D mobile game,
gothic cathedral with broken spires and twisted arches in deep
shadow, dark crimson sky behind, jagged stone fragments,
hellish atmosphere, dramatic dark fantasy, painterly art style,
mostly black silhouette with dark red rim light, transparent
upper third for sky to show through, no characters, no text,
landscape orientation
--ar 27:16 --v 6
```

**Технічні параметри:**
- Розмір: ~1300×800 px (трохи ширший за viewport 1080 щоб був запас на parallax)
- Format: PNG with alpha (верх 1/3 прозорий, щоб червоне небо просвічувало)
- Файл: `res://Assets/menu_bg_mid.png`

### 4.2 Foreground silhouette — `Assets/menu_bg_near.png`

Передній план — пагорб, скелясті виступи, попіл, чорний камінь. Темніший
за mid-layer.

```
silhouette foreground layer for a 2D dark fantasy mobile game,
craggy black hills with jagged rocks and wisps of ash rising,
broken bones poking out of the soil, deep abyssal red glow at
the bottom, tall vertical aspect of stone formations, painterly
art style, almost pure black silhouette with crimson under-glow,
transparent at top half to layer over a sky background, no
characters, no text, landscape orientation
--ar 27:16 --v 6
```

**Технічні параметри:**
- Розмір: ~1300×600 px
- Format: PNG with alpha (верхні 50% прозорі)
- Файл: `res://Assets/menu_bg_near.png`

### 4.3 (Optional) Static sky texture — `Assets/menu_bg_sky.png`

Якщо procedural FBM shader на L0 не подобається можна замінити статичним
texture. Тоді треба буде відключити sky-shader у `MenuBackground._build_sky`.

```
hellish red sky background for a dark fantasy game, dramatic
crimson and ember orange clouds, smoke and embers drifting,
faint silhouette of horns or wings in distant clouds (very
subtle), painterly cinematic art style, vertical gradient from
deep maroon at top to bright ember at bottom, no characters,
no text, no UI
--ar 9:16 --v 6
```

- Розмір: 1080×1920 px (full viewport)
- Файл: `res://Assets/menu_bg_sky.png`
- Замінити `_build_sky()` на TextureRect з цим файлом, якщо хочеться static look

### Як підключити

1. Згенеруй у Midjourney → завантаж 1300×800 / 1300×600 версії
2. Поклади у `Assets/` під саме ці імена (`menu_bg_mid.png`,
   `menu_bg_near.png`)
3. Перезапусти гру — `MenuBackground._build_silhouette_layer` сам їх
   підхопить + запустить parallax drift
4. Якщо потім захочеш видалити — просто видали файл, шар знову зникне

---

## Нотатки

- Для консистентного стилю між промптами додай однаковий `--seed XXXXX`
- Анімації в грі: idle, walk, jump, fall, wall_hang, staff_swing, pickup, carry_idle, carry_walk, hurt, death
- Шейдер: `res://shaders/player_sin.gdshader` (crossfade між texture + texture_next)
