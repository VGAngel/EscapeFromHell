# Todo — Plan rozrobky «Escape from Hell»

> Ostatnie onovlennya: 2026-04-21  
> Status: ✅ Arkhitektura hotova. Pochynaemo rozrobku.

---

## Legendа

| Значок | Статус |
|--------|--------|
| ✅ | Готово |
| 🔄 | В процесі |
| ⬜ | Не розпочато |
| 🔥 | Критичний блокер |

---

## Milestone 0 — Перший запуск (DONE)

> Ціль: гра запускається, рівень завантажується, душа підбирається.

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 0.1 | LevelBase: горизонтальна збірка кімнат | `scripts/LevelBase.gd` | ✅ |
| 0.2 | LevelBase: вертикальна збірка кімнат | `scripts/LevelBase.gd` | ✅ |
| 0.3 | LevelGenerator: процедурна генерація | `scripts/LevelGenerator.gd` | ✅ |
| 0.4 | LevelGenerator: branch-рівні | `scripts/LevelGenerator.gd` | ✅ |
| 0.5 | PlaceholderRoom: фізичні стіни + варіанти | `scripts/PlaceholderRoom.gd` | ✅ |
| 0.6 | 26 сцен кімнат circle_1 | `scenes/rooms/circle_1/` | ✅ |
| 0.7 | Soul.gd: add_to_group, set_soul_data | `Soul.gd` | ✅ |
| 0.8 | Input Map: `interact` → клавіша E | `project.godot` | ✅ |
| 0.9 | AltarNode: мід-алтар для вертикальних рівнів | `scripts/AltarNode.gd` | ✅ |
| 0.10 | Всі configs та документація синхронізована | `doc/`, `configs/` | ✅ |

---

## Milestone 1 — Playable Circle 1

> Ціль: пройти всі 10 рівнів першого кола з базовою механікою.

### 1.1 Гравець (Player)

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 1.1.1 | Базовий рух: хода, стрибок, гравітація | `scripts/Player.gd` | ✅ |
| 1.1.2 | Подвійний стрибок (`double_jump` upgrade) | `scripts/Player.gd` | ✅ |
| 1.1.3 | М'яке приземлення (`soft_landing`) | `scripts/Player.gd` | ✅ |
| 1.1.4 | Удар посохом (staff swing, cooldown) | `scripts/Player.gd` | ✅ |
| 1.1.5 | Підбір / скидання душі (pickup/carry/drop) | `scripts/Player.gd` | ✅ |
| 1.1.6 | Система HP + пошкодження + непоразність | `scripts/Player.gd` | ✅ |
| 1.1.7 | Shake-анімація при ударі | `scripts/Player.gd` | ⬜ |
| 1.1.8 | Анімації: idle, walk, jump, fall, attack, dead | `scenes/Player.tscn` | ⬜ |
| 1.1.9 | Сцена Player зі SpritеsSheet або AnimatedSprite | `scenes/Player.tscn` | ⬜ |

### 1.2 Вороги circle_1

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 1.2.1 | BaseEnemy: patrol, detect, attack, hp | `scripts/enemies/BaseEnemy.gd` | ✅ |
| 1.2.2 | ShadowLost: конкретний ворог кола 1 | `scripts/enemies/ShadowLost.gd` | ✅ |
| 1.2.3 | PaleWanderer: повільний бродяга кола 1 | `scripts/enemies/PaleWanderer.gd` | ✅ |
| 1.2.4 | Сцени ворогів + placeholder спрайти | `scenes/enemies/` | ✅ (19/19) |
| 1.2.5 | Розміщення ворогів у PlaceholderRoom (room_main) | `scripts/rooms/PlaceholderRoom.gd` | ✅ |

### 1.3 Платформи

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 1.3.1 | BasePlatform: базова логіка | `scripts/platforms/BasePlatform.gd` | ✅ |
| 1.3.2 | `stone` — статична (вже є через StaticBody2D) | — | ✅ |
| 1.3.3 | `one_way` — одностороння | `scripts/platforms/OneWayPlatform.gd` | ✅ |
| 1.3.4 | `crumbling` — розсипається після торкання | `scripts/platforms/CrumblingPlatform.gd` | ✅ |
| 1.3.5 | `moving_horizontal` / `moving_vertical` | `scripts/platforms/MovingPlatform.gd` | ✅ |
| 1.3.6 | `bounce` — відштовхує гравця вгору | `scripts/platforms/BouncePlatform.gd` | ✅ |
| 1.3.7 | Додати платформи в PlaceholderRoom для circle_1 | `scripts/rooms/PlaceholderRoom.gd` | ✅ |

