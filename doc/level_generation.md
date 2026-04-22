# Генерація Рівнів

> Файл-довідник. Джерело: `level_generation_config.json`, `levels_config.json`

---

## Підхід: Гібридний

**Всього рівнів: 145** (100 основних + 45 бічних).  
~35 основних — **статичні** (вручну). ~65 основних — **процедурні** (збираються з кімнат-блоків).  
45 бічних (лабіринт, void, escape) — всі процедурні, генеруються через той самий пул що і батьківське коло.

---

## Бічні рівні (branch levels)

**ID схема:** `branch_id = parent_id + 100`. Бічні рівні мають `id > 100`.

| Батьківський рівень | Тип гілки | Напрям | Branch ID |
|--------------------|-----------|--------|-----------|
| pos 3 кожного кола | `labyrinth` | праворуч | `+100` |
| pos 4 кожного кола | `void` | ліворуч | `+100` |
| pos 5 кожного кола | `escape` | праворуч | `+100` |
| pos 7 кожного кола | `labyrinth` | праворуч | `+100` |
| pos 9 кожного кола | `void` | ліворуч | `+100` |

Приклади (коло 1): level 3 → branch **103**, level 4 → branch **104**, level 9 → branch **109**.  
Приклади (коло 2): level 13 → **113**, level 14 → **114** … (коло 9): level 83 → **183**.

**Бічні рівні в `LevelGenerator.gd`:**
- `_is_branch(level_id)` → `level_id > 100`
- `_parent_of(level_id)` → `level_id - 100`
- `generate(branch_id)` — використовує `circle` і `difficulty` батьківського рівня; `is_branch = true`, `parent_id` заповнені в `GeneratedLevel`.

---

## Статичні рівні (~35)

| Тип | Рівні | Причина |
|-----|-------|---------|
| Босс-арени | 10, 20, 30, 50, 70, 100 | Точне розміщення пасток і меж арени |
| Відкривачі кола | 1, 11, 21, 31, 41, 51, 61, 71, 81, 91 | Наративний момент, God message, особлива атмосфера |
| Рівні з прихованими душами | визначається з `souls_collection.json` | Підказки і схованки повинні бути точними |
| Milestone | 50, 75, 99, 100 | Ключові наративні точки |

---

## Процедурні рівні (~65)

### Алгоритм збірки

```
Seed = level_id  →  однаковий рівень завжди однаковий
↓
Вибрати кімнати з пулу кола (3–6 кімнат)
↓
[Entrance] → [Main × 1-4] → [Exit]
↓
Розмістити душу в Main кімнаті (з souls_collection.json)
↓
Застосувати difficulty_injection (enemy_count_mod, trap_density)
```

**Типи кімнат:**
- `entrance` — завжди перша, без ворогів, гравець орієнтується
- `main` — вороги, душі, пастки, платформи
- `exit` — вихід, може мати охорону

### Розміщення душ
- Для кожного рівня береться відповідна іменна душа з `souls_collection.json`
- Розміщується в `main` кімнаті за правилами кола (`soul_mechanics_config.json → guard_scaling`)

### Seed
`seed = level_id` → однаковий рівень завжди генерується однаково. Гравець може вивчити рівень при повторній спробі.

---

## Складність всередині кола

| Позиція в колі | Enemy mod | Пастки | Кімнат |
|----------------|-----------|--------|--------|
| Рівні 1–3 | −1 ворог | low | 3 |
| Рівні 4–6 | 0 | medium | 4 |
| Рівні 7–9 | +1 ворог | high | 5 |
| Рівень 10 | — | — | Boss (статичний) |

---

## Шаблон типів рівнів на коло

`platformer → platformer → vertical → platformer → labyrinth → platformer → void → platformer → escape → boss`

Повторюється для кожного кола. `void` і `escape` завжди на фіксованих позиціях.

---

## Пули кімнат по колах

