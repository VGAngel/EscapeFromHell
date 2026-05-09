extends CanvasLayer

# Accessible from: main menu, pause, level complete.
# Call open() / close() from outside.
# Call notify_soul_added(soul_id) when a new soul is collected mid-game.
#
# Static layout (header, type stats strip, circle progress container,
# filter tabs, type row, search/sort row, grid+side panel split, sheet
# popup) lives entirely in scenes/ui/CollectionScreen.tscn. This script
# wires signals, fills counters, builds the per-circle cells + grid
# cells dynamically (their count and styling depends on save state),
# and routes detail to the sheet (narrow) or side panel (wide).

signal closed

# ── Constants ─────────────────────────────────────────────────────────────────
const SOULS_PATH    := "res://souls_collection.json"
const FADE_DURATION := 0.35
# Grid is now adaptive: cols computed from viewport width, clamped to
# [MIN_COLS, MAX_COLS]. CELL_TARGET_W is the per-cell footprint used to
# decide how many columns fit.
const MIN_COLS         := 3
const MAX_COLS         := 8
const CELL_TARGET_W    := 140
const CELL_SIZE        := Vector2(130, 110)
const CELL_GAP         := 10
const DETAIL_W         := 320
# Bottom sheet caps at this fraction of viewport height; content scrolls
# inside if a hidden soul's full_story exceeds the cap.
const SHEET_MAX_H_FRAC := 0.62
# Above this viewport width the layout switches from grid + bottom-sheet
# to grid-left + persistent detail-panel-right (Persona/Hades style).
const WIDE_LAYOUT_PX   := 900
const SIDE_PANEL_W     := 380

# ── Soul data ─────────────────────────────────────────────────────────────────
var _named_souls:  Array = []
var _hidden_souls: Array = []

# ── Filter state ──────────────────────────────────────────────────────────────
var _filter_circle:  int    = 0
var _filter_type:    String = "all"
var _filter_missing: bool   = false

# Sort + search state. Sort mode is one of "id" (declared order, default),
# "name" (alphabetical), "circle" (Лімб → Трон), "type" (innocent →
# broken → sleeping). Search query is a case-insensitive substring
# matched against soul name AND epitaph/full_story.
var _sort_mode:    String = "id"
var _search_query: String = ""
const SORT_MODES: Array[String] = ["id", "name", "circle", "type"]

# ── Cell node map: soul_id (int or String) → Button ──────────────────────────
var _cell_nodes: Dictionary = {}

# Computed at _ready time — keeps an ordered list of circle filter buttons
# so _update_circle_tabs / _on_circle_tab can index by circle number.
var _circle_tabs: Array      = []   # Array[Button], index 0 = "Всі"
var _type_btns:   Dictionary = {}   # type key → Button

# Test-only override. When set to "narrow" or "wide", _is_wide_layout()
# returns the forced value instead of probing the viewport. Lets the
# integration suite assert sheet-vs-side-panel routing without juggling
# the test viewport size.
var _force_layout: String = ""

# True if last-shown detail came in wide mode (used to re-route on resize).
var _last_detail: Dictionary       = {}     # {soul, is_hidden} or empty
var _last_detail_was_not_found: bool = false

var _sheet_open: bool = false
var _sheet_tween: Tween = null

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var _root:        ColorRect = $Backdrop
@onready var _lbl_named:   Label = $Backdrop/VBox/HeaderMargin/Header/NamedLabel
@onready var _lbl_hidden:  Label = $Backdrop/VBox/HeaderMargin/Header/HiddenLabel
@onready var _lbl_total:   Label = $Backdrop/VBox/HeaderMargin/Header/TotalLabel
@onready var _close_btn:   Button = $Backdrop/VBox/HeaderMargin/Header/CloseButton
@onready var _lbl_type_stats: Label = $Backdrop/VBox/TypeStatsMargin/TypeStats
@onready var _circle_progress_box: HBoxContainer = $Backdrop/VBox/CircleProgressMargin/CircleProgress

@onready var _circle_row:  HBoxContainer = $Backdrop/VBox/CircleScroll/CircleRow
@onready var _tab_all:     Button = $Backdrop/VBox/CircleScroll/CircleRow/TabAll

@onready var _type_all:    Button = $Backdrop/VBox/TypeRowMargin/TypeRow/TypeAll
@onready var _type_inn:    Button = $Backdrop/VBox/TypeRowMargin/TypeRow/TypeInnocent
@onready var _type_brk:    Button = $Backdrop/VBox/TypeRowMargin/TypeRow/TypeBroken
@onready var _type_slp:    Button = $Backdrop/VBox/TypeRowMargin/TypeRow/TypeSleeping
@onready var _btn_missing: Button = $Backdrop/VBox/TypeRowMargin/TypeRow/MissingToggle

@onready var _search_input: LineEdit = $Backdrop/VBox/SearchSortMargin/SearchSort/SearchInput
@onready var _btn_sort:     Button   = $Backdrop/VBox/SearchSortMargin/SearchSort/SortButton

@onready var _grid:         GridContainer = $Backdrop/VBox/Split/GridScroll/GridMargin/Grid

