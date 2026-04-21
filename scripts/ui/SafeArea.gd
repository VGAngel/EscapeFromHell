extends Node

# SafeArea — single source of truth for edge regions that UI must stay
# clear of: ad banner at the bottom, OS notches at the top, and so on.
#
# Any screen anchoring elements to the bottom or top should query this
# autoload instead of using literal pixel offsets, so:
#   * toggling the ad banner (e.g. after "no_ads" IAP) instantly
#     reclaims the space via the `changed` signal
#   * devices with different safe-area insets work without per-screen
#     tweaks
#
# Portable — this file has NO hard dependency on any other autoload.
# Drop it into a new project, register as `SafeArea` in the autoload
# list, and feed it insets through either of the two channels below:
#
#   1. Manual push. Call `SafeArea.set_bottom_reserved(px)` or
#      `SafeArea.set_top_reserved(px)` whenever your code learns
#      the insets (e.g. mobile safe-area callback, ad SDK event).
#
#   2. Optional AdsManager integration. If an autoload named
#      `AdsManager` is registered AND exposes `get_banner_height()`,
#      SafeArea polls it on boot. If it also emits `no_ads_purchased`
#      the bottom inset auto-collapses to 0.
#
# Screen usage pattern:
#
#   func _ready() -> void:
#       SafeArea.changed.connect(_layout)
#       _layout()
#
#   func _layout() -> void:
#       my_button.offset_bottom = -float(SafeArea.bottom_reserved)
#       my_button.offset_top    = my_button.offset_bottom - BUTTON_H

signal changed

var bottom_reserved: int = 0
var top_reserved:    int = 0

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_poll_ads_manager()

# ── Public API ────────────────────────────────────────────────────────────────

func set_bottom_reserved(px: int) -> void:
	var v: int = maxi(px, 0)
	if v == bottom_reserved:
		return
	bottom_reserved = v
	changed.emit()

func set_top_reserved(px: int) -> void:
	var v: int = maxi(px, 0)
	if v == top_reserved:
		return
	top_reserved = v
	changed.emit()

## True viewport height minus any reserved top/bottom regions. Useful
## when a screen wants to centre something inside the playable slab.
func usable_height() -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return maxf(vp.y - float(bottom_reserved + top_reserved), 0.0)

## Anchor a Control so its bottom edge sits `padding` pixels above the
## bottom safe area. The control keeps its current height; top/bottom
## offsets are rewritten each call so it follows banner changes.
func anchor_bottom(control: Control, padding: int = 0) -> void:
	if not control:
		return
	control.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, true)
	var h: float = maxf(control.size.y, 1.0)
	control.offset_bottom = -float(bottom_reserved + padding)
	control.offset_top    = control.offset_bottom - h

# ── Internal — optional AdsManager discovery ──────────────────────────────────

func _poll_ads_manager() -> void:
	var ads: Node = get_node_or_null("/root/AdsManager")
	if not ads:
		return
	if ads.has_method("get_banner_height"):
		set_bottom_reserved(int(ads.get_banner_height()))
	if ads.has_signal("no_ads_purchased"):
		ads.no_ads_purchased.connect(_on_no_ads_purchased)

func _on_no_ads_purchased() -> void:
	set_bottom_reserved(0)
