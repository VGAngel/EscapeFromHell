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

### 6. ✅ Whisper при високому sin

**Реалізовано** як новий autoload `WhisperManager`
([scripts/managers/WhisperManager.gd](../scripts/managers/WhisperManager.gd)).

- **Контент:** [whispers_config.json](../whispers_config.json) — 4 фрази
  для кожного з 3 порогів (`tier_30`, `tier_60`, `tier_85`)
- **Тригер:** слухає `GameManager.sin_changed` → виявляє перехід через поріг
  (порівняння `_last_sin` vs `new_sin`); найвищий перейдений поріг
  виграє за один delta (наприклад demon-deal стрибок 25%→90% → tier_85)
- **Cap:** 1 whisper на тир на рівень. Скидається на `level_started`
- **UI:** окрема CanvasLayer (layer 12 — над HUD), PanelContainer з
  rounded border, shadow, dark backdrop. Label 36 px з товстим outline 7
  щоб був чітко читабельний на будь-якому фоні
- **Анімація:** fade-in 0.6с → hold 3.5с → fade-out 1.2с
- **Тести:** 7 кейсів у `test_whisper_manager.gd` — config load,
  threshold crossing, no-emit нижче порогів, multi-tier delta resolution,
  cap-1, reset на level_started

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

### 35. ✅ Статистика гравця

**Реалізовано:**
- `SaveManager.data["statistics"]` — універсальний bucket з API:
  `add_stat(key, delta)`, `get_stat(key, default)`, `incr_death_cause(cause)`,
  `get_deaths_by_cause()`, `add_play_time(seconds)`
- `GameManager.trigger_death(cause)` записує в `deaths_total` +
  `deaths_by_cause[cause]`
- `GameManager.complete_level()` додає `total_play_seconds` (elapsed) +
  `levels_cleared` + `light_earned_total`
- `SaveManager.spend_light()` тепер автоматично пише `light_spent_total`
- Новий [scripts/ui/StatisticsScreen.gd](../scripts/ui/StatisticsScreen.gd)
  — окрема CanvasLayer-overlay з секціями: Прогрес, Душі, Смерті (з
  per-cause breakdown), Світло, Рекорди (найкращий рівень з level_bests),
  Гріх
- Кнопка "📊 Статистика" у PauseScreen → emits `statistics_requested` →
  LevelBase відкриває overlay
- Сцена [scenes/ui/StatisticsScreen.tscn](../scenes/ui/StatisticsScreen.tscn)
  додана у Level.tscn (вертикальні + платформери). Boss/Void можна додати
  таким же способом якщо потрібно.

---

### 36. ✅ Soul collection by circle

**Реалізовано** у [CollectionScreen](../scripts/ui/CollectionScreen.gd):
- Новий `_circle_progress_box` HBox під заголовком — 10 клітин (К1..К10)
- Кожна клітина: "К%d" + "X/Y" (named) + опційно "✦ X/Y" (hidden, лише
  якщо circle має приховані душі)
- Заповнені цілком ліки (X==Y) — золото-жовтий tint, інакше нейтральний
- `_refresh_circle_progress()` викликається з `_refresh_counters()` →
  оновлюється кожен раз як screen відкривається або душа додається
- Дані беруться з `_named_souls`/`_hidden_souls` (loaded JSON) +
  `SaveManager.get_saved_soul_ids()` / `get_hidden_soul_ids()` — групування
  по `circle` field з кожної душі

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

### 40. ✅ Boss progress bar для довгих фаз

**Реалізовано:**
- `BossAI` новий signal `progress_updated(label, value, max_value)` —
  емітиться у `on_collectible_picked`, `on_totem_activated`, `tick_prayer`,
  `reset_prayer` (zeroed)
- Per-boss labels (`_collectible_label`): "Уламки" / "Кристали" / "Душі"
  залежно від `boss_id`
- `BossLevel._build_phase_panel` тепер додає прогрес-бар (label + numeric
  value + colored bar) під phase dots. Spawnиться навіть для single-phase
  босів якщо є `progress_updated`
- `_on_boss_progress` оновлює label + кількість, лерпом анімує заповнення,
  пульс золотим кольором при ratio ≥ 0.8 ("ось-ось")
- Smart formatting: "3 / 5" для int counts, "5.4 / 8.0" для prayer seconds
- Bar зникає після `_on_boss_win` через `_hide_phase_panel` (вже існував)

**Тести:** 7 нових тестів у `test_boss_ai.gd` — signal emit на pickup/
totem/prayer/reset, value parameters, label per boss_id, no-emit при
неправильному порядку тотему.

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

---

# Sin Mechanic — глибинні покращення

