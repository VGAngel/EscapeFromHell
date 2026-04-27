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

### 4. 🟢 Soul echo — нести 2 душі

**Що:** Апгрейд `soul_memory` (вже у конфігу!) дозволяє носити 2 душі
одночасно.

**Чому:**
- **Вже у `upgrades_config.json`** — лишилось додати логіку
- Розблоковує паттерни: "пройди раз, збери дві, поверни обидві"
- Стимулює прокачку upgrades
- Економія часу = неявна нагорода за вибір цього апгрейда

**Як:** `Player.carried_soul_id: String` → `carried_soul_ids: Array[String]`.
Capacity = `1 + SaveManager.get_upgrade_level("soul_memory")`. У
`pick_up_soul`:
```gdscript
var cap: int = 1 + (SaveManager.get_upgrade_level("soul_memory") if SaveManager else 0)
if carried_soul_ids.size() >= cap: return
carried_soul_ids.append(soul_id)
```
SoulCarryVisual → візуально 2 sprite-spheres збоку.

**Складність:** Середня. Зачіпає Player, AltarNode (deliver loop), HUD,
LevelBase (multi-soul drop on death).

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

### 7. 🟢 Coyote-time візуалізація для сповзаючих платформ

**Що:** Поточні `CRUMBLE_DELAY = 0.5` (Crumbling) і `0.2` (Ash) дають
вікно щоб встигнути стрибнути, але візуально це не зрозуміло. Додати
тремтіння + falling-sand particles під час delay.

**Чому:** Гравець знає "скоро впаде, треба стрибати ЗАРАЗ". Менше відчуття
"я не вийшов винним".

**Як:** У `_on_body_entered` стартонути shake-tween на `_visual` плюс
`ParticleEffects.spawn("crumble_warn", ...)`.

**Складність:** Дуже низька.

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
