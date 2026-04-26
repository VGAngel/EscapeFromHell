# Beehave AI — шаблон для ворогів

Ці leaf-вузли дублюють логіку `BaseEnemy.gd` у форматі behavior tree. Поки що це
лише **демо/шаблон**: жоден існуючий ворог на них не переключений. Додано, щоб
оцінити, як виглядатиме повноцінна міграція, перш ніж її починати.

## Як спробувати

1. Відкрити Godot, переконатись що Beehave увімкнено в Project Settings → Plugins.
2. Створити сцену-копію `scenes/enemies/PaleWanderer.tscn` (наприклад
   `PaleWandererBeehave.tscn`).
3. Додати під корінь ворога вузол `BeehaveTree`.
4. Збудувати таке дерево (через Add Child Node):

```
BeehaveTree
└── SelectorReactive          # перериває нижчі гілки, якщо вища стала придатною
    ├── Sequence              # CHASE branch
    │   ├── CanSeePlayerCondition
    │   └── ChaseAction
    ├── GiveUpAction          # запускається коли CHASE падає у FAILURE
    └── PatrolAction          # default — завжди RUNNING
```

5. Видалити `_physics_process` зі скрипту ворога (або тимчасово виставити
   `set_physics_process(false)`) — щоб state machine `BaseEnemy` не конфліктувала
   з деревом.

## Що далі

Якщо демо подобається, повна міграція виглядатиме так:

- `BaseEnemy.gd` спрощується: лишаються гравітація, анімації, отримання урону,
  завантаження конфігу. Уся state-логіка переїздить у дерево.
- Кожен підклас (`PaleWanderer`, `ShadowLost`, тощо) отримує власне дерево —
  або один спільний шаблон з параметрами через `@export`.
- `BossAI.gd` (469 рядків, 7 станів) — найкраща мета: фази стають піддеревами
  з `Sequence` + `Cooldown` декораторами замість таймерів-полів.

## Перенесені поведінки

| State (BaseEnemy)  | Beehave заміна                              |
|--------------------|---------------------------------------------|
| PATROL             | `PatrolAction`                              |
| ALERT → CHASE      | `Sequence(CanSeePlayerCondition, ChaseAction)` |
| GIVE_UP            | `GiveUpAction`                              |
| RETURN             | (вилучено в оригіналі — авто-PATROL)        |
| STUNNED            | окреме під-дерево або interrupt всього tree |

## Що НЕ перенесено в шаблоні

Свідомо лишилось у `BaseEnemy.gd` як інфраструктура:

- гравітація, анімації, sprite flip
- завантаження конфігу з `enemies_config.json`
- контактний урон і кулдаун ударів
- spatial audio
- знокбек / стан

Ці речі не пов'язані з прийняттям рішень — їм у дереві не місце.