@onready var _side_panel:    PanelContainer = $Backdrop/VBox/Split/SidePanel
@onready var _side_placeholder: Label = $Backdrop/VBox/Split/SidePanel/Scroll/VBox/SidePlaceholder
@onready var _side_name:     Label = $Backdrop/VBox/Split/SidePanel/Scroll/VBox/SideName
@onready var _side_age:      Label = $Backdrop/VBox/Split/SidePanel/Scroll/VBox/SideAge
@onready var _side_loc:      Label = $Backdrop/VBox/Split/SidePanel/Scroll/VBox/SideLoc
@onready var _side_sep:      HSeparator = $Backdrop/VBox/Split/SidePanel/Scroll/VBox/SideSep
@onready var _side_text:     Label = $Backdrop/VBox/Split/SidePanel/Scroll/VBox/SideText
@onready var _side_extra:    Label = $Backdrop/VBox/Split/SidePanel/Scroll/VBox/SideExtra

@onready var _sheet_backdrop: Button = $Backdrop/SheetBackdrop
@onready var _sheet:          PanelContainer = $Backdrop/Sheet
@onready var _sheet_name:     Label = $Backdrop/Sheet/Outer/Scroll/VBox/SheetName
@onready var _sheet_age:      Label = $Backdrop/Sheet/Outer/Scroll/VBox/SheetAge
@onready var _sheet_loc:      Label = $Backdrop/Sheet/Outer/Scroll/VBox/SheetLoc
@onready var _sheet_sep:      HSeparator = $Backdrop/Sheet/Outer/Scroll/VBox/SheetSep
@onready var _sheet_text:     Label = $Backdrop/Sheet/Outer/Scroll/VBox/SheetText
@onready var _sheet_extra:    Label = $Backdrop/Sheet/Outer/Scroll/VBox/SheetExtra
@onready var _sheet_scroll:   ScrollContainer = $Backdrop/Sheet/Outer/Scroll

@onready var _completion_lbl: Label = $Backdrop/CompletionLabel

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_souls()
	_wire_widgets()
	_grid.columns = _compute_cols()
	# Sheet content height tracks viewport so long stories scroll inside.
	_sheet_scroll.custom_minimum_size.y = get_viewport().get_visible_rect().size.y * SHEET_MAX_H_FRAC
	_root.modulate.a = 0.0
	visible = false
	_apply_layout_mode()
	_close_sheet_instant()
	# Live-refresh on language switch — full rebuild via open() if visible.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)
	# Live-relayout on rotation / window resize so columns adapt.
	get_viewport().size_changed.connect(_on_viewport_resized)


# Hook up button signals + populate localised text on the static widgets
# from the .tscn. Called once from _ready.
func _wire_widgets() -> void:
	_close_btn.pressed.connect(close)
	_search_input.placeholder_text = _t("collection.search_placeholder",
		{}, "🔍  Пошук за іменем або історією")
	_search_input.text_changed.connect(_on_search_text_changed)
	_btn_sort.text = _sort_label_for(_sort_mode)
	_btn_sort.pressed.connect(_on_sort_cycle_pressed)
	_btn_sort.modulate = Color.WHITE  # always "active"-tinted

	_sheet_backdrop.pressed.connect(_close_sheet)

	# Circle tabs — 11 buttons, 0 = "Всі", 1..10 = circles. The .tscn ships
	# them with hardcoded labels; re-localise + collect into an ordered array.
	_circle_tabs = [_tab_all]
	_tab_all.text = _t("collection.filter_all", {}, "Всі")
	_tab_all.pressed.connect(_on_circle_tab.bind(0))
	for c in range(1, 11):
		var btn: Button = _circle_row.get_node("Tab%d" % c) as Button
		btn.text = _t("collection.circle_tab_format", {"n": c}, "Коло %d" % c)
		btn.pressed.connect(_on_circle_tab.bind(c))
		_circle_tabs.append(btn)
	_update_circle_tabs()

	# Type buttons
	_type_all.text = _t("collection.filter_type_all",      {}, "Всі типи")
	_type_inn.text = _t("collection.filter_type_innocent", {}, "Невинні")
	_type_brk.text = _t("collection.filter_type_broken",   {}, "Зламані")
	_type_slp.text = _t("collection.filter_type_sleeping", {}, "Сплячі")
	_type_btns = {
		"all":      _type_all,
		"innocent": _type_inn,
		"broken":   _type_brk,
		"sleeping": _type_slp,
	}
	_type_all.pressed.connect(_on_type_btn.bind("all"))
	_type_inn.pressed.connect(_on_type_btn.bind("innocent"))
	_type_brk.pressed.connect(_on_type_btn.bind("broken"))
	_type_slp.pressed.connect(_on_type_btn.bind("sleeping"))

	_btn_missing.text = _t("collection.filter_not_found", {}, "Не знайдені")
	_btn_missing.pressed.connect(_on_missing_toggle)

	# Side panel placeholder + completion label localisation.
	_side_placeholder.text = _t("collection.side_placeholder", {},
		"Натисни на душу щоб побачити деталі")
	var n_target: int = SaveManager.get_named_souls_target() if SaveManager else 100
	_completion_lbl.text = _t("collection.complete_text",
		{"total": n_target}, "Всі %d душ знайдені" % n_target)


