# Midjourney Prompts — Відсутні ассети

> Джерело: `doc/assets_status.md`
> Лише **візуальні** ассети (Midjourney не генерує аудіо, шейдери, частинки).
> Плеєр та душі вже описані в `midjourney_prompts.md` і `midjourney_soul_prompt.md`.

## Базовий стиль (додавай до кожного промта)

```
chibi anime 2D game art, dark fantasy RPG, flat cel shading, clean black outline,
transparent background, craftpix style, vibrant colors, high detail, game asset ready
--v 6.1 --style raw
```

---

## 1. Player — 4 стани гріху

> Детальні промти: `doc/midjourney_prompts.md` розділ 5.

| Файл | Статус | Посилання |
|------|--------|-----------|
| `Assets/OurAssets/player_clean.png` | ❌ | `midjourney_prompts.md` §5.1 |
| `Assets/OurAssets/player_tainted.png` | ❌ | `midjourney_prompts.md` §5.2 |
| `Assets/OurAssets/player_fallen.png` | ❌ | `midjourney_prompts.md` §5.3 |
| `Assets/OurAssets/player_demon.png` | ❌ | `midjourney_prompts.md` §5.4 |

---

## 2. UI — Іконки та елементи

### 2.1 Серця здоров'я (HP)

Потрібно: 2 варіанти — повне серце та порожнє серце.

```
2D game UI icon set, heart health icons, gothic hellish style, TWO versions side by side:
LEFT - full red glowing heart with inner golden light, holy fire inside, dark outline,
RIGHT - empty cracked dark heart outline, cold grey, lifeless,
pixel art icon style, 64x64 each, transparent background, cel shading, flat colors,
fantasy RPG dark theme, mobile game UI
--ar 2:1 --v 6.1 --style raw
```

Файли: `Assets/OurAssets/ui_heart_full.png`, `Assets/OurAssets/ui_heart_empty.png`

---

### 2.2 Іконка душі (Soul counter)

```
2D game UI icon, small ghost soul spirit icon, warm white-gold glowing silhouette,
tiny floating figure with soft aura, simple design for HUD counter,
clean black outline, 64x64, transparent background, cel shading,
chibi game icon style, legible at small size, mobile game asset
--ar 1:1 --v 6.1 --style raw
```

Файл: `Assets/OurAssets/ui_soul_icon.png`

---

### 2.3 Іконки здібностей

#### Невидимість (Invisibility)

```
2D game UI ability icon 64x64, INVISIBILITY skill, ghostly silhouette fading to transparent,
dark purple aura, small cloak wrapping around a shadow figure,
gothic fantasy game icon, transparent background, flat cel shading, black outline
--ar 1:1 --v 6.1 --style raw
```

Файл: `Assets/OurAssets/ui_ability_invisibility.png`

---

#### Відволікання (Distraction)

```
2D game UI ability icon 64x64, DISTRACTION skill, small bell with dark sound waves,
shadow echoes radiating outward, gothic fantasy style, mysterious dark purple-blue tones,
transparent background, flat cel shading, clean black outline, game HUD icon
--ar 1:1 --v 6.1 --style raw
```

Файл: `Assets/OurAssets/ui_ability_distraction.png`

---

#### Приманка (Decoy)

```
2D game UI ability icon 64x64, DECOY skill, dark shadow puppet clone silhouette,
small dark figure with glowing red eyes, mysterious aura, gothic RPG,
transparent background, flat cel shading, black outline, mobile game icon
--ar 1:1 --v 6.1 --style raw
```

Файл: `Assets/OurAssets/ui_ability_decoy.png`

---

### 2.4 Зірки рейтингу (Level complete)

```
2D game UI icon set, THREE star rating icons in a row,
gothic fantasy style, LEFT star: dark grey empty cracked star outline,
CENTER and RIGHT stars: full golden glowing stars with inner fire glow,
black outline, flat colors, 64x64 each, transparent background, dark RPG game UI
--ar 3:1 --v 6.1 --style raw
```

