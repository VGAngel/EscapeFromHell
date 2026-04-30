extends GutTest

# Static guards on the build pipeline files (D1+D2+D6+D7).
# These don't run the scripts — they just verify that everything the
# pipeline expects to find at fixed paths is present and looks sane.
# Catches accidental rename / delete during refactors, and confirms
# CI workflows reference real scripts.

func _exists(path: String) -> bool:
	return FileAccess.file_exists(path)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


# ── Build scripts ─────────────────────────────────────────────────────────────

func test_build_scripts_present() -> void:
	assert_true(_exists("res://scripts/build/create_keystore.sh"),
			"keystore generator script must exist")
	assert_true(_exists("res://scripts/build/build_android.sh"),
			"Android build script must exist")
	assert_true(_exists("res://scripts/build/audit_manifest.sh"),
			"manifest audit script must exist")
	assert_true(_exists("res://scripts/build/bump_version.sh"),
			"version bump script must exist (D6)")


func test_secrets_template_present_but_real_files_absent() -> void:
	# The example must exist (devs need a starting point) but the
	# real env file must NOT — if it shows up in the repo, secrets
	# leaked.
	assert_true(_exists("res://secrets/keystore.env.example"),
			"secrets/keystore.env.example must be checked in")
	assert_true(_exists("res://secrets/.gitignore"),
			"secrets/.gitignore must whitelist only safe files")
	assert_false(_exists("res://secrets/keystore.env"),
			"secrets/keystore.env must NEVER be committed")
	assert_false(_exists("res://secrets/release.keystore"),
			"secrets/release.keystore must NEVER be committed")


# ── CI workflows (D7) ─────────────────────────────────────────────────────────

func test_ci_workflows_present() -> void:
	assert_true(_exists("res://.github/workflows/tests.yml"),
			"GUT tests CI workflow missing")
	assert_true(_exists("res://.github/workflows/android.yml"),
			"Android AAB CI workflow missing")


func test_android_workflow_references_real_scripts() -> void:
	var wf: String = _read("res://.github/workflows/android.yml")
	assert_true(wf.find("scripts/build/build_android.sh") != -1,
			"android.yml must invoke build_android.sh")
	assert_true(wf.find("scripts/build/audit_manifest.sh") != -1,
			"android.yml must invoke audit_manifest.sh")
	# Required secrets must be referenced (typo guard).
	for s in ["EFH_RELEASE_KEYSTORE_BASE64",
			"EFH_RELEASE_KEYSTORE_PASS",
			"EFH_RELEASE_KEYSTORE_USER"]:
		assert_true(wf.find(s) != -1,
				"android.yml must reference secret %s" % s)


func test_tests_workflow_runs_gut() -> void:
	var wf: String = _read("res://.github/workflows/tests.yml")
	assert_true(wf.find("addons/gut/gut_cmdln.gd") != -1,
			"tests.yml must invoke GUT")
	assert_true(wf.find("res://tests") != -1,
			"tests.yml must point GUT at res://tests")


# ── Docs ──────────────────────────────────────────────────────────────────────

func test_android_build_docs_present() -> void:
	assert_true(_exists("res://docs/ANDROID_BUILD.md"),
			"docs/ANDROID_BUILD.md must explain the build flow")