# Recompute grid columns based on current viewport width and rebuild the
# grid so cells reflow. Cheap when collection isn't visible; we still
# rebuild because a future open() would otherwise show the old col count
# for one frame.
func _on_viewport_resized() -> void:
	if not _grid:
		return
	# Layout mode (sheet vs side panel) is width-driven — re-evaluate
	# BEFORE recomputing columns since cols depend on whether the side
	# panel is visible.
	_apply_layout_mode()
	var cols := _compute_cols()
	if _grid.columns != cols:
		_grid.columns = cols
	if visible:
		_rebuild_grid()
	# If a soul was shown in the now-inactive panel, re-route to the new one.
	if not _last_detail.is_empty():
		if _last_detail_was_not_found:
			_show_detail_not_found(_last_detail.get("soul", {}))
		else:
			_show_detail(_last_detail.get("soul", {}),
				bool(_last_detail.get("is_hidden", false)))


func _compute_cols() -> int:
	var w: float = get_viewport().get_visible_rect().size.x
	# In wide layout the right side panel claims SIDE_PANEL_W of horizontal
	# space, so the grid has less room — subtract it before computing cols.
	if _is_wide_layout():
		w -= float(SIDE_PANEL_W + 24)  # +24 for HBox separation/margin
	# Subtract horizontal margins (18 left + 18 right) and a soft buffer
	# so the rightmost cell never clips against the scrollbar.
	var usable: float = max(0.0, w - 56.0)
	var per_cell: float = float(CELL_TARGET_W + CELL_GAP)
	var cols: int = int(floor(usable / per_cell))
	return clamp(cols, MIN_COLS, MAX_COLS)


# True when viewport is wide enough for the desktop split layout (grid +
# persistent right detail panel). Falsey on phones / portrait tablets.
func _is_wide_layout() -> bool:
	if _force_layout == "wide":
		return true
	if _force_layout == "narrow":
		return false
	return get_viewport().get_visible_rect().size.x >= float(WIDE_LAYOUT_PX)


func _on_language_changed(_lang: String) -> void:
	if visible:
		_refresh_counters()
		_rebuild_grid()


# Loc.t() with fallback so headless tests / boot without Loc still render.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	return fallback if not fallback.is_empty() else key

func _load_souls() -> void:
	var file := FileAccess.open(SOULS_PATH, FileAccess.READ)
	if not file:
		push_warning("CollectionScreen: souls_collection.json not found")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_named_souls  = parsed.get("named_souls",  [])
	_hidden_souls = parsed.get("hidden_souls", [])

# ── Public API ────────────────────────────────────────────────────────────────

func router_title() -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t("router_title.collection"))
	return "Врятовані душі"

func open() -> void:
	visible = true
	_cell_nodes.clear()
	_apply_layout_mode()
	_refresh_counters()
	_rebuild_grid()
	_close_sheet_instant()
	# Reset side panel to placeholder on each open so stale content from
	# a previous session doesn't show.
	_last_detail = {}
	_last_detail_was_not_found = false
	_side_placeholder.visible = true
	for lbl in [_side_name, _side_age, _side_loc, _side_text, _side_extra]:
		lbl.visible = false
	_side_sep.visible = false
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func close() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit()
	)

# Called by GameManager when a new soul is collected during a level.
func notify_soul_added(soul_id: int) -> void:
	_refresh_counters()
	# Animate the matching cell if visible
	if _cell_nodes.has(soul_id):
		_animate_new_soul_cell(_cell_nodes[soul_id])
	# Full-collection completion fanfare. Target read from the souls JSON
	# via SaveManager so adding more souls to the pool just works.
	var target: int = SaveManager.get_named_souls_target() if SaveManager else 100
	if SaveManager and SaveManager.get_total_souls() >= target:
		_animate_completion()

func notify_hidden_soul_added(soul_id: String) -> void:
	_refresh_counters()
	if _cell_nodes.has(soul_id):
		_animate_new_soul_cell(_cell_nodes[soul_id])

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _sheet_open:
			_close_sheet()
		else:
			close()
		get_viewport().set_input_as_handled()

# ── Counters ──────────────────────────────────────────────────────────────────

func _refresh_counters() -> void:
	var named:  int = SaveManager.get_total_souls()         if SaveManager else 0
	var hidden: int = SaveManager.get_total_hidden_souls()  if SaveManager else 0
	var n_target: int = SaveManager.get_named_souls_target() if SaveManager else 100
	var h_target: int = SaveManager.get_hidden_souls_target() if SaveManager else 20
	_lbl_named.text  = _t("collection.counter_named",
		{"saved": named, "total": n_target}, "%d / %d" % [named, n_target])
	_lbl_hidden.text = _t("collection.counter_hidden",
		{"saved": hidden, "total": h_target}, "✦ %d / %d" % [hidden, h_target])
	_lbl_named.add_theme_color_override("font_color",
		Color("#FFD700") if named >= n_target else Color(0.82, 0.80, 0.86))

	# Grand total — named + hidden against the combined target. Localised
	# via collection.counter_total with a fallback that matches the format.
	var grand: int        = named + hidden
	var grand_target: int = n_target + h_target
	_lbl_total.text = _t("collection.counter_total",
		{"saved": grand, "total": grand_target},
		"∑ %d / %d" % [grand, grand_target])
	_lbl_total.add_theme_color_override("font_color",
		Color("#FFD700") if grand_target > 0 and grand >= grand_target
			else Color(0.62, 0.60, 0.68))

	_refresh_type_stats()
	_refresh_circle_progress()