Файли: `Assets/OurAssets/ui_star_full.png`, `Assets/OurAssets/ui_star_empty.png`

---

### 2.5 Рамка/фон для кнопок

```
2D game UI button frame, gothic dark fantasy style, horizontal pill shape,
dark stone texture with golden filigree border, subtle red ember glow on edges,
hell-themed game, two states side by side: LEFT normal dark stone, RIGHT highlighted
with brighter golden border and warm glow, transparent background, 256x64
--ar 4:1 --v 6.1 --style raw
```

Файл: `Assets/OurAssets/ui_button_frame.png`

---

### 2.6 Sin Bar — декоративні краї

```
2D game UI sin bar end cap icons, small devil horns icon on left, small flame icon on right,
dark red gothic style, flat vector game asset, 32x32 each, transparent background,
mobile game HUD elements, clean black outline
--ar 2:1 --v 6.1 --style raw
```

Файли: `Assets/OurAssets/ui_sinbar_left.png`, `Assets/OurAssets/ui_sinbar_right.png`

---

## 3. Головне меню — Background

```
2D game background, HELL GATES scene, massive ancient stone gates with demonic carvings,
cracked ground with glowing lava rivers, dark crimson sky with ember particles,
silhouette of a lone priest figure with staff standing before the gates,
epic vertical composition, mobile game main menu background 1080x1920,
dark fantasy painterly style, dramatic lighting, atmospheric, deep reds and blacks,
no text, no characters (only silhouette), cinematic mood
--ar 9:16 --v 6.1
```

Файл: `Assets/OurAssets/bg_main_menu.png`

---

## 4. Хаб Раю — Background

```
2D game background, HEAVEN HUB scene, ethereal golden-white clouds platform,
soft divine light rays from above, floating islands with golden grass,
distant white towers, gentle sparkle particles, warm and serene mood,
contrast to hell levels — pure and peaceful,
mobile game background 1080x1920, painterly anime style,
warm gold and white palette, soft glow, no characters
--ar 9:16 --v 6.1
```

Файл: `Assets/OurAssets/bg_hub_heaven.png`

---

## 5. Бог-силует для Хабу

```
2D game character silhouette, GOD figure, tall majestic divine presence,
bright white-gold glowing silhouette WITHOUT a face, radiating warm light,
robe-like flowing form, gentle particles emanating from body,
full body front view, transparent background, very simple clean design,
anime painterly style, ethereal, awe-inspiring, 512x1024
--ar 1:2 --v 6.1 --style raw
```

Файл: `Assets/OurAssets/npc_god_silhouette.png`

---

## 6. Логотип / Назва гри

```
game logo text "ESCAPE FROM HELL", dramatic gothic title design,
cracked stone letters with glowing red lava inside the cracks,
flames flickering on top of letters, dark background with subtle ember particles,
hell-themed game logo, bold and readable, horizontal layout,
no additional characters or decorations, clean transparent background
--ar 3:1 --v 6.1
```

Файл: `Assets/OurAssets/ui_game_logo.png`

---

## 7. Android App Icon

### 7.1 Main icon 192×192

```
mobile app icon 1:1, dark gothic game icon, chibi fallen priest character,
white hair, glowing red eye, holding wooden staff with golden cross,
circular framing with hellfire border, deep crimson and black background,
bold and readable at small size, flat cel shading, app store icon style,
highly detailed center composition
--ar 1:1 --v 6.1
```

Файл: `Assets/OurAssets/launcher_icon_main.png` (масштабувати до 192×192)

---

### 7.2 Adaptive foreground 432×432

```
app icon foreground layer, chibi fallen priest with staff raised,
white hair, one glowing red eye, dark tattered robes, soul fragments around him,
TRANSPARENT BACKGROUND, centered composition with safe zone padding,
flat cel shading, black outline, clean game character
--ar 1:1 --v 6.1 --style raw
```

