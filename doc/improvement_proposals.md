# Improvement Proposals

Live document — додавай нові пропозиції, відмічай прийняті/відхилені.
Останнє оновлення: 2026-04-26.

Формат:
- 🟢 = варто зробити
- 🟡 = потребує обговорення
- 🔴 = ризиковано / великий рефактор
- ✅ = зроблено
- ❌ = відхилено

---

## Виявлення гравця ворогами (BaseEnemy)

Поточна логіка `_can_see_player()` ([scripts/enemies/BaseEnemy.gd:185](../scripts/enemies/BaseEnemy.gd:185)):
проста перевірка дистанції `<= detection_range` (default 200 px). Бачить крізь
стіни, ззаду, вертикально через платформи.

### A. 🟢 Конус зору попереду (facing cone)

**Що:** Замість 360° кола — конус ~120° перед обличчям ворога (по `_facing_right`).
Позаду гравець невидимий.

**Чому:** Дозволяє реальний stealth, додає тактику обходу. Гравець може
прокрастися ззаду до палаючого охоронця в Колі 3.

**Як:** Додати перевірку кута:
```gdscript
var to_player: Vector2 = _player.global_position - global_position
var facing: Vector2 = Vector2.RIGHT if _facing_right else Vector2.LEFT
var angle_deg: float = rad_to_deg(facing.angle_to(to_player))
return absf(angle_deg) < 60.0   # 120° cone total
```

**Складність:** Дуже низька (5 рядків).
**Ризики:** Може бути занадто легко прокрасти ззаду. Балансується кутом.

---

### B. 🟡 Raycast Line-of-Sight

**Що:** Перевіряти що між ворогом та гравцем нема стін/платформ.

**Чому:** Платформи стають укриттям. Сховався за товстою плитою — в безпеці.

**Як:**
```gdscript
func _has_line_of_sight() -> bool:
    var space := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.create(
        global_position, _player.global_position, 1)  # mask 1 = platforms
    query.exclude = [self, _player]
    return space.intersect_ray(query).is_empty()
```

**Складність:** Середня. Додатково тротлінг до 0.1-0.2с щоб не raycast'ити кожен кадр × N ворогів.

**Ризики:** Продуктивність на 20+ ворогах. Кешувати результат на 0.15с.

**Залежність:** Найкраще працює разом з C (інакше ворог біжить порожньо повний 6с навіть втративши гравця).

---

### C. 🟢 Скорочений chase при втраті LOS

**Що:** У стані `CHASE` тіче таймер швидше якщо ворог не бачить гравця. 6с → ~3с (multiplier ×2).

**Чому:** Зараз ворог переслідує всі 6с навіть якщо гравець заскочив за стіну
3 платформи назад. Це робить переслідування "мертвим" — ворог біжить порожньо.

**Як:**
```gdscript
const LOST_SIGHT_TIMER_MULT: float = 2.0   # × normal decay rate
const LOS_CHECK_INTERVAL:    float = 0.15

var _los_check_timer: float = 0.0
var _has_los_cached:  bool  = true

func _do_chase(delta: float) -> void:
    _los_check_timer -= delta
    if _los_check_timer <= 0.0:
        _los_check_timer = LOS_CHECK_INTERVAL
        _has_los_cached = _has_line_of_sight()
    if _has_los_cached:
        _last_known_pos = _player.global_position
    else:
        # Burn extra time when blind — chase ends ~3s instead of 6s
        _chase_timer -= delta * (LOST_SIGHT_TIMER_MULT - 1.0)
    ...
```

**Multiplier варіанти:**
| × | Час до give_up без LOS | Відчуття |
|---|---|---|
| 1.5 | ~4с | М'який |
| **2.0 ⭐** | **3с** | **Збалансовано** |
| 3.0 | 2с | Жорстко |
| ∞ | миттєво | Занадто, втрачається "він мене шукає" |

**Складність:** Низька (~15 рядків).
**Ризики:** Тротлінг важливий — без нього raycast щокадру × N ворогів просяде fps.

**Синергія:** Підсилює ефект A, B, D — без C вони малопомітні.

---

### D. ✅ Вертикальний клемп