# Tally per-type totals from the loaded named-soul list against the
# SaveManager's saved IDs and render them as a single emoji strip.
func _refresh_type_stats() -> void:
	var saved_ids:  Array = SaveManager.get_saved_soul_ids()  if SaveManager else []
	var hidden_ids: Array = SaveManager.get_hidden_soul_ids() if SaveManager else []

	var totals: Dictionary = {"innocent": 0, "broken": 0, "sleeping": 0}
	var saved:  Dictionary = {"innocent": 0, "broken": 0, "sleeping": 0}
	for soul in _named_souls:
		var t: String = String(soul.get("type", ""))
		if not totals.has(t):
			continue
		totals[t] = int(totals[t]) + 1
		if int(soul.get("id", 0)) in saved_ids:
			saved[t] = int(saved[t]) + 1

	var icons: Dictionary = {
		"innocent": "🔥",
		"broken":   "💀",
		"sleeping": "😴",
	}
	var parts: PackedStringArray = []
	for k in ["innocent", "broken", "sleeping"]:
		var tot: int = int(totals[k])
		if tot <= 0:
			continue
		parts.append("%s %d/%d" % [icons[k], int(saved[k]), tot])

	# Hidden souls — separate "tier" rendered alongside the type counts.
	var h_total: int = _hidden_souls.size()
	if h_total > 0:
		var h_found: int = 0
		for soul in _hidden_souls:
			if str(soul.get("id", "")) in hidden_ids:
				h_found += 1
		parts.append("✦ %d/%d" % [h_found, h_total])

	_lbl_type_stats.text = "  •  ".join(parts)

## Compute per-circle (1..10) counts from the loaded named/hidden lists and
## the SaveManager's saved IDs, then refresh the inline progress strip so
## the player can see "Circle 3: 7/10 ✦1/2" at a glance.
func _refresh_circle_progress() -> void:
	for child in _circle_progress_box.get_children():
		child.queue_free()

	var saved_ids:  Array = SaveManager.get_saved_soul_ids()  if SaveManager else []
	var hidden_ids: Array = SaveManager.get_hidden_soul_ids() if SaveManager else []

	# Build per-circle totals + found counts in one pass each.
	var per_circle_total:    Dictionary = {}   # circle → named total
	var per_circle_found:    Dictionary = {}   # circle → named found
	var per_circle_h_total:  Dictionary = {}   # circle → hidden total
	var per_circle_h_found:  Dictionary = {}   # circle → hidden found
	for soul in _named_souls:
		var c: int = int(soul.get("circle", 0))
		if c <= 0:
			continue
		per_circle_total[c] = int(per_circle_total.get(c, 0)) + 1
		if int(soul.get("id", 0)) in saved_ids:
			per_circle_found[c] = int(per_circle_found.get(c, 0)) + 1
	for soul in _hidden_souls:
		var c: int = int(soul.get("circle", 0))
		if c <= 0:
			continue
		per_circle_h_total[c] = int(per_circle_h_total.get(c, 0)) + 1
		if str(soul.get("id", "")) in hidden_ids:
			per_circle_h_found[c] = int(per_circle_h_found.get(c, 0)) + 1

	# Render 10 cells (1..10), one per circle. Filled circles glow gold.
	for c in range(1, 11):
		var total:    int = int(per_circle_total.get(c, 0))
		var found:    int = int(per_circle_found.get(c, 0))
		var h_total:  int = int(per_circle_h_total.get(c, 0))
		var h_found:  int = int(per_circle_h_found.get(c, 0))
		_circle_progress_box.add_child(
			_make_circle_cell(c, found, total, h_found, h_total)
		)

func _make_circle_cell(circle: int, found: int, total: int,
		h_found: int, h_total: int) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var head := Label.new()
	head.text = _t("collection.circle_short", {"n": circle}, "К%d" % circle)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color",
		Color(0.55, 0.52, 0.62) if total == 0 else Color(0.85, 0.82, 0.90))
	v.add_child(head)

	var counts := Label.new()
	counts.text = "%d/%d" % [found, total]
	counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counts.add_theme_font_size_override("font_size", 22)
	var done: bool = total > 0 and found >= total
	counts.add_theme_color_override("font_color",
		Color("#FFD700") if done else Color(0.92, 0.90, 0.96))
	v.add_child(counts)

	if h_total > 0:
		var hidden_lbl := Label.new()
		hidden_lbl.text = "✦ %d/%d" % [h_found, h_total]
		hidden_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hidden_lbl.add_theme_font_size_override("font_size", 16)
		hidden_lbl.add_theme_color_override("font_color",
			Color("#FFE066") if h_found >= h_total else Color("#A07820"))
		v.add_child(hidden_lbl)
	return v

# ── Search / sort helpers ─────────────────────────────────────────────────────