Файл: `Assets/OurAssets/launcher_adaptive_foreground.png`

---

### 7.3 Adaptive background 432×432

```
app icon background layer, abstract hell environment,
deep crimson red and black gradient, subtle lava cracks pattern,
glowing ember particles, no characters, flat design,
simple bold visual texture, suitable as app icon background
--ar 1:1 --v 6.1 --style raw
```

Файл: `Assets/OurAssets/launcher_adaptive_background.png`

---

## 8. Боси — відсутні (04, 06, 08, 09)

> Боси існуючих кіл: Воротар (01), Хранитель Вітрів (02), Вогняний Колос (03), Гнів Втілений (05), Зрадник (07), Люцифер (10).
> Відсутні: боси кіл 4 (трясовина), 6 (собор), 8 (машина), 9 (лід).

### 8.1 Бос Кола 4 — Болотний Жрець (Swamp Priest)

Коло 4: `dark_swamps`. Тема: болото, трясовина, темрява.

```
2D game boss character, SWAMP PRIEST boss, ancient bloated demonic shaman,
rotting robe covered in dark moss and swamp vines, glowing green eyes,
bone staff with hanging skulls, dark green-black aura, standing in murky water,
chibi proportions but menacing, full body front view, transparent background,
flat cel shading, black outline, dark fantasy RPG boss sprite
--ar 1:2 --v 6.1 --style raw
```

Файл: `Assets/enemies/boss_04/Idle.png` (sprite pack needed)

---

### 8.2 Бос Кола 6 — Єретичний Архієпіскоп (Heresy Archbishop)

Коло 6: `heresy_cathedral`. Тема: спотворена церква, гордість, єресь.

```
2D game boss character, CORRUPTED ARCHBISHOP boss, tall dark bishop figure,
elaborate corrupted vestments with inverted crosses and dark runes,
golden mitre crown cracked and glowing with dark energy,
purple-black aura of heresy, staff with broken halo,
chibi proportions but imposing, full body front view, transparent background,
flat cel shading, black outline, dark gothic fantasy boss
--ar 1:2 --v 6.1 --style raw
```

Файл: `Assets/enemies/boss_06/Idle.png`

---

### 8.3 Бос Кола 8 — Годинниковий Маг (Clockwork Sorcerer)

Коло 8: `fraud_machine`. Тема: обман, механізми, маніпуляція.

```
2D game boss character, CLOCKWORK SORCERER boss, demonic mechanical mage,
half-organic half-mechanical body with gears and cogs embedded in skin,
multiple mechanical arms holding playing cards and gears,
dark bronze and black coloring, glowing orange clock-face eyes,
smoke and steam wisps, chibi proportions, full body front view,
transparent background, flat cel shading, black outline, steampunk-hell fusion boss
--ar 1:2 --v 6.1 --style raw
```

Файл: `Assets/enemies/boss_08/Idle.png`

---

### 8.4 Бос Кола 9 — Крижана Зрадниця (Frozen Betrayer)

Коло 9: `betrayal_ice`. Тема: зрада, холод, вічне замерзання.

```
2D game boss character, FROZEN BETRAYER boss, tall ice demon queen figure,
pale blue crystalline skin with dark ice cracks, silver crown of frozen tears,
large ice wings partially shattered, cold blue-white aura with snowflakes,
one hand reaching forward pleadingly, cold empty eyes,
chibi proportions, full body front view, transparent background,
flat cel shading, black outline, dark ice fantasy boss
--ar 1:2 --v 6.1 --style raw
```

Файл: `Assets/enemies/boss_09/Idle.png`

---

## 9. Фони для кіл (Circles 2–10)

> Використовується як задній план рівнів. Стиль: темне фентезі, painterly, атмосферно.
> Розмір: 1920×1080 або адаптивний tile background.

### 9.1 Коло 2 — Вітряні Коридори (wind_corridors)

