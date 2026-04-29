extends GutTest

# Tests for the souls_seen tracking added to SaveManager (drives the
# CollectionScreen NEW! badge).

var sm: Node

func before_each() -> void:
	sm = preload("res://scripts/managers/SaveManager.gd").new()
	add_child_autofree(sm)

# ── Defaults ──────────────────────────────────────────────────────────────────

func test_fresh_save_has_empty_souls_seen() -> void:
	assert_eq(sm.data.get("souls_seen"), [])

func test_unseen_returns_zero_when_no_souls() -> void:
	assert_eq(sm.get_unseen_souls_count(), 0)

# ── mark / is_seen ────────────────────────────────────────────────────────────

func test_is_soul_seen_default_false() -> void:
	assert_false(sm.is_soul_seen(7))

func test_mark_soul_seen_flips_check() -> void:
	sm.mark_soul_seen(7)
	assert_true(sm.is_soul_seen(7))

func test_mark_soul_seen_is_idempotent() -> void:
	sm.mark_soul_seen(7)
	sm.mark_soul_seen(7)
	# souls_seen array shouldn't grow on second mark.
	assert_eq(sm.data["souls_seen"].count(7), 1)

# ── get_unseen_souls_count ────────────────────────────────────────────────────

func test_unseen_counts_collected_minus_seen() -> void:
	# Collect three; mark one as seen.
	sm.add_soul(1)
	sm.add_soul(2)
	sm.add_soul(3)
	sm.mark_soul_seen(2)
	assert_eq(sm.get_unseen_souls_count(), 2)

func test_unseen_skips_seen_but_uncollected() -> void:
	# Edge case: marking a soul as seen even before it's collected
	# shouldn't artificially inflate or deflate the unseen count.
	sm.mark_soul_seen(99)
	sm.add_soul(1)
	assert_eq(sm.get_unseen_souls_count(), 1)

# ── mark_all_souls_seen ───────────────────────────────────────────────────────

func test_mark_all_clears_unseen() -> void:
	sm.add_soul(10)
	sm.add_soul(11)
	sm.add_soul(12)
	assert_eq(sm.get_unseen_souls_count(), 3)
	sm.mark_all_souls_seen()
	assert_eq(sm.get_unseen_souls_count(), 0)
	assert_true(sm.is_soul_seen(10))
	assert_true(sm.is_soul_seen(11))
	assert_true(sm.is_soul_seen(12))

# ── Migration ─────────────────────────────────────────────────────────────────

func test_migration_seeds_seen_with_existing_collected() -> void:
	# Simulate loading a save from before souls_seen existed: drop
	# the field entirely, populate saved_soul_ids with old data, then
	# run _migrate. After migration, all old souls should be marked
	# as seen (no surprise NEW-badge wave).
	sm.data.erase("souls_seen")
	sm.data["saved_soul_ids"] = [4, 5, 6]
	sm.data["version"] = 1
	sm._migrate()
	assert_eq(sm.get_unseen_souls_count(), 0,
			"existing souls should be pre-seeded as seen")
	for id in [4, 5, 6]:
		assert_true(sm.is_soul_seen(id))
