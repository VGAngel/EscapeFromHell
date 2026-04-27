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

### 26. 🟢 Per-level personal best + зірки ⭐⭐

**Що:** HUD при заході на рівень: "Best: 23s ⭐⭐⭐ • Souls: 3/3". Хаб /
LevelComplete — три зірки: 1 = clear, 2 = no-deaths, 3 = under target time.

**Чому:**
- `_calc_stars` уже існує
- Replay value: коли вже 1⭐ є, гравець повертається за 2-3⭐
- Зробити best per-level в SaveManager.data.level_bests

**Як:** SaveManager: `set_level_best(id, time, stars, souls)` /
`get_level_best(id)`. LevelComplete показує old vs new. Hub continue показує
поточний best.

**Складність:** Низька-середня.

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

### 29. 🟢 Іскри/flash від staff-удару ⭐

**Що:** Зараз посох тільки стуннув — нуль візуального feedback'у. Додати
spark-particles на ворогові + білий flash на 0.08с.

**Чому:** Імпакт без переробки урону. `Engine.time_scale = 0` під час
flash уже є — додати тільки візуальну частину.

**Як:** У `_apply_staff_hit` для кожного ворога → `ParticleEffects.spawn(
"staff_impact", body.global_position)` + `body.modulate = white`, tween
back to normal.

**Складність:** Дуже низька. Може потребувати нового particle preset.

---

## Моя нова топ-5 (свіжі)

1. **🥇 Камера look-down** (#14) — критично для вертикальних рівнів
2. **🥈 Stomp на стуннутих** (#13) — combat completion loop
3. **🥉 Soul radar pulse** (#16) — оживляє існуючий upgrade
4. **Squash & stretch** (#28) — найдешевший feel-boost
5. **Death cause toast** (#19) — миттєве quality-of-life