### 1.4 HUD

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 1.4.1 | HP-серця (3 серця → 6 з апгрейдом) | `scripts/ui/HUD.gd` | ✅ |
| 1.4.2 | Sin-bar (0–100%, кольори за порогами) | `scripts/ui/HUD.gd` | ✅ |
| 1.4.3 | Лічильник душ `found/total` | `scripts/ui/HUD.gd` | ✅ |
| 1.4.4 | Таймер рівня (MM:SS stopwatch) | `scripts/ui/HUD.gd` | ✅ |
| 1.4.5 | Сцена HUD з усіма нодами | `scenes/ui/HUD.tscn` | ✅ |

### 1.5 GameManager — рівневий цикл

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 1.5.1 | `begin_level` / `end_level` | `scripts/GameManager.gd` | ✅ |
| 1.5.2 | `collect_soul(soul_id)` → light calculation | `scripts/GameManager.gd` | ✅ |
| 1.5.3 | Смерть → `SIN_ON_DEATH`, respawn | `scripts/GameManager.gd` | ✅ |
| 1.5.4 | Transition між рівнями (fade) | `scripts/managers/SceneTransition.gd` | ✅ |
| 1.5.5 | `level_complete` screen: stats + next level | `scripts/ui/LevelComplete.gd` | ✅ |
| 1.5.6 | Death limit per level type | `scripts/GameManager.gd` | ✅ |

### 1.6 Збереження

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 1.6.1 | SaveManager: save/load до файлу | `scripts/managers/SaveManager.gd` | ✅ |
| 1.6.2 | Зберігати: current_level, circle, sin, upgrades, light | `scripts/managers/SaveManager.gd` | ✅ (hp per-run тільки) |
| 1.6.3 | Зберігати: collected souls (saved_soul_ids + hidden) | `scripts/managers/SaveManager.gd` | ✅ |
| 1.6.4 | Auto-save після кожного рівня | `scripts/managers/GameManager.gd:238` | ✅ |

### 1.7 Перший boss (рівень 10)

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 1.7.1 | BossLevel.gd: статична арена | `scripts/levels/BossLevel.gd` | ✅ |
| 1.7.2 | Boss circle_1: поведінка | `scripts/enemies/BossCircle1.gd` | ✅ |
| 1.7.3 | Сцена арени level_10 | `scripts/levels/BossLevel.gd:_build_arena_boss_01` | ✅ (procedural) |
| 1.7.4 | Кат-сцена перед/після боса | — | ⬜ |

---

## Milestone 2 — Hub + Upgrades

> Ціль: між рівнями є Hub, можна купувати апгрейди.

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 2.1 | Hub.gd: навігація до рівнів, алтарь | `scripts/Hub.gd` | ✅ |
| 2.2 | Hub сцена з NPC, алтарем, виходами | `scenes/Hub.tscn` | ⬜ |
| 2.3 | UpgradesScreen: відображення, покупка | `scripts/ui/UpgradesScreen.gd` | ✅ скелет |
| 2.4 | UpgradesScreen: підключити до SaveManager | `scripts/ui/UpgradesScreen.gd` | ⬜ |
| 2.5 | Застосування апгрейдів до Player в `_ready` | `scripts/Player.gd` | ✅ |
| 2.6 | Light currency: відображення в Hub і HUD | `scripts/HUD.gd`, `scripts/Hub.gd` | ⬜ |
| 2.7 | Перевірити всі 22 апгрейди з `upgrades_config.json` | — | ⬜ |
| 2.8 | DonatePanel: IAP placeholder | `scripts/ui/DonatePanel.gd` | ✅ скелет |

---

## Milestone 3 — Circles 2–5

