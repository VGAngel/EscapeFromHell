# Генерація Рівнів

> Файл-довідник. Джерело: `level_generation_config.json`, `levels_config.json`

---

## Підхід: Гібридний

~35 рівнів — **статичні** (вручну). ~65 рівнів — **процедурні** (збираються з кімнат-блоків).

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

**Що має робити:**

```
_load_config()          — читає level_generation_config.json
_is_static(level_id)    — повертає true якщо рівень статичний
generate(level_id)      — головна функція:
    seed(level_id)
    rooms = _pick_rooms(circle, difficulty)
    _assemble_rooms(rooms)
    _place_soul(level_id)
    _apply_difficulty(level_index_in_circle)
_pick_rooms(circle, difficulty) → Array[PackedScene]
_assemble_rooms(rooms)  — з'єднує кімнати послідовно
_place_soul(level_id)   — вибирає душу з souls_collection.json
```

**Сцени кімнат:** `res://scenes/rooms/circle_{N}/room_{type}_{index}.tscn`

---

## Типи платформ (всі кола)

`stone`, `one_way`, `crumbling`, `moving_vertical`, `moving_horizontal`, `bounce`, `pressure_plate`, `mud`, `ash`, `lava_edge`, `chain`, `falling`, `sin_platform`, `faith`, `conveyor`, `illusory`, `ice`, `soul_bridge`

> Детальний опис кожного типу: `platforms_config.json`