```
2D game level background, WIND CORRIDOR in hell, dark stormy canyon,
swirling purple-grey storm clouds, debris and souls flying in the wind,
crumbling stone pillars with glowing runes, distant lightning flashes,
dark desaturated palette with purple accents, atmospheric depth, no characters,
horizontal game level background 16:9, painterly dark fantasy style
--ar 16:9 --v 6.1
```

Файл: `Assets/hellAssets/Background/bg_circle_2.png`

---

### 9.2 Коло 3 — Вогняні Печери (fire_caverns)

```
2D game level background, FIRE CAVERNS in hell, massive volcanic cave,
rivers of glowing orange lava below, stalactites of black rock above,
smoke columns rising, embers floating everywhere, dramatic red-orange glow,
hell fire jets from walls, intense heat atmosphere, no characters,
horizontal game level background 16:9, painterly dark fantasy
--ar 16:9 --v 6.1
```

Файл: `Assets/hellAssets/Background/bg_circle_3.png`

---

### 9.3 Коло 4 — Темні Трясовини (dark_swamps)

```
2D game level background, DARK SWAMP in hell, murky stagnant water,
gnarled dead trees with hanging moss and chains, toxic green fog wisps,
bubbles rising from black mud, dim sickly green-yellow light,
oppressive claustrophobic atmosphere, no characters,
horizontal game level background 16:9, painterly dark fantasy
--ar 16:9 --v 6.1
```

Файл: `Assets/hellAssets/Background/bg_circle_4.png`

---

### 9.4 Коло 5 — Руїни Гніву (rage_ruins)

```
2D game level background, RAGE RUINS in hell, destroyed ancient city,
crumbling buildings with eternal fires burning inside windows,
cracked ground with glowing orange crevices, dust and embers in the air,
violent aggressive atmosphere, burning red sky, no characters,
horizontal game level background 16:9, painterly dark fantasy
--ar 16:9 --v 6.1
```

Файл: `Assets/hellAssets/Background/bg_circle_5.png`

---

### 9.5 Коло 6 — Єретичний Собор (heresy_cathedral)

```
2D game level background, CORRUPTED CATHEDRAL in hell, vast gothic church interior,
twisted inverted arches, stained glass windows showing demonic scenes in dark purples,
candles with black flames, corrupted religious symbols carved in walls,
purple-black atmosphere, oppressive divine architecture gone wrong,
no characters, horizontal game level background 16:9, painterly dark fantasy
--ar 16:9 --v 6.1
```

Файл: `Assets/hellAssets/Background/bg_circle_6.png`

---

### 9.6 Коло 7 — Фортеця Насилля (violence_fortress)

```
2D game level background, FORTRESS OF VIOLENCE in hell, massive dark stone fortress interior,
iron spikes and chains everywhere, rivers of dark blood below,
torch fires casting harsh shadows, brutal iron architecture,
deep red and black palette, war-like oppressive atmosphere, no characters,
horizontal game level background 16:9, painterly dark fantasy
--ar 16:9 --v 6.1
```

Файл: `Assets/hellAssets/Background/bg_circle_7.png`

---

### 9.7 Коло 8 — Шахрайська Машина (fraud_machine)

```
2D game level background, FRAUD MACHINE in hell, massive mechanical infernal factory,
enormous gears and pistons moving endlessly, conveyor belts with lost souls,
steam and dark smoke, bronze and black iron everywhere, orange industrial glow,
eerie mechanical heartbeat atmosphere, no characters,
horizontal game level background 16:9, painterly steampunk dark fantasy
--ar 16:9 --v 6.1
```

Файл: `Assets/hellAssets/Background/bg_circle_8.png`

---

### 9.8 Коло 9 — Зрадницький Лід (betrayal_ice)