> Ціль: 50 рівнів з різними вороги та особливостями середовища.

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 3.1 | Кімнати circle_2 (wind_corridors, 22–30 шт.) | `scenes/rooms/circle_2/` | ⬜ |
| 3.2 | Кімнати circle_3 (fire_caverns) | `scenes/rooms/circle_3/` | ⬜ |
| 3.3 | Кімнати circle_4 (dark_swamps) | `scenes/rooms/circle_4/` | ⬜ |
| 3.4 | Кімнати circle_5 (rage_ruins) | `scenes/rooms/circle_5/` | ⬜ |
| 3.5 | Вороги circle_2: WindShade, PaleWanderer | `scripts/enemies/` | ⬜ |
| 3.6 | Вороги circle_3: FlameImp, FireHound | `scripts/enemies/` | ⬜ |
| 3.7 | Вороги circle_4: SwampCrawler, BogPhantom | `scripts/enemies/` | ⬜ |
| 3.8 | Вороги circle_5: RageShade, FrostKnight | `scripts/enemies/` | ⬜ |
| 3.9 | Середовищні ефекти: вітер (circle_2) | `scripts/environments/WindZone.gd` | ⬜ |
| 3.10 | Середовищні ефекти: лава, вогняні джети (circle_3) | `scripts/environments/LavaZone.gd` | ⬜ |
| 3.11 | Середовищні ефекти: болото, отрута (circle_4) | `scripts/environments/SwampZone.gd` | ⬜ |
| 3.12 | Боси 20, 30, 50 | `scripts/enemies/Boss*.gd` | ⬜ |
| 3.13 | Платформи circle_2–5 (moving, bounce, mud, ash) | `scripts/platforms/` | ⬜ |
| 3.14 | Void / Labyrinth / Escape рівні (branch) — circle_1 | `scenes/rooms/circle_1_branch/` | ⬜ |

---

## Milestone 4 — Souls Collection

> Ціль: 100 іменних душ з діалогами та правильними механіками.

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 4.1 | Підключити `souls_collection.json` до LevelGenerator | `scripts/LevelGenerator.gd` | ✅ |
| 4.2 | Soul.tscn: відображення імені при підборі | `Soul.tscn`, `Soul.gd` | ⬜ |
| 4.3 | CollectionScreen: список врятованих душ | `scripts/ui/CollectionScreen.gd` | ✅ скелет |
| 4.4 | Приховані душі: placement у StaticRoom | — | ⬜ |
| 4.5 | Приховані душі: `soul_sense` підсвітка | `Soul.gd` | ⬜ |
| 4.6 | Логіка `soul_memory` (залишається при смерті) | `scripts/Player.gd`, `scripts/GameManager.gd` | ⬜ |
| 4.7 | Іменна душа: показати portrait + short lore | `scripts/ui/SoulRevealPanel.gd` | ⬜ |
| 4.8 | Доставка душі до алтаря на рівні | `scripts/LevelBase.gd` | ⬜ |

---

## Milestone 5 — Sin System + Endings

> Ціль: гріх впливає на гру, 4 кінцівки працюють.

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 5.1 | Sin tracking в GameManager | `scripts/GameManager.gd` | ✅ |
| 5.2 | Sin → зміна кольору HUD bar | `scripts/HUD.gd` | ⬜ |
| 5.3 | High-sin: faith_platforms зникають (circle_6) | `scripts/platforms/FaithPlatform.gd` | ⬜ |
| 5.4 | Угоди з демонами: UI, логіка, +sin | `scripts/ui/DemonDealPanel.gd` | ⬜ |
| 5.5 | `temptation_resist` апгрейд | `scripts/Player.gd` | ⬜ |
| 5.6 | `cleansing` апгрейд: знижує гріх після рівня | `scripts/GameManager.gd` | ⬜ |
| 5.7 | Milestone рівень 50: наративна подія | `scenes/levels/level_50.tscn` | ⬜ |
| 5.8 | Milestone рівень 100: 4 варіанти кінцівки | `scripts/GameManager.gd` | ⬜ |
| 5.9 | Кінцівки: Redemption / Damnation / Void / Hidden | `scenes/endings/` | ⬜ |

---

## Milestone 6 — Circles 6–10 + All Bosses

> Ціль: повна гра, всі 145 рівнів.

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 6.1 | Кімнати + вороги circle_6 (heresy_cathedral) | — | ⬜ |
| 6.2 | Кімнати + вороги circle_7 (violence_fortress) | — | ⬜ |
| 6.3 | Кімнати + вороги circle_8 (fraud_machine) | — | ⬜ |
| 6.4 | Кімнати + вороги circle_9 (betrayal_ice) | — | ⬜ |
| 6.5 | Кімнати + вороги circle_10 (throne_abyss) | — | ⬜ |
| 6.6 | Платформи circle_6–10 (faith, sin, illusory, ice, soul_bridge) | `scripts/platforms/` | ⬜ |
| 6.7 | Боси 70, 100 | `scripts/enemies/` | ⬜ |
| 6.8 | Фінальний бос (рівень 100) — фаза 1/2/3 | `scripts/enemies/BossFinal.gd` | ⬜ |
| 6.9 | Всі 45 branch-рівнів (void/labyrinth/escape) | `scenes/rooms/circle_*_branch/` | ⬜ |
| 6.10 | Статичні рівні 75, 99 (milestone) | `scenes/levels/` | ⬜ |