Поточний стан sin-системи: shader-tint + Faith-platform gate + ending-розгалуження + щойно додані whispers (#6). Sin майже нічого не робить **механічно** до самого фіналу, гравець не бачить причин зростання. Нижче — покращення щоб sin став активним gameplay-loop'ом замість косметики.

### S1. ✅ Sin-source toast

**Реалізовано:**
- `GameManager.add_sin(amount, cause)` + `reduce_sin(amount, cause)`
  розширено новим параметром та signal'ом `sin_added(amount, cause)`
  (negative для cleansing/confession)
- Усі call-сайти оновлено з cause: `Player._handle_staff` → "staff",
  `GameManager.trigger_death` → "death", `_check_death_limit` →
  "extra_attempt", `complete_level` cleansing → "cleansing",
  `SinPlatform._process` → "sin_platform" (через GameManager),
  `BossLevel._on_sin_aura_tick` → "sin_aura"
- HUD будує `_sin_toast_box` (BOTTOM_LEFT) і слухає `sin_added`:
  - Іконки/labels у двох dict'ах для 9 cause-типів
  - Throttle 4с per-cause + acumulator щоб per-frame ticks (sin_platform,
    sin_aura) не спамили — пропущена сума доплачується наступним toast'ом
  - Стек capped на 3, найстаріший FIFO
  - Червоний backdrop + crimson border для +sin, зелений для −sin
  - 22 px label з outline 4 px для читабельності
  - Fade-in 0.15 → hold 1.2 → fade-out 0.35
- 4 нових тести у `test_game_manager.gd` — signal emit з cause/default,
  negative amount для reduce_sin, sin_changed contract collinear

---

### S2. 🟢 Sin gates — блокування контенту по порогах ⭐⭐⭐

**Що:** Жорсткіші пороги які щось **відключають/змінюють**:

| Поріг | Що відбувається |
|-------|-----------------|
| ≥ 30% | Ангельські діалоги в Хабі холодніші, ціна апгрейдів +10% |
| ≥ 60% | Бог замовкає (нема повідомлень у Хабі), демони пропонують **кращі** угоди |
| ≥ 85% | Молитва на вівтарі недоступна (можна доставити, але не зніжити sin), faith-platforms завжди недоступні |
| = 100% | boss_10 фаза 3 (молитва) **неможлива** — інстант-fail, треба явно очистити sin |

**Чому:** Sin отримує реальну ціну. Зараз можна довести до 95% і нічого
критичного не станеться до фіналу.

**Як:** Кілька point-of-use перевірок:
- AltarNode._activate — gate на sin <85
- Hub._show_god_message — skip pickup if sin >=60
- UpgradesScreen._make_buy_btn — cost *= 1.1 if sin >=30
- FaithPlatform — already checks sin

**Складність:** Середня. ~5 точок дотику.

---

### S3. 🟢 Sin decay при чистій грі ⭐⭐

**Що:** Якщо протягом 60с гравець не отримує `+sin` (ніяких джерел) →
**−0.5% sin**. Tick кожен 60-сек інтервал чистоти.

**Чому:** Позитивний фідбек за restraint. Гравець відчуває "я ще можу
повернутись" замість "вже занадто пізно щоб щось мінять".

**Як:** Таймер у GameManager. Скидається у `sin_added` (з positive amount).
Кожні 60с без скиду → `add_sin(-0.5, "decay")`.

**Складність:** Низька (~20 рядків).

---

### S4. 🟢 Стат-штрафи за sin ⭐⭐⭐

**Що:** Не тільки візуал — реальна механічна вага:

| Поріг | Штрафи |
|-------|--------|
| ≥ 30% | walk_speed −5%, jump_height −5% |
| ≥ 60% | walk_speed −15%, jump_height −10%, ворогам fatigue −20% (агресивніші) |
| ≥ 85% | walk_speed −25%, fall damage ×1.5, soul_shield duration ÷2 |

**Чому:** "Демонічний шлях" повинен бути **буквально важчим**. Зараз
гравець майже не платить за грішну гру в реальному часі.

**Як:** Player.gd та BaseEnemy додають getter'и `_sin_speed_mult()`,
`_sin_jump_mult()` etc., читають `SaveManager.get_sin()`. Викликаються в
`_handle_movement`, `_handle_jump`, `_handle_gravity`. BaseEnemy:
fatigue_duration *= mult коли sin gate переходить.

**Складність:** Середня. Player має ~5 точок, BaseEnemy 1.

**Синергія з S1:** гравець бачить toast + ОДРАЗУ відчуває "ага, я повільніший" → каскад фідбеку.

---

### S5. 🟢 Soul-affinity: тип душі впливає на sin ⭐⭐

**Що:** Поки гравець несе душу:
- **Innocent** душа → sin **−0.1%/сек**
- **Broken** душа → sin **+0.05%/сек** (вони корумповані)
- **Sleeping** → нейтрально

**Чому:** Робить тип душі **не косметичним**. Гравець стратегічно вирішує
кого піднімати першим, які душі краще лишити "на потім".

**Як:** Player._physics_process → якщо `is_carrying()` → крок sin
delta базуючись на `_carried_souls_data[id].soul_type`. LevelBase
тримає мапу id→type в `_carried_souls_data`.

**Складність:** Низька (~15 рядків).

---

### S6. 🟡 Per-soul sin запис ⭐⭐

**Що:** При доставці зберігається `sin_at_delivery` за кожну душу.
В CollectionScreen клітина показує статус:
- 🟢 (sin <30) "врятований чистим"
- 🟡 (30-60) "з тягарем"
- 🟠 (60-85) "у тіні"
- 🔴 (≥85) "згоріла грань" (можливий вплив на кінцівку)

**Чому:** Карма тривалого виміру. Гравець відчуває "цю врятував зломаним"
коли натрапляє на 99-у душу.

**Як:** `SaveManager.add_soul(id)` → `add_soul(id, sin_at_delivery)`.
`saved_soul_ids` стає `saved_souls: { id: { sin: float } }`. CollectionScreen
читає `.sin` з кожного запису → tint-frame клітини.

**Складність:** Низька-середня. Потребує save-format міграції (v2 → v3).

---

### S7. 🟡 Confessional booth ⭐⭐ (вже згадано як #47, прив'язка тут)

**Що:** Рідкісна кімната — пожертвуй 10% Світла → −5% sin. Інверсія
Risk-altar.

**Чому:** Дає **активний** спосіб знизити sin (не пасивний як cleansing).
Гравець обирає "тримаюсь" чи "відмиваю".

**Складність:** Низька-середня (новий room scene).

---

### S8. 🟡 Аудіо/візуальна підсилка sin ⭐⭐

**Що:**
- ≥60%: тихий heartbeat loop у фоні (більше sin = голосніше)
- ≥85%: червона vignette по краях екрану + low-pass фільтр на музиці
- Particles — червоні wisp'и навколо гравця при високому sin

**Чому:** Гравець **відчуває** sin не лише дивлячись на цифру.
Атмосфера стає клаустрофобічною. Підсилює core fantasy.

**Як:**
- Heartbeat — SoundManager новий ambient track з гучністю від sin
- Vignette — ColorRect overlay у HUD з radial gradient texture, alpha = f(sin)
- Particles — нова CPUParticles2D на Player, активна якщо sin >= 60

**Складність:** Низька-середня. Потребує assets (heartbeat sound, vignette texture).

---

### S9. 🟡 Sacrifice mechanic — спалення душі за чистоту ⭐⭐

**Що:** Біля вівтаря альтернативна дія: "Спалити душу" (затисни кнопку
2с) → втрачаєш душу з колекції, але **−15% sin**.

**Чому:** Жорсткий моральний вибір. Гравцю можна "пожертвувати малим
заради себе". Вплив на кінцівку — додаткова `sacrificed_souls` метрика.

**Як:** AltarNode додає другий prompt-state коли гравець несе душу.
`sacrifice_soul()` → `Player._drop_soul()` без emit'у `soul_delivered` +
`add_sin(-15)` + `SaveManager.add_stat("sacrificed_souls", 1)`.

**Складність:** Середня. AltarNode + Player + кінцівка-логіка.

---

## Топ-3 sin-механіки (моя рекомендація)

1. **🥇 Sin-source toast** (S1) — копійки коду, миттєвий "ага" момент
2. **🥈 Стат-штрафи за sin** (S4) — переводить sin з косметики в реальну механіку
3. **🥉 Soul-affinity по типу** (S5) — оживляє існуючу систему типів душ

**Якщо обираєш ОДНУ зміну з найбільшим чистим впливом — S4 (стат-штрафи).** Зараз гравець може бути 95% sin і пройти весь рівень як 0%. З штрафами кожен % коштує реально.

**Найкраща пара:** S1 + S4 — гравець бачить причину І відчуває наслідок одночасно. Каскад фідбеку.

---

# Controls — покращення управління

### C5. ✅ Налаштовувані позиції/розміри кнопок

**Реалізовано** як customisation layer над
[MobileControls](../scripts/ui/MobileControls.gd) + UI у Settings →
Keys tab.

- **Persistence:** `SaveManager.get_mobile_layout()` /
  `set_mobile_layout(layout)` зберігають `{ size_scale: float, offsets:
  { action: {x, y} } }`. Auto-`_flush()` при save щоб crash mid-game не
  втрачав налаштування
- **Розмір (global):** slider 60-140% у Settings, immediate apply через
  `MobileControls.set_size_scale(scale)`. Усі 3 розмірні класи
  (SMALL/MEDIUM/LARGE) масштабуються синхронно. Шрифти на кнопках
  ресайзяться разом з ними (`_refresh_btn_style`)
- **Позиції (drag-to-move):** "✋ Редагувати позиції кнопок" → закриває
  Settings, MobileControls входить у edit-mode (золоті borders), показує
  floating "✓ Готово" overlay. Ігнорує game input — лише drag-to-move.
  Натиск "Готово" → `save_layout()` + вихід
- **Зберігання як offsets**, не absolute pos — `_commit_drag` обчислює
  delta від default position (виставляє пусті offsets, перерахоує defaults,
  бере різницю), щоб safe-area / scale зміни не "приклеювали" кнопку до
  однієї точки
- **Reset:** "↺ Скинути позиції" повертає всі offsets + scale до 1.0
- **Тести:** 8 кейсів у `test_mobile_layout.gd` — defaults, clamp scale
  0.5..1.6, layout round-trip через SaveManager, reset, edit-mode toggle,
  розмір кнопки масштабується

### C4. ✅ Haptic feedback (mobile)

**Реалізовано** як новий autoload `HapticManager`
([scripts/managers/HapticManager.gd](../scripts/managers/HapticManager.gd)).

- **Wraps** `Input.vibrate_handheld(duration_ms, amplitude)` з:
  - Toggle перевіркою (`is_enabled()`)
  - Mobile-only check через `OS.has_feature("mobile" / "android")`
  - Auto-no-op на desktop і коли користувач вимкнув
- **Event helpers:** `hit()` (80ms / 0.55), `jump()` (25ms / 0.20),
  `pickup()` (55ms / 0.45), `death()` (220ms / 0.85),
  `deliver()` (70ms / 0.40), `boss_stun()` (3 burst по 40ms)
- **Хуки:**
  - `Player._take_damage` → hit
  - `Player._handle_jump` (обидві гілки — звичайний + double-jump) → jump
  - `Player._finish_pickup` → pickup
  - `Player._die` → death
  - `Player.deliver_soul` → deliver
  - `BossLevel._on_boss_stunned` → boss_stun
- **Settings UI:** новий toggle "Вібрація (mobile)" у Sound tab.
  Зберігається в `settings.json` як `haptics: bool` (default true).
  `_apply_haptics()` пушить значення у HapticManager на старті
- **Тести:** 10 кейсів у `test_haptic_manager.gd` — toggle persistence,
  mobile detection, всі helper'и не крашаться, disabled state safe

---

# 🖼  UI / UX rework — головне меню та інтерфейс

Розширений brainstorm. Легенда складності: ⭐ малий, ⭐⭐ середній,
⭐⭐⭐ великий. Колір — мій вотинг: 🟢 беремо, 🟡 під питанням,
🔴 на потім.

## A. Головне меню — структура та ієрархія

### U1. 🟡 Скоротити список кнопок до 5–6 ⭐⭐ — **відкладено**
Не реалізовано (не міняє відчуття так, як hero-картка U2 + dynamic
CTA U3). Лишається кандидатом на майбутнє: footer-row з іконками
(Seed/NoAds/Donate/Exit) можна зробити окремим етапом.

### U2. ✅ Hero-картка над кнопками

**Реалізовано** як `scripts/ui/HeroCard.gd` — `PanelContainer`
(DarkPanel variation), що інстансується з MainMenu між TitleLabel і
ButtonsContainer.

**Layout:**
```
┌────────────────────────────────────────┐
│ <profile name>                  Коло X │
│                                Рівень Y│
├────────────────────────────────────────┤
│ 👻 Souls 23/100 · ✦ 4/20 · 💡 120      │
│ 🏆 Найкращий: 0:42 ★★★ (рівень 7)      │
│ 😈 Гріх 18%                            │
└────────────────────────────────────────┘
```

- **Profile name** — `SaveManager.get_profile_name()`, fallback
  "Невідомий"
- **Circle/Level** — поточні значення, right-aligned в окремому VBox
- **Souls/Hidden/Light** — компактний рядок з 3 значеннями
- **Best run** — пройти всі 100 рівнів, max stars + min time
  tiebreaker (та сама логіка що в StatisticsScreen)
- **Sin** — кольоровий gradient SUCCESS → WARNING → SIN_RED через
  lerp; 0% зелений, 50% жовтий, 100% червоний
- **Auto-refresh** — `_process` polls SaveManager раз на секунду
  поки картка видима (теж без сигналів)
- **Theme variations** — TitleLabel, BodyLabel, ValueLabel, GoldSeparator
- **Тести:** 6 кейсів у `tests/unit/test_hero_card.gd` — build,
  refresh substring перевірки, sin-color mapping, repeated-refresh safety

### U3. ✅ Динамічний текст на «Грати»

**Реалізовано** в `MainMenu._refresh_play_button()`:
- Якщо ще не грали (total_play_seconds == 0) або level==1 →
  `▶  Грати`
- Інакше → `▶  Продовжити — рівень N`
- Викликається з `_refresh_souls_counter()` (який запускається при
  `_ready` і після кожного закриття overlay'у)

### U4. 🟡 Сховати Levels(debug) у релізі ⭐
Видалити кнопку або заховати під 5-тап на VersionLabel
(як Android Developer Mode).

### U5. ✅ Параллакс і амбієнт на тлі меню

**Реалізовано** як окремий помічник
[scripts/ui/MenuAmbient.gd](../scripts/ui/MenuAmbient.gd), що чіпляється
до MainMenu з `_ready()`. Усе — у коді, без нових ассетів.

- **Embers (CPUParticles2D, 22 шт)** — теплі оранжеві іскри піднімаються
  з низу екрану. Spread 22°, gravity -18, velocity 18..42 px/s
- **Ash (CPUParticles2D, 18 шт)** — холодний попіл сипле зверху,
  gravity 8, velocity 10..22 px/s
- **Warm flicker** — повноекранний ColorRect з canvas_item шейдером:
  радіальний теплий gradient у центрі + темний vignette, амплітуда
  пульсує по sin (1.7 с період) + small high-freq jitter — імітація
  факелу
- **Sin-tinted vignette** — окремий ColorRect, alpha = sin% / 100 ×
  0.22, плавно tween-ається при зміні. Полл-інтервал 0.5 с
- **Parallax drift** — embers/ash зміщуються на ±14×8 px залежно від
  нахилу пристрою (`Input.get_accelerometer()`) на mobile або від
  позиції миші на desktop. Lerp smoothing 6.0
- **Title breathing** — TitleLabel плавно дише (scale 1.000↔1.018,
  0.45 Hz) через `pivot_offset = size * 0.5`
- **Sliding shadows** — два темні елліптичні «плями» дрейфують
  горизонтально на різних швидкостях (-46 / +28 px/s) і alpha (0.26 /
  0.18). Ширина rect'а 1.6× / 1.1× екрану з canvas_item shader що
  робить soft elliptical mask — seam при wrap-around невидимий.
  Імітує тіні від невидимого джерела світла на стінах підземелля
- **Reduce-motion gate** — читає `SaveManager.get_setting("reduce_motion")`
  з graceful fallback. Якщо ввімкнено — embers/ash не emit'ять,
  parallax/flicker/breathing/shadows не оновлюються
- **Presets** — `setup(root, title, preset)` приймає `"menu"` (повний
  набір) або `"hub"` (без ash, без parallax, без title-breath).
  Дозволяє переюзати скрипт у Hub.gd одним рядком
- **Hub.gd інтеграція** — атмосферний шар на Hub-екрані з пресетом
  `"hub"`: shadows + flicker + embers + sin-tint
- **Тести:** 8 кейсів у `tests/unit/test_menu_ambient.gd` —
  створення дітей (включно з shadows), безпечний `_process` tick,
  sin-tint clamp, attach без title, reduce_motion no-op (для shadows
  теж), hub preset skip ash, shadow drift over time

### U6. 🟡 Звуковий бекграунд меню ⭐
Low drone + дальній хор з fade-in/out при переходах.

## B. Навігація / overlay поведінка

### U7. 🟡 Tabbed hub замість 5 окремих overlay ⭐⭐⭐
Один Drawer/Tab контейнер: «Прогрес | Колекція | Покращення |
Статистика | Налаштування». Менше fade-tween, швидший доступ.
Великий рефактор.

### U8. ✅ Централізований UIRouter / back-stack

**Реалізовано** як новий autoload
[scripts/managers/UIRouter.gd](../scripts/managers/UIRouter.gd).

- **Стек overlay'ів** — `_stack: Array[Node]`. API: `push()`, `pop()`,
  `pop_all()`, `top()`, `depth()`, `is_open()`, `contains()`
- **Сигнали** — `stack_changed(depth)`, `screen_pushed(screen)`,
  `screen_popped(screen)` (готові підписники для майбутнього TopBar)
- **Duck-typing контракт** — overlay має `signal closed`, `func open()`,
  `func close()`. Опційно `router_title()` для TopBar
- **Не перехоплює Esc** — overlay'і вже коректно це роблять через
  `_unhandled_input` + `set_input_as_handled`. Замість цього router
  слухає `closed` сигнал щоб тримати стек у синхроні
- **Android hardware-back** — `NOTIFICATION_WM_GO_BACK_REQUEST`
  викликає `pop()` якщо стек не порожній (Godot за замовчуванням
  робить quit)
- **Автоочистка** — підписаний на `tree_exiting` кожного pushed
  screen'а, тому scene-change / queue_free автоматично видаляє з
  стеку
- **Подвійний push того ж screen'а** — no-op + повторний `open()` для
  refresh контенту
- **MainMenu міграція** — кожен `_on_*` хендлер тепер викликає
  `_open_via_router(screen)` замість прямого `.open()`. 5 рядків
  загального коду замість дублювання
- **Тести:** 12 кейсів у `tests/unit/test_ui_router.gd` — push/pop
  глибина, no-op на null, дубль-push, multi-stack ordering, pop-всі,
  closed-signal sync, tree-exit cleanup, signal параметри

### U9. 🟡 Swipe-to-close для overlay ⭐
Свайп вниз від хедера закриває екран — мобільна звичка
(Telegram, iOS sheets).

### U10. ✅ Persistent top-bar на hub-екранах

**Реалізовано** як `scripts/ui/TopBar.gd` (CanvasLayer на layer 11,
вище overlay layer 10). Інстансується з MainMenu одним рядком.

- **Видимість** — підписаний на `UIRouter.stack_changed`. depth>=1 →
  fade-in (0.18 с), depth==0 → fade-out
- **Layout (left → right):**
  - 🔙 Back-кнопка (IconButton variation) — викликає `UIRouter.pop()`
  - Title (TitleLabel variation) — заповнює центр, текст з
    `UIRouter.top().router_title()`
  - Resources block: 💡 light (gold), 👻 souls (blue), 😈 sin (red)
- **Resource polling** — оновлюється на router-change + раз на
  секунду поки видимий (SaveManager не має сигналів)
- **Safe-area aware** — top inset зчитується з `SafeArea.top_reserved`
  і застосовується до `_bar.offset_top`. Підписаний на `SafeArea.changed`
- **Tap absorbing** — BG ColorRect має `MOUSE_FILTER_STOP` щоб таппи
  по бару не падали на overlay під ним
- **Theme variations** — використовує IconButton/TitleLabel/BodyLabel
  з UITheme; кольори ресурсів через `add_theme_color_override` +
  Palette.GOLD/ACCENT_BLUE/SIN_RED
- **`router_title()` додано** до 6 overlay'ів: StatisticsScreen
  ("Статистика"), CollectionScreen ("Врятовані душі"), SettingsScreen
  ("Налаштування"), DonatePanel ("Підтримати"), ProfileScreen
  ("Профілі"), SeedDialog ("Зерно світу"), LevelDebugMenu
  ("Рівні (debug)")
- **Тести:** 6 кейсів у `tests/unit/test_top_bar.gd` — initial hidden,
  show on push, title from router_title, empty title fallback, back
  button → pop, resources render

## C. Візуальний стиль / theme

### U11. ✅ Єдина Theme + UITheme autoload

**Реалізовано** як `scripts/ui/UITheme.gd` autoload, що будує `Theme`
у коді (тримати у тексті простіше за binary `.tres` бо StyleBoxFlat
має багато властивостей) і чіпляє його до `tree.root.theme`.

- **Type variations** (Godot 4 mechanism — встановлюється через
  `node.theme_type_variation = "..."`):
  - **Labels:** `DisplayLabel`, `TitleLabel`, `SectionLabel`,
    `BodyLabel`, `ValueLabel`, `CaptionLabel`, `MutedLabel`
  - **Buttons:** `PrimaryButton`, `SecondaryButton`, `DangerButton`,
    `IconButton`
  - **Panel:** `DarkPanel` (PanelContainer)
  - **Separator:** `GoldSeparator` (HSeparator)
- **Default Button + Label** теж стилізовані — більшість Control'ів
  отримують гарний look без жодного коду
- **Демо-міграція** на `StatisticsScreen.gd` — видалено 9 викликів
  `add_theme_*_override` + 2 builds StyleBoxFlat → 4 рядки з
  `theme_type_variation`. Майбутні екрани мігрують поступово
- **Тести:** 12 кейсів у `tests/unit/test_ui_theme.gd` — наявність
  всіх variation'ів, правильна base-type, font-size scale
  ascending, Palette кольори підтягуються

### U12. ✅ Шрифтова ієрархія (5 рівнів)

Реалізовано як константи в UITheme:
- `SIZE_DISPLAY = 48` — hero-headlines
- `SIZE_TITLE = 32` — секційні заголовки overlay'ів
- `SIZE_SECTION = 24` — підзаголовки
- `SIZE_BODY = 18` — основний текст (default Label)
- `SIZE_CAPTION = 14` — підказки, hint'и

**Display-font typography polish:** оскільки в проекті немає
окремого display-font asset'а, hero-варіації (DisplayLabel,
TitleLabel) отримують `outline_size` constant (4 для TitleLabel,
6 для DisplayLabel) з кольором BG_BLACK через theme. Це робить
дефолтний sans-font Godot'а схожим на «engraved» display-cut без
ассета. BodyLabel/CaptionLabel залишаються чистими — outline
на маленьких розмірах робить текст бруднішим.

**Прогрес міграції** (`add_theme_font_size_override` → theme variation):
- ✅ StatisticsScreen — мігровано в комміті U11/U12/U13
- ✅ PauseScreen — title/sin/exit-confirm/stats мігровано
- ✅ LevelComplete — header/subtitle/new-best/stats/buttons мігровано
- ✅ UpgradesScreen — title/cards/currency/close-button мігровано
- 🟡 Решта 13 файлів (SettingsScreen, CollectionScreen, HUD, ProfileScreen,
  DonatePanel, SeedDialog, MainMenu, LevelDebugMenu, EndingScreen,
  SoulRevealPanel, PrivacyPolicy, MobileControls + manager UI scripts)
  — мігрують поступово при наступних правках (low-risk approach
  замість одного 800-рядкового sweep'у)

### U13. ✅ Palette.gd з іменованими кольорами

**Реалізовано** як `scripts/ui/Palette.gd` (`class_name Palette extends
RefCounted`). Чисто-data клас з SCREAMING_SNAKE_CASE константами,
згрупованими за призначенням:

- **Brand:** `GOLD`, `GOLD_DIM`, `HELL_RED`, `HELL_RED_DIM`
- **Backgrounds:** `BG_BLACK`, `BG_DARK`, `BG_DARKER`, `BG_PANEL`,
  `BG_PANEL_HOVER`, `BG_PANEL_PRESSED`
- **Text:** `TEXT_DISPLAY`, `TEXT_PRIMARY`, `TEXT_SECONDARY`,
  `TEXT_MUTED`, `TEXT_DISABLED`
- **Accents:** `ACCENT_GREEN`, `ACCENT_BLUE`, `ACCENT_ORANGE`,
  `SIN_RED`
- **Borders:** `BORDER_DIM`, `BORDER_NEUTRAL`, `BORDER_HOVER`,
  `BORDER_PRIMARY`, `BORDER_PRIMARY_H`
- **Status:** `SUCCESS`, `WARNING`, `DANGER`
- **Button flavors:** `BTN_PRIMARY_BG{,_H,_P}`, `BTN_DANGER_BG`

UITheme використовує Palette скрізь, тому одна правка в Palette
ріплекіт по всій грі.

### U14. 🟡 Ripple/glow на pressed-state ключових кнопок ⭐⭐
Особливо «Грати» і soul-deliver popup OK — додає вагу натиску.

### U15. 🟢 Sin-stained UI tint ⭐⭐
За високого sin% UI поступово темніє/червоніє
(global Modulate на root CanvasLayer). Діегетична деталь, унікальна
для гри.

## D. Feedback & «feel»

### U16. ✅ Haptic + sound на кожен button-press

**Реалізовано** разом з U17 через новий autoload
`scripts/managers/UIFeedback.gd`. Слухає `tree.node_added` та
авто-вішає feel-callback на кожен `BaseButton` у грі — minor
mechanical sweep був не потрібен, працює глобально.

- **Sound** — вже забезпечував SoundManager (auto-wire `ui.button_click`
  на кожен `pressed`)
- **Haptic** — новий метод `HapticManager.tap_light()` (15ms / 0.15
  amplitude — barely-there confirmation), викликається з UIFeedback
  при натиску
- **Skip cases:**
  - `disabled` кнопки → skip обидва (no false signal)
  - Buttons з meta `feel_disabled = true` → skip (для drag-edit modes)

### U17. ✅ Tap-grow анімація на всіх кнопках

**Реалізовано** як частина того ж UIFeedback autoload.

- **Pulse:** scale tween 1.00 → 1.10 → 1.00 за 0.18 с з easing
  TRANS_QUAD-OUT (overshoot up) + TRANS_BACK-OUT (settle down) —
  читається як «satisfying click»
- **Pivot offset** автоматично виставляється у center (`size * 0.5`)
  щоб pulse виглядав симетрично незалежно від anchoring
- **IconButton variation** (✕, 🔙, ⏸) отримує менший amplitude
  (PULSE_AMP_ICON = 1.06 vs PULSE_AMP_DEFAULT = 1.10) — chrome
  кнопки не повинні візуально стрибати
- **Concurrent presses safe:** previous tween на цьому ж button
  kill'ається перед стартом нового через meta-stash
- **Idempotent wiring:** `_wired` registry guard + cleanup на
  `tree_exited` щоб не накопичувати зомбі-IDs
- **Тести:** 9 кейсів у `tests/unit/test_ui_feedback.gd` —
  auto-wire on add, auto-wire existing at boot, idempotent re-wire,
  tree-exit cleanup, pulse tween created, pivot centred, disabled
  skip, feel_disabled meta skip, IconButton smaller amp

### U18. 🟡 Skeleton-loader / shimmer ⭐⭐
Statistics і Collection: показувати shimmer-плейсхолдери
поки SaveManager парсить. Зараз клік → пауза → екран.

### U19. 🟡 «NEW!» badge у Collection ⭐
Якщо нову душу врятовано — відмітити в SaveManager.collection_seen
і показати пульсуючий бейдж.

### U20. 🔴 Versions/build chip → changelog overlay ⭐⭐
Клік по `v0.1` відкриває changelog popup. Для тестерів і фанів.

## E. HUD під час гри

### U21. ✅ Sin-bar як «отруйні вени» по краю екрану

**Реалізовано** як `scripts/ui/SinVignette.gd` — Control з canvas_item
шейдером, що рендерить діегетичний red-veins vignette по краях
екрану під час геймплею. Інстансується HUD'ом одним рядком.

**Шейдер:**
- `edge_mask(uv)` — radial smoothstep, 0 у центрі, 1 на кутах. Тільки
  на краях рендеримо щось — центр екрану лишається чистим
- `veins(uv, t)` — двошаровий warped sin field з `pow(...,8)` щоб
  зробити чіткі тонкі риджі ("вени")
- Pulse: `0.5 + 0.5 * sin(time * pulse_hz * TAU)` множиться на alpha
- `pulse_hz` lerp'ається 0.4 → 2.0 Hz залежно від sin% (0 = повільне
  дихання, 100 = панічна пульсація)
- Final alpha: `(mask*0.5 + veins*0.5) * pulse * intensity`,
  capped at MAX_ALPHA = 0.55

**Поведінка:**
- На 0% sin — повністю прозорий
- 30% — ледве помітний
- 60% — чітко червоний по краях
- 100% — інтенсивна швидка пульсація
- Tween modulate.a (0.6 с) при зміні sin — ніколи не "стрибає"

**Хуки:**
- `GameManager.sin_changed(new_value)` → `set_sin()`
- На `_ready` poll'имо `SaveManager.get_sin()` для resume з ненульовим sin
- `_process(dt)` оновлює `time` uniform для пульсу

**Тести:** 6 кейсів у `tests/unit/test_sin_vignette.gd` — shader
material build, intensity = sin%/100, pulse_hz scales, clamp 0..100,
time advances

### U22. ✅ Soul-counter pop-анімація

**Реалізовано** — апгрейд існуючого `HUD._pulse_node()` до повноцінного
«pop» з overshoot + golden glow + concurrent-press protection.

**Зміни:**
- **Pivot offset** автоматично виставляється у center (`size * 0.5`)
  щоб bounce виходив навкруги middle, а не з top-left
- **Scale tween (split-phase):**
  - Up: 1.00 → 1.32 за 35% duration (TRANS_QUAD-OUT, snappy)
  - Down: 1.32 → 1.00 за 65% duration (TRANS_BACK-OUT, overshoot
    → settle) — читається як «+1!»
- **Color glow (для Label):**
  - Seed `font_color` override з поточного theme color (без цього
    Godot читає Nil і property tween silently не стартує)
  - Up: orig → `Color(1.0, 0.92, 0.45)` warm gold за 30% duration
  - Down: gold → orig за 70% (TRANS_SINE-IN, тонкий fade)
- **Concurrent-press safe** — попередній tween на тому ж node
  kill'ається через meta-stash `hud_pop_tween` (той самий patern як
  у UIFeedback)
