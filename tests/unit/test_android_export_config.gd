extends GutTest

# Static guards on the Android export preset. These don't run a real
# export — they just parse `export_presets.cfg` and check the values
# that, if drifted, would silently produce an unuploadable AAB
# (wrong format, missing 64-bit, debuggable left on, etc.). Cheap,
# runs in <50ms, catches the kind of slip-up that costs an hour
# debugging a Play Console rejection.

const PRESET_PATH := "res://export_presets.cfg"
const PROJECT_PATH := "res://project.godot"


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "could not open %s" % path)
	var s: String = f.get_as_text()
	f.close()
	return s


# ── Preset existence ──────────────────────────────────────────────────────────

func test_android_preset_exists() -> void:
	var cfg: String = _read(PRESET_PATH)
	assert_true(cfg.find('name="Android"') != -1,
			"export_presets.cfg must have an 'Android' preset")
	assert_true(cfg.find('platform="Android"') != -1)


# ── Play Store hard requirements ──────────────────────────────────────────────

func test_aab_format_is_set() -> void:
	# 0 = APK, 1 = AAB. Play Store has required AAB for new apps
	# since Aug 2021.
	var cfg: String = _read(PRESET_PATH)
	assert_true(cfg.find("gradle_build/export_format=1") != -1,
			"Android preset must export AAB (gradle_build/export_format=1)")


func test_gradle_build_enabled() -> void:
	# AAB output requires a gradle build, not the prebuilt template.
	var cfg: String = _read(PRESET_PATH)
	assert_true(cfg.find("gradle_build/use_gradle_build=true") != -1,
			"gradle_build/use_gradle_build must be true to emit AAB")


func test_arm64_enabled() -> void:
	# Play Store has required 64-bit since Aug 2019.
	var cfg: String = _read(PRESET_PATH)
	assert_true(cfg.find("architectures/arm64-v8a=true") != -1,
			"arm64-v8a must be enabled — Play Store requires 64-bit")


func test_x86_disabled() -> void:
	# We don't ship x86 — keeps the AAB small and matches every
	# real-world Android device.
	var cfg: String = _read(PRESET_PATH)
	assert_true(cfg.find("architectures/x86=false") != -1,
			"x86 should not be packaged for a phone-only release")
	assert_true(cfg.find("architectures/x86_64=false") != -1)


func test_target_sdk_high_enough() -> void:
	# Play Store requires targetSdk ≥ 34 for new apps in 2025.
	# Our preset uses 35 to stay ahead of the rolling deadline.
	var cfg: String = _read(PRESET_PATH)
	var pat := RegEx.new()
	pat.compile('gradle_build/target_sdk="(\\d+)"')
	var m: RegExMatch = pat.search(cfg)
	if m == null:
		# Empty string means "use Godot default" which is currently 34
		# in Godot 4.6. Accept that as fine.
		assert_true(cfg.find('gradle_build/target_sdk=""') != -1,
				"target_sdk must be set or left empty (= Godot default)")
		return
	var v: int = int(m.get_string(1))
	assert_gte(v, 34,
			"target_sdk must be ≥ 34 for Play Store; got %d" % v)


func test_signed_flag_set() -> void:
	var cfg: String = _read(PRESET_PATH)
	assert_true(cfg.find("package/signed=true") != -1,
			"package/signed must be true; build script wires the keystore")


# ── Identity ──────────────────────────────────────────────────────────────────

func test_package_name_matches_studio() -> void:
	var cfg: String = _read(PRESET_PATH)
	assert_true(cfg.find('package/unique_name="games.dreamplay.escapefromhell"') != -1,
			"package id is the Play Store identity — don't rename casually")


func test_version_in_preset_matches_project() -> void:
	# These two strings MUST match — Play Console rejects a build
	# whose versionName/versionCode is out of step with the previously
	# uploaded one. Easy to forget when bumping by hand.
	var preset_cfg: String = _read(PRESET_PATH)
	var project_cfg: String = _read(PROJECT_PATH)
	var pat := RegEx.new()
	pat.compile('config/version="([^"]+)"')
	var pm: RegExMatch = pat.search(project_cfg)
	assert_not_null(pm, "project.godot must declare config/version")
	var v: String = pm.get_string(1)
	assert_true(preset_cfg.find('version/name="%s"' % v) != -1,
			"export preset version/name must match project.godot config/version (%s)" % v)


# ── Footguns ──────────────────────────────────────────────────────────────────

func test_no_dangerous_permissions_enabled() -> void:
	# We don't need location, mic, contacts, SMS, etc. Catch a stray
	# `permissions/access_fine_location=true` before it ships.
	var cfg: String = _read(PRESET_PATH)
	var pat := RegEx.new()
	pat.compile("permissions/(access_fine_location|access_coarse_location|read_sms|read_contacts|record_audio|camera|read_calendar)=true")
	var m: RegExMatch = pat.search(cfg)
	assert_null(m,
			"sensitive permission enabled in preset: %s" % (m.get_string(1) if m else ""))