**Реалізовано** у [scripts/enemies/BaseEnemy.gd](../scripts/enemies/BaseEnemy.gd):
`@export var max_vertical_sight: float = 100.0`. У `_can_see_player()` ворог
повертає `false` якщо `|player.y - enemy.y| > max_vertical_sight`. Для
літаючих ворогів (коли з'являться) — поставити `max_vertical_sight = 0` у
сцені, що відключає перевірку.

---

### E. 🟡 Прямокутне поле зору замість кола

**Що:** Перевіряти `abs(dx) <= W and abs(dy) <= H` замість дистанції.
Дає коридор зору замість "купола".

**Чому:** Узгоджується з природою платформера (горизонтальний gameplay).
W=240, H=80 → ворог бачить уперед і назад на 4 метри, але не вертикально.

**Як:**
```gdscript
var d: Vector2 = _player.global_position - global_position
return absf(d.x) <= sight_w and absf(d.y) <= sight_h
```

**Складність:** Низька. Альтернатива до D (не разом).

---

### F. 🔴 Бінарне → градієнт (suspicion meter)

**Що:** Замість миттєвого ALERT при попаданні в радіус — повільне накопичення
"підозри". Глянув 0.5с — може помітити, бачив 2с — точно ALERT.

**Чому:** Реалістичніше, дає вікно для того, щоб швидко перетнути зону зору.

**Складність:** Висока — нова state machine, візуальний індикатор (іконка з заповненням).
**Ризики:** Великий рефактор. Може заплутати гравця без чіткої UI підказки.

---

## Рекомендований шлях

**Швидкі перемоги (1 PR):** `D + C + A`
- D (вертикальний клемп) — миттєво вирішує "ворог бачить через стелю"
- C (LOS-скорочення chase) — 6с→3с при відриві, відчутно динамічніше
- A (конус зору) — додає stealth-можливість обходу

Усі три разом ~30 рядків коду. Без raycast → нуль ризику для продуктивності.

**Опційно потім:** B (raycast LOS) + F (suspicion meter) — як полірування коли core combat readyє.

---

## Інше (не enemy AI)

### Платформи

#### G. 🟡 MudPlatform / SwampZone — fps-залежне сповільнення
[scripts/platforms/MudPlatform.gd:42](../scripts/platforms/MudPlatform.gd:42),
[scripts/environments/SwampZone.gd:55](../scripts/environments/SwampZone.gd:55)

`velocity.x *= 0.55` кожен physics-кадр компаундить → за 5 кадрів швидкість ~5%.
На різних fps різна поведінка.

**Виправити:** `velocity.x = move_toward(velocity.x, 0, decel * delta)` або кеп
максимальної швидкості.

#### H. 🟢 IcePlatform — компаундна амплітуда
[scripts/platforms/IcePlatform.gd:43-44](../scripts/platforms/IcePlatform.gd:43)

`velocity.x = clampf(vx * 1.04, -340, 340)` — те саме fps-залежне множення,
тільки в зворотний бік. Обмежено `clampf`-ом, але крива швидкості залежить від fps.

### Sin

#### I. 🟢 Cleansing-cap не реалізовано
[scripts/managers/GameManager.gd:252-254](../scripts/managers/GameManager.gd:252)

В `upgrades_config.json` правило: "Очищення не може знизити гріх нижче 5%".
Код просто викликає `reduce_sin(tier)` без нижньої межі.

**Виправити:** Замінити на `set_sin(maxf(get_sin() - tier, 5.0))` коли cleansing tier > 0.

### Збереження

#### J. 🟡 Sin за смерть не персистить
[scripts/managers/GameManager.gd:188](../scripts/managers/GameManager.gd:188)

`add_sin(SIN_ON_DEATH)` пишеться лише в пам'ять до `save_after_level`. Якщо
гравець помер і вийшов з гри, sin "пробачається". Можливо за дизайном.

**Якщо bug:** додати `SaveManager._flush()` в `trigger_death`.

### Респавн

#### K. 🟡 Player.respawn не скидає run-state
[scripts/Player.gd:669](../scripts/Player.gd:669)

`_jumps_done`, `_staff_timer`, `_jump_buffer_timer`, `_landing_decel_timer`,
`_was_on_floor`, `_coyote_timer` — лишаються від моменту смерті. Більшість
самокоригуються після першого фрейму на підлозі, але `_jumps_done=1` може
блокувати double-jump одразу після респавна.

**Виправити:** обнулити всі run-state у `respawn()`.

### Дрібниці

#### L. 🟢 GameManager.take_damage / instant_death / heal — мертвий код
[scripts/managers/GameManager.gd:107-128](../scripts/managers/GameManager.gd:107)

Ніде не викликаються. "forgiveness" upgrade відсутній у `upgrades_config.json`.
Чисте сміття, можна видалити (~30 рядків).

---

# Gameplay Improvements

Не баги — нові механіки/фічі для покращення feel'у. Відсортовано за
співвідношенням "імпакт / складність".

## 🎯 Висока користь, мала складність

### 1. 🟢 Wall-slide + wall-jump

**Що:** Гравець в повітрі торкається стіни → сповзає на 40-60% gravity.
Натиснення Jump під час wall-slide → штовхає у протилежний бік + догори.

**Чому ідеально:**
- Рівні **вертикальні шахти** — буквально створені для цього
- Розширює дизайн платформ (вузькі коридори, "колодязі")
- Шанс врятуватися з фейленого стрибка
- Стандарт жанру (Hollow Knight, Celeste) — гравці очікують

**Як:** Нова `State.WALL_SLIDE` у Player. `is_on_wall_only()` детектить → клемп
`velocity.y = min(velocity.y, WALL_SLIDE_SPEED)`. Jump під час слайду →
`velocity = Vector2(WALL_PUSH_X * away_dir, JUMP_VELOCITY)`.

**Складність:** Середня (~30 рядків).
**Залежності:** none.

---

### 2. 🟢 Швидкісний бонус Світла

**Що:** Завершив рівень за < X секунд — додаткове Світло (наприклад +5/+10/+15
залежно від рівня).

**Чому:**
- Уже є `_level_start_time` і `elapsed` у `complete_level`
- Дає привід **перепроходити** рівні замість одноразового clear
- Природна поява speedrun-комʼюніті
- Прості тригери для соц-ключіп ("clear L23 in <30s")

**Як:** У `levels_config.json` додати `gold_time_seconds`. У `complete_level`:
```gdscript
if elapsed < gold_time:
    light_earned += 10
    stats["gold_time"] = true
```
LevelComplete показує ⏱ icon коли gold_time true.

**Складність:** Дуже низька (~10 рядків + конфіг).

---

### 3. 🟢 Risk-altar — пожертвуй гріх за подвійну нагороду

**Що:** На вівтарі додатковий вибір — "Доставити з гріхом". Дає +2 Світла
замість +1 але +5% sin.

**Чому:**
- Реалізує core fantasy ("частина пекла в тобі")
- Гравець реально вибирає мораль кожні 30с
- Counter (sin) і нагорода (light) уже є

**Як:** Друга кнопка на altar prompt ("[Q] Sin-deliver"). У `_deliver_soul`:
```gdscript
if sinful_delivery:
    SaveManager.add_light(2)
    GameManager.add_sin(5.0)
else:
    SaveManager.add_light(1)
```

**Складність:** Низька. AltarNode + 1 нова дія в InputMap.

---

## 🎯 Висока користь, середня складність

### 4. ✅ Soul echo — нести 2 душі

**Реалізовано** як апгрейд `soul_echo` ("Подвійна Ноша", cost 9) у
[upgrades_config.json](../upgrades_config.json) категорії "Душа".

Зміни:
- `Player.carried_soul_id: String` → `carried_soul_ids: Array[String]`
- `Player.soul_capacity()` → 1 без апгрейду, 2 з `soul_echo`
- `Player.is_carrying()` / `is_full()` — нові helper'и
- `Player.deliver_soul()` емітить `soul_delivered` для **кожної** душі (не
  тільки першої), AltarNode також пропускає всі через `soul_delivered_here`
- `Player._die()` дропає кожну окремо — обидві re-spawn'ляться
- `LevelBase._carried_soul_data` → `_carried_souls_data` (Dictionary keyed
  by soul_id) — кожна душа має свою картку до доставки/смерті
- `SoulBridgePlatform` оновлено для роботи з новим API
- Старе поле `carried_soul_id` для legacy-fallback все ще читається в
  AltarNode та SoulBridgePlatform (на випадок зовнішніх скриптів)

**Не зроблено (можна додати окремо):**
- Візуальний стек з 2-х душ над гравцем (зараз `SoulCarryVisual` показує
  одну іконку незалежно від кількості)
- HUD-індикатор "1/2" поточної ємності

---

### 5. 🟡 Dash з cooldown'ом

**Що:** Подвійний tap руху (або окрема кнопка) → ривок 180 px за 0.15с з
1.5с cooldown. iframes на час dash'у.

**Чому:**
- Спосіб втекти від ворога коли посох на cooldown
- Розширює platforming-puzzles
- Природний апгрейд (rookies без, prosper з shorter cooldown)

**Як:** `_dash_timer`, `_dash_cooldown`. Під час `_dash_timer > 0`:
- `velocity = Vector2(facing * DASH_SPEED, 0)`
- `_invincibility_timer = max(...)` для iframes
- gravity = 0

**Складність:** Середня (~25 рядків) + UI cooldown indicator.
**Ризик:** Може зламати дизайн level'ів (обхід платформ через dash через
"непробивний" gap).