- **Null safety** — early return на null/invalid node
- **Non-Label tolerance** — colour-flash branch гейтнутий `if node is Label`

**Куди застосовується** (вже існуючі hookups, тепер з кращим feel):
- `_souls_level` + `_souls_total` при підборі душі (`_on_player_soul_picked_up`)
- `_carry_label` при зміні capacity (`_on_carry_changed`)
- `_light_label` при отриманні світла

**Тестів:** 6 кейсів у `tests/unit/test_hud_pop.gd` —
pivot centring, meta-tween stash, rapid re-pulse kills previous,
non-Label не падає, null safe, peak scale > 1.15

### U23. 🟡 Mini-map / depth-indicator ⭐⭐
Ліворуч екрану вертикальна шкала: положення на круглі
(altar → bottom). Іконки душ, чекпойнтів, боса.

### U24. ✅ Damage flash vignette

**Реалізовано** як `scripts/ui/DamageFlash.gd` — Control з canvas_item
шейдером який рендерить solid red ring по краях екрану. Sister of
SinVignette, але transient: кожен damage_taken event тригерить
0 → peak → 0 alpha tween за ~0.34 с.

- **Шейдер:** `edge_ring(uv)` — radial smoothstep 0.45 → 1.0,
  bright at corners, clear in centre. Колір зафіксований
  `vec3(0.85, 0.10, 0.10)`
