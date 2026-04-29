# Release Plan — «Escape from Hell»

> Створено: 2026-04-29
> Власник: dev team
> Огляд поточного стану: див. `doc/Todo.md` (134 елементи, 92 ✅, 41 ⬜) і `doc/assets_status.md`.
>
> Цей документ — **release-readiness roadmap**: що залишилось зробити щоб вийти у Google Play / App Store, з пріоритетами, оцінками часу і залежностями.

---

## Легенда

| Значок | Сенс |
|--------|------|
| 🔥 | Release-blocker — без цього не можна публікувати |
| 🟠 | Quality-bar — можна без, але страждає reception |
| 🟡 | Nice-to-have — після MVP |
| ⚪ | Post-launch / V2 |

| Розмір | Час |
|--------|-----|
| S | < 1 день |
| M | 2–5 днів |
| L | 1–2 тижні |
| XL | 2+ тижні (потребує дробити) |

---

## 🎯 Шлях до релізу (high-level)

```
Phase A: Content completion       → 8-12 тижнів  (LARGE — потребує контент-команди)
Phase B: Assets (art + audio)     → 6-10 тижнів  (LARGE — паралельно з A)
Phase C: Polish & accessibility   → 2-4 тижні    (значна частина зроблена)
Phase D: Tech / build pipeline    → 1-2 тижні
Phase E: Privacy / legal          → 1 тиждень
Phase F: Analytics & telemetry    → 1 тиждень
Phase G: QA & beta                → 3-4 тижні
Phase H: Store presence           → 1-2 тижні
Phase I: Release flow             → 1 тиждень
```

**Реалістична MTTR (Time-to-Release):** ~4–5 місяців якщо контент і art ідуть паралельно.

---

## Phase A — Content completion 🔥

> Ціль: 100% gameplay reachable, всі endings + souls + bosses.

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| A1 | 🔥 Кімнати + вороги circle_6 (heresy_cathedral) | L | ⬜ |
| A2 | 🔥 Кімнати + вороги circle_7 (violence_fortress) | L | ⬜ |
| A3 | 🔥 Кімнати + вороги circle_8 (fraud_machine) | L | ⬜ |
| A4 | 🔥 Кімнати + вороги circle_9 (betrayal_ice) | L | ⬜ |
| A5 | 🔥 Кімнати + вороги circle_10 (throne_abyss) | L | ⬜ |
| A6 | 🔥 18 branch-рівнів (void) — handmade | L | ⬜ |
| A7 | 🔥 Статичні рівні 75 + 99 (milestone) | M | ⬜ |
| A8 | 🔥 Доставка душі до алтаря на рівні (механіка) | S | ✅ — Player.deliver_soul + AltarNode + light pillar + LevelBase._on_soul_delivered + DeliveryRitual |
| A9 | 🟠 Угоди з демонами — UI + логіка | M | ⬜ |
| A10 | 🟠 Кат-сцени перед/після боса (10 шт) | M | ⬜ |
| A11 | 🟠 Hidden souls: placement у handmade кімнатах | S | ⬜ |
| A12 | 🟠 Milestone рівень 50: нарративна подія | S | ⬜ |
| A13 | 🟠 Нарратив 50/75/99/100 (тексти) | M | ⬜ |
| A14 | 🟠 Tutorial-рівні 1+2 з вшитими hand-made підказками | M | ⬜ |
| A15 | 🟠 God messages при відкритті нових кіл | S | ⬜ |
| A16 | 🟡 Діалоги: 100 душ (тексти) | M | ⬜ |
| A17 | 🟡 Угоди з демонами — варіанти на рівнях 4-9 | M | ⬜ |

**Залежності:** A1-A5 потребують enemy AI який вже є, але вимагають final art (Phase B).
A8 — невеликий, можна робити одразу.
A14 — частково покрито онбордингом (TitleCard, WelcomeCard, jump hints).

---

## Phase B — Assets 🔥 (паралельно з Phase A)

> Ціль: усе візуальне і аудіо replace placeholders на final art.

### B1. Player art

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| B1.1 | 🔥 Player sprites: idle, walk, jump, fall, attack, carry, dead | M | ⬜ |
| B1.2 | 🔥 Sin-state textures (clean / tainted / fallen) для shader | S | ⬜ |
| B1.3 | 🟠 Death animation specific | S | ⬜ |
| B1.4 | 🟠 Soul-carry visual on player | S | ⬜ |

### B2. Environment art

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| B2.1 | 🔥 Tilesets для 10 кіл (`Assets/tilesets/`) | XL | ⬜ |
| B2.2 | 🔥 Background art (parallax layers per circle, 10) | L | ⬜ |
| B2.3 | 🟠 Hazard sprites (lava, spikes, void) | M | ⬜ |
| B2.4 | 🟠 Particle assets для embers/ash/fog | S | ⬜ |
| B2.5 | 🟡 Decorative props (pews, chains, statues per circle) | M | ⬜ |