---

### 6. 🟡 Whisper при високому sin

**Що:** Коли sin перевищує пороги (30/60/85) — раз на рівень над гравцем
з'являється шепіт-репліка від демона/Бога.

**Чому:**
- Підсилює narrative tension без cutscenes
- Гравець відчуває спостереження
- Перевикористовує `_show_soul_delivered_popup` для відображення

**Як:** Невеликий менеджер `WhisperManager` (autoload). Список реплік у
JSON по тегах: `sin_30`, `sin_60`, `sin_85`, `low_hp`, `near_death`.
Тригер у `GameManager.add_sin` коли перетинаємо поріг.

**Складність:** Низька-середня. Контент-залежно (треба написати репліки).

---

## 🎯 Якісне покращення feel'у

### 7. ✅ Coyote-time візуалізація для сповзаючих платформ

**Реалізовано:** [CrumblingPlatform](../scripts/platforms/CrumblingPlatform.gd)
та [AshPlatform](../scripts/platforms/AshPlatform.gd) тепер під час
CRUMBLE_DELAY програють shake (±2 px по X) + warm-orange tint на `_visual`.
Гравець бачить що "ось-ось" і встигає стрибнути.

Не реалізовано (опційно): falling-sand particles via ParticleEffects —
поточних shake+tint достатньо щоб читалося як попередження.

---

### 8. 🟢 Маркер дропнутої душі в HUD

**Що:** Коли гравець помирає несучи душу (вона дропається на платформі —
вже працює), HUD показує іконку "↓ X м нижче — ти лишив там душу".

**Чому:**
- Гравець знає **куди повертатися**
- Емоційне підкріплення "цю людину я ще не врятував"

**Як:** У `LevelBase._on_soul_dropped` зберегти позицію → передати в HUD.
HUD показує плаваючу іконку біля краю екрану з вертикальним зміщенням.

**Складність:** Низька (~20 рядків).

---

### 9. 🟢 Динамічний chase music на ALERT

**Що:** Перехід ворога у ALERT/CHASE → музика темнішає (низькі частоти
підкреслюються або додається drum-шар). Повертається до спокійної через 5с
після останнього CHASE.

**Чому:**
- Аудіо-фідбек "тебе побачили"
- `SoundManager` уже підтримує crossfade

**Як:** SoundManager exposed `set_intensity(0.0..1.0)` що ламає 2-track
crossfade. BaseEnemy у `_enter_alert` → `SoundManager.bump_intensity(0.5)`,
у `_begin_fatigue` → `SoundManager.decay_intensity()`.

**Складність:** Низька-середня. Потребує наявності второї music-доріжки
("intense" варіант).

---