- **Tween:** sharp attack (PEAK_TIME = 0.06 с, TRANS_QUAD-OUT) +
  slower decay (FADE_TIME = 0.28 с, TRANS_SINE-IN) — читається як
  "punch" а не fade
- **Intensity scaling:** `clamp(amount / 3, 0.4, 1.0)`. 1-damage
  tick — softer, 3+-damage spike — saturated. peak_alpha =
  MAX_ALPHA × intensity (= 0.55 × intensity)
- **Concurrent flashes safe** — previous tween kill'ається перед
  стартом нового через `_current_tween` reference
- **Player signal wiring:**
  - Новий `signal damage_taken(amount: int)` у Player.gd, emit'ить
    в `_take_damage()` поряд з `hp_changed`
  - DamageFlash шукає Player через `get_first_node_in_group("player")`
    + слухає `tree.node_added` (з deferred check бо `add_to_group`
    у Player._ready відбувається після `node_added`)
- **HUD інтеграція** — `_install_damage_flash()` дзеркалить
  `_install_sin_vignette()`, кладеться на index 1 (вище sin vignette)
- **Mouse filter ignore** — таппи проходять до геймплею
- **Тести:** 8 кейсів у `tests/unit/test_damage_flash.gd` —
  shader build, initial alpha 0, flash creates tween, intensity
  scaling math, concurrent kill, FakePlayer connection (already in
  tree + added later), signal triggers flash

