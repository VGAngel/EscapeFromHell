# Release — Code-only TODO

> Створено: 2026-04-29
> Сфокусована підмножина `doc/release_plan.md`: лише **code work** (без art / audio / store / legal copy / QA-runs).
>
> Це список того що має написати програміст щоб гра могла піти в реліз. Контент-команда (художник/композитор/перекладач) робить паралельну роботу — вона **не** в цьому списку.

---

## Легенда

| Значок | Сенс |
|---|---|
| 🔥 | Release-blocker |
| 🟠 | Quality-bar |
| 🟡 | Nice-to-have |

| Розмір | Час (1 програміст) |
|---|---|
| S | < 1 день |
| M | 2–5 днів |
| L | 1–2 тижні |

---

## A. Gameplay (код)

| ID | Задача | Розмір | Тип |
|---|---|---|---|
| A9 | 🔥 **Demon deal UI + logic** — DemonDealPanel + DemonNPC + spawn integration + 6 boon types + accept/refuse persistence | M | new feature |
| A10 | 🟠 **Boss intro/outro cutscenes** — loading flow + 10 boss-specific scenes/triggers | M | new feature |
| A12 | 🟠 **Milestone narrative events** — рівні 50, 75, 99, 100 з narrative trigger + scenes | S | new feature |
| A15 | 🟠 **God messages** при відкритті нового кола — hook у `Hub._show_hub` коли `current_circle` зростає | S | new feature |

## D. Build pipeline 🔥

| ID | Задача | Розмір | Тип |
|---|---|---|---|
| D1 | 🔥 Android keystore generation script + safe storage (env var або 1Password) | S | infra |
| D2 | 🔥 Android signed AAB build script (`scripts/build_android.sh`) — debug + release modes | S | infra |
| D3 | 🔥 AndroidManifest audit — target SDK 34+, permissions list (INTERNET, VIBRATE, ...) | S | infra |
| D4 | 🔥 iOS export preset + Apple Developer cert (один раз на macOS) | M | infra |
| D5 | 🔥 TestFlight workflow — `scripts/build_ios.sh` + Fastlane integration | M | infra |
| D6 | 🟠 Version-bump script — synchs `project.godot` + `AndroidManifest.xml` versionCode/Name + iOS build | S | infra |
| D7 | 🟠 GitHub Actions CI — build Android AAB on push to main, upload artifact | M | infra |

## E. Privacy/Legal (код-частина) 🔥

| ID | Задача | Розмір | Тип |
|---|---|---|---|
| E1 | 🔥 Privacy policy hosted URL — `dreamplay.games/privacy.html` (статичний HTML) | S | content+code |
| E2 | 🔥 In-game PrivacyPolicy screen — body content + посилання на hosted URL | S | content |
| E3 | 🔥 GDPR consent dialog на першому запуску — детект EU локалі, persistent decision, reset path у Settings | M | new feature |
| E4 | 🟠 IDFA / Ad ID consent (iOS 14.5+) — `App Tracking Transparency` prompt, gated by AdsManager | S | new feature |
| E5 | 🔥 Google Play Data Safety form payload — config file з declarations (collected data, purposes, third parties) | S | content |
| E6 | 🔥 Apple App Privacy details — той самий config переведений на формат Apple | S | content |

## F. Analytics & crash reporting

| ID | Задача | Розмір | Тип |
|---|---|---|---|
| F1 | 🔥 Crashlytics (Firebase) integration — Godot Android plugin + smoke test (handled exception) | M | new feature |
| F2 | 🔥 Crash reporting verified end-to-end (intentional crash → Firebase dashboard) | S | QA |
| F3 | 🟠 Funnel analytics events — `level_started`, `level_completed`, `soul_collected`, `demon_deal_{accepted/refused}`, `death_cause`, `circle_unlocked` | M | new feature |
| F4 | 🟠 Privacy/Analytics opt-in toggle — Settings → новий Privacy tab з 2 toggles (analytics ON/OFF, crash reports ON/OFF) | S | new feature |
| F5 | 🟡 Anonymized session metrics — average FPS, peak memory, session length — sent on app close | S | new feature |

## G. Performance & robustness 🔥

| ID | Задача | Розмір | Тип |
|---|---|---|---|
| G5 | 🔥 Performance profile на min-spec Android (Pixel 4a / Galaxy A12) — identify worst frame-time hotspots | M | optimization |
| G6 | 🟠 Thermal throttling response — 30 min session test, fallback (зменшити particle count, disable shadow vignette) під throttle | S | optimization |
| G7 | 🟠 Battery drain measurement — < 8%/година на 50% яскравості | S | optimization |
| G8 | 🔥 Save corruption recovery stress-test — 5 scenarios (truncated JSON, invalid version, partial backup, disk full, concurrent write) | M | QA-code |
| G11 | 🟠 Auto-pause на app focus loss — `NOTIFICATION_WM_WINDOW_FOCUS_OUT` (Godot 4 default; verify на Android target) | S | bug-prevention |

## C. Polish (UX)

| ID | Задача | Розмір | Тип |
|---|---|---|---|
| C1 | 🟠 High-contrast theme variant — Settings toggle, окрема Theme з вищим contrast ratio | S | new feature |
| C2 | 🟠 UI text scale 90/100/110/120% — global multiplier на theme font_size overrides | M | new feature |
| C3 | 🟠 Death-recap screen — після 3+ deaths на одному рівні: anti-frustration tip + опціональна skip-checkpoint кнопка | M | new feature |
| C4 | 🟠 Adaptive difficulty silent assist — після 5+ deaths: +1 max HP на цей рівень (без banner) | M | new feature |
| C9 | 🟠 Demo mode build flag — project setting → lock circles 4-10 + soft paywall на level 31 | M | new feature |
| C10 | 🟡 Credits screen — `scripts/ui/CreditsScreen.gd` + `credits.json` config | S | new feature |
| C11 | 🟡 In-game build version + commit hash — debug overlay + Settings → About | S | new feature |