```
2D game level background, BETRAYAL ICE FIELD in hell, vast frozen wasteland,
cracked dark ice floor with figures frozen inside visible below surface,
ice stalactites from dark ceiling, pale blue-white cold light,
absolute silence and stillness atmosphere, frozen tears on every surface,
no characters, horizontal game level background 16:9, painterly dark fantasy
--ar 16:9 --v 6.1
```

Файл: `Assets/hellAssets/Background/bg_circle_9.png`

---

### 9.9 Коло 10 — Трон Безодні (throne_abyss)

```
2D game level background, THRONE OF THE ABYSS, cosmic void throne room,
enormous dark throne in center distance, reality torn apart around it,
swirling purple-black void energy, fragments of stone floating in nothingness,
distant stars visible through rifts, absolute evil presence felt,
no characters, horizontal game level background 16:9, painterly dark epic fantasy
--ar 16:9 --v 6.1
```

Файл: `Assets/hellAssets/Background/bg_circle_10.png`

---

## 10. Портрети душ (Soul Portraits — 100 штук)

> Використовується в `SoulRevealPanel` (Todo 4.7). Потрібен шаблон для масової генерації.

### Базовий промт-шаблон

```
2D game portrait icon, SOUL of [ІМ'Я], [ВІКОВА ГРУПА], [ОПИС ЗОВНІШНОСТІ],
small portrait in oval golden frame, ethereal translucent ghost appearance,
warm-white glow, melancholic expression, [УНІКАЛЬНА ДЕТАЛЬ ДЛЯ ЦЮ ДУШУ],
64x64 or 128x128, anime painterly style, dark background, game collectible portrait
--ar 1:1 --v 6.1 --style raw
```

### Приклади для перших 10 іменних душ

> Імена та деталі з `doc/souls.md`

**Шаблон використання:**
1. Замінити `[ІМ'Я]` → ім'я персонажа
2. Замінити `[ВІКОВА ГРУПА]` → дитина / молода людина / доросла / стара людина
3. Замінити `[ОПИС ЗОВНІШНОСТІ]` → характерна риса
4. Замінити `[УНІКАЛЬНА ДЕТАЛЬ]` → атрибут або пам'ятний елемент персонажа

**Пачка Коло 1 (souls 1–10):**

```
2D game portrait icons, 10 different souls in oval frames in a 2x5 grid,
each a different ghost portrait: elderly woman with headscarf, young boy with toy,
middle-aged man with beard, young woman with flowers, old fisherman,
child with ball, merchant in coat, farmer woman, young soldier, priest,
all in same style: warm-white ethereal ghost, melancholic, golden oval frame,
anime painterly, dark background, consistent art style
--ar 2:5 --v 6.1
```

Файли: `Assets/OurAssets/souls/soul_portrait_[001-010].png`

---

## Workflow

1. Генеруємо в Midjourney
2. Видаляємо фон → [remove.bg](https://remove.bg) або Photoshop
3. Нарізаємо якщо потрібно (спрайт шит → окремі кадри)
4. Зберігаємо в потрібну папку (шляхи вказані під кожним промтом)
5. Підключаємо в Godot

---

## Пріоритет генерації

| # | Ассет | Критичність |
|---|-------|-------------|
| 1 | Player 4 sin states | 🔥 Блокує sin shader |
| 2 | UI Hearts + Soul icon | 🔥 HUD виглядає незавершеним |
| 3 | Main Menu Background | 🟡 Перше враження |
| 4 | Game Logo | 🟡 Store + меню |
| 5 | Android App Icon | 🟡 Play Store |
| 6 | Hub Heaven Background | 🟡 Між рівнями |
| 7 | God Silhouette | 🟡 Hub сцена |
| 8 | Ability Icons | ⚪ UI polish |
| 9 | Boss 04, 06, 08, 09 | ⚪ Потрібні при розробці кіл |
| 10 | Circle backgrounds 2–10 | ⚪ При розробці рівнів |
| 11 | Soul Portraits | ⚪ Todo 4.7 |