### U25. 🟡 Контекстні підказки внизу ⭐⭐
Whisper-style: «Тримай ↓ щоб побачити нижче», «Подвійний тап —
гасить світло», «Зачаїтись — Shift». Показувати раз на сесію
через TutorialManager.

## F. Доступність / зручність

### U26. 🟢 Текстова шкала в Settings ⭐⭐
UI 90/100/110/120%. Множник на font_size override-и.

### U27. 🟡 High-contrast тема ⭐⭐
Для денного світла на телефоні. Перемикач в Settings.

### U28. ✅ Reduce motion toggle

**Реалізовано** — додано accessibility toggle "Зменшити рух (анімації)"
у Settings → Графіка, з персистентністю в settings.json і
broadcasting через новий autoload `MotionSettings`.

- **`scripts/managers/MotionSettings.gd`** — autoload, тримає
  `_enabled: bool`, public API `is_enabled()` / `set_enabled(value)`,
  signal `changed(reduce_motion: bool)`. No-op при no-change щоб
  не спамити підписників на повторних `_apply_all()`
- **SettingsScreen integration:**
  - `reduce_motion: false` додано до DEFAULTS
  - `_toggle_reduce_motion` Button у Graphics tab
  - Boot: `_apply_all()` → `_apply_reduce_motion()` пушить значення
    у MotionSettings; subscribers re-render
  - Toggle clicks: persist + push live
