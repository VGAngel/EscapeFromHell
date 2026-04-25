# Assets — що є, чого немає

> Оновлено: 2026-04-21
> Джерела: `Assets/`, `shaders/`, `export_presets.cfg`, `audio_config.json`, `enemy_sprite_map.json`, `scripts/**/*.gd`

Легенда: ✅ є • 🟡 частково • ❌ відсутнє

---

## Підсумок

| Категорія | Стан | Коментар |
|-----------|------|----------|
| Player sprites | 🟡 | Є `player_idle.png`. Немає 4 sin-state текстур + walk/jump/fall/attack/carry/death анімацій |
| Enemy sprites | ✅ | Усі 19 ворогів + 6 босів мають sprite-паки в `Assets/enemies/` |
| Environment sprites | ✅ | `Assets/hellAssets/` (Background, Environment, Platformer, Collectable) |
| Tilesets (`.tres`) | ❌ | Жодного TileSet не зібрано |
| Bonus items | 🟡 | 5 з `OurAssets/`. Всі інші з `audio_config`/upgrades ще не мають арту |
| Souls | ❌ | Немає спеціального спрайту Soul — візуал процедурний |
| UI / іконки | ❌ | Серця, sin-bar, лічильники — emoji (♥, 👻, 🙏). Немає UI-атласу |
| Шрифти | ❌ | Використовується дефолтний Godot. Немає українського бренд-шрифту |
| Музика | ❌ | Повний спек на 40+ треків — файлів 0 |
| SFX | ❌ | Повний спек на ~60 звуків — файлів 0 |
| Particle ефекти | ❌ | Жодного `.tres` з CPUParticles/GPUParticles |
| Шейдери | 🟡 | Є `player_sin.gdshader`. Інші (fade, holy glow, fire distortion) — немає |
| Android launcher icons | ❌ | Порожні шляхи в export_presets.cfg, лише дефолтний `icon.svg` |
| Room scenes | 🟡 | `circle_1` — 26 сцен. `circle_2–10` — 0 |

---

## 1. Player

**Папка:** `Assets/OurAssets/`

| Файл | Стан | Використовується в |
|------|------|--------------------|
| `player_idle.png` | ✅ | — (не підключений у код) |
| `player_clean.png` | ❌ | `scripts/Player.gd:64` (sin shader) |
| `player_tainted.png` | ❌ | `scripts/Player.gd:65` |
| `player_fallen.png` | ❌ | `scripts/Player.gd:66` |
| `player_demon.png` | ❌ | `scripts/Player.gd:67` |

**Анімації (Todo 1.1.8, 7.7) — усі відсутні:**
- walk, jump, fall, attack (staff_swing), pickup, carry_idle, carry_walk, death, respawn, hurt

**Альтернатива:** є `Assets/rpg-platformer-game-assets/1_Main_character/Dark_Elves/PNG Sequences` — можна використати як тимчасовий плейсхолдер.

---

## 2. Enemies + Bosses

**Папка:** `Assets/enemies/` — 19 sprite-паків з PNG sequences (Idle, Walking, Running, Hurt, Dying, Slashing, Jump, etc).

**Мапінг:** `enemy_sprite_map.json` — усі 19 ворогів і 6 босів мають валідні pack/character.

| Група | Кількість | Стан |
|-------|-----------|------|
| Circle 1 вороги (shadow_lost, pale_wanderer) | 2 | ✅ |
| Circle 2–10 вороги | 17 | ✅ |
| Боси 01, 02, 03, 05, 07, 10 | 6 | ✅ |
| **Боси 04, 06, 08, 09 (final)** | 4 | ❌ не призначені в `enemy_sprite_map.json → bosses` |

**Підключення до `BaseEnemy.gd` / `ShadowLost.gd`:** ще не зроблено — жоден `.tscn` в `scenes/enemies/` не існує.

---

## 3. Середовище (стіни, платформи, фон)

**Папка:** `Assets/hellAssets/`

| Підпапка | Файли | Стан |
|----------|-------|------|
| `Background/` | Background_01.png, Background_02.png | ✅ |
| `Environment/` | 22 файли (Rocks, Trees, Fence, Lantern, Signs, Statue, Rift) | ✅ |
| `Platformer/` | 30 файлів (Ground 1–13, Bricks, Bridges, Ladder, Spikes, Barrel, Box) | ✅ |
| `Collectable Object/` | 18 файлів (Apple, Chest, Coins, Diamond, Key, Life, Light, Star) | ✅ |