| Коло | Стиль | Вороги | Особливість |
|------|-------|--------|-------------|
| 1 | antechamber_stone | shadow_lost, pale_wanderer | — |
| 2 | wind_corridors | wind_shade, pale_wanderer | вітер штовхає гравця горизонтально |
| 3 | fire_caverns | flame_imp, fire_hound | лава, вогняні джети |
| 4 | dark_swamps | swamp_crawler, bog_phantom | болото, отрута |
| 5 | rage_ruins | rage_shade, frost_knight | frost_knight — рідкісний на рівнях 7–9 |
| 6 | heresy_cathedral | heresy_priest, cursed_stone | faith_platforms зникають при гріх > 50% |
| 7 | violence_fortress | hell_knight, blood_hound | soul_bridge, лава |
| 8 | fraud_machine | mimic_shade, clockwork_guard | illusory платформи — треба спостерігати |
| 9 | betrayal_ice | frost_shade, silent_stalker | крига — ковзання, планування стрибків |
| 10 | throne_abyss | void_sentinel, throne_guard, hell_knight | всі типи платформ і пасток |

> Кількість кімнат у пулі: 22–30 на коло. Детально: `level_generation_config.json → room_pools`

---

## Скрипт: LevelGenerator.gd

**Реалізовані методи:**

```
_load_config()              — читає level_generation_config.json
_load_souls()               — читає souls_collection.json, будує _hidden_soul_levels
_is_static(level_id)        — true якщо рівень статичний
_is_branch(level_id)        — true якщо level_id > 100 (бічний рівень)
_parent_of(level_id)        — повертає level_id - 100 (або 0 для основних)
generate(level_id) → GeneratedLevel:
    is_branch = _is_branch(level_id)
    effective_id = parent_id якщо branch, інакше level_id
    circle = _circle_of(effective_id)
    seed(level_id)
    diff = _difficulty_for_index(_index_in_circle(effective_id))
    room_scenes = _pick_rooms(circle, room_count)
    soul_data = _soul_for_level(level_id, circle)
_pick_rooms(circle, count)  → Array[String] — шляхи до .tscn
_soul_for_level(level_id, circle) — з _hidden_soul_levels або з пулу кола
is_branch(level_id)         — публічна обгортка
get_parent_id(level_id)     — публічна обгортка
```

**GeneratedLevel — поля результату:**
`level_id`, `circle`, `is_static`, `is_branch`, `parent_id`, `room_scenes`, `soul_id`, `soul_data`, `enemy_count_mod`, `trap_density`, `room_count`, `circle_style`, `difficulty_zone`, `vertical_spacing`, `platform_type_hint`, `platform_width`

| Нове поле | Тип | Опис |
|-----------|-----|------|
| `difficulty_zone` | `String` | Тир зони: `"easy"` / `"medium"` / `"hard"` / `"extreme"` |
| `vertical_spacing` | `float` | Відстань між рядами платформ (px) |
| `platform_type_hint` | `String` | Тип платформи для zone-special рядів |
| `platform_width` | `float` | Ширина zone-special платформи (px) |

**Сцени кімнат:** `res://scenes/rooms/circle_{N}/room_{type}_{index}.tscn`

---

## Difficulty Zones (зони складності)

Кожен рівень отримує тир складності через `LevelGenerator.get_zone(level_id)`.

| Тир | Відстань | Тип платформи | Ширина |
|-----|----------|---------------|--------|
| `easy` | 100 px | `stone` | 220 px |
| `medium` | 150 px | `stone` | 110 px |
| `hard` | 200 px | `moving_horizontal` | 110 px |
| `extreme` | 200 px | `moving_vertical` | 110 px |

**Прогресія** (позиція в колі 0–9):

| Позиції | Базовий тир |
|---------|-------------|
| 0–2 | `easy` |
| 3–5 | `medium` |
| 6–8 | `hard` |
| 9 | `extreme` |

Кола 4–7: +1 тир. Кола 8–10: +2 тири.

**Валідація шляху:** `LevelGenerator.missing_bridge_ys()` — BFS перевіряє чи досяжний кожен ряд знизу вгору. Якщо проміжок > MAX\_JUMP\_HEIGHT (200 px) — вставляється bridge-платформа.  
`moving_vertical` враховує подорож ±80 px → ефективна висота досягнення 280 px.

---

## Типи платформ (всі кола)

`stone`, `one_way`, `crumbling`, `moving_vertical`, `moving_horizontal`, `bounce`, `pressure_plate`, `mud`, `ash`, `lava_edge`, `chain`, `falling`, `sin_platform`, `faith`, `conveyor`, `illusory`, `ice`, `soul_bridge`

> Детальний опис кожного типу: `platforms_config.json`
