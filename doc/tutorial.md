# Туторіал — Система Підказок

> Файл-довідник. Джерело: `tutorial_config.json`

---

## Підхід: Контекстний

Туторіал **вбудований у рівні** — підказки з'являються при першій зустрічі з механікою. Окремого туторіального режиму немає.

- Кожна підказка показується **лише один раз** (зберігається в save файлі)
- Виняток: **міні-гра сплячої душі** — показується щоразу (механіка рандомна, гравець міг забути)
- При **New Game+** всі підказки вимкнені автоматично
- Підказку можна скипнути будь-якою кнопкою дії

---

## Стиль підказок

```
┌────────────────────────────────┐
│  [🎮 іконка]  Текст підказки   │
└────────────────────────────────┘
        bottom-center
```

- Позиція: `bottom_center`
- Фон: темна "пілюля"
- Fade in: 0.3 сек / Fade out: 0.5 сек / Тривалість: 4 сек
- Іконка автоматично підлаштовується під keyboard або gamepad

---

## Типи візуальних демонстрацій

| Тип | Опис | Використовується для |
|-----|------|----------------------|
| `animated_ghost_player` | Напівпрозорий силует гравця (opacity 0.5) показує рух у loop | move, jump, staff, carry |
| `highlight_pulse` | Об'єкт пульсує жовтим контуром | soul_pickup, платформи |
| `arrow_animated` | Анімована стрілка вказує напрямок | carry_to_exit, hidden_souls |
| `input_press_animation` | Іконка кнопки натискається у loop | jump, staff |
| `input_hold_animation` | Іконка кнопки + прогрес-бар заповнення | variable_jump, exorcism |

---

## Всі тригери підказок

| ID | Рівень | Тригер | Візуалізація |
|----|--------|--------|--------------|
| `move` | 1 | старт рівня (затримка 1.5с) | ghost ходить ліво-право |
| `jump` | 1 | наближення до першої ями (120px) | ghost стрибає, press_animation |
| `variable_jump` | 1 | після першого стрибка | ghost: короткий vs довгий стрибок |
| `soul_pickup` | 1 | наближення до першої душі (100px) | highlight_pulse + ghost підбирає |
| `carry_to_exit` | 1 | після підбору першої душі | стрілка → вихід |
| `enemy_nearby` | 1 | перший ворог у полі зору | ghost обходить ворога ззаду |
| `enemy_chasing` | 2 | перше переслідування | — |
| `one_way_platform` | 2 | наближення (80px) | highlight_pulse |
| `crumbling_platform` | 2 | наближення (60px) | платформа тремтить preview |
| `staff` | 3 | ворог блокує прохід | ghost б'є посохом, ворог відлітає |
| `staff_sin_warning` | 3 | після першого удару посохом | іконка sin_bar |
| `sin_bar` | 1 | перший приріст гріху | пояснення шкали |
| `sleeping_soul` | 5 | наближення до сплячої душі (120px) | highlight_pulse + ghost взаємодіє |
| `minigame_hint` | 5 | старт міні-гри | **завжди**, demo 1.5с |
| `mimic` | 7 | наближення до міміка (150px) | highlight_pulse |
| `mimic_exorcism` | 7 | стоїть поруч з міміком 2с | ghost утримує кнопку, мімік зникає |
| `faith_platform` | 51 | наближення (100px) | platform зникає при sin > 50% |
| `soul_bridge` | 61 | наближення (100px) | ghost без душі падає, з душею стоїть |
| `hidden_souls` | 1 | 30 сек після старту рівня | — |

---

## Скрипт: TutorialManager.gd (Autoload)

**Що має робити:**

```
_ready()
    _load_config()          — читає tutorial_config.json
    _load_seen_hints()      — з SaveManager завантажує список показаних підказок

show_hint(trigger_id)       — публічний метод, викликається з рівня/ворогів
    if _is_seen(trigger_id) and not _is_always_show(trigger_id): return
    _display_hint(trigger_id)
    _start_visual_demo(trigger_id)
    _mark_seen(trigger_id)

_display_hint(id)           — показує текст + іконку з fade in/out
_start_visual_demo(id)      — запускає відповідний тип анімації
_mark_seen(id)              — зберігає в SaveManager
_is_seen(id) → bool
_is_always_show(id) → bool  — true тільки для minigame_hint
```

**Виклики з інших скриптів:**
```gdscript
# Рівень при старті:
TutorialManager.show_hint("move")

# Коли гравець підходить до душі:
TutorialManager.show_hint("soul_pickup")

# Після удару посохом:
TutorialManager.show_hint("staff_sin_warning")

# Перед міні-грою (завжди):
TutorialManager.show_hint("minigame_hint")
```

---

## Бог як туторіал

Деякі механіки пояснює Бог через повідомлення в Хабі — не через окремі підказки:
- Рівень 1: загальна атмосфера, відчуття небезпеки, мотивація рухатись
- Детальні тексти: `doc/dialogues.md`