## 🎯 Великі/опційні речі

### 10. 🟡 Combo-staff

**Що:** Послідовні удари в межах 1.5с підвищують stun-duration: 4с → 6с
→ 8с. Скидається при пропуску вікна або міні-cooldown.

**Чому:**
- Більше мастері в комбаті
- Винагороджує точну гру замість простого "стани і відбіжи"

**Як:** `_combo_count`, `_combo_window_timer`. У `_apply_staff_hit` якщо
hit && window > 0 → ++count, stun *= 1.0 + 0.5*count.

**Складність:** Середня. Потребує балансу.

---

### 11. 🟡 Demon deals UI

**Що:** Випадкові пропозиції від демонів між рівнями: "віддай 1 душу
отримай 20% Світла". Уже є `SaveManager._demon_deals_accepted` лічильник.

**Чому:**
- Розкриває ending-розгалуження (`traitor`)
- Дає гравцю мораль-вибори
- Лічильники готові, треба тільки UI + контент

**Як:** Новий `CanvasLayer` показується в Hub з 30% шансом між рівнями.
2 кнопки: "Прийняти" (дрібниці зберігаються через `add_reward`,
`_demon_deals_accepted += 1`) / "Відмовитися" (`+_deals_refused`).

**Складність:** Середня (UI + балансування пропозицій).

---

### 12. 🔴 Daily seed challenge

**Що:** Окремий режим "Daily" — фіксований seed для всіх гравців на день,
leaderboard за часом/душами.

**Чому:**
- Спільнота: всі грають один і той же рівень
- Daily retention boost
- Seed-система **уже є** (world_seed_str)

**Як:** Новий entry point у MainMenu. Daily seed = today's date hash. Стат
зберігається окремо. Серверна частина — або без leaderboard (offline-only),
або інтеграція з Steam/PlayGames.

**Складність:** Висока (особливо leaderboard). Без leaderboard — низька.

---

## Топ-3 рекомендація

