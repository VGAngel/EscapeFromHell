# Android build pipeline

End-to-end checklist for producing a signed `.aab` ready for Play
Store. One-time setup is ~15 min; subsequent builds are one command.

## One-time setup

### 1. Install JDK 17

```bash
brew install openjdk@17
sudo ln -sfn $(brew --prefix)/opt/openjdk@17/libexec/openjdk.jdk \
            /Library/Java/JavaVirtualMachines/openjdk-17.jdk
```

### 2. Install Android SDK build-tools (for `aapt` audit)

Easiest path: install Android Studio → SDK Manager → SDK Tools →
"Android SDK Build-Tools 35". Add `~/Library/Android/sdk/build-tools/35.0.0`
to PATH so `aapt` is callable, or set `AAPT_BIN` to its full path.

### 3. Install the Android build template inside Godot

Open the project in the Godot editor:

> Project → Install Android Build Template…

This creates `./android/build/` with the gradle source tree. The folder
is `.gitignore`-d — every dev regenerates it locally.

### 4. Generate keystores

```bash
./scripts/build/create_keystore.sh
```

- Debug keystore: created with the standard `androiddebugkey` /
  `android` password. Safe to regenerate on any machine.
- Release keystore: prompts for a strong password (≥12 chars).
  **Back up the file AND the password** to two offline locations
  immediately. If lost, the Play Store listing dies forever.

### 5. Wire up the env file

```bash
cp secrets/keystore.env.example secrets/keystore.env
$EDITOR secrets/keystore.env   # paste the release password
```

Both files are in `secrets/` which is `.gitignore`-d.

### 6. Validate the setup

```bash
./scripts/build/build_android.sh --validate-only
```

Expected output: `✅ all checks passed (validate-only)`.

## Building

```bash
./scripts/build/build_android.sh            # signed release AAB
./scripts/build/build_android.sh --debug    # debug-signed APK
```

Output goes to `build/escape-from-hell-<version>-<sha>-<ts>.aab`.

After the export, `audit_manifest.sh` runs automatically and verifies:
- package id matches `export_presets.cfg`
- `versionName` matches `project.godot`
- `versionCode` matches preset
- `targetSdkVersion` ≥ 34 (Play Store requirement)
- `android:debuggable` not set on release builds

## Troubleshooting

| Symptom | Cause |
|---|---|
| `android/build/ missing` | Run "Install Android Build Template" in editor |
| `keystore not found` | Run `scripts/build/create_keystore.sh` |
| `gradle_build/export_format must be 1` | Open editor → Android preset → Encryption: AAB |
| `aapt not found` | Install SDK build-tools or set `AAPT_BIN` |
| Build hangs at "Signing..." | Wrong password in `secrets/keystore.env` |

## Releasing

```bash
# 1. Bump versions in lockstep (project.godot + export_presets.cfg).
./scripts/build/bump_version.sh patch          # 0.1.0 → 0.1.1
# or:
./scripts/build/bump_version.sh minor          # 0.1.3 → 0.2.0
./scripts/build/bump_version.sh 0.5.0 --tag    # explicit + commit + tag

# 2. Build locally OR push the tag and let CI build it.
./scripts/build/build_android.sh

# Or, for a tagged release:
git push origin main && git push origin v0.1.1
# → triggers .github/workflows/android.yml, which builds the AAB
#   and attaches it to the GitHub Release for that tag.

# 3. Upload the AAB to Play Console → Internal Testing track first.
```

`versionCode` auto-increments on every `bump_version.sh` run. Play
Console rejects a build whose code is not strictly greater than the
last uploaded one, so never edit `version/code` by hand.

## CI

Two GitHub Actions workflows live in `.github/workflows/`:

- **`tests.yml`** — runs the GUT suite on every push and PR to
  `main`. Cached Godot binary keeps each run ~1 min.
- **`android.yml`** — builds a signed AAB on `v*` tag push (or
  manual dispatch). Requires three repo secrets:
  - `EFH_RELEASE_KEYSTORE_BASE64` — `base64 -i secrets/release.keystore`
  - `EFH_RELEASE_KEYSTORE_PASS`   — the password
  - `EFH_RELEASE_KEYSTORE_USER`   — alias (`escape_from_hell`)

  Output AAB is attached to the workflow run as an artifact and
  (on tag push) to the GitHub Release for that tag.
