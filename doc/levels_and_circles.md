# Рівні та Кола — Детальний Довідник

> **Призначення:** єдине джерело правди про те, як виглядають і генеруються рівні в кожному з 10 кіл пекла.
> GDD містить тільки загальну механіку — деталі сюди.
>
> **Сусідні документи:**
> - [GDD.md](GDD.md) — загальна механіка гри.
> - [level_generation.md](level_generation.md) — короткий опис гібридного підходу (статичні + процедурні рівні).
>
> **Конфіги, які доповнюють цей документ:**
> - [`levels_config.json`](../levels_config.json) — кожен рівень + `circle_defaults` (ворог-пул, тематика, тайлсет).
> - [`level_generation_config.json`](../level_generation_config.json) — стиль кола, room_pools, гібридна генерація.
> - [`scripts/levels/LevelGenerator.gd`](../scripts/levels/LevelGenerator.gd) — `VERTICAL_SPACING`, `ZONE_PLATFORMS`, `MAX_JUMP_HEIGHT`.
> - [`scripts/rooms/PlaceholderRoom.gd`](../scripts/rooms/PlaceholderRoom.gd) — `SECTION_PROFILES`, `TIER_SECTIONS`, Markov-шахта.

---

## 1. Загальна структура гри

| | |
|---|---|
| Кіл | **10** (за Данте) |
| Основних рівнів | **100** (10 рівнів на коло) |
| Бічних рівнів | **45** (5 на кола 1–9; коло 10 без гілок) |
| Загалом | **145** |
| Прихованих душ | **20** (по 2 на коло) |

**Нумерація:**
- Основні: `1..100`. Коло визначається як `ceil(level_id / 10)`.
- Бічні: `parent_id + 100` (наприклад, level 3 → branch 103). `is_branch ⇔ id > 100`.

**Шаблон кола (кола 1–9):**

```
[⛩ Altar]
   ↓
[1. vertical — наративний]   ← статичний, перший рівень кола, божественне послання
[2. vertical]
[3. vertical] ─→ [3.1 labyrinth]   обов'язковий, праворуч
[4. vertical] ←─ [4.1 void]        необов'язковий, ліворуч
[5. vertical] ─→ [5.1 escape]      обов'язковий, праворуч
[6. vertical]
[7. vertical] ─→ [7.1 labyrinth]   обов'язковий, праворуч
[8. vertical]
[9. vertical] ←─ [9.1 void]        необов'язковий, ліворуч
[10. boss]
```

**Коло 10 — особлива структура:**

| Позиція | level_id | Тип | Примітка |
|---|---|---|---|
| 1 | 91 | vertical | наративний |
| 2 | 92 | labyrinth | |
| 3 | 93 | vertical | |
| 4 | 94 | labyrinth | |
| 5 | 95 | void | 15 душ — найбільший рівень гри |
| 6 | 96 | escape | chase_all_elements |
| 7 | 97 | vertical | |
| 8 | 98 | escape | chase_lucifer_hand |
| 9 | 99 | vertical | передфінальний |
| 10 | 100 | boss | Люцифер |

---

## 2. Типи рівнів — як виглядають

### 2.1 `vertical` — Шахта (хребет кола)

**Суть:** гравець спавниться **зверху** біля вівтаря, спускається донизу, збирає іменну душу, повертається до вівтаря для доставки.

