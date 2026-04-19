extends GutTest

# Integration tests for CollectionScreen.gd (CanvasLayer).

var screen: Node

func before_each() -> void:
	# TODO: instantiate CollectionScreen, inject souls JSON, build UI
	pass

# ── Open / close ──────────────────────────────────────────────────────────────

func test_invisible_by_default() -> void:
	# TODO: assert screen.visible == false after _ready()
	pass

func test_open_makes_visible() -> void:
	# TODO: call screen.open(), assert visible == true
	pass

func test_close_emits_signal() -> void:
	# TODO: watch "closed", call close(), assert received
	pass

# ── Grid ──────────────────────────────────────────────────────────────────────

func test_grid_shows_all_named_souls() -> void:
	# TODO: inject 10 named souls, open, assert grid has 10 cells
	pass

func test_saved_soul_shows_name() -> void:
	# TODO: add soul_id 1 to SaveManager, open,
	# assert cell for id=1 shows soul name (not "?")
	pass

func test_unsaved_soul_shows_question_mark() -> void:
	# TODO: soul not saved → cell label text == "?"
	pass

func test_hidden_soul_shows_star_badge() -> void:
	# TODO: inject hidden soul, assert ✦ badge visible on cell
	pass

# ── Filtering ─────────────────────────────────────────────────────────────────

func test_circle_filter_hides_other_circles() -> void:
	# TODO: set _filter_circle = 1, assert only circle-1 souls shown
	pass

func test_type_filter_shows_only_matching_type() -> void:
	# TODO: set _filter_type = "innocent", assert non-innocent cells removed
	pass

func test_missing_filter_hides_found_souls() -> void:
	# TODO: save soul_id 1, enable missing filter,
	# assert soul_id 1 cell not in grid
	pass

# ── Detail sheet ──────────────────────────────────────────────────────────────

func test_tap_saved_soul_opens_sheet() -> void:
	# TODO: simulate cell press for a saved soul, assert _sheet_open == true
	pass

func test_tap_unsaved_soul_shows_not_found_message() -> void:
	# TODO: simulate cell press for unsaved soul,
	# assert sheet shows "Душа не знайдена"
	pass

func test_escape_key_closes_sheet_not_screen() -> void:
	# TODO: open sheet, press ui_cancel, assert sheet closed but screen still open
	pass

# ── Notifications ─────────────────────────────────────────────────────────────

func test_notify_soul_added_animates_cell() -> void:
	# TODO: open screen, call notify_soul_added(1),
	# assert cell 1 has scale tween triggered
	pass

func test_completion_label_shown_at_100_souls() -> void:
	# TODO: add 100 souls to SaveManager, call notify_soul_added,
	# assert _completion_lbl.visible == true
	pass