**Чого немає:**
- `TileSet` ресурси (`.tres`) з колізіями — треба зібрати з Ground/Brick спрайтів
- Унікальні тайлсети на коло (circle_2 вітри, circle_3 вогонь, circle_4 болото, circle_5–10) — зараз один набір для всіх 10 кіл

---

## 4. Souls

| Об'єкт | Стан | Нотатка |
|--------|------|---------|
| `Soul.tscn` sprite | ❌ | Зараз процедурний (ColorRect/Label) |
| Icon для CollectionScreen | ❌ | Використовується emoji 👻 |
| Portraits для іменних душ (100 шт.) | ❌ | Todo 4.7 — `SoulRevealPanel` |
| Soul типи (innocent/sleeping/mimic) — візуальне розрізнення | ❌ | — |

---

## 5. Бонуси / Collectibles

**Папка:** `Assets/OurAssets/`

| Файл | Стан |
|------|------|
| `bonus_angel_feather.png` | ✅ |
| `bonus_holy_water.png` | ✅ |
| `bonus_manna.png` | ✅ |
| `bonus_prayer_stone.png` | ✅ |
| `bonus_torch.png` | ✅ |

**Не підключені в код:** жодна з 5 іконок не використовується — `HUD.gd` рендерить бонуси як emoji через `start_bonus(bonus_id, icon_char, duration)`.

**Відсутні з `audio_config.json → bonuses`:** немає спрайтів для `pickup_generic` (базовий shimmer).

---

## 6. UI / Іконки / Шрифти

| Елемент | Стан | Поточне рішення |
|---------|------|------------------|
| Серця HP | ❌ | emoji ♥ / ♡ |
| Sin bar | 🟡 | ColorRect — працює але виглядає як progress bar без стилю |
| Souls counter icon | ❌ | emoji 👻 |
| Ability icons (invisibility/distraction/decoy) | ❌ | emoji 👁 🔔 🌑 |
| Бонус-слот icons | ❌ | emoji (🙏 для prayer і т.д.) |
| Buttons styleboxes | 🟡 | Згенеровані в коді (`StyleBoxFlat`) — без текстур |
| Шрифт UA/кириличний | ❌ | Використовується дефолтний Godot, кирилиця може виглядати негарно |
| Logo / game title | ❌ | Текст "ESCAPE FROM HELL" через Label у MainMenu |
| Background для MainMenu | ❌ | Просто ColorRect |
| Background для Hub (heaven) | ❌ | ColorRect `#0C050F` |

---

## 7. Музика

**Спек:** `audio_config.json` — 40+ треків у 4-шаровій адаптивній системі.

| Група | Файлів очікується | Наявно |
|-------|-------------------|--------|
| `main_menu` | 1 | ❌ |
| `hub_heaven` | 1 | ❌ |
| `prologue` | 1 | ❌ |
| `circles 1–10` (base + 3 шари кожне коло) | 40 | ❌ |
| Boss arenas (boss_1, 2, 5, 10) | 4 | ❌ |
| `level_complete` | 1 | ❌ |
| **Разом** | **≈48** | **0** |

**Формат:** очікується `.ogg` (Vorbis) для мобільних. Шляхи — `music/*.ogg` (папки `audio/music` поки немає).

---

## 8. SFX

**Спек:** `audio_config.json → sfx` — ~60 звуків у 9 групах.

| Група | Файлів | Наявно |
|-------|--------|--------|
| Player (footsteps × 3, jump, land × 2, hurt, death, respawn) | 9 | ❌ |
| Souls (hum, pickup, carry, deliver, memory, reveal, banished, exorcism, awaken — 11 шт.) | 11 | ❌ |
| Minigames (heartbeat × 2, spark, echo, prayer, success, fail) | 7 | ❌ |
| Enemies (patrol_step, alert, chase_start, give_up, breathing) | 5 | ❌ |
| Environment (lava, fire, wind, swamp, drip, chain, mechanism, door, trap) | 9 | ❌ |
| UI (hover, click, tab, toggle × 2, slider, pause × 2, level_complete, stars × 2, choir, chime) | 13 | ❌ |
| Bonuses (pickup, water, feather, manna, tick, expired) | 6 | ❌ |
| Sin (rise, drop, critical, warning 80%) | 4 | ❌ |
| **Разом** | **≈64** | **0** |

---

## 9. Частинки / Ефекти (Todo 7.4)