## L. Localization (код-side)

| ID | Задача | Розмір | Тип |
|---|---|---|---|
| L1 | 🟠 Translate 200 `souls.*` lore strings (named + hidden) → EN | (translator pass) | content |
| L2 | 🟠 Audit `prologue` + `god_messages` UA/EN parity — деякі ключі тільки UA | S | content |

## T. Tech debt (можна паралельно)

| ID | Задача | Розмір | Тип |
|---|---|---|---|
| T1 | 🟡 Move `Soul.gd` + `Soul.tscn` з кореня → `scripts/` + `scenes/` | S | refactor |
| T2 | 🟡 Move `Level1.gd` + `Level2.gd` test scenes → `archive/` | S | refactor |
| T3 | 🟡 LevelBase.gd refactor — 1100+ рядків → 3 модулі (LevelBuilder + LevelLoop + LevelDelivery) | M | refactor |
| T4 | 🟡 gdformat sweep — 70+ файлів з tab/space mixed warnings | S | hygiene |
| T5 | 🟡 gdlint sweep — fix max-line-length 120, duplicated-load, name-convention (~30+ warnings) | S | hygiene |
| T6 | 🟡 Delete unused `Assets/rpg-platformer-game-assets/` — saves disk + APK size | S | hygiene |

---

## 📊 Critical-path до релізу (тільки код)

**Тиждень 1-2: Build pipeline + Privacy**
- D1, D2, D3 (Android signed AAB)
- E1, E2 (privacy policy hosted + in-game)
- E5, E6 (store privacy declarations)

**Тиждень 3: Crash reporting + Analytics**
- F1, F2 (Crashlytics)
- F3, F4 (funnel + opt-in)

**Тиждень 4-5: Gameplay completion + GDPR**
- A9 (demon deal — найбільший залишковий feature)
- A10, A12, A15 (cutscenes + milestone events + god messages)
- E3 (GDPR consent)

**Тиждень 6: Performance + robustness**
- G5, G8 (profile + save corruption test)
- G6, G7, G11 (thermal + battery + auto-pause)

**Тиждень 7: iOS pipeline**
- D4, D5 (iOS provisioning + TestFlight)

**Тиждень 8: Polish features**
- C1, C2 (a11y: high-contrast + text scale)
- C3, C4 (death-recap + adaptive difficulty)
- C9 (demo mode flag — для App Store free tier)

**Тиждень 9: Tech debt + final polish**
- T4, T5 (formatter sweep)
- C10, C11 (credits + version display)
- L2 (i18n parity audit)

**= 9 тижнів code work** при 1 програмісту, full-time, без блокерів від контент-команди.

---

## 🎯 Топ-10 наступних задач (start here)

1. **D1+D2** — Android signed AAB pipeline (без цього не можемо build на real device)
2. **E1+E2** — hosted privacy policy + in-game body (Google Play blocker)
3. **F1** — Crashlytics integration (без crash reports реліз сліпий)
4. **A9** — Demon deal mechanic (найбільший залишковий gameplay feature)
5. **G5** — performance profile на min-spec
6. **E3** — GDPR consent dialog (EU release blocker)
7. **G8** — save corruption stress test (data integrity blocker)
8. **A10** — boss cutscenes (10 cinematic beats)
9. **C3** — death-recap (anti-frustration impact на retention)
10. **D7** — GitHub Actions CI (kicks off after D1-D2)

---

## 📌 Що **не** в цьому списку (умисно)

| Категорія | Хто робить |
|---|---|
| Player анімації, tilesets, backgrounds, soul illustrations | Художник |
| Music (10 треків) + SFX (~60) + voice acting | Композитор / sound designer |
| App Store screenshots, trailer, hero artwork | Marketing / художник |
| Description text (UA + EN, 4000 chars) | Copywriter |
| Manual playthrough всіх 100 рівнів | QA-тестери |
| Beta tester recruitment + Discord moderation | Community manager |
| Press kit + outreach до gaming media | PR / marketing |

Ці категорії в `doc/release_plan.md` (Phases B, H — повний 9-фазний план).

---

## ✅ Що вже зроблено (код-side, цей session + раніше)

**Foundation:** Player movement, всі 19 ворогів, всі platforms, save system, level generation, hub, prologue, mechanics (souls, sin, upgrades, endings)

**UI:** Theme + Palette, UIRouter (back-stack), TopBar, HeroCard + dynamic Play CTA, SinVignette, DamageFlash, HUD pop, NEW badge у Collection, MenuAmbient (parallax/embers/ash/shadows), TitleCard, WelcomeCard

**Feel:** UIFeedback (haptic + tap-grow на ВСІ кнопки), DeliveryRitual (slow-mo + audio duck при доставці), MotionSettings (reduce-motion accessibility)

**i18n:** Loc autoload + UA/EN files, **138 ключів** в audit, **15/15 UI screens** мігровано, **live language switch** через Settings

**Onboarding:** WelcomeCard pre-prologue, TitleCard "Коло N — НАЗВА" на кожен рівень, auto-fire move + jump tutorial hints на level 1

**Tests:** **442 unit + 553 integration** зелені

---

> **Наступний крок:** обрати топ-3 з шортлисту і занести як активний sprint. Або скажи `далі` для конкретного — я візьмусь.
