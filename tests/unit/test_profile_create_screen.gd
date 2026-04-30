extends GutTest

# Tests for ProfileCreateScreen — the mandatory first-launch onboarding.
# The screen calls into the live SaveManager autoload, so we tear down
# any test-created profiles in after_each to keep the autoload's view
# of disk pristine for unrelated tests.

const ProfileCreateScreenScript := preload("res://scripts/ui/ProfileCreateScreen.gd")

var screen: CanvasLayer
var sm: Node


func before_each() -> void:
	sm = get_node_or_null("/root/SaveManager")
	# Clean any leftover profiles from prior runs so we have a true
	# first-launch state.
	if sm:
		for i in sm.MAX_SLOTS:
			if sm.has_save(i):
				sm.delete_slot(i)
	screen = ProfileCreateScreenScript.new()
	add_child_autofree(screen)


func after_each() -> void:
	if sm:
		for i in sm.MAX_SLOTS:
			if sm.has_save(i):
				sm.delete_slot(i)


# ── Build ─────────────────────────────────────────────────────────────────────

func test_screen_builds_input_and_button() -> void:
	assert_not_null(screen._name_edit)
	assert_not_null(screen._btn_start)
	assert_not_null(screen._hint_lbl)


# ── Validation feedback ───────────────────────────────────────────────────────

func test_start_button_disabled_when_name_invalid() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	screen._name_buffer = ""
	screen._refresh_validation()
	assert_true(screen._btn_start.disabled,
			"empty name must keep Start disabled")
	screen._name_buffer = "ab"   # too short
	screen._refresh_validation()
	assert_true(screen._btn_start.disabled)


func test_start_button_enabled_when_name_valid() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	screen._name_buffer = "Геймер"
	screen._refresh_validation()
	assert_false(screen._btn_start.disabled,
			"valid name must enable Start")


# ── Submit ────────────────────────────────────────────────────────────────────

func test_submit_creates_profile_and_emits_signal() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	watch_signals(screen)
	screen._name_buffer = "ТестГерой"
	screen._on_submit()
	assert_signal_emitted(screen, "created")
	assert_true(sm.has_any_profiles())
	assert_eq(sm.get_profile_name(), "ТестГерой")


func test_submit_with_invalid_name_does_nothing() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	watch_signals(screen)
	screen._name_buffer = "  "
	screen._on_submit()
	assert_signal_not_emitted(screen, "created")
	assert_false(sm.has_any_profiles())