1. **🥇 Швидкісний бонус Світла** (#2) — найменша робота, найбільший replay-value bump
2. **🥈 Wall-slide + wall-jump** (#1) — найбільший gameplay-impact, природньо для жанру
3. **🥉 Risk-altar** (#3) — реалізує narrative core, тривіальна імплементація

---

# Gameplay Improvements — Round 2

Друга хвиля ідей. Орієнтир — кор-механіки що ще не торкалися (камера, combat
completion, експлорація, learning, polish).

## 🎯 Кор-механіки

### 13. 🟢 Stomp на оглушеного ворога ⭐⭐⭐

**Що:** Стрибок зверху на стуннутого ворога → той розсипається, +1 Світло,
гравець відскакує (mini-jump ~300 px).

**Чому:**
- Зараз combat не має фіналу — ворога можна тільки стуннути та обійти
- Stomp = винагорода за точну гру + знищення
- Класика жанру (Mario, Hollow Knight, Dead Cells)

**Як:** Player при `velocity.y > 100` (падіння) і колізія з ворогом у
`stunned` стані → killing-hit + bounce. Перевіряти через Area2D під ногами
гравця (як `_staff_area`, але вертикальний).

**Складність:** Низька-середня (~30 рядків + новий Area2D у Player.tscn).

---

### 14. ✅ Камера look-down

**Реалізовано** у [LevelCamera](../scripts/managers/LevelCamera.gd):
- `LOOK_DOWN_OFFSET = 220` px, `LOOK_DOWN_HOLD_DELAY = 0.30s`
- Нова дія `look_down` у `project.godot` (за замовчуванням ↓ та `S`)
- Активується тільки коли: гравець на землі **і** не натискає `move_left`/
  `move_right` (щоб ↓ використане для майбутнього fast-fall не дублювало)
- `_resolve_look_down_target` віддає 0 / `LOOK_DOWN_OFFSET`, зглажує лерпом
  через існуючий `_OFFSET_FOLLOW_SPEED`
- При відпусканні таймер обнуляється — камера плавно повертається

---

### 15. 🟡 Mini-map шахти ⭐⭐

**Що:** Збоку HUD (або в pause-screen) тонка вертикальна полоска: позиція
гравця, золоті крапки = душі, синя = вівтар, зелена = вихід. Без ворогів.

**Чому:**
- Гравець знає **скільки лишилось** і де основні цілі
- Менше фрустрації "куди йти"
- Підсилює level дизайн (можна "обіцяти" душу далеко знизу)

**Як:** HUD vertical bar, координати з `_souls_in_level` + `_room_height`
+ `_player.global_position.y`.

**Складність:** Середня. UI + перевірка для шахт vs горизонтальних.

---

## 🎯 Soul mechanic

### 16. 🟢 Soul radar pulse з `soul_sense` ⭐⭐

**Що:** Зараз апгрейд "Відчуття" дає **тільки тонке свічення душ крізь
платформи** (`Soul._update_hidden_visibility`). Додати **HUD-стрілку на
краю екрана** що пульсує до напрямку найближчої зібраної душі — інтенсивність
підвищується коли близько.

**Чому:** Робить існуючий апгрейд тактильним. Зараз він майже непомітний.

**Як:** Окрема Control-нода в HUD. Раз на 0.1с шукає найближчу `soul`-group
ноду, обчислює напрямок → виставляє rotation, alpha = function(distance).

**Складність:** Низька-середня.

---

### 17. 🟡 Soul whisper при перенесенні ⭐

**Що:** Поки гравець несе іменовану душу — раз на 5-8с над головою з'являється
коротка фраза від цієї душі ("Я не пам'ятаю чому я тут...", "Поспіши..."). Текст
з `souls_collection.json` (description або новий field whispers).

**Чому:** Емоційний зв'язок із душею-як-персонажем замість "анонімне Світло".

**Як:** Таймер у Player при is_carrying() → запит до LevelBase → якщо є
`whispers` для цього soul_id → spawn floating label.

**Складність:** Низька-середня. Контент-залежно (треба написати фрази).

---

## 🎯 Death / Learning

### 18. 🟢 Адаптивний хінт після N смертей ⭐⭐

**Що:** 3+ смерті на одному рівні → на наступному респавні плаваючий текст:
"Спробуй стрибати з даху" / "Це сповзаюча — не стій" / "Зліва є альтернативний
шлях".

**Чому:** Враховує що гравець застряг. Без хінтів — все що він може —
повторювати. З хінтами — навчається.

**Як:** У `levels_config.json` опційне поле:
```json
"hint_after_deaths": { "3": "Це сповзаюча — стрибай швидко",
                       "5": "Спробуй обхідним шляхом" }
```
LevelBase читає, після респавна перевіряє `_deaths_this_level` >= тригер.

**Складність:** Низька (~15 рядків + контент).

---

### 19. 🟢 Death cause toast ⭐

**Що:** При смерті — короткий текст у центрі екрана: "Падіння з висоти" /
"Удар ворога" / "Лава" / "Шипи". `GameManager.trigger_death(cause)` уже приймає
cause але не використовує його візуально.

**Чому:** Гравець розуміє що сталося. Зараз — просто чорний екран.

**Як:** GameManager.trigger_death emit cause в overlay-fade-in callback.
Простий Label на 1.5с над центром перед респавном.

**Складність:** Дуже низька.

---

## 🎯 Risk / reward

### 20. 🟡 Forbidden Book — ризик за інформацію ⭐⭐

**Що:** Рідкісний bonus type "forbidden_book" — взяти → +5% sin але
показує **позицію прихованої душі** на цьому рівні (маркер на 10с).

**Чому:**
- Реалізує core "знання за гріх"
- Додає сенс прихованим душам — тепер їх можна свідомо шукати, а не
  випадково знаходити

**Як:** Новий enum value у BonusPickup, ефект — postфактум маркер
на хіту в HUD з world_position.

**Складність:** Низька-середня.

---

### 21. 🟡 Greed gate перед altar ⭐

**Що:** Перед vivarium є необов'язкова "врата": "Пройти повз → +50% Світла з
рівня, але sin зростає на +1% з кожних 30с поки не дійдеш до наступного
вівтаря".

**Чому:**
- Сильна тактична альтернатива safe-play
- Реалізує "терпи демонів заради нагороди"

**Як:** Новий тип room (`greed_gate`). Активна змінна `_greed_active` у
LevelBase, тіче sin кожен фрейм.

**Складність:** Середня. Новий room scene + level дизайн.

---

## 🎯 Procgen / level variety

### 22. 🔴 Branching paths ⭐⭐

**Що:** Замість лінійного шахту — на одному рядку **дві сторони**: ліва
безпечна, права з душею + 1 ворог. Через 2-3 рядки сходяться.

**Чому:** Реальний вибір "ризик vs швидкість".

**Складність:** Висока. Великі зміни в `PlaceholderRoom._build_vertical_layout`,
PathValidator потрібно оновити для двох-шляхів.

---

### 23. 🟡 Hidden room за crumbling wall ⭐⭐

**Що:** 1-2 рази на 10 рівнів: одна стіна виглядає звичайною, але насправді
crumbling. Розбити (стрибок угору в неї посохом?) → невелика кімната з
прихованою душею + 1-2 бонусами.

**Чому:** Стимул до експлорації. Класика roguelike.

**Як:** Спеціальний `WallCrumbling` тип. Виявляється тільки якщо staff
ударяє у нього (`_staff_area.body_entered`).

**Складність:** Середня. Новий тип + детектор у Player.

---

## 🎯 Audio / feedback

### 24. 🟢 Footstep варіанти за поверхнею ⭐⭐

**Що:** Mud / Ash / Ice / Stone / Bridge — різні footstep-семпли.

**Чому:** Підсвідомий feedback "я зараз на льоду" без необхідності дивитись.
Підсилює існуючу систему типів платформ.

**Як:** Player polls контактну поверхню через raycast вниз → на основі
`platform_type` мета grants грає `play_sfx("footstep", surface_type)`.
Або платформа сама викликає це коли `body_entered`.

**Складність:** Низька. Залежить від наявності аудіо-семплів.

---

### 25. 🟡 Vertical music progression ⭐

**Що:** По мірі спуску по шахту — низькі частоти посилюються (LP-фільтр на
music-track). Найнижче = майже dub-bass без верхів.

**Чому:** Психологічно посилює "ти йдеш глибше у пекло".

**Як:** AudioStreamPlayer з AudioEffectLowPassFilter на bus. Параметр
`cutoff_hz` змінюється від 8000 → 1500 в залежності від
`_player.global_position.y / total_h`.

**Складність:** Низька-середня. Один effect + per-frame update.

---

## 🎯 Long-tail / replay

### 26. ✅ Per-level personal best + зірки

**Реалізовано:**
- `SaveManager.get_level_best(id)` / `update_level_best(id, time, stars,
  souls, deaths)` — записує лише якщо stars зросли або при тому ж stars час
  кращий
- `GameManager._calc_stars(found, total, deaths, elapsed)` оновлено під
  нову рубрику: 1 = clear, 2 = clear+0 deaths, 3 = clear+0 deaths+under
  target_time. Target time бере `levels_config.target_time_seconds` або
  fallback `45 + circle * 6` секунд
- `GameManager.complete_level()` додає `previous_best`, `new_best`,
  `target_time` у `stats` для UI
- `LevelComplete` тепер показує час, попередній рекорд (чи "—") та badge
  "✨ НОВИЙ РЕКОРД ✨" коли поточний run покращив запис
- `Hub` continue button показує "🏆 0:23 ★★★" якщо для наступного рівня
  є зерезервований рекорд
- Тести в `test_game_manager.gd` оновлено під нову рубрику

---

### 27. 🟡 Achievement система ⭐

**Що:** Список умов: "Пройти Коло 1 без смертей", "Зібрати 10 прихованих
душ", "100 душ за <5 годин", "Закінчити з sin < 10%". При досягненні —
popup + persistent flag у SaveManager.

**Чому:** Класичний long-tail. Без Steam/Google API можна локально, потім
експортувати.

**Як:** `AchievementManager` autoload. Список у JSON.

**Складність:** Середня. UI popup + список конфігу + тригери у різних місцях.

---

## 🎯 Polish / juice

### 28. 🟢 Squash & stretch на стрибку/приземленні ⭐

**Що:** Спрайт гравця на стрибку трохи розтягується по Y (1.0 → 1.1 → 1.0);
на приземленні стискається (1.0 → 0.85 на 0.06с → 1.0 на 0.1с).

**Чому:** Найвідоміший трюк "feel'у". Платформер з squash&stretch здається
на 30% більш responsive.

**Як:** У Player при `is_on_floor()` після `not _was_on_floor` → tween
`_anim_sprite.scale`. На стрибку у `_handle_jump` → tween зворотний.

**Складність:** Дуже низька (~10 рядків).

---

### 29. ✅ Іскри/flash від staff-удару

**Реалізовано:**
- `ParticleEffects._preset_staff_impact()` — короткий жовтий burst (18
  частинок, 0.32с lifetime, gravity-pulled униз) — читається як одна
  "вибух-іскра"
- `BaseEnemy.flash_white(duration)` — тимчасово виставляє modulate на
  over-bright (2.5×) і tween'ить назад до збереженого оригіналу. Викликається
  з `receive_knockback()`, тож працює і для AI ворогів і для бажаних
  скриптів-обгорток
- `Player._apply_staff_hit` тепер спавнить `staff_impact` particles на
  кожного потрапленого ворога (іскри) — це працює навіть для не-BaseEnemy
  цілей (кастомні боси), а flash виконує сам ворог

---

## Моя нова топ-5 (свіжі)

1. **🥇 Камера look-down** (#14) — критично для вертикальних рівнів
2. **🥈 Stomp на стуннутих** (#13) — combat completion loop
3. **🥉 Soul radar pulse** (#16) — оживляє існуючий upgrade
4. **Squash & stretch** (#28) — найдешевший feel-boost
5. **Death cause toast** (#19) — миттєве quality-of-life

---

# Gameplay Improvements — Round 3

Третя хвиля. Категорії що перші дві хвилі майже не зачепили: endgame
content, accessibility, статистика/мета, polish-ритуали смерті, лор,
boss readability.

## 🎯 Endgame content (після 100 душ)

### 30. 🟡 Endless Dive mode ⭐⭐⭐

**Що:** Розблоковується після 100/100 душ. Безкінечна шахта з прогресуючою
складністю (як arcade-режим). Метрика — глибина за 1 спробу. Локальний
leaderboard.

**Чому:**
- 100 душ ≈ 5-10 годин геймплея → далі гравцю **нічого робити**
- Endless дає replay на десятки годин
- Очікувана фіча для roguelike-аудиторії

**Як:** Новий entry point у MainMenu (gated). Власний сцен-тип
`EndlessShaft.tscn`, який спадково використовує PlaceholderRoom але без
exit — генерує наступну "кімнату" коли гравець перетинає поріг.
Складність = функція від глибини.

**Складність:** Середня-висока. Сама шахта проста (повторювати рядки),
але потрібен difficulty-ramp + UI + leaderboard.

---

### 31. 🟡 NG+ (Newgame+) ⭐⭐

**Що:** Після 100 душ — "Розпочати NG+" з:
- збереженими апгрейдами та Світлом
- +20% sin baseline
- ворогам fatigue ÷2 (агресивніші)
- inversed-souls — те що було невинною = тепер мімік

**Чому:** Класика roguelike. Друге проходження стає новим викликом — не
"той самий контент".

**Як:** Прапорець `ng_plus_active` у SaveManager. Усі модифікатори
застосовуються через нього в Player/BaseEnemy/Soul.

**Складність:** Середня. Багато точок дотику.

---

### 32. 🟢 Coло-completion bonus ⭐

**Що:** Зібрати **всі** душі в колі (10 + бонусні приховані) →
перманентний пасивний бонус. Приклади:
- Коло 1: -5% sin baseline forever
- Коло 5: +1 max HP
- Коло 10: -10% staff cooldown

**Чому:** Стимулює 100% completion, нагороджує дослідників, додає вертикальну прогресію поза апгрейдами.

**Як:** Новий save field `circle_completion_bonuses: Array[int]`. Player
читає при `_apply_upgrades`.

**Складність:** Низька-середня (логіка проста, потребує балансу).

---

## 🎯 Accessibility

### 33. 🟢 Налаштування доступності ⭐⭐

**Що:** Окремий розділ у Settings:
- **Розмір тексту** (Small / Normal / Large) — впливає на font_size HUD/UI
- **Інтенсивність screen shake** (0-100% slider) — множник у CameraShake
- **Дальтонізм** (presets: deutera/proto/tritan) — змінює палітру (sin colors, soul tints, enemy alerts)
- **Easy mode** — sin росте на 50% повільніше, fatigue на 50% довший, +1 HP

**Чому:** Реальний внесок у доступність. Мала вартість на код (більшість
параметрів уже екзистують як константи). Велика ціна для гравців з потребами.

**Як:** Новий tab у SettingsScreen. Параметри в `settings_config.json`,
читаються глобальними менеджерами.

**Складність:** Середня. Найважче — colorblind palettes (потребує дизайн).

---

### 34. ✅ Перепризначення клавіш (PC)

**Реалізовано** як 4-й tab у [SettingsScreen](../scripts/ui/SettingsScreen.gd):

- Список 7 rebindable actions: `move_left`, `move_right`, `jump`, `action`,
  `interact`, `look_down`, `pray` (визначений у `REBINDABLE_ACTIONS` const)
- Per-row: label + кнопка з поточним key label (через `OS.get_keycode_string`)
- Натискання кнопки → "Натисніть клавішу..." → наступний `InputEventKey`
  замінює `physical_keycode`. Esc скасовує без змін.
- Зберігає у `user://settings.json` → `keybindings: { action: physical_keycode }`
- На старті `_capture_default_keys()` робить snapshot → `_apply_keybindings()`
  відновлює користувацькі біндинги після `_load()`
- Кнопка "↺ Скинути всі" повертає до snapshot з project.godot
- Зберігаються non-key events (gamepad, mouse) — переписується тільки
  перший key event

**Не реалізовано:** мобільне переставлення кнопок MobileControls — це
окрема велика задача (drag-and-drop UI). Потребує окремого етапу.

---

## 🎯 Statistics & meta

### 35. 🟢 Статистика гравця ⭐⭐

**Що:** Окремий екран у Pause / MainMenu:
- Загальний час гри: 12:34:56
- Смертей: 234 (з них від падіння: 89, ворогів: 67, лави: 23, шипів: 41…)
- Найкращий рівень: L42 — 0:23 ★★★
- Витрачено Світла: 1245
- Середній sin за рівень: 23%
- Найдовший combo: 7 ворогів за один прохід

**Чому:**
- Гравці люблять цифри
- Допомагає рефлексувати "пройшов X% гри"
- Маркетинг — прозорі скріни в Steam reviews

**Як:** Тригери в GameManager рахують метрики, зберігаються у
`SaveManager.data.statistics`. Окремий UI читає й малює.

**Складність:** Низька-середня (логіка проста, UI один екран).

---

### 36. 🟢 Soul collection by circle ⭐

**Що:** В CollectionScreen додати progress bars по колах:
"Коло 3: 7/10 ✦ 1/2". Замість одного "X/100".

**Чому:** Орієнтує гравця "куди йти за пропущеними душами".

**Як:** У `_refresh_counters` в CollectionScreen — групувати
`saved_soul_ids` за circle (з souls_collection.json).

**Складність:** Низька (~30 рядків).

---

## 🎯 Player movement

### 37. 🟡 Fast-fall (↓ в повітрі) ⭐⭐

**Що:** Натискання ↓ під час падіння → прискорене падіння (×2
max_fall_speed на 0.3с). Не активує look-down (look-down тільки grounded).

**Чому:**
- Вертикальна гра + швидкісні бонуси (#2) — fast-fall дає тактичну швидкість
- Не конфліктує з camera look-down (ті ж клавіши, різні стани)
- Дає вибір "обережно спускатися vs мчати"

**Як:** У Player._handle_gravity → якщо `not is_on_floor()` AND
`Input.is_action_pressed("look_down")` → multiplier на gravity та
max_fall_speed.

**Складність:** Низька (~10 рядків).

---

### 38. 🟡 Slide / crouch під низьким стелею ⭐

**Що:** ↓ + рух → slide під низькими виступами (1-tile висотою). Зараз
не використовується.

**Чому:** Більше варіантів для level-design (secret passages під
платформами, push-через-вузький прохід).

**Як:** Нова State.SLIDE у Player. Зменшує collision shape
тимчасово (з 90 → 50 px). Швидкість зростає коли почне slide.

**Складність:** Середня. Зміна collision shape мід-grand вимагає
обережності з фізикою.

---

## 🎯 Boss polish

### 39. 🟢 Телеграф атак боса ⭐⭐

**Що:** Перед charge / AOE — бос flash'ить помаранчевим (~0.3с) + AOE-зона
showed на підлозі (Hollow Knight стиль). Не змінює урон, тільки readability.

**Чому:** Боси зараз "miss-and-die-instantly". Telegraph знімає
frustration "звідки це взялось".

**Як:** У BossAI перед `_start_charge` → tween modulate(orange, 0.3) →
emit flash. Drawing AOE — Polygon2D на підлозі.

**Складність:** Середня. Залежить від типу атаки боса.

---

### 40. 🟢 Boss HP/Progress Bar для довгих фаз ⭐

**Що:** Поточні боси без HP (5-душ collect / wait-for-prayer), але
**progress bar для "як близько кінець"** знизить тривогу. Наприклад
для boss_10 показати "Душ зібрано: 3/5" + "Молитва: 4/8с".

**Чому:** Замість "коли це закінчиться?" → "ще трохи".

**Як:** BossLevel вже має `_phase_dots` — розширити на progress-meters.

**Складність:** Низька (~30 рядків UI).

---

## 🎯 Lore / атмосфера

### 41. 🟡 Лорні нотатки ⭐⭐

**Що:** Рідкісний колекційний пункт — "сторінки щоденника" розкидані в
рівнях. Читаєш → зберігається в Collection (новий tab "Записи"). Описують
історію Кіл, минуле Данила, NPC.

**Чому:**
- Глибший світ без cutscenes
- Стимулює exploration ("я ще не знайшов записку Кола 4")
- Контент-багатий — можна додавати завжди

**Як:** Новий тип pickup `LoreNote`. Спавн рідкісно (1 на 5-7 рівнів).
SaveManager `found_lore_notes: Array[String]`. Texts у новому JSON.

**Складність:** Низька-середня. Контент-залежно.

---

### 42. 🟡 Спрайт-еволюція по sin ⭐

**Що:** Зараз shader-blend змінює tint. Додати **повноцінні sprite-swaps**
на 4 стани (clean / tainted / fallen / demon) — різна броня, рога, аура.
Активи вже в `SIN_TEXTURES`.

**Чому:** Зараз тільки колір — гравцю важко "побачити" свій sin. Повна
заміна моделі робить його жахливо видимим (а це частина core fantasy).

**Як:** Замінити shader-blend на повний swap _anim_sprite.sprite_frames
коли threshold перетнули. Потребує 4 повних SpriteFrame наборів.

**Складність:** Середня (код простий, ASSETS — багато роботи).

---

## 🎯 QoL & polish

### 43. 🟢 Save indicator ⭐

**Що:** Маленька 💾 іконка в куті на 1с коли SaveManager._flush()
запускається. Показує що прогрес дійсно збережений.

**Чому:** Заспокоює "а чи зберігається?". Особливо важливо на mobile
(закрив гру → втратив).

**Як:** SaveManager emit `save_started`/`save_completed`. HUD ловить →
показує fade-in/out іконку.

**Складність:** Дуже низька (~15 рядків).

---

### 44. 🟡 Quick retry на death screen ⭐

**Що:** Замість автоматичного respawn — короткий екран
"💀 Спробувати знову? [tap] / Меню". Дає секунду осмислити.

**Чому:** Зараз death-fade миттєвий — гравець не встигає зрозуміти що
сталось. З quick retry — момент рефлексії + явний "ще раз" замість
автоматизованого циклу.

**Як:** GameManager.trigger_death — замість таймера на respawn → показує
GUI з кнопками. Tap-anywhere = retry.

**Складність:** Низька.

---

### 45. 🟢 Death zoom-out ⭐

**Що:** Перед death-fade — камера zoom out на 0.3с до 0.7×. Драматичний
момент.

**Чому:** Більше "ваги" смерті. Кінематографічно.

**Як:** У Player._die → tween Camera2D.zoom from current to current*0.7.

**Складність:** Дуже низька (~5 рядків).

---

### 46. 🟡 Photo mode ⭐

**Що:** Пауза → нова кнопка "📷 Photo" → free pan камера + сховати UI +
export PNG в галерею (mobile) або robotic-screenshot (desktop).

**Чому:** Безкоштовний marketing channel. Twitter/Reddit screenshots =
organic reach.

**Як:** Окремий стан в PauseScreen. Активує "free camera" режим
(swipe = переміщення, pinch = zoom). Tap "📷" → DisplayServer screenshot.

**Складність:** Середня. Mobile gallery export — додаткова інтеграція.

---

## 🎯 Risk / reward (продовження)

### 47. 🟢 Confessional booth ⭐

**Що:** Рідкісна кімната — "Сповідальня". Ввійшов → пожертвуй 10% Світла
→ -5% sin. Інверсія Risk-altar (#3).

**Чому:** Гравцю зараз нікуди здати "грішне Світло". Дає "відмити" гріхи
ціною прогресу.

**Як:** Новий тип room (`confession`). Спавн рідко, ~1 на коло.

**Складність:** Низька-середня (новий room scene).

---

### 48. 🔴 Spectre душ (death replay ghost) ⭐

**Що:** Якщо в одному рівні помираєш ≥3 раз → твій "Тінь" з минулої
спроби з'являється на тому самому шляху і повторює рухи. Допомагає
бачити свої помилки. Або заважає — є дизайн-вибір.

**Чому:** Унікальна механіка roguelike-навчання. Перетворює "повторне
проходження" з frustration на дослідження.

**Як:** Записувати `Player.global_position` кожні 0.1с → відтворювати
наступний run як Sprite2D без collision. Потребує save state per session.

**Складність:** Висока. Запис/відтворення треба тестувати багато.

---

## Моя топ-5 (Round 3)

1. **🥇 Endless Dive** (#30) — критичний endgame; без нього гра 5-10г
2. **🥈 Налаштування доступності** (#33) — низька вартість, велика користь
3. **🥉 Лорні нотатки** (#41) — cheap continuous content drip
4. **Boss телеграф** (#39) — знімає frustration в найпам'ятнішому моменті
5. **Save indicator** (#43) — крихітний QoL який всі помічають