func _sort_label_for(mode: String) -> String:
	# Compact label so it fits the small button. Localised through
	# collection.sort_label_<mode>; UA fallback keeps the screen
	# functional during boot.
	const FALLBACKS := {
		"id":     "↕  За ID",
		"name":   "↕  За ім'ям",
		"circle": "↕  За колом",
		"type":   "↕  За типом",
	}
	return _t("collection.sort_label_" + mode, {},
		String(FALLBACKS.get(mode, "↕  Сортувати")))


func _on_search_text_changed(new_text: String) -> void:
	_search_query = new_text.strip_edges()
	_close_sheet_instant()
	_rebuild_grid()


func _on_sort_cycle_pressed() -> void:
	var idx: int = SORT_MODES.find(_sort_mode)
	idx = (idx + 1) % SORT_MODES.size()
	_sort_mode = SORT_MODES[idx]
	_btn_sort.text = _sort_label_for(_sort_mode)
	_close_sheet_instant()
	_rebuild_grid()

# ── Grid ──────────────────────────────────────────────────────────────────────

func _rebuild_grid() -> void:
	_cell_nodes.clear()
	for child in _grid.get_children():
		child.queue_free()

	var saved_ids:  Array = SaveManager.get_saved_soul_ids()   if SaveManager else []
	var hidden_ids: Array = SaveManager.get_hidden_soul_ids()  if SaveManager else []

	for soul in _sort_souls(_named_souls):
		if not _passes_filter(soul, false):
			continue
		var id: int   = soul.get("id", 0)
		var saved: bool = id in saved_ids
		if _filter_missing and saved:
			continue
		var cell := _make_cell(soul, false, saved)
		_grid.add_child(cell)
		_cell_nodes[id] = cell

	# Hidden souls are appended after named ones regardless of sort mode —
	# they're a distinct tier, the player expects them grouped at the end.
	for soul in _hidden_souls:
		if not _passes_filter(soul, true):
			continue
		var id: String = str(soul.get("id", ""))
		var saved: bool = id in hidden_ids
		if _filter_missing and saved:
			continue
		var cell := _make_cell(soul, true, saved)
		_grid.add_child(cell)
		_cell_nodes[id] = cell


# Ukrainian alphabet → 2-digit rank, padded so lexicographic compare
# matches the alphabetical order. Used by the "name" sort mode below
# because raw codepoint comparison places і / ї / є in the wrong
# slots relative to и / й / е.
const _UA_ALPHABET_ORDER := {
	"а": "01", "б": "02", "в": "03", "г": "04", "ґ": "05", "д": "06",
	"е": "07", "є": "08", "ж": "09", "з": "10", "и": "11", "і": "12",
	"ї": "13", "й": "14", "к": "15", "л": "16", "м": "17", "н": "18",
	"о": "19", "п": "20", "р": "21", "с": "22", "т": "23", "у": "24",
	"ф": "25", "х": "26", "ц": "27", "ч": "28", "ш": "29", "щ": "30",
	"ь": "31", "ю": "32", "я": "33",
}


# Convert a string into a sort key whose lexicographic order matches
# the Ukrainian alphabet. Unknown chars (latin, digits, punctuation)
# get a "99" prefix so they cluster after Cyrillic but stay self-stable.
func _ua_sort_key(s: String) -> String:
	var lower: String = s.to_lower()
	var key: String = ""
	for ch in lower:
		key += String(_UA_ALPHABET_ORDER.get(ch, "99" + ch))
	return key


# Returns a copy of `souls` ordered by the current _sort_mode. Stable
# secondary sort by id so identical primary keys (same circle, same
# type) keep a deterministic order between rebuilds.
func _sort_souls(souls: Array) -> Array:
	var out: Array = souls.duplicate()
	match _sort_mode:
		"name":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				# Codepoint < on lowercased Cyrillic strings sorts wrong:
				# е.g. і (U+0456) lands AFTER м (U+043C) by raw codepoint
				# even though м is alphabetically later in Ukrainian.
				# Map each char to its alphabet index via _ua_sort_key.
				var na: String = _ua_sort_key(String(a.get("name", "")))
				var nb: String = _ua_sort_key(String(b.get("name", "")))
				if na == nb:
					return int(a.get("id", 0)) < int(b.get("id", 0))
				return na < nb)
		"circle":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ca: int = int(a.get("circle", 0))
				var cb: int = int(b.get("circle", 0))
				if ca == cb:
					return int(a.get("id", 0)) < int(b.get("id", 0))
				return ca < cb)
		"type":
			# Stable order: innocent → broken → sleeping → other.
			const TYPE_RANK := {"innocent": 0, "broken": 1, "sleeping": 2}
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ra: int = int(TYPE_RANK.get(String(a.get("type", "")), 99))
				var rb: int = int(TYPE_RANK.get(String(b.get("type", "")), 99))
				if ra == rb:
					return int(a.get("id", 0)) < int(b.get("id", 0))
				return ra < rb)
		_:
			pass  # "id" — already in declared order
	return out