- **Subscribers:**
  - **MenuAmbient** — `_on_motion_changed()` зупиняє embers/ash,
    скидає title scale до 1.0; перевіряє MotionSettings першим
    (legacy SaveManager.get_setting fallback збережено)
  - **SinVignette** — `_process()` бейлить early коли reduce_motion;
    pulsing veins зупиняються, але static red ring лишається
    (інтенсивність читається в `set_sin`)
- **Localization:** новий ключ `settings.reduce_motion`
  ("Зменшити рух (анімації)" / "Reduce motion (animations)") в
  обох UK + EN
- **Тести:** 5 кейсів у `tests/unit/test_motion_settings.gd` —
  default disabled, set emits with value, no-op on same value,
  round-trip emits each flip, MenuAmbient subscribes + freezes
  emitters live

### U29. 🟡 Однорукий режим / left-handed ⭐⭐
Дзеркальне розташування MobileControls + великий «Грати»
внизу екрану меню (а не в центрі).

### U30. ✅ Локалізація-ready (через `Loc` autoload)

**Реалізовано** — Loc autoload + `uk.json`/`en.json` вже існували, але
жоден UI скрипт їх не використовував. Зроблено:

- **Loc.language_changed signal** — emit'иться на кожен `_load_language()`.
  UI компоненти підписуються щоб live-refresh'итись без scene reload
