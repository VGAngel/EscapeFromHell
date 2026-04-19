# Сцени — Повний Список

> Всі сцени що потрібно створити для гри. Джерело: `project.godot` + всі конфіги.

---

## Головні сцени

| Сцена | Шлях | Скрипт | Статус |
|-------|------|--------|--------|
| Головне меню | `res://MainMenu.tscn` | `scripts/MainMenu.gd` | ⚠️ порожня |
| Базова сцена рівня | `res://scenes/Level.tscn` | `scripts/Level.gd` | ❌ |
| Босс-арена | `res://scenes/BossLevel.tscn` | `scripts/BossLevel.gd` | ❌ |
| Хаб Раю | `res://scenes/Hub.tscn` | `scripts/Hub.gd` | ❌ |

---

## UI сцени (окремі шари/оверлеї)

| Сцена | Шлях | Скрипт | Конфіг |
|-------|------|--------|--------|
| HUD | `res://scenes/ui/HUD.tscn` | `scripts/ui/HUD.gd` | `hud_config.json` |
| Пауза | `res://scenes/ui/PauseScreen.tscn` | `scripts/ui/PauseScreen.gd` | `pause_screen_config.json` |
| Завершення рівня | `res://scenes/ui/LevelComplete.tscn` | `scripts/ui/LevelComplete.gd` | `level_complete_config.json` |
| Колекція душ | `res://scenes/ui/CollectionScreen.tscn` | `scripts/ui/CollectionScreen.gd` | `collection_screen_config.json` |
| Налаштування | `res://scenes/ui/SettingsScreen.tscn` | `scripts/ui/SettingsScreen.gd` | `settings_config.json` |
| Екран смерті | `res://scenes/ui/DeathScreen.tscn` | `scripts/ui/DeathScreen.gd` | `death_system_config.json` |
| Туторіал підказка | `res://scenes/ui/TutorialHint.tscn` | (частина TutorialManager) | `tutorial_config.json` |

---

## Персонаж та вороги

| Сцена | Шлях | Скрипт |
|-------|------|--------|
| Гравець | `res://scenes/Player.tscn` | `scripts/Player.gd` ✅ |
| Базовий ворог | `res://scenes/enemies/BaseEnemy.tscn` | `scripts/enemies/BaseEnemy.gd` ✅ |
| Босс базовий | `res://scenes/enemies/Boss.tscn` | `scripts/enemies/BossAI.gd` ❌ |

---

## Душі

| Сцена | Шлях | Опис |
|-------|------|------|
| Невинна душа | `res://scenes/souls/InnocentSoul.tscn` | Базова — підібрати і нести |
| Спляча душа | `res://scenes/souls/SleepingSoul.tscn` | Вимагає міні-гру |
| Мімік | `res://scenes/souls/MimicSoul.tscn` | Виглядає як душа, пастка |
| Прихована душа | `res://scenes/souls/HiddenSoul.tscn` | За секретною стіною |

---

## Платформи

| Сцена | Шлях | Скрипт |
|-------|------|--------|
| Базова платформа | `res://scenes/platforms/BasePlatform.tscn` | `scripts/platforms/BasePlatform.gd` ✅ |
| Кожен тип платформи | `res://scenes/platforms/{type}.tscn` | успадковує BasePlatform |

Типи: `stone`, `one_way`, `crumbling`, `moving_vertical`, `moving_horizontal`, `bounce`, `pressure_plate`, `mud`, `lava_edge`, `falling`, `sin_platform`, `faith`, `conveyor`, `illusory`, `ice`, `soul_bridge`

---

## Кімнати для генерації рівнів

```
res://scenes/rooms/
  circle_1/
    room_entrance_01.tscn
    room_main_01.tscn ... room_main_24.tscn
    room_exit_01.tscn
  circle_2/ ...
  circle_10/
```

> ~22–30 кімнат на коло. Всього ~250 кімнат. Детально: `doc/level_generation.md`

---

## Autoload скрипти (без сцен)

| Autoload | Шлях | Статус |
|----------|------|--------|
| GameManager | `res://GameManager.gd` | ✅ |
| SaveManager | `res://SaveManager.gd` | ✅ |
| LevelConfig | `res://LevelConfig.gd` | ✅ |
| AdsManager | `res://scripts/AdsManager.gd` | ✅ |
| TutorialManager | `res://scripts/TutorialManager.gd` | ❌ треба створити + зареєструвати |
| LevelGenerator | `res://scripts/LevelGenerator.gd` | ❌ треба створити + зареєструвати |

---

## Порядок розробки (рекомендований)

1. `Player.tscn` + `Level.tscn` + базові платформи → можна бігати і стрибати
2. `HUD.tscn` + `SaveManager` → видно HP і гріх
3. `BaseEnemy.tscn` → є вороги
4. `InnocentSoul.tscn` → можна підбирати і нести душі
5. `LevelComplete.tscn` + `Hub.tscn` → базовий цикл рівень → хаб → рівень
6. `MainMenu.tscn` → повноцінний старт
7. `LevelGenerator.gd` → процедурні рівні
8. `BossAI.gd` → бос-арени
9. `TutorialManager.gd` → підказки
10. Решта UI екранів, налаштування, IAP
