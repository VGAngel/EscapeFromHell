extends GutTest

# Tests for the multi-profile lifecycle: name validation, active-slot
# pointer, signals, and the recovery path when the active profile is
# deleted. Uses fresh SaveManager.gd instances under add_child_autofree;
# real persistence is exercised by writing to user://saves/_test* paths
# we clean up after each test.

const SaveManagerScript := preload("res://scripts/managers/SaveManager.gd")

var sm: Node


func before_each() -> void:
	sm = SaveManagerScript.new()
	add_child_autofree(sm)


func after_each() -> void:
	# Clean up anything the test wrote to disk so subsequent tests get
	# pristine state. (We never share the autoload — that's left alone.)
	for i in sm.MAX_SLOTS:
		if FileAccess.file_exists(sm._save_path(i)):
			DirAccess.remove_absolute(sm._save_path(i))
		if FileAccess.file_exists(sm._backup_path(i)):
			DirAccess.remove_absolute(sm._backup_path(i))
	if FileAccess.file_exists(sm.ACTIVE_SLOT_PATH):
		DirAccess.remove_absolute(sm.ACTIVE_SLOT_PATH)


# ── Name validation ───────────────────────────────────────────────────────────

func test_valid_latin_name_accepted() -> void:
	assert_true(sm.is_valid_profile_name("Danylo"))


func test_valid_cyrillic_name_accepted() -> void:
	assert_true(sm.is_valid_profile_name("Данило"))


func test_valid_mixed_name_with_digits_and_space_accepted() -> void:
	assert_true(sm.is_valid_profile_name("Player 1"))
	assert_true(sm.is_valid_profile_name("Гравець 42"))


func test_too_short_rejected() -> void:
	assert_false(sm.is_valid_profile_name("ab"))
	assert_false(sm.is_valid_profile_name(""))


func test_too_long_rejected() -> void:
	assert_false(sm.is_valid_profile_name("X".repeat(21)))


func test_whitespace_only_rejected() -> void:
	assert_false(sm.is_valid_profile_name("    "))


func test_emoji_rejected() -> void:
	assert_false(sm.is_valid_profile_name("Player😈"))


func test_punctuation_rejected() -> void:
	# Specifically: dash, dot, slash, comma — outside the allowed set.
	assert_false(sm.is_valid_profile_name("Player-1"))
	assert_false(sm.is_valid_profile_name("Player.1"))
	assert_false(sm.is_valid_profile_name("Player/1"))


# ── create_profile ───────────────────────────────────────────────────────────

func test_create_profile_persists_name_and_emits_signals() -> void:
	watch_signals(sm)
	assert_true(sm.create_profile(0, "Тест"))
	assert_eq(sm.get_profile_name(), "Тест")
	assert_eq(sm.get_active_slot(), 0)
	assert_signal_emitted(sm, "profile_created")
	assert_signal_emitted(sm, "profile_switched")


func test_create_profile_rejects_invalid_name() -> void:
	assert_false(sm.create_profile(0, ""))
	assert_false(sm.create_profile(0, "X"))   # too short
	# slot must remain empty
	assert_false(sm.has_save(0))


func test_create_profile_rejects_occupied_slot() -> void:
	sm.create_profile(0, "First")
	# Trying to create over an existing slot must fail without nuking it.
	assert_false(sm.create_profile(0, "Second"))
	assert_eq(sm.get_profile_name(), "First")


# ── Active-slot persistence ──────────────────────────────────────────────────

func test_active_slot_written_to_disk() -> void:
	sm.create_profile(1, "Alpha")
	assert_true(FileAccess.file_exists(sm.ACTIVE_SLOT_PATH))
	# Re-read via the private helper (testing implementation detail
	# is fine here — the on-disk format is the contract we care about).
	assert_eq(sm._read_active_slot(), 1)


func test_load_slot_updates_active_pointer() -> void:
	sm.create_profile(0, "Alpha")
	sm.create_profile(1, "Beta")
	sm.load_slot(0)
	assert_eq(sm.get_active_slot(), 0)
	assert_eq(sm._read_active_slot(), 0)


# ── has_any_profiles / first_existing_slot ────────────────────────────────────

func test_has_any_profiles_false_when_empty() -> void:
	assert_false(sm.has_any_profiles())
	assert_eq(sm.first_existing_slot(), -1)


func test_has_any_profiles_true_after_create() -> void:
	sm.create_profile(2, "Gamma")
	assert_true(sm.has_any_profiles())
	assert_eq(sm.first_existing_slot(), 2)


# ── Delete recovery ───────────────────────────────────────────────────────────

func test_delete_active_falls_back_to_first_existing() -> void:
	sm.create_profile(0, "Alpha")
	sm.create_profile(1, "Beta")
	sm.load_slot(1)
	assert_eq(sm.get_active_slot(), 1)
	watch_signals(sm)
	sm.delete_slot(1)
	# Active should silently switch to slot 0 (the only remaining one).
	assert_eq(sm.get_active_slot(), 0)
	assert_eq(sm.get_profile_name(), "Alpha")
	assert_signal_emitted(sm, "profile_deleted")
	assert_signal_emitted(sm, "profile_switched")


func test_delete_last_profile_clears_active_pointer() -> void:
	sm.create_profile(0, "Solo")
	sm.delete_slot(0)
	assert_false(sm.has_any_profiles())
	assert_false(FileAccess.file_exists(sm.ACTIVE_SLOT_PATH),
			"active_slot.json must be removed when no profiles remain")


# ── Boot restoration ──────────────────────────────────────────────────────────

func test_boot_restore_picks_up_active_slot_pointer() -> void:
	# Simulate the autoload boot path. We populate disk via one
	# instance, then create a fresh one and call _boot_restore() —
	# parented to a non-root, so the public _ready() path skips it.
	sm.create_profile(2, "Persistent")
	var fresh: Node = SaveManagerScript.new()
	add_child_autofree(fresh)
	# Manual restore (mirrors what autoload does at /root).
	fresh._boot_restore()
	assert_eq(fresh.get_active_slot(), 2)
	assert_eq(fresh.get_profile_name(), "Persistent")


func test_boot_restore_falls_back_when_pointer_missing() -> void:
	# Existing player upgrading from pre-profiles build: only slot
	# files exist, no active_slot.json. Boot must still load *some*
	# profile rather than land on an empty slot.
	sm.create_profile(1, "Legacy")
	# Wipe the pointer file to simulate the upgrade scenario.
	if FileAccess.file_exists(sm.ACTIVE_SLOT_PATH):
		DirAccess.remove_absolute(sm.ACTIVE_SLOT_PATH)
	var fresh: Node = SaveManagerScript.new()
	add_child_autofree(fresh)
	fresh._boot_restore()
	assert_eq(fresh.get_active_slot(), 1)
	assert_eq(fresh.get_profile_name(), "Legacy")
	# And the recovery should have repopulated the pointer for next boot.
	assert_true(FileAccess.file_exists(sm.ACTIVE_SLOT_PATH))


func test_boot_restore_no_profiles_leaves_clean_state() -> void:
	# True first launch: no slot files, no active pointer. Boot must
	# leave SaveManager in reset state so MainMenu sees
	# has_any_profiles() == false and triggers the create screen.
	var fresh: Node = SaveManagerScript.new()
	add_child_autofree(fresh)
	fresh._boot_restore()
	assert_false(fresh.has_any_profiles())
	assert_eq(fresh.get_profile_name(), "")