- **Нові ключі** в обох `localization/*.json`:
  - `hero_card.*` — name_unknown, circle_format, level_format,
    stats_format, best_none, best_format, sin_format
  - `main_menu_dyn.*` — play_first, play_continue
  - `router_title.*` — statistics, collection, settings, donate,
    profile, seed, level_debug
- **HeroCard.gd мігровано** — всі hardcoded UA рядки замінено на
  `Loc.t()` з graceful fallback на key якщо Loc недоступний у
  тестах. Підписана на `language_changed` для live refresh
- **MainMenu Play CTA** — `▶ Грати` / `▶ Продовжити — рівень N`
  тепер через Loc з fallback на UA. MainMenu підписана на
  `language_changed` і викликає `_refresh_souls_counter()`
- **7 router_title()s мігровано** — StatisticsScreen, CollectionScreen,
  SettingsScreen, DonatePanel, ProfileScreen, SeedDialog,
  LevelDebugMenu — кожен повертає `Loc.t("router_title.*")` з UA fallback
- **Тести:** 8 кейсів у `tests/unit/test_loc.gd` —
  language_changed signal emission, no-op на same-language,
  t() resolves + params, missing key fallback, **key-audit** (всі
  16 нових ключів існують у UK і EN), UA↔EN round-trip

**Прогрес:** infrastructure ready, мігровано:
- HeroCard
- MainMenu (dynamic Play CTA)
- 7 router_titles (Statistics, Collection, Settings, Donate, Profile,
  SeedDialog, LevelDebugMenu)