func _passes_filter(soul: Dictionary, is_hidden: bool) -> bool:
	if _filter_circle > 0 and soul.get("circle", 0) != _filter_circle:
		return false
	# Hidden souls don't carry a `type` field — they're their own category.
	# Without this guard, picking "Innocent" / "Broken" / "Sleeping" filtered
	# them all out, hiding the ✦ ones from the grid entirely.
	if _filter_type != "all" and not is_hidden \
			and soul.get("type", "") != _filter_type:
		return false
	# Search query — case-insensitive substring against name AND
	# epitaph/full_story so the player can find a soul by half-remembered
	# story details, not just the name.
	if not _search_query.is_empty():
		var q: String = _search_query.to_lower()
		var hay: String = String(soul.get("name", "")).to_lower() \
			+ " " + String(soul.get("epitaph", "")).to_lower() \
			+ " " + String(soul.get("full_story", "")).to_lower()
		if not hay.contains(q):
			return false
	return true

func _make_cell(soul: Dictionary, is_hidden: bool, saved: bool) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = CELL_SIZE
	btn.clip_contents = true
	btn.focus_mode    = Control.FOCUS_NONE

	# Tooltip preview — Godot's built-in tooltip fires on hover (desktop)
	# and long-press (mobile, ~600 ms hold), so a player can scan a soul
	# without committing to opening the full detail panel. Saved souls
	# show name + epitaph; undiscovered souls keep their secret.
	if saved:
		var nm: String = String(soul.get("name", "?"))
		var epi: String = String(soul.get("full_story",
			soul.get("epitaph", "")))
		btn.tooltip_text = nm + "\n\n" + epi if not epi.is_empty() else nm
	else:
		btn.tooltip_text = _t("collection.not_found_tooltip", {},
			"Прихована душа — шукай уважніше")

	var normal := StyleBoxFlat.new()
	var hover  := StyleBoxFlat.new()
	_style_cell(normal, is_hidden, saved, false)
	_style_cell(hover,  is_hidden, saved, true)
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("focus",   normal)

	# Main label — full name, autowrap so longer names like "Безіменний"
	# or "Горислава" stay readable instead of getting chopped to 5 chars.
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left   = 6
	lbl.offset_right  = -6
	lbl.offset_top    = 6
	lbl.offset_bottom = -6
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	lbl.clip_text            = true
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE

	if saved:
		var raw_name: String = String(soul.get("name", "?"))
		# Long names get a smaller font so they fit the cell without
		# overflowing into the corner badges.
		var fs: int = 20 if raw_name.length() <= 8 else (17 if raw_name.length() <= 12 else 15)
		lbl.add_theme_font_size_override("font_size", fs)
		lbl.text = raw_name
		lbl.add_theme_color_override("font_color",
			Color("#FFD700") if is_hidden else Color(0.88, 0.86, 0.92))
	else:
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.text = _t("collection.not_found_label", {}, "?")
		lbl.add_theme_color_override("font_color",
			Color(0.55, 0.48, 0.22) if is_hidden else Color(0.32, 0.30, 0.38))

	btn.add_child(lbl)

	# Hidden badge ✦
	if is_hidden:
		var badge := Label.new()
		badge.text = "✦"
		badge.add_theme_font_size_override("font_size", 20)
		badge.add_theme_color_override("font_color",
			Color("#FFD700") if saved else Color(0.45, 0.38, 0.12))
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.position = Vector2(-18, 2)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(badge)

	# "NEW!" badge — shown on collected named souls the player hasn't
	# opened the detail sheet for yet. Hidden souls don't get this since
	# their identity is the discovery itself; the ✦ glow already says it.
	if saved and not is_hidden:
		var sid: int = int(soul.get("id", -1))
		if sid >= 0 and SaveManager and not SaveManager.is_soul_seen(sid):
			btn.add_child(_make_new_badge())

	btn.pressed.connect(_on_cell_pressed.bind(soul, is_hidden, saved))
	return btn


