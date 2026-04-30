extends GutTest

# Tests for ProfileScreen card-state rendering.
# The screen uses the live SaveManager autoload (at /root/SaveManager),
# so we clean up profiles in after_each just as test_profile_create_screen.gd does.

const ProfileScreenScript := preload("res://scripts/ui/ProfileScreen.gd")

var screen: CanvasLayer
var sm: Node


func before_each() -> void:
	sm = get_node_or_null("/root/SaveManager")
	if sm:
		for i in sm.MAX_SLOTS:
			if sm.has_save(i):
				sm.delete_slot(i)
	screen = ProfileScreenScript.new()
	add_child_autofree(screen)


func after_each() -> void:
	if sm:
		for i in sm.MAX_SLOTS:
			if sm.has_save(i):
				sm.delete_slot(i)


# ── Build ─────────────────────────────────────────────────────────────────────

func test_screen_builds_slots_box() -> void:
	assert_not_null(screen._slots_box)


# ── _make_slot_card three states ─────────────────────────────────────────────

func test_empty_card_has_no_switch_button() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	var info := {"slot": 0, "exists": false}
	var card: Control = screen._make_slot_card(info)
	add_child_autofree(card)
	# No "▶ Грати за цим" / btn_switch should be in an empty card.
	_assert_no_button_text_contains(card, "Грати за цим")


func test_empty_card_has_new_profile_button() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	var info := {"slot": 0, "exists": false}
	var card: Control = screen._make_slot_card(info)
	add_child_autofree(card)
	assert_true(_card_has_button_text_containing(card, "Профіль"),
			"empty card must show a create/new button")


func test_inactive_existing_card_has_switch_button() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	# Slot 0 exists but slot 1 is active → slot 0 is inactive.
	sm.create_profile(0, "Alpha")
	sm.create_profile(1, "Beta")
	sm.load_slot(1)
	var info := {"slot": 0, "exists": true, "level": 1, "total_souls": 0, "name": "Alpha"}
	var card: Control = screen._make_slot_card(info)
	add_child_autofree(card)
	assert_true(_card_has_button_text_containing(card, "Грати за цим"),
			"inactive slot must offer a switch button")


func test_inactive_existing_card_has_delete_button() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	sm.create_profile(0, "Alpha")
	sm.create_profile(1, "Beta")
	sm.load_slot(1)
	var info := {"slot": 0, "exists": true, "level": 1, "total_souls": 0, "name": "Alpha"}
	var card: Control = screen._make_slot_card(info)
	add_child_autofree(card)
	assert_true(_card_has_button_text_containing(card, "Видалити"),
			"inactive slot must offer a delete button")


func test_active_card_shows_active_indicator_disabled() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	sm.create_profile(0, "Solo")
	var info := {"slot": 0, "exists": true, "level": 1, "total_souls": 0, "name": "Solo"}
	var card: Control = screen._make_slot_card(info)
	add_child_autofree(card)
	# The active indicator button must be present and disabled.
	var btn := _find_button_text_containing(card, "Активний")
	assert_not_null(btn, "active card must have an Активний indicator button")
	if btn:
		assert_true(btn.disabled, "Активний button must be disabled")


func test_active_card_has_no_switch_button() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	sm.create_profile(0, "Solo")
	var info := {"slot": 0, "exists": true, "level": 1, "total_souls": 0, "name": "Solo"}
	var card: Control = screen._make_slot_card(info)
	add_child_autofree(card)
	_assert_no_button_text_contains(card, "Грати за цим")


func test_active_card_still_has_delete_button() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	sm.create_profile(0, "Solo")
	var info := {"slot": 0, "exists": true, "level": 1, "total_souls": 0, "name": "Solo"}
	var card: Control = screen._make_slot_card(info)
	add_child_autofree(card)
	assert_true(_card_has_button_text_containing(card, "Видалити"),
			"active slot must still show delete")


# ── _request_delete double-tap confirm ───────────────────────────────────────

func test_delete_requires_double_tap() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	sm.create_profile(0, "Alpha")
	sm.create_profile(1, "Beta")
	sm.load_slot(1)
	# First tap: sets _confirm_slot, does NOT delete.
	screen._request_delete(0)
	assert_true(sm.has_save(0), "first tap must not delete")
	assert_eq(screen._confirm_slot, 0)


func test_delete_second_tap_removes_slot() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	sm.create_profile(0, "Alpha")
	sm.create_profile(1, "Beta")
	sm.load_slot(1)
	screen._request_delete(0)   # first tap → confirm mode
	screen._request_delete(0)   # second tap → actually deletes
	assert_false(sm.has_save(0), "second tap must delete the slot")


# ── _select_slot updates SaveManager ─────────────────────────────────────────

func test_select_slot_switches_active_profile() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	sm.create_profile(0, "Alpha")
	sm.create_profile(1, "Beta")
	sm.load_slot(1)
	assert_eq(sm.get_active_slot(), 1)
	# _select_slot calls SaveManager.load_slot and closes the screen.
	screen._select_slot(0)
	assert_eq(sm.get_active_slot(), 0)
	assert_eq(sm.get_profile_name(), "Alpha")


# ── Helpers ───────────────────────────────────────────────────────────────────

## Recursively collect all Button nodes inside a control.
func _collect_buttons(node: Node) -> Array:
	var result: Array = []
	if node is Button:
		result.append(node)
	for child in node.get_children():
		result += _collect_buttons(child)
	return result


func _card_has_button_text_containing(card: Control, fragment: String) -> bool:
	for btn in _collect_buttons(card):
		if fragment in btn.text:
			return true
	return false


func _find_button_text_containing(card: Control, fragment: String) -> Button:
	for btn in _collect_buttons(card):
		if fragment in btn.text:
			return btn
	return null


func _assert_no_button_text_contains(card: Control, fragment: String) -> void:
	assert_false(_card_has_button_text_containing(card, fragment),
			"Card must NOT contain a button with text containing '%s'" % fragment)
