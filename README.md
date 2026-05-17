# Escape from Hell

2D платформер на Godot 4 для Android.

## Документація

Повний Game Design Document знаходиться в `doc/GDD.md`.

### Як оновити GDD.docx

1. Відредагуй `doc/GDD.md`
2. Запусти в терміналі з папки проекту:

```bash
python3 doc/convert_gdd.py
```

3. Отримаєш оновлений `doc/GDD.docx`

> Скрипт `doc/convert_gdd.py` читає `GDD.md` і перезаписує `GDD.docx`.

---

## Тести

Проект використовує [GUT](https://github.com/bitwes/Gut) для unit + integration тестів.
Два готові скрипти запускають увесь набір у headless-режимі та зберігають
повний лог із timestamp:

```bash
./tests/run_unit.sh           # ~1 хв,  263 unit тести (tests/unit/)
./tests/run_integration.sh    # ~3-5 хв, integration тести (tests/integration/)
```

**Логи:** `tests/logs/{unit,integration}_<timestamp>.log` (gitignored).
На stdout виводиться останні 30 рядків (саммарі + які впали).
Exit code: `0` якщо все зелене, не нуль — є fails.

**Опціонально:** якщо Godot встановлено в нестандартному місці —
```bash
GODOT_BIN=/path/to/godot ./tests/run_unit.sh
```

---

## Build & Release (Android)

Повна інструкція — `docs/ANDROID_BUILD.md`. Коротко:

```bash
# One-time (per machine):
./scripts/build/create_keystore.sh             # генерує debug + release keystores
cp secrets/keystore.env.example secrets/keystore.env   # вписати release пароль
# Потім у редакторі: Project → Install Android Build Template…

# Кожен реліз:
./scripts/build/bump_version.sh patch          # 0.1.0 → 0.1.1 (+ versionCode)
./scripts/build/build_android.sh               # signed AAB у build/
```

Усе в `secrets/` (keystores + паролі) gitignored. `bump_version.sh`
тримає `project.godot` і `export_presets.cfg` синхронними — Play Console
відхиляє upload з не-монотонним `versionCode`.

### Debug vs Release UI

`BuildConfig` autoload — єдине джерело істини "це debug-білд?". Ховає
debug-only UI (Levels(debug), Seed, F3 DebugOverlay) у release-білдах.
Перемикання — через `application/config/debug_ui_mode` в
`project.godot` (`auto` / `force_on` / `force_off`) або через додавання
`release` feature tag у export preset.

### CI (GitHub Actions)

- `.github/workflows/tests.yml` — GUT suite на push/PR в main
- `.github/workflows/android.yml` — AAB build на tag `v*` push або
  manual dispatch; артефакт + GitHub Release на тег

Активувати Android CI — додати три repo secrets:
`EFH_RELEASE_KEYSTORE_BASE64` (`base64 -i secrets/release.keystore`),
`EFH_RELEASE_KEYSTORE_PASS`, `EFH_RELEASE_KEYSTORE_USER`.

---

## Обробка ассетів

### Видалення фону (`tools/bg_remove.py`)

Утиліта для чистки фону з ассетів (наприклад, згенерованих у Midjourney).
Працює на 1–2 кольорах фону з допуском (RGB distance) і плавним переходом на краях.

**Залежності:** Python 3, `Pillow`, `numpy` (обидва вже є в стандартному середовищі).

```bash
# 1 колір, вручну
python3 tools/bg_remove.py in.png out.png --colors "#ffffff"

# 2 кольори + більший допуск
python3 tools/bg_remove.py in.png out.png --colors "#ffffff,#f0f0f0" --tolerance 35

# авто-детект кольорів фону з кутів зображення (до 2)
python3 tools/bg_remove.py in.png out.png --auto

# пакетно по всій папці + м'який край
python3 tools/bg_remove.py Assets/raw/ Assets/OurAssets/ --auto --feather 1
```

**Прапорці:**
- `--colors "#hex,#hex"` — 1–2 кольори фону (hex)
- `--auto` — автоматично бере кольори з 4 кутів зображення
- `--tolerance N` — допуск RGB-відстані (за замовч. `25`; більше → агресивніше стирає)
- `--feather N` — Gaussian-розмиття альфи для згладжування зубців (за замовч. `0`)

**Як працює:**
пікселі ближчі за `tolerance` до фонового кольору стають повністю прозорими,
далі за `tolerance*2` — повністю непрозорими, між ними — плавний градієнт (щоб
не було ореолів на краях).

### Безшовна тайл-фактура (`tools/seam_blend.py`)

Робить зображення безшовно повторюваним по вертикалі (або горизонталі). Використовується
для стін/фонів, які у грі повторюються вздовж шахти: MJ рідко дає ідеально зшивний
результат, цей тул дотягує стик за ~секунду кросфейдом верх↔низ.

```bash
# вертикальний тайл (для стін шахти)
python3 tools/seam_blend.py wall.png wall_tiled.png --band 64

# горизонтальний тайл (для фонів, підлоги)
python3 tools/seam_blend.py floor.png floor_tiled.png --band 48 --axis x

# обидві осі (для текстури що повторюється в сітку)
python3 tools/seam_blend.py tex.png tex_tiled.png --band 64 --axis both
```

**Прапорці:**
- `--band N` — скільки пікселів з кожного краю змішувати (дефолт `64`). Більше → м'якший перехід, але й більше «розмитого» контенту з країв.
- `--axis y|x|both` — по якій осі робити безшовним (дефолт `y`).

Типовий пайплайн для стіни: Midjourney (`--tile --ar 1:2`) → `bg_remove.py` (якщо є фон) → `seam_blend.py --band 64` → в гру.

---

## Збірка APK для Android

Preset `Android` уже налаштований в `export_presets.cfg` (arm64-v8a, debug).

### Одноразова підготовка (на Mac)

1. **JDK 17+**
   ```bash
   brew install --cask temurin@17
   ```

2. **Android SDK** (command-line tools)
   ```bash
   brew install --cask android-commandlinetools
   sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34"
   ```

3. **Godot Android export templates**
   В редакторі: `Editor → Manage Export Templates → Download and Install`.
   Версія шаблонів має збігатися з версією движка (зараз 4.6.1-stable).

4. **Debug keystore** (генерується один раз)
   ```bash
   keytool -keyalg RSA -genkeypair -alias androiddebugkey \
	 -keypass android -keystore ~/.android/debug.keystore \
	 -storepass android -dname "CN=Android Debug,O=Android,C=US" \
	 -validity 9999 -deststoretype pkcs12
   ```

5. **Шляхи в Godot Editor Settings** (`Editor → Editor Settings → Export → Android`):
   - `Android Sdk Path` → шлях до SDK (зазвичай `~/Library/Android/sdk` або те що вивів `brew --prefix android-commandlinetools`)
   - `Debug Keystore` → `~/.android/debug.keystore`
   - `Debug Keystore User` → `androiddebugkey`
   - `Debug Keystore Pass` → `android`

### Збірка APK з командного рядка

З папки проекту:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --export-debug "Android" build/escape-from-hell.apk
```

APK зʼявиться в `build/escape-from-hell.apk` (~20–40 МБ).

### Встановлення на телефон

1. На телефоні: `Налаштування → Для розробників → USB Debugging = ON`.
2. Підʼєднай телефон по USB, підтверди довіру на екрані.
3. Перевір що телефон бачиться:
   ```bash
   adb devices
   ```
4. Постав APK:
   ```bash
   adb install -r build/escape-from-hell.apk
   ```

   Прапорець `-r` перевстановлює поверх існуючої версії зі збереженням даних.

### Швидкий one-liner «збери і постав»

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --export-debug "Android" build/escape-from-hell.apk \
  && adb install -r build/escape-from-hell.apk
```

### Якщо збірка падає

- `export template not found` → не встановлені шаблони (крок 3).
- `Invalid SDK path` → неправильний `Android Sdk Path` у Editor Settings.
- `keytool: command not found` → не встановлений JDK або не в `PATH`.
- `adb: no devices` → не увімкнений USB debugging або не підтверджена довіра на телефоні.