**Поточна архітектура (квітень 2026 — після рефактору в [b6964f37](https://github.com/VGAngel/EscapeFromHell/commit/b6964f37)):**

Один рівень = **одна суцільна шахта** (`PlaceholderRoom` з `room_type = "shaft"`).
Висота = `room_count × VIEWPORT_HEIGHT × VERTICAL_ROOM_SCREENS` = `room_count × 3840 px`.
До рефактору шахта складалася з N стекових 2-екранних кімнат, що створювало візуальні розриви; тепер це історія.

```
              ⛩ ВІВТАР (топ-рядок шахти)
              ━━━━━━━━━━━━━━━━━━━━━━
              ▓▓▓▓     ▓▓▓▓        rest section (старт)
                    ▓▓▓▓▓▓▓
              ▓▓                   challenge: вузькі + спецтипи
                       ▓▓▓
              ░░░░░░░  ░░░░        spike: crumbling/bounce/one_way
                  ▓▓
              ▓▓▓▓                 breath: широкі + bridges
                       ▓▓▓▓▓
              …       ↓             (Markov генерує наскрізно ~85 рядків
                                     на room_count=4, секційний ритм
                                     повторюється до низу)
              ▓▓▓     ▓▓▓
                       💀          ворог (один із room_count розкиданих)
              ▓▓                   іменна душа на ~50–70% висоти
                  🕊
              ▓▓▓▓     ▓▓▓
              ━━━━━━━━━━━━━━━━━━━━━━
              ⛔ EXIT (низ шахти, заблокований до доставки душі)
```

**Спавни (на одну шахту):**

| Сутність | Кількість | Розподіл |
|---|---|---|
| Вороги | `room_count` | Рівномірно по рядках (виключно перші 2 і останні 3) |
| Іменна душа | 1 | На рядку ~50–70% висоти |
| Звичайні душі | `room_count − 2` (мін 1) | Рівномірно |
| Бонуси | `room_count / 2` (мін 1) | Рівномірно |

**Генерація платформ — Markov + Sections:**

Розділ детальний у §4 нижче. Коротко:
- Висота шахти ділиться на **секції** (rest / challenge / spike / breath) за шаблоном тиру.
- Кожна секція задає ваги для ширини, типу платформи і шансу bridge.
- X-позиція кожного рядка обирається через Markov chain з 4 зон + reachability snap-back.

**Камера:** вертикальне стеження за гравцем; горизонтальна мертва зона ±60 px.

**Ширина кімнати:** 1080 px (повний viewport).

**Win condition:**
1. Підібрати іменну душу.
2. Якщо є обов'язковий бічний (3.1, 5.1, 7.1) — пройти його.
3. Повернутись до вівтаря з душею → доставка [E].

---

### 2.2 `void` — Пустота

**Суть:** велика відкрита печера без чіткого шляху. Дослідницький рівень.

```
←──────────── 1600 px (5 екранів) ────────────→
↑
│  1200 px   .  .  ▓▓▓▓  .  .  💀  .  .  .
│  (4 екр.)  .  ▓▓▓▓  .  .  🕊  .  .  .  ▓▓▓
│            .  .  .  💀  .  .  .  ▓▓▓  .  .
│            ▓▓▓  .  .  🕊  .  .  .  .  .  .   ← звичайні + іменна
│            .  .  .  .  .  ▓▓▓  .  .  💀
↓            [🕳 вхід з vertical]    [EXIT — закритий]
```

| Параметр | Значення |
|---|---|
| Розміри | ~1600×1200 px (5×4 екрани) |
| Камера | зум 0.8, lookahead вільний |
| Душ | 1 іменна + 3–5 звичайних |
| Ліміт смертей | 5 |
| Вихід | відкривається після збору іменної + усіх **підсвічених** душ |
| Прихована душа | з'являється тут частіше за інші типи |

Корисні апгрейди: `tracker`, `map` (показує контур печери на 3 сек), `soul_sense`.

---

### 2.3 `labyrinth` — Лабіринт

**Суть:** горизонтальна сітка тунелів з тупиками. Іменна душа завжди в тупику.

```
←─────────────── 2400 px (7–8 екранів) ───────────────→

[🕳 вхід]                                       [EXIT →]
   │                                                  ↑
───┴──────┬──────────────────────┬───────────────────┘
          │                      │
   ────┐  │  ┌──────────┐  ┌────┘  ┌─────────────┐
       │  │  │  тупик 1 │  │       │  🕊 іменна  │ ← в тупику
   ────┘  └──┘  🪙 душа │  └────┐  │  душа        │
              └──────────┘      │  └─────────────┘
                                │
   ────────────────────────────┬┘
                               │
                          [тупик 2]
```

| Параметр | Значення |
|---|---|
| Розміри | ~2400×640 px (7–8 екранів × 2 рівні висоти) |
| Камера | горизонтальне стеження, lookahead 180 px |
| Душ | 1 іменна + 2–3 звичайних |
| Мінімап | недоступний (intentionally) |
| Тупики | мінімум 2 на рівень |
| Міміки | у тупиках на колах 8–9 |

Корисні апгрейди: `quiet_step`, `distraction`, `recognition`, `map`, `premonition`.

---

### 2.4 `escape` — Втеча

**Суть:** тільки підйом угору; знизу піднімається переслідувач (лава / хвиля / сутність).

```
   ←── 400 px ──→

  ╔══════════════╗   ← EXIT (верх)
  ╚══════╤═══════╝
         │
  ┌──────────────────┐
  │   ВЕРХНЯ  ~600px │
  │  ▓▓  ▓▓▓  ▓▓    │
  │           🕊     │  звичайна (ризикована, на 80% висоти)
  └──────┬───────────┘
  │   СЕРЕДНЯ ~800   │
  │  ▓▓▓▓  ▓▓▓      │
  │   🕊 іменна      │  на 60–70% висоти, в ніші збоку
  │  ▓  ▓▓▓  ▓▓▓    │
  ┌──────────────────┐
  │   НИЖНЯ ~600     │
  │  ▓▓▓  ▓▓  ▓▓▓   │
  │       🕊         │  легка душа на 30%
  └──────┬───────────┘
         │ ← [вхід гравця]
  ████████████████     ← ПЕРЕСЛІДУВАЧ (стартує через 2 сек)
```

| Параметр | Значення |
|---|---|
| Висота | 2400–3200 px (6–8 екранів) |
| Камера | lookahead 200 px вгору; легке потрясіння при наближенні переслідувача |
| Душ | 1 іменна + 1–2 звичайних |
| Переслідувач | швидкість трохи нижча за гравця без апгрейдів; підбір душі сповільнює |
| Контакт із переслідувачем | −1 HP + відштовхування вгору (не смерть) |
| Respawn | завжди на початку рівня |

Критичні апгрейди: `quick_pickup`, `double_jump`, `jump`.

---

### 2.5 `boss` — Бос-арена

**Суть:** замкнена арена з босом. Перемога не через вбивство, а через виконання механіки.

| Параметр | Значення |
|---|---|
| Розміри | ~800×600 px (2–3 екрани) |
| Камера | фіксований зум, без lookahead |
| Душ | 1–2 іменних (звільняються після перемоги) |
| Ліміт смертей | немає |
| Респ | у вівтарі біля входу в арену |

Усі бос-рівні — **статичні** (не процедурні). Геометрія арени підібрана під механіку конкретного боса (зібрати уламки, активувати тотеми, оглушити посохом тощо).

---

## 3. Тематика 10 кіл

> Кожне коло має тематику з канону Данте + свій настрій.
> Поточна імплементація в `levels_config.json → circle_defaults` подекуди
> розходиться з канонічними мотивами Данте — нижче відображено фактичний стан
> на квітень 2026; підрозділ «Канон» — для довідки.

### Загальна таблиця

| Коло | Канон Данте | `theme` | Стиль (room_pool) | Tileset | Ключовий настрій |
|---|---|---|---|---|---|
| 1 | Лімб | `grey_stone` | `antechamber_stone` | tileset1 | Передпокій пекла, тиша, сірість |
| 2 | Хіть | `swamp` | `wind_corridors` | tileset1 | Вітер, приреченість, скрипи |
| 3 | Жага / обжерливість | `lava` | `fire_caverns` | tileset2 | Жар, лава, червоне світло |
| 4 | Жадібність | `gold` | `dark_swamps` | tileset2 | Золотий блиск, важкість, tomes |
| 5 | Гнів | `ice` | `rage_ruins` | tileset2 | Розбите каміння, агресія |
| 6 | Єресь | `palace` | `heresy_cathedral` | tileset2 | Готичні арки, faith-платформи |
| 7 | Насилля | `dead_forest` | `violence_fortress` | tileset2 | Кров, ліс самогубств |
| 8 | Шахрайство | `machine` | `fraud_machine` | tileset2 | Шестерні, ілюзорні платформи |
| 9 | Зрада | `void_space` | `betrayal_ice` | tileset2 | Мертва тиша, ковзання |
| 10 | Люцифер | `lucifer_throne` | `throne_abyss` | tileset2 | Все одночасно, останній спуск |

> **Розбіжності theme ↔ style** (наприклад circle 5: `theme=ice` але `style=rage_ruins`)
> позначають історичну плутанину між двома конфігами. Перед затвердженням арту
> треба зафіксувати, який саме мотив рендерити, і вирівняти обидва файли.

### 3.1 Коло 1 — Лімб (Antechamber)

| | |
|---|---|
| **Атмосфера** | Сіро-кам'яний передпокій, тиша, ехо. Жодного багаття чи кольору. |
| **Колір фону (`CIRCLE_COLORS`)** | `Color(0.10, 0.04, 0.20)` — глибокий фіолетовий |
| **Вороги** | `skeleton`, `skeleton_warrior`, `skeleton_archer` |
| **Пастки** | `collapse`, `ghost_platform`, `bottom_spikes` |
| **Бонуси** | `manna`, `angel_feather`, `prayer_stone` |
| **Платформи** | `stone`, `one_way`, `crumbling`, `moving_vertical`, `pressure_plate` |
| **Кімнат у пулі** | 24 |
| **Тайлсет** | `tileset1` |
| **Приблизний look** | Похмурі кам'яні плити, без декору. Базовий рівень для навчання. |

### 3.2 Коло 2 — Хіть (Wind Corridors)

| | |
|---|---|
| **Атмосфера** | Постійний вітер, що штовхає гравця по горизонталі. Вузькі коридори. |
| **Колір фону** | `Color(0.04, 0.10, 0.20)` — глибокий синій |
| **Вороги** | `skeleton`, `undead_archer`, `skeleton_witch` |
| **Пастки** | `sinking_platform`, `poison_gas`, `ghost_platform` |
| **Бонуси** | `holy_water`, `hope_torch`, `broken_halo` |
| **Платформи** | `stone`, `one_way`, `moving_horizontal`, `moving_vertical`, `bounce` |
| **Особливість** | **Вітер** штовхає гравця горизонтально — стрибки потребують поправки |
| **Тайлсет** | `tileset1` |

### 3.3 Коло 3 — Жага (Fire Caverns)

| | |
|---|---|
| **Атмосфера** | Лава, червоне світло, вогняні спалахи. |
| **Колір фону** | `Color(0.20, 0.08, 0.04)` — обвуглений червоний |
| **Вороги** | `fire_golem`, `demon_archer`, `blood_demon` |
| **Пастки** | `lava_pit`, `lava_flow`, `bottom_spikes` |
| **Бонуси** | `holy_water`, `righteous_shadow`, `prayer_stone` |
| **Тайлсет** | `tileset2` ← **перший рівень нового арт-сету** |

### 3.4 Коло 4 — Жадібність (Gold / Dark Swamps)

| | |
|---|---|
| **Атмосфера** | Золотий блиск на темному фоні, важкі предмети, скарби-приманки. |
| **Колір фону** | `Color(0.04, 0.16, 0.08)` — болотний зелений |
| **Вороги** | `succubus`, `mimic`, `hell_knight` |
| **Пастки** | `treasure_chest` (фейкова), `fake_soul`, `mirror` |
| **Бонуси** | `sinner_map`, `burnt_wings`, `manna` |
| **Особливість** | **Treasure chests** — приманка, активація шкодить |
| **Тайлсет** | `tileset2` |

### 3.5 Коло 5 — Гнів (Ice / Rage Ruins)

| | |
|---|---|
| **Атмосфера** | Розбиті руїни з кригою. Звуки розколювання. |
| **Колір фону** | `Color(0.18, 0.12, 0.02)` — золотий пил |
| **Вороги** | `ice_golem`, `magician_demon` |
| **Пастки** | `ice_slide`, `cracking_ice`, `ghost_platform` |
| **Бонуси** | `hope_torch`, `angel_feather`, `holy_water` |
| **Особливість** | Поверхні ковзкі, шипи з'являються після затримки |
| **Тайлсет** | `tileset2` |

### 3.6 Коло 6 — Єресь (Heresy Cathedral)

| | |
|---|---|
| **Атмосфера** | Готичні арки, поховальні горни, faith-платформи. |
| **Колір фону** | `Color(0.02, 0.14, 0.18)` — крижаний бірюзовий |
| **Вороги** | `hell_knight`, `demon_archer`, `ghost_warrior`, `fallen_angel` |
| **Пастки** | `falling_column`, `wind_blast`, `collapse` |
| **Бонуси** | `prayer_stone`, `broken_halo`, `manna` |
| **Особливість** | **Faith платформи** зникають коли гріх > 50% |
| **Тайлсет** | `tileset2` |

### 3.7 Коло 7 — Насилля (Violence Fortress / Dead Forest)

| | |
|---|---|
| **Атмосфера** | Кривавий ліс самогубств, фортечні стіни, лава у траншеях. |
| **Колір фону** | `Color(0.14, 0.02, 0.14)` — багряні сутінки |
| **Вороги** | `skeleton_witch`, `necromancer`, `mimic`, `phantom_knight` |
| **Пастки** | `voice_of_relatives`, `mirror`, `bottom_spikes` |
| **Бонуси** | `sinner_map`, `righteous_shadow`, `hope_torch` |
| **Особливість** | `soul_bridge` платформи (з'являються коли носиш душу) |
| **Тайлсет** | `tileset2` |

### 3.8 Коло 8 — Шахрайство (Fraud Machine)

| | |
|---|---|
| **Атмосфера** | Іржаві шестерні, конвеєри, парові гейзери. |
| **Колір фону** | `Color(0.16, 0.08, 0.00)` — іржавий метал |
| **Вороги** | `stone_golem`, `blood_demon`, `magician_demon` |
| **Пастки** | `crusher`, `conveyor`, `gear_trap`, `steam_jet` |
| **Бонуси** | `holy_water`, `angel_feather`, `prayer_stone` |
| **Особливість** | **Illusory** платформи — деякі візуальні платформи фейкові |
| **Тайлсет** | `tileset2` |

### 3.9 Коло 9 — Зрада (Betrayal Ice / Void)

| | |
|---|---|
| **Атмосфера** | Замерзле озеро, мертва тиша, чорний простір. |
| **Колір фону** | `Color(0.08, 0.08, 0.08)` — попелястий сірий |
| **Вороги** | `dark_entity`, `reaper`, `phantom_knight` |
| **Пастки** | `gravity_shift`, `void_tear`, `darkness` |
| **Бонуси** | `burnt_wings`, `righteous_shadow`, `broken_halo` |
| **Особливість** | **Gravity shifts** змінюють напрям падіння |
| **Тайлсет** | `tileset2` |

### 3.10 Коло 10 — Люцифер (Throne Abyss)

| | |
|---|---|
| **Атмосфера** | Усі мотиви разом, кров на тлі чорної прірви. |
| **Колір фону** | `Color(0.20, 0.00, 0.00)` — кривавий червоний |
| **Вороги** | `fallen_angel`, `dark_entity`, `demon_archer`, `mimic` |
| **Пастки** | усі типи з попередніх кіл |
| **Бонуси** | мікс із усіх кіл |
| **Особливість** | Боси на 100 — Люцифер; рівні 95–98 мають унікальну геометрію |
| **Тайлсет** | `tileset2` |

---

## 4. Процедурна генерація шахти (vertical)

### 4.1 Висотна сітка `_compute_all_rows`

```
floor_y      = room_height − WALL_T − safe_area_bottom
ceiling_y    = WALL_T + safe_area_top
spacing      = max(zone.spacing, MAX_JUMP_HEIGHT × 0.9) = ≥ 180 px
              (для is_vertical; легкий тир дав би 100 px,
               але тоді платформи лізуть одна на одну)
rows         = [floor_y − spacing, floor_y − 2·spacing, …]
              поки y ≥ ceiling_y + 120
```

Для `room_count = 4` (за замовчуванням) шахта = 15 360 px → ~85 рядків.

### 4.2 Markov + Section pacing

Для кожного рядка генератор обирає:

1. **Секцію** — з шаблону тиру (`TIER_SECTIONS`).
2. **Зону X** — Markov chain з 4 зон (центри 0.18, 0.39, 0.61, 0.82 від `room_width`), ваги переходів `[0.08, 0.40, 0.12, 0.04]` для |Δ|=0..3, заборона трьох однакових зон поспіль.
3. **Ширину** і **тип платформи** — зважений мішок з профілю секції.
4. **Шанс bridge** (дві платформи на рядку) — теж із профілю; заборона двох bridges підряд.
5. **Reachability snap-back** — якщо горизонтальна відстань між сусідніми платформами більша за `_max_horizontal_jump(v_gap)` + півширини обох — X нового рядка стискається до досяжного.

**Шаблони секцій по тирах** (`TIER_SECTIONS`):

| Тир | Послідовність |
|---|---|
| `easy` | rest → challenge → breath → challenge → rest |
| `medium` | rest → challenge → spike → breath → challenge → rest |
| `hard` | challenge → spike → breath → spike → challenge → spike |
| `extreme` | spike → challenge → spike → breath → spike → spike |

Шаблон зациклюється до заповнення усіх рядків шахти.

**Профілі секцій** (`SECTION_PROFILES`, ширини × множник `_platform_width`):

| Секція | Length | Widths | Types | bridge_chance |
|---|---|---|---|---|
| `rest` | 2–3 | wide(1.5)×0.5, xwide(2.2)×0.5 | stone | 0% |
| `challenge` | 3–5 | narrow(0.7)×0.15, shelf(1.0)×0.45, wide(1.5)×0.4 | stone 0.8, _hint 0.2 | 5% |
| `spike` | 3–4 | narrow×0.45, shelf×0.45, wide×0.10 | stone 0.30, crumbling 0.25, bounce 0.10, one_way 0.10, _hint 0.25 | 0% |
| `breath` | 2–3 | wide×0.7, xwide×0.3 | stone | 20% |

`_hint` = `_platform_type_hint` зони (наприклад, `moving_vertical` для extreme).

### 4.3 Reachability check

```
v_gap = prev_row_y − new_row_y          (>0 = новий рядок вище)
max_h = lerp(SAME_LEVEL_REACH=240, MAX_UP_REACH=120, v_gap / MAX_JUMP_HEIGHT) × 1.15
max_dx_center = max_h + (prev_w + new_w) / 2
if |x − prev_x| > max_dx_center:
    x = prev_x + sign(x − prev_x) × max_dx_center
    x = clamp(x, room_width × 0.10, room_width × 0.90)
```

Гарантує, що з кожної single-платформи **фізично** можна допригнути до наступної.

### 4.4 Y-jitter

Для рядків крім першого і останнього: `y += rng.randf_range(±gap × 0.12)` — щоб платформи не вишиковувались у геометричну сітку.
Поточне максимальне відхилення ±21 px (для spacing = 180), що іноді може дати gap ~210 px > MAX_JUMP. Запланований фікс — зменшити до ±5–8%.

### 4.5 Спавни в шахті (`_spawn_distributed`)

Хелпер обирає `count` рядків рівномірно по висоті, виключаючи перші 2 та останні 3 (там вівтар і вихід):

```
for i in count:
    t = (i + 0.5) / count
    row_idx = first + round(t × (last − first))
```

| Сутність | `count` | З чого береться тип |
|---|---|---|
| Вороги | `room_count` | `LevelConfig.get_enemies(level_id)` (rotate by slot) |
| Іменна душа | 1 | `souls_collection.json` через `LevelGenerator.get_soul_data()` |
| Звичайні душі | `max(1, room_count − 2)` | `Soul.tscn` загальний |
| Бонуси | `max(1, room_count / 2)` | `LevelConfig.get_bonuses(level_id)` (rotate by slot) |

---

## 5. Difficulty Zones (зони складності)

Кожен vertical-рівень отримує **тир** через `LevelGenerator.get_zone(level_id)`.

| Тир | spacing (px) | Тип спецплатформи | Ширина бази |
|---|---|---|---|
| `easy` | 100 | `stone` | 220 |
| `medium` | 150 | `stone` | 110 |
| `hard` | 200 | `moving_horizontal` | 110 |
| `extreme` | 200 | `moving_vertical` | 110 |

> Для шахти spacing завжди підтягується до `≥ MAX_JUMP_HEIGHT × 0.9 = 180 px`,
> бо щільніше — зайва щільність (платформа на кожні 100 px перетворює рівень на «стіну»).

**Прогресія тирів усередині кола** (за позицією 0–9 у колі):

| Позиції | Базовий тир |
|---|---|
| 0–2 | `easy` |
| 3–5 | `medium` |
| 6–8 | `hard` |
| 9 | `extreme` |

Модифікатори по колах:
- Кола 1–3: без зміни.
- Кола 4–7: тир `+1` (easy → medium тощо).
- Кола 8–10: тир `+2`.

---

## 6. Камера та фізика

| Константа | Значення | Файл |
|---|---|---|
| `VIEWPORT_WIDTH` | 1080 | `PlaceholderRoom.gd` |
| `VIEWPORT_HEIGHT` | 1920 | `PlaceholderRoom.gd` |
| `VERTICAL_ROOM_SCREENS` | 2 | `PlaceholderRoom.gd` |
| `WALL_T` | 32 | `PlaceholderRoom.gd` |
| `SIDE_WALL_T` | 60 | `PlaceholderRoom.gd` |
| `PLATFORM_T` | 30 | `PlaceholderRoom.gd` |
| `MAX_JUMP_HEIGHT` | 200 | `LevelGenerator.gd` |
| `walk_speed` | 180 | `Player.gd` |
| `jump_force` | 600 | `Player.gd` |
| `min_jump_force` | 240 | `Player.gd` (variable jump) |
| `gravity` | 900 | `Player.gd` |
| `max_fall_speed` | 600 | `Player.gd` |
| `air_acceleration` | 500 | `Player.gd` |

**Похідні:**

- Висота повного стрибка ≈ 200 px (= `MAX_JUMP_HEIGHT`).
- Час до apex ≈ 0.667 с.
- Горизонтальна дальність на максимальному стрибку вгору ≈ 120 px.
- Горизонтальна дальність на стрибку «на той самий рівень» ≈ 240 px.

**Fall damage** (див. також [GDD.md → HP та пошкодження](GDD.md#hp-та-пошкодження)):

| Падіння | У стрибках | Шкода |
|---|---|---|
| < 300 px | < 1.5 | — |
| 300 – 500 px | 1.5 – 2.5 | −1 HP |
| 500 – 800 px | 2.5 – 4 | −2 HP |
| > 800 px | > 4 | смерть |

Апгрейд `soft_landing` множить усі пороги на 1.5×.

---

## 7. Конфіги — повний reference

### 7.1 `levels_config.json`

**Структура:**

```jsonc
{
  "version": "1.3",
  "enums": { "level_types": [...], "soul_types": [...], "bonus_types": [...],
             "trap_types": [...], "enemy_types": [...], "boss_types": [...] },

  "enemy_sprites": { "skeleton": "<asset_folder>", ... },

  "circle_defaults": {
    "1": {
      "theme": "grey_stone",
      "tileset": "tileset1",            // ← новий ключ
      "enemies": ["skeleton", ...],
      "traps":   ["collapse", ...],
      "bonuses": ["manna", ...]
    },
    ...
  },

  "levels": [
    { "id": 1, "circle": 1, "type": "vertical", "is_narrative": true,
      "soul_id": "soul_001", ... },
    ...
  ]
}
```

**Ключі `circle_defaults["<n>"]`:**

| Ключ | Тип | Призначення |
|---|---|---|
| `theme` | string | Внутрішній id теми (для арту/SFX) |
| `tileset` | string | Який тайлсет рендерити (`tileset1` / `tileset2` / …) |
| `enemies` | string[] | Пул ворогів кола (rotate by slot) |
| `traps` | string[] | Пул пасток |
| `bonuses` | string[] | Пул бонусів |

**Чинне мапування `tileset`:**

| Кола | Tileset |
|---|---|
| 1, 2 | `tileset1` |
| 3–10 | `tileset2` |

Майбутні tilesets додаються у конфіг — код їх читає через `LevelConfig.get_circle_tileset(circle)`.

**Ключі `levels[i]`:**

| Ключ | Тип | Опис |
|---|---|---|
| `id` | int | Унікальний ID рівня (1..100, бічні +100) |
| `circle` | int | До якого кола належить (1..10) |
| `type` | string | `vertical` / `void` / `labyrinth` / `escape` / `boss` |
| `is_narrative` | bool | Перший рівень кола з God message |
| `soul_id` | string | ID іменної душі (з `souls_collection.json`) |
| `hidden_soul` | string | `"H1"`..`"H20"` — мітка прихованої душі |
| `name` | string | Локалізована назва (опційно) |

### 7.2 `level_generation_config.json`

**Структура:**

```jsonc
{
  "version": "1.0",
  "approach": "hybrid",

  "static_levels": {
    "boss_levels": [10, 20, 30, 50, 70, 100],
    "circle_openers": { "levels": [1, 11, 21, ...] },
    "milestone_levels": [50, 75, 99, 100]
  },

  "procedural_levels": {
    "assembly": {
      "method": "sequential_rooms",       // legacy: переходить на shaft
      "room_count_per_level": { "min": 3, "max": 6 }
    },

    "room_pools": {
      "circle_1": {
        "style": "antechamber_stone",
        "platforms": ["stone", "one_way", ...],
        "enemies":   ["shadow_lost", ...],
        "traps":     ["spike_floor", ...],
        "rooms_count": 24
      },
      ...
    }
  }
}
```

> **Примітка про невідповідність:** `circle_defaults.theme` (у `levels_config.json`) і `room_pools.circle_X.style` (у `level_generation_config.json`) можуть розходитись (див. §3 «Розбіжності»). Перед затвердженням арту привести до одного джерела правди.

### 7.3 `LevelGenerator.gd` — константи

```gdscript
# Vertical jump physics
const MAX_JUMP_HEIGHT: float = 200.0
const PART_JUMP:       float = MAX_JUMP_HEIGHT / 2.0   # 100 px
const STEP_JUMP:       float = PART_JUMP / 2.0         # 50 px

# Spacing per tier (vertical levels)
const VERTICAL_SPACING := {
    "easy":    PART_JUMP,                       # 100 px
    "medium":  PART_JUMP + STEP_JUMP,           # 150 px
    "hard":    PART_JUMP + STEP_JUMP * 2.0,     # 200 px
    "extreme": MAX_JUMP_HEIGHT,                 # 200 px
}

# Platform preferences per tier
const ZONE_PLATFORMS := {
    "easy":    { "type": "stone",             "width": 220.0 },
    "medium":  { "type": "stone",             "width": 110.0 },
    "hard":    { "type": "moving_horizontal", "width": 110.0 },
    "extreme": { "type": "moving_vertical",   "width": 110.0 },
}
```

**`generate(level_id) → GeneratedLevel`** — центральна точка генерації:

| Поле `GeneratedLevel` | Тип | Звідки |
|---|---|---|
| `level_id`, `circle` | int | вхідний параметр |
| `is_static`, `is_branch`, `parent_id` | bool/int | таблиці статичних + правило `id > 100` |
| `room_scenes` | Array[String] | `_pick_rooms(circle, room_count)` |
| `room_count` | int | `_difficulty_for_index(idx)` |
| `soul_id`, `soul_data` | int/Dict | `_soul_for_level(level_id, circle)` |
| `enemy_count_mod` | int | difficulty по позиції в колі |
| `trap_density` | string | `low` / `medium` / `high` |
| `circle_style` | string | з `room_pools` |
| `difficulty_zone` | string | `easy` / `medium` / `hard` / `extreme` |
| `vertical_spacing` | float | `VERTICAL_SPACING[tier]` |
| `platform_type_hint` | string | `ZONE_PLATFORMS[tier].type` |
| `platform_width` | float | `ZONE_PLATFORMS[tier].width` |

### 7.4 `PlaceholderRoom.gd` — exported vars

| Var | Type | Default | Опис |
|---|---|---|---|
| `room_type` | String | `"main"` | `entrance` / `main` / `exit` / `shaft` |
| `room_index` | int | 1 | Номер у стеку (для legacy) |
| `circle` | int | 1 | 1..10 |
| `room_width` | float | 1080 | Ширина (LevelBase override → 1080 для shaft) |
| `room_height` | float | 900 | Висота (для vertical: VIEWPORT × 2 × room_count) |
| `is_vertical` | bool | false | Прапорець вертикального режиму |
| `level_id` | int | 0 | ID для config-запитів |
| `tileset` | String | `"tileset1"` | Який тайлсет (з `LevelConfig.get_circle_tileset`) |
| `room_count` | int | 1 | Множник висоти в `shaft` режимі |

**Константи фізичної геометрії:**

```gdscript
const VIEWPORT_WIDTH:        float = 1080.0
const VIEWPORT_HEIGHT:       float = 1920.0
const VERTICAL_ROOM_SCREENS: int   = 2       # один сегмент = 2 екрани
const WALL_T:                float = 32.0
const SIDE_WALL_T:           float = 60.0
const PLATFORM_T:            float = 30.0

const MOVING_V_DISTANCE: float = -80.0       # вертикальна рухома: −80 px вгору
const MOVING_H_DISTANCE: float = 140.0       # горизонтальна: ±140 px
```

---

## 8. Дебаг-інструменти

> Дев-онлі (вимикається в release-білді).

| Дія | Як |
|---|---|
| Toggle оверлею | **F3** |
| Скопіювати seed поточного рівня | Клік по рядку `seed  <id>#<room>  📋` у дебаг-картці |
| Дамп розкладки шахти | Друкується в консоль на старті кімнати: `[room <id>#<idx>] tier=… rows=N max_y_gap=Xpx`, далі по рядку на кожну платформу (Y, X, ширина, kind, type) |

Дебаг-картка стоїть зверху по центру екрану і змінює колір залежно від тиру (зелений → жовтий → оранжевий → червоний).

---

## 9. Чек-лист для нового кола

При додаванні чи зміні кола перевіри:

1. **`levels_config.json → circle_defaults["<n>"]`:** заповнено `theme`, `tileset`, `enemies[]`, `traps[]`, `bonuses[]`.
2. **`level_generation_config.json → room_pools.circle_<n>`:** `style`, `platforms[]`, `enemies[]`, `traps[]`, `rooms_count`.
3. **Тематика збігається** між `theme` (json#1) і `style` (json#2). Якщо ні — внести виправлення зараз, поки немає арту.
4. **Сцени кімнат** (`scenes/rooms/circle_<n>/room_*.tscn`) існують; `rooms_count` у конфігу не більший за фактичний.
5. **Tileset** доданий у `LevelConfig.get_circle_tileset` (наразі mapping береться напряму з json — нові tilesets «просто з'являються», якщо потрапили в `levels_config.json`).
6. **Список ворогів** покритий у `ENEMY_SCENE_MAP` ([PlaceholderRoom.gd](../scripts/rooms/PlaceholderRoom.gd)) — інакше fallback пул кола.
7. **Прихована душа** (якщо коло має) занесена в `souls_collection.json` з полем `circle: <n>`.
8. **Тематична платформа** (наприклад `mud` для кола 4) має override-маппінг у `_add_typed_platform()`.

---

> **Зворотній зв'язок:** якщо щось у грі поводиться інакше ніж описано тут — це **баг документа**, а не коду. Оновіть документ або заведіть таску.