Жодного `.tres` або `.tscn` з CPUParticles2D/GPUParticles2D:
- Soul glow (коли лежить / коли переноситься)
- Staff swing trail
- Death/respawn (чорний дим → білий спалах)
- Fire jets (circle_3)
- Lava bubbles (circle_3)
- Wind streaks (circle_2)
- Swamp bubbles (circle_4)
- Demon deal (фіолетовий дим)
- Boss phase transition

---

## 10. Шейдери

**Папка:** `shaders/`

| Файл | Стан | Призначення |
|------|------|-------------|
| `player_sin.gdshader` | ✅ | Blend між sin-stages |

**Очікуються (з GDD):**
- `holy_glow.gdshader` — світіння врятованої душі / hub
- `sin_corruption.gdshader` — спотворення на high-sin
- `fire_distortion.gdshader` — тепловий потік (circle_3)
- `fade_transition.gdshader` — перехід між рівнями (Todo 7.6)

---

## 11. Android / Store metadata

| Ресурс | Стан |
|--------|------|
| `icon.svg` (дефолтний Godot icon) | ✅ (плейсхолдер) |
| `launcher_icons/main_192x192` | ❌ порожнє в `export_presets.cfg` |
| `launcher_icons/adaptive_foreground_432x432` | ❌ |
| `launcher_icons/adaptive_background_432x432` | ❌ |
| `launcher_icons/adaptive_monochrome_432x432` | ❌ |
| Store screenshots (Google Play, 2–8 шт.) | ❌ |
| Feature graphic (1024×500) | ❌ |
| App Store preview video | ❌ |

---

## 12. Кімнати (scenes/rooms)

| Коло | Очікується | Наявно | Файли |
|------|-----------|--------|-------|
| circle_1 | ≈25 | 26 | ✅ |
| circle_2 (wind_corridors) | ≈25 | 0 | ❌ |
| circle_3 (fire_caverns) | ≈25 | 0 | ❌ |
| circle_4 (dark_swamps) | ≈25 | 0 | ❌ |
| circle_5 (rage_ruins) | ≈25 | 0 | ❌ |
| circle_6 (heresy_cathedral) | ≈25 | 0 | ❌ |
| circle_7 (violence_fortress) | ≈25 | 0 | ❌ |
| circle_8 (fraud_machine) | ≈25 | 0 | ❌ |
| circle_9 (betrayal_ice) | ≈25 | 0 | ❌ |
| circle_10 (throne_abyss) | ≈25 | 0 | ❌ |
| Branch рівні (void × 9 кіл × 2) | 18 | 0 | ❌ |
| Milestone static levels (50, 75, 99, 100) | 4 | 0 | ❌ |

> Кімнати `circle_1` — це `PlaceholderRoom` з процедурною геометрією. Реальних тайлсет-кімнат ще немає в жодному колі.

---

## 13. Пріоритети (рекомендація)

**Критичний шлях до playable MVP:**

1. 🔥 **Player sprites** — 4 sin-state текстури (щоб не падав sin shader). Можна взяти `Dark_Elves` з `rpg-platformer-game-assets` як тимчасовий плейсхолдер.
2. 🔥 **Enemy .tscn wrappers** — спакувати `free-fallen-angel-chibi` в `scenes/enemies/ShadowLost.tscn` з AnimatedSprite2D.
3. 🔥 **TileSet для circle_1** — з `hellAssets/Platformer/Ground_*.png` + колізії.
4. 🟡 **HUD replacement icons** — хоча б серце, душа, sin — щоб UI не був emoji.
5. 🟡 **Базовий SFX pack** — jump, hurt, death, soul_pickup, ui_click (5 звуків щоб відчувалось живим).
6. 🟡 **Background для головного меню + Hub** — з `hellAssets/Background_01.png`.
7. ⚪ **Launcher icon** — простий червоний варіант для Android build.

**Можна відкласти:**
- Музика (40+ треків — великий проект на окремий етап)
- Portraits 100 душ
- Particle ефекти (поки є placeholder tween-фейди)
- Шрифт (Nunito з addons працює нормально)

---

## Додатки

### Що в `Assets/rpg-platformer-game-assets/` ще не розібрано

- `1_Main_character/Dark_Elves/` — **потенційний плейсхолдер гравця** (PNG Sequences)
- `2_Enemies/` — 6 паків (Demon Archer, Demons_of_Darkness, Devil, Hell_Knight, Magician_Demon, Succubus) — більшість уже призначені в `enemy_sprite_map.json`
- `3_Shop`, `4_Main_location`, `5_Levels`, `6_UI` — не переглянуто детально