---

## Milestone 7 — Audio + Visual Polish

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 7.1 | Підключити SoundManager або AudioStreamPlayer | `scripts/SoundManager.gd` | ⬜ |
| 7.2 | Sound effects: jump, attack, soul pickup, death | `assets/sfx/` | ⬜ |
| 7.3 | Музика: ambient per circle (9 треків + hub) | `assets/music/` | ⬜ |
| 7.4 | Particle effects: soul glow, death, staff swing | — | ⬜ |
| 7.5 | Screen shake при ударі, смерті | `scripts/CameraShake.gd` | ⬜ |
| 7.6 | Transition ефект між рівнями (fade to black) | `scripts/managers/SceneTransition.gd` | ✅ |
| 7.7 | Спрайти гравця (idle/walk/jump/attack/carry) | `assets/sprites/player/` | ⬜ |
| 7.8 | Спрайти ворогів (всі 18 типів) | `assets/sprites/enemies/` | ⬜ |
| 7.9 | Тайлсети по колах (10 стилів) | `assets/tilesets/` | ⬜ |

---

## Milestone 8 — Tutorial + Narrative

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 8.1 | TutorialManager: показ підказок у правильний момент | `scripts/TutorialManager.gd` | ✅ скелет |
| 8.2 | Tutorial рівень 1: рух, стрибок | `scenes/levels/level_1.tscn` | ⬜ |
| 8.3 | Tutorial рівень 2: підбір душі | `scenes/levels/level_2.tscn` | ⬜ |
| 8.4 | God messages при відкритті нових кіл | `scripts/ui/GodMessage.gd` | ⬜ |
| 8.5 | Діалоги: 100 душ (текст) | `configs/dialogues.json` | ⬜ |
| 8.6 | Нарратив рівень 50 / 75 / 99 / 100 | — | ⬜ |

---

## Milestone 9 — Monetization + Platform

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 9.1 | AdsManager: rewarded ads (continues) | `scripts/AdsManager.gd` | ✅ скелет |
| 9.2 | IAP: Donate Light пакети | `scripts/ui/DonatePanel.gd` | ✅ скелет |
| 9.3 | Android build: export preset, icons | `export_presets.cfg` | ⬜ |
| 9.4 | iOS build: export preset, signing | `export_presets.cfg` | ⬜ |
| 9.5 | Локалізація: UA / EN | `scripts/LocalizationManager.gd` | ✅ скелет |
| 9.6 | Privacy policy screen | — | ⬜ |
| 9.7 | App Store / Google Play metadata | — | ⬜ |

---

## Milestone 10 — QA + Release

| # | Задача | Файли | Статус |
|---|--------|-------|--------|
| 10.1 | Пройти всі 100 основних рівнів вручну | — | ⬜ |
| 10.2 | Пройти всі 45 branch-рівнів | — | ⬜ |
| 10.3 | Перевірити всі 4 кінцівки | — | ⬜ |
| 10.4 | Перевірити всі 22 апгрейди в дії | — | ⬜ |
| 10.5 | Performance: 60 fps на mid-range Android | — | ⬜ |
| 10.6 | Crashlytics / error reporting | — | ⬜ |
| 10.7 | Soft launch (Testflight / Internal Testing) | — | ⬜ |
| 10.8 | Public release | — | ⬜ |

---

## Наступні кроки (зараз)

> Що робимо в першу чергу щоб зіграти у гру.

```
1. ⬜ Анімації Player (хоча б 4: idle/walk/jump/fall)
2. ⬜ ShadowLost.gd — перший ворог circle_1
3. ⬜ HUD.tscn — HP серця + sin bar (мінімальна версія)
4. ⬜ LevelComplete screen — показати після exit
5. ⬜ Transition fade між рівнями
```

Після цих 5 задач — перший playable loop готовий.

---

## Технічний борг

| Задача | Де | Пріоритет |
|--------|----|-----------|
| Перенести `Soul.gd` / `Soul.tscn` з кореня в `scripts/` / `scenes/` | root | низький |
| Перенести `Level1/2.gd` та старі тестові сцени в архів | root | низький |
| Покрити `GameManager` unit-тестами | `tests/unit/` | середній |
| Покрити `SaveManager` unit-тестами | `tests/unit/` | середній |
| Видалити `PlaceholderVisual.gd` коли з'являться реальні тайлсети | `scripts/` | пізніше |