# Pulsing red corner ribbon. Reused for all unseen-named-soul cells.
func _make_new_badge() -> Control:
	var box := PanelContainer.new()
	box.name = "NewBadge"
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(2, 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var s := StyleBoxFlat.new()
	s.bg_color = Color("#CC2233")
	s.border_color = Color("#FF6688")
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	box.add_theme_stylebox_override("panel", s)

	var lbl := Label.new()
	lbl.text = "NEW"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(lbl)

	# Subtle infinite pulse so the eye snaps to the badge — looped tween
	# on modulate.a between 0.7 and 1.0.
	var ms: Node = get_node_or_null("/root/MotionSettings")
	var reduce_motion: bool = (
			ms and ms.has_method("is_enabled") and ms.is_enabled())
	if not reduce_motion:
		var tw := box.create_tween()
		tw.set_loops()
		tw.tween_property(box, "modulate:a", 0.7, 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(box, "modulate:a", 1.0, 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return box

func _style_cell(s: StyleBoxFlat, is_hidden: bool, saved: bool, hovered: bool) -> void:
	if is_hidden:
		s.bg_color     = Color(0.22, 0.16, 0.06) if (saved and hovered) else \
						 (Color(0.18, 0.13, 0.05) if saved else Color(0.10, 0.08, 0.04))
		s.border_color = Color("#FFD700") if hovered else Color("#A07820")
	else:
		s.bg_color     = Color(0.26, 0.24, 0.32) if (saved and hovered) else \
						 (Color(0.18, 0.16, 0.22) if saved else Color(0.10, 0.09, 0.13))
		s.border_color = Color(0.65, 0.60, 0.78) if hovered else \
						 (Color(0.42, 0.38, 0.52) if saved else Color(0.22, 0.20, 0.28))
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left    = 6
	s.corner_radius_top_right   = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6

# ── Cell animation (new soul) ─────────────────────────────────────────────────

func _animate_new_soul_cell(cell: Control) -> void:
	var tw := create_tween()
	tw.tween_property(cell, "scale", Vector2(1.35, 1.35), 0.12)
	tw.tween_property(cell, "scale", Vector2.ONE,         0.18)
	# Flash white overlay
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.55)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(flash)
	var ftw := create_tween()
	ftw.tween_property(flash, "modulate:a", 0.0, 0.4)
	ftw.tween_callback(flash.queue_free)

# ── 100/100 completion ────────────────────────────────────────────────────────

func _animate_completion() -> void:
	_completion_lbl.visible = true
	_completion_lbl.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_completion_lbl, "modulate:a", 1.0, 0.6)
	tw.tween_interval(3.0)
	tw.tween_property(_completion_lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: _completion_lbl.visible = false)

	# Warm glow all saved cells
	for id in _cell_nodes:
		var cell: Control = _cell_nodes[id]
		var gtw := create_tween()
		gtw.tween_property(cell, "modulate", Color(1.3, 1.1, 0.7), 1.2)
		gtw.tween_property(cell, "modulate", Color.WHITE, 1.8)

# ── Detail bottom sheet ───────────────────────────────────────────────────────

func _on_cell_pressed(soul: Dictionary, is_hidden: bool, saved: bool) -> void:
	if saved:
		# Mark named souls as seen so the NEW badge clears next refresh.
		if not is_hidden and SaveManager:
			var sid: int = int(soul.get("id", -1))
			if sid >= 0 and not SaveManager.is_soul_seen(sid):
				SaveManager.mark_soul_seen(sid)
				# Pull the badge off the just-pressed cell instantly so
				# the player sees the cause-and-effect.
				_remove_new_badge_for(sid)
		_show_detail(soul, is_hidden)
	else:
		_show_detail_not_found(soul)


# Find the cell associated with this soul id and queue_free its
# NewBadge child if present. Cheap — cells are tracked in _cell_nodes.
func _remove_new_badge_for(soul_id: int) -> void:
	var cell: Variant = _cell_nodes.get(soul_id, null)
	if cell == null or not is_instance_valid(cell):
		return
	var badge: Node = cell.get_node_or_null("NewBadge")
	if badge:
		badge.queue_free()

# Returns the dict of active label refs (sheet OR side panel) based on
# current layout mode. Both sets share the exact same key names so the
# populate functions don't need to know which one they're filling.
func _active_refs() -> Dictionary:
	if _is_wide_layout():
		return {
			"name": _side_name, "age": _side_age, "loc": _side_loc,
			"sep":  _side_sep,  "text": _side_text, "extra": _side_extra,
		}
	return {
		"name": _sheet_name, "age": _sheet_age, "loc": _sheet_loc,
		"sep":  _sheet_sep,  "text": _sheet_text, "extra": _sheet_extra,
	}


func _populate_detail(refs: Dictionary, soul: Dictionary, is_hidden: bool) -> void:
	var name_lbl: Label = refs["name"]
	name_lbl.text = soul.get("name", "?")
	name_lbl.add_theme_color_override("font_color",
		Color("#FFD700") if is_hidden else Color(0.92, 0.90, 0.96))
	name_lbl.visible = true

	# Age can be int OR the string "?" (used by soul id 100, "Безіменний").
	# %d would crash on a string, and the literal "років" was hardcoded
	# even in English. Route through Loc with a robust string param.
	var age_v: Variant = soul.get("age", 0)
	var age_s: String  = str(age_v) if typeof(age_v) == TYPE_STRING else str(int(age_v))
	var age_lbl: Label = refs["age"]
	age_lbl.text    = _t("collection.detail_age_format", {"age": age_s}, "%s років" % age_s)
	age_lbl.visible = true

	var circle: int = soul.get("circle", 1)
	var level:  int = soul.get("level",  0)
	var loc_lbl: Label = refs["loc"]
	if is_hidden:
		loc_lbl.text = _t("collection.detail_location_hidden",
			{"circle": circle}, "Коло %d • Прихована" % circle)
	else:
		loc_lbl.text = _t("collection.detail_location_common",
			{"circle": circle, "level": level},
			"Коло %d • Рівень %d" % [circle, level])
	loc_lbl.visible = true
	(refs["sep"] as HSeparator).visible = true

	var story: String = soul.get("full_story", soul.get("epitaph", ""))
	var text_lbl: Label = refs["text"]
	text_lbl.text    = story
	text_lbl.visible = true

	var extra_lbl: Label = refs["extra"]
	if is_hidden:
		var reward: String = soul.get("reward", "")
		extra_lbl.text = _t("collection.detail_reward_format",
			{"reward": reward}, "Нагорода: %s" % reward) if reward else ""
		extra_lbl.add_theme_color_override("font_color", Color("#FFD700"))
	else:
		var sin_val: String = soul.get("sin", "none")
		if sin_val != "none":
			extra_lbl.text = _t("collection.detail_sin_format",
				{"sin": sin_val}, "Гріх: %s" % sin_val)
		else:
			extra_lbl.text = ""
		extra_lbl.add_theme_color_override("font_color", Color(0.65, 0.60, 0.72))
	extra_lbl.visible = extra_lbl.text != ""


func _populate_detail_not_found(refs: Dictionary) -> void:
	var name_lbl: Label = refs["name"]
	name_lbl.text = _t("collection.detail_not_found", {}, "Душа не знайдена")
	name_lbl.add_theme_color_override("font_color", Color(0.48, 0.46, 0.54))
	name_lbl.visible = true
	(refs["age"] as Label).visible = false
	(refs["loc"] as Label).visible = false
	(refs["sep"] as HSeparator).visible = false
	var text_lbl: Label = refs["text"]
	text_lbl.text = _t("collection.detail_not_found_hint", {},
		"Продовжуй шукати в цьому Колі")
	text_lbl.visible = true
	(refs["extra"] as Label).visible = false


# Direct sheet populators — kept narrow-only so unit tests can assert
# against _sheet_* labels regardless of test viewport width. Production
# UI uses _show_detail() below, which picks between sheet and side panel.
func _show_sheet(soul: Dictionary, is_hidden: bool) -> void:
	_populate_detail({
		"name": _sheet_name, "age": _sheet_age, "loc": _sheet_loc,
		"sep":  _sheet_sep,  "text": _sheet_text, "extra": _sheet_extra,
	}, soul, is_hidden)
	_open_sheet()


func _show_sheet_not_found(_soul: Dictionary) -> void:
	_populate_detail_not_found({
		"name": _sheet_name, "age": _sheet_age, "loc": _sheet_loc,
		"sep":  _sheet_sep,  "text": _sheet_text, "extra": _sheet_extra,
	})
	_open_sheet()


# Layout-aware detail entry — chooses bottom sheet (narrow) or right
# side panel (wide ≥ WIDE_LAYOUT_PX). _on_cell_pressed routes here so
# desktop users get the persistent-panel experience automatically.
func _show_detail(soul: Dictionary, is_hidden: bool) -> void:
	_last_detail = {"soul": soul, "is_hidden": is_hidden}
	_last_detail_was_not_found = false
	if _is_wide_layout():
		_populate_detail(_active_refs(), soul, is_hidden)
		_side_placeholder.visible = false
	else:
		_show_sheet(soul, is_hidden)


func _show_detail_not_found(soul: Dictionary) -> void:
	_last_detail = {"soul": soul, "is_hidden": false}
	_last_detail_was_not_found = true
	if _is_wide_layout():
		_populate_detail_not_found(_active_refs())
		_side_placeholder.visible = false
	else:
		_show_sheet_not_found(soul)

# Switch between narrow (sheet) and wide (side panel) presentations.
# Called on _ready, open(), and viewport size_changed.
func _apply_layout_mode() -> void:
	var wide: bool = _is_wide_layout()
	_side_panel.visible = wide
	# In wide mode the bottom sheet must never appear. Force-close it.
	if wide and _sheet_open:
		_close_sheet_instant()

func _open_sheet() -> void:
	_sheet_open = true
	_sheet.visible = true
	_sheet_backdrop.visible = true
	if _sheet_tween:
		_sheet_tween.kill()
	_sheet_tween = create_tween()
	var sa: Node = get_node_or_null("/root/SafeArea")
	var banner: float = float(sa.bottom_reserved) if sa else 60.0
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_sheet_tween.tween_property(_sheet, "position:y",
		vp_h - _sheet.size.y - banner, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)

func _close_sheet() -> void:
	if not _sheet_open:
		return
	_sheet_open = false
	if _sheet_tween:
		_sheet_tween.kill()
	_sheet_tween = create_tween()
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_sheet_tween.tween_property(_sheet, "position:y", vp_h + 100.0, 0.18)
	_sheet_tween.tween_callback(func() -> void:
		_sheet.visible = false
		_sheet_backdrop.visible = false
	)

func _close_sheet_instant() -> void:
	_sheet_open = false
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_sheet.position.y = vp_h + 100.0
	_sheet.visible = false
	_sheet_backdrop.visible = false

# ── Filter callbacks ──────────────────────────────────────────────────────────

func _on_circle_tab(circle: int) -> void:
	_filter_circle = circle
	_update_circle_tabs()
	_close_sheet_instant()
	_rebuild_grid()

func _update_circle_tabs() -> void:
	for i in _circle_tabs.size():
		var active: bool = (i == 0 and _filter_circle == 0) or (i > 0 and _filter_circle == i)
		_circle_tabs[i].modulate = Color.WHITE if active else Color(0.55, 0.53, 0.60)

func _on_type_btn(t: String) -> void:
	_filter_type = t
	for key in _type_btns:
		_type_btns[key].modulate = Color.WHITE if key == t else Color(0.55, 0.53, 0.60)
	_close_sheet_instant()
	_rebuild_grid()

func _on_missing_toggle() -> void:
	_filter_missing = not _filter_missing
	_btn_missing.modulate = Color.WHITE if _filter_missing else Color(0.55, 0.53, 0.60)
	_close_sheet_instant()
	_rebuild_grid()