### B3. UI / icons

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| B3.1 | 🔥 UI icons replace emoji (♥ ♡ 👻 💡 ⏸ ⚔) | M | ⬜ |
| B3.2 | 🔥 Android launcher icons (всі density) | S | ⬜ |
| B3.3 | 🔥 iOS app icon (всі sizes 20-1024) | S | ⬜ |
| B3.4 | 🟠 Custom font для display-text (для UA + EN) | M | ⬜ |
| B3.5 | 🟠 Soul illustrations (100 named souls) | XL | ⬜ |
| B3.6 | 🟡 Hidden soul illustrations (20) | M | ⬜ |

### B4. Audio

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| B4.1 | 🔥 Music: ambient per circle (10 треків + hub) | XL | ⬜ |
| B4.2 | 🔥 Music: boss theme variant per боса (6) | L | ⬜ |
| B4.3 | 🔥 SFX: jump, attack, soul_pickup, death, hit | M | ⬜ |
| B4.4 | 🔥 SFX: UI clicks, page-turn, deliver, prologue | M | ⬜ |
| B4.5 | 🟠 SFX: hazards (lava sizzle, spike jab, crumble) | M | ⬜ |
| B4.6 | 🟠 Voice: narrator (prologue) — UA + EN | L | ⬜ |
| B4.7 | 🟡 Voice: God lines (Hub prologue) — UA + EN | M | ⬜ |
| B4.8 | 🟡 Soul whispers (collected in CollectionScreen) | M | ⬜ |

**Залежності:** B1, B2, B3 — критичні для App Store screenshots (Phase H).
B4 audio — можна тримати як «final 3 weeks» бо асет легкий до інтеграції.

---

## Phase C — Polish & accessibility

> Більшість — зроблено в цій сесії. Лишаються довороботи.

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| C1 | 🟠 High-contrast theme в Settings (U27) | S | ⬜ |
| C2 | 🟠 UI text scale 90/100/110/120% (U26) | M | ⬜ |
| C3 | 🟠 Death-recap screen після 3+ deaths (U25/C2) | M | ⬜ |
| C4 | 🟠 Adaptive difficulty silent assist (C3) | M | ⬜ |
| C5 | 🟡 Mini-map / depth-indicator (U23) | M | ⬜ |
| C6 | 🟡 Tabbed hub overlay (U7 — великий рефакторинг) | L | ⬜ |
| C7 | 🟡 Versions chip → changelog overlay (U20) | S | ⬜ |
| C8 | 🟡 Ghost trail на player при швидкому русі (B3) | S | ⬜ |
| C9 | 🟡 Slow-mo на критичні моменти (B2) | S | ⬜ |
| C10 | 🟡 Adaptive sin-driven music layers (B1) | M | ⬜ |
| C11 | ⚪ One-handed mode (left-right swap, U29) | S | ⬜ |
| C12 | ⚪ Damage number popups над ворогами (B4) | S | ⬜ |

**Стан foundation:** UIRouter ✅, UITheme + Palette ✅, Loc ✅,
MotionSettings ✅, UIFeedback (haptic+pulse) ✅, MenuAmbient ✅,
TopBar ✅, HeroCard + dynamic Play ✅, SinVignette ✅, DamageFlash ✅,
HUD pop ✅, NEW badge у Collection ✅, DeliveryRitual ✅, TitleCard ✅,
WelcomeCard ✅, Auto-tutorial level 1 ✅.

---

## Phase D — Tech / build pipeline 🔥

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| D1 | 🔥 Android export preset + keystore generation | S | 🟡 (preset існує, keystore?) |
| D2 | 🔥 Android signed release APK + AAB build script | S | ⬜ |
| D3 | 🔥 Android manifest: target SDK 34+, permissions audit | S | ⬜ |
| D4 | 🔥 iOS export preset + Apple Developer cert | M | ⬜ |
| D5 | 🔥 iOS provisioning + TestFlight workflow | M | ⬜ |
| D6 | 🟠 Version bumping script (project.godot + manifest) | S | ⬜ |
| D7 | 🟠 CI build на push (GitHub Actions, Android only початково) | M | ⬜ |
| D8 | 🟠 PWA build (web demo на itch.io? optional) | M | ⬜ |
| D9 | 🟡 macOS / Windows desktop builds (для маркетингу демо) | S | ⬜ |

---

