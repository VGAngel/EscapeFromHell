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