- **PauseScreen** — title, all 5 buttons, exit-confirm, level/souls/
  sin formats — з live-refresh на `language_changed`
- **SettingsScreen language toggle** — клік по UA/EN тепер реально
  викликає `Loc.set_language(code)`. Початковий язик з settings.json
  застосовується через новий `_apply_language()` у `_apply_all()`.

**EN audit:** `uk.json` має 512 ключів, `en.json` — 312. Розрив у 200
ключів виключно в секції `souls.*` (lore named souls — 100 named +
20 hidden, ~200 рядків наративу). Лоре-переклад залишено translator'у
— pattern працює для всіх UI-секцій.

**Bug fix:** виправлено баг з минулої коміту, де `func _on_language_
changed` помилково інлайнилось у середині `_ready()` — це робило
`_apply_banner_space()` нерухомим (4 integration-тести у
`test_main_menu_layout.gd` падали). Тепер 369 unit + 553 integration
зелені.

## 🎯 Топ-5 за ROI

1. **U1 + U2 + U3** — Hero-картка + динамічна «Грати» —
   миттєво робить меню «живим». ⭐⭐
2. **U11 + U12 + U13** — Theme.tres + Palette.gd + font hierarchy —
   найбільший майбутній виграш у часі. ⭐⭐⭐ (одноразово)
3. **U10 + U8** — Top-bar з 💡/👻 + back-stack — рятує
   «куди натиснути back». ⭐⭐
4. **U5** — Параллакс/частинки на меню — найвищий «WOW» / зусилля. ⭐⭐⭐
5. **U15 + U21** — Sin-stained UI tint + поізонні вени —
   діегетичні деталі, унікальні для гри. ⭐⭐⭐