## Phase E — Privacy / legal 🔥

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| E1 | 🔥 Privacy policy URL — hosted on github.io / dreamplay.games | S | ⬜ |
| E2 | 🔥 In-game PrivacyPolicy screen — link до hosted URL | S | 🟡 (екран є, тексти?) |
| E3 | 🔥 GDPR consent dialog при першому запуску (EU) | M | ⬜ |
| E4 | 🔥 COPPA assessment (children's privacy) — заявити age rating | S | ⬜ |
| E5 | 🔥 Google Play Data Safety form | S | ⬜ |
| E6 | 🔥 Apple App Privacy details questionnaire | S | ⬜ |
| E7 | 🟠 Terms of Service / EULA (стандартний шаблон) | S | ⬜ |
| E8 | 🟠 IDFA / Ad ID consent dialog (iOS 14.5+) | S | ⬜ |

---

## Phase F — Analytics & crash reporting 🔥

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| F1 | 🔥 Crashlytics (Firebase) integration | M | ⬜ |
| F2 | 🔥 Crash reporting тестується на handled exception | S | ⬜ |
| F3 | 🟠 Funnel analytics: levels reached, deaths, retries | M | ⬜ |
| F4 | 🟠 Opt-in toggle в Settings → Privacy | S | ⬜ |
| F5 | 🟠 Anonymized session metrics (FPS, memory) | S | ⬜ |
| F6 | 🟡 A/B test framework (для post-launch tuning) | M | ⬜ |

---

## Phase G — QA & beta testing 🔥

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| G1 | 🔥 Manual playthrough всіх 100 рівнів (1 проходження = 1 тестер) | L | ⬜ |
| G2 | 🔥 Manual playthrough всіх 18 branch-рівнів | M | ⬜ |
| G3 | 🔥 Перевірка всіх 6 кінцівок (saint/redeemed/bound/fallen/traitor/rebel) | M | ⬜ |
| G4 | 🔥 Перевірка всіх 22 апгрейдів в дії | M | ⬜ |
| G5 | 🔥 Performance: 60 fps на min-spec Android (Snapdragon 660 / 4GB) | M | ⬜ |
| G6 | 🔥 Performance: thermal throttling після 30 хв сесії | S | ⬜ |
| G7 | 🔥 Battery drain: <8%/година при яскравості 50% | S | ⬜ |
| G8 | 🔥 Save corruption recovery (з backup) — 5 stress-тест scenarios | M | ⬜ |
| G9 | 🔥 Beta channel: 20-50 testers через Google Internal Testing | L | ⬜ |
| G10 | 🔥 Beta channel: TestFlight (50 invites) | M | ⬜ |
| G11 | 🟠 Edge cases: low battery, low storage, airplane mode mid-game | S | ⬜ |
| G12 | 🟠 Localization QA: native UA + EN review (читабельність + obscenities) | S | ⬜ |
| G13 | 🟠 Accessibility: kolour-blind palette test, screen-reader basic | S | ⬜ |
| G14 | 🟡 Speedrun community alpha (Discord/Reddit, 50 invites) | M | ⬜ |

---

## Phase H — Store presence 🔥

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| H1 | 🔥 App Store screenshots (iPhone 6.5"/5.5" + iPad) — 5 sizes × 2 langs | M | ⬜ |
| H2 | 🔥 Google Play screenshots (phone + 7"/10" tablet) | S | ⬜ |
| H3 | 🔥 Feature graphic (1024×500, Play Store) | S | ⬜ |
| H4 | 🔥 App Store hero artwork (1024×1024) | S | ⬜ |
| H5 | 🔥 Trailer video 30 с (App Store + Play Store + YouTube) | M | ⬜ |
| H6 | 🔥 Description text — UA + EN, both stores (4000 chars) | S | ⬜ |
| H7 | 🔥 Keywords / tags optimization (ASO research) | S | ⬜ |
| H8 | 🟠 Press kit: PNG hero + screenshots + EN one-pager | M | ⬜ |
| H9 | 🟠 Demo build (free, Circle 1-3 only) для itch.io / Steam | M | ⬜ |
| H10 | 🟡 Localization store metadata: RU? PL? (потенційні markets) | S | ⬜ |

---

## Phase I — Release flow

| ID | Задача | Розмір | Стан |
|----|--------|--------|------|
| I1 | 🔥 Soft launch (Internal Testing) → fix critical bugs | L | ⬜ |
| I2 | 🔥 Closed beta (Open Testing) → 1-2 тижні на feedback | L | ⬜ |
| I3 | 🔥 Production release Google Play | S | ⬜ |
| I4 | 🔥 Production release App Store (revival 1-3 days) | S | ⬜ |
| I5 | 🟠 Launch trailer публікація (YouTube + Twitter / Reddit) | S | ⬜ |
| I6 | 🟠 Reach out до Ukrainian gaming media (gamedev.dou.ua тощо) | S | ⬜ |
| I7 | 🟠 Day-1 patch plan (hotfix workflow) | S | ⬜ |

---

## Phase J — Tech debt (do alongside, not blocking release)

| ID | Задача | Розмір |
|----|--------|--------|
| J1 | Перенести `Soul.gd` / `Soul.tscn` з кореня у `scripts/` / `scenes/` | S |
| J2 | Перенести `Level1/2.gd` та старі тестові сцени в архів | S |
| J3 | Покрити `GameManager` unit-тестами (зараз 50%) | M |
| J4 | Видалити `PlaceholderVisual.gd` коли з'являться tilesets | S |
| J5 | gdformat sweep — 70+ файлів з warnings про tab/space mix | S |
| J6 | gdlint pass — 30+ warnings про line length 120+ | S |
| J7 | Asset audit: видалити невикористовувані `Assets/rpg-platformer-game-assets/` | S |
| J8 | Refactor `LevelBase.gd` (1000+ рядків) на ≤3 класи | M |

---

## 📊 Критичний шлях (Critical Path) — найкоротший до релізу

```
Week 1-4   → A1-A5 (Circles 6-10) + B1.1, B2.1 (player + tilesets)
Week 5-6   → B4.1-B4.4 (music + SFX)
Week 7     → A6, A7, A8, A9 (branches, milestones, deals)
Week 8     → C1-C4 (a11y polish), D1-D5 (build pipeline)
Week 9     → E1-E8 (privacy/legal), F1-F2 (crashlytics), B3.1-B3.3 (UI icons)
Week 10    → G1-G7 (manual QA), H1-H7 (store assets)
Week 11    → G9-G10 (beta), I1 (soft launch)
Week 12-13 → G11-G12 (beta fixes), H5 (trailer)
Week 14    → I2-I4 (production release)
```

**При паралельному виконанні Art ↔ Code teams:** ~14 тижнів = 3.5 місяці.

---

## 🎯 Топ-5 наступних задач (start here)

1. ~~**A8** — Доставка душі до алтаря~~ ✅ **уже реалізовано** (audit 2026-04-29)
2. **D1+D2** — Android signed build pipeline. Без цього не можемо ніщо тестити на real device.
3. **E1+E2** — Privacy policy hosted + in-game link. Блокатор Google Play.
4. **F1** — Crashlytics integration. Без crash reports реліз сліпий.
5. **A1** — Circle 6 (heresy). Найбільший залишковий контент-шматок.

**Новий кандидат на #1:** **A9** — Угоди з демонами UI + логіка
(M, sin-mechanic уже інтегрована, бракує лише UI), або
**A11** — Hidden souls placement у handmade rooms (S).

---

## 📌 Ризики та мітигації

| Ризик | Ймовірність | Імпакт | Мітигація |
|-------|-------------|--------|-----------|
| Художник не встигає з tilesets | Висока | Високий | Брати premium-tileset з Itch.io як fallback (B2.1 = M замість XL) |
| Музика не готова | Середня | Високий | freesound.org + ambient pack ($30) як фалбек, повна композиція post-launch |
| Voice acting затримується | Низька | Середній | Пуск без voice — він і не критичний для core loop'у |
| iOS provisioning складний | Середня | Високий | Запуск тільки Android в день 1, iOS — місяць після |
| Beta tester pool слабкий | Середня | Середній | Discord-сервер для перевірки + 5-10 знайомих |
| Performance не тягне на min-spec | Середня | Високий | Раннє профілювання на референс-телефоні (Pixel 4a / Galaxy A12) |
| Google Play відхиляє за GDPR | Середня | Високий | Чекатись 2-3 ітерації consent dialog'у — закладаємо +2 тижні |

---

## 🟢 Що вже готово (стан на 2026-04-29)

- **Foundation:** Player movement, all 19 enemies, all platforms, save system, level generation, hub, prologue
- **Mechanics:** Souls (named + hidden), upgrades (22), sin system, endings (6 logic), demon deals (partial)
- **UI:** Theme + Palette, UIRouter, TopBar, HeroCard + dynamic Play, SinVignette, DamageFlash, HUD pop, NEW badge у Collection, MenuAmbient (parallax/embers/ash/shadows), TitleCard, WelcomeCard
- **Feel:** UIFeedback (haptic + tap-grow), DeliveryRitual (slow-mo + audio duck), MotionSettings (reduce-motion)
- **i18n:** Loc autoload + UA/EN files, 138 ключів audit, 15/15 UI screens migrated, live language switch
- **Tests:** 435 unit + 553 integration, всі зелені

---

> **Наступний крок:** обрати Phase + перші 3-5 елементів і занести в `doc/Todo.md` як активний sprint.
