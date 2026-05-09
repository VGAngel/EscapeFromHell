extends Node

# Autoload: AdsManager
# Потребує плагінів: admob-godot + GodotGooglePlayBilling

signal no_ads_purchased
signal donate_purchased(sku: String)

const CONFIG_PATH := "res://monetization_config.json"

var _cfg: Dictionary = {}
var _sku_no_ads:       String = ""
var _skus_donate:      Array  = []
var _interstitial_cooldown: float = 120.0
var _interstitial_triggers: Array = []

var _ads_removed:        bool  = false
var _interstitial_ready: bool  = false
var _last_interstitial:  float = -999.0
var _billing_ready:      bool  = false

var _admob:   Object = null
var _billing: Object = null

# ── Mock mode ─────────────────────────────────────────────────────────────────
# When neither AdMob nor Billing singletons are registered (editor, desktop
# dev builds, CI) AdsManager flips into a visible mock flow so MainMenu /
# DonatePanel / level transitions work end-to-end without real SDKs.
var _mock_mode:          bool        = false
var _mock_banner_layer:  CanvasLayer = null

func _ready() -> void:
	_load_config()
	var save_key: String = _cfg.get("iap", {}).get("no_ads", {}).get("save_key", "no_ads_purchased")
	_ads_removed = SaveManager.get_flag(save_key) if SaveManager else false
	_setup_admob()
	_setup_billing()
	_mock_mode = (_admob == null) and (_billing == null)
	if _mock_mode:
		_billing_ready = true     # mock purchases always available
		if not _ads_removed:
			_show_mock_banner()

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_error("AdsManager: monetization_config.json not found")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("AdsManager: failed to parse monetization_config.json")
		return
	_cfg = parsed
	# Defensive: a corrupted / partial monetization_config.json would
	# previously crash the autoload at boot ("Dictionary key not
	# found"). Read every nested key via .get() with sensible
	# fallbacks so the rest of the game still loads — ads + IAP just
	# won't be configured.
	var iap: Dictionary = _cfg.get("iap", {})
	var iap_no_ads: Dictionary = iap.get("no_ads", {})
	var iap_donate: Dictionary = iap.get("donate", {})
	var donate_tiers: Array = iap_donate.get("tiers", [])
	var admob: Dictionary = _cfg.get("admob", {})
	var admob_interstitial: Dictionary = admob.get("interstitial", {})

	_sku_no_ads  = String(iap_no_ads.get("sku", ""))
	_skus_donate = donate_tiers.map(func(t): return String(t.get("sku", "")))
	_interstitial_cooldown = float(admob_interstitial.get("cooldown_seconds", 60.0))
	_interstitial_triggers = admob_interstitial.get("show_on", [])
	if _sku_no_ads.is_empty():
		push_warning("AdsManager: missing iap.no_ads.sku — IAP unavailable")

# ── AdMob ─────────────────────────────────────────────────────────────────────
func _setup_admob() -> void:
	if not Engine.has_singleton("AdMob"):
		return
	_admob = Engine.get_singleton("AdMob")
	_admob.banner_loaded.connect(_on_banner_loaded)
	_admob.interstitial_loaded.connect(_on_interstitial_loaded)

	if _ads_removed:
		return

	var is_debug: bool = OS.is_debug_build()
	var b_cfg: Dictionary = _cfg["admob"]["banner"]
	var i_cfg: Dictionary = _cfg["admob"]["interstitial"]
	var banner_id: String = b_cfg["unit_id_test"] if is_debug else b_cfg["unit_id_release"]
	var inter_id:  String = i_cfg["unit_id_test"] if is_debug else i_cfg["unit_id_release"]

	_admob.initialize()
	if b_cfg.get("enabled", true):
		_admob.load_banner(banner_id, b_cfg["size"], b_cfg["position"])
	if i_cfg.get("enabled", true):
		_admob.load_interstitial(inter_id)

func _on_banner_loaded() -> void:
	if not _ads_removed:
		_admob.show_banner()

func _on_interstitial_loaded() -> void:
	_interstitial_ready = true

func should_show_on(trigger: String) -> bool:
	return trigger in _interstitial_triggers

func show_interstitial() -> void:
	if _ads_removed:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_interstitial < _interstitial_cooldown:
		return
	if _mock_mode:
		_last_interstitial = now
		_show_mock_interstitial()
		return
	if not _admob or not _interstitial_ready:
		return
	_admob.show_interstitial()
	_interstitial_ready = false
	_last_interstitial = now

	var is_debug: bool = OS.is_debug_build()
	var i_cfg: Dictionary = _cfg["admob"]["interstitial"]
	var inter_id: String = i_cfg["unit_id_test"] if is_debug else i_cfg["unit_id_release"]
	_admob.load_interstitial(inter_id)

func hide_banner() -> void:
	if _admob:
		_admob.hide_banner()

func _remove_ads_locally() -> void:
	_ads_removed = true
	if _admob:
		_admob.hide_banner()
		_admob.destroy_banner()
	SaveManager.set_flag("no_ads_purchased", true)
	no_ads_purchased.emit()

func is_ads_removed() -> bool:
	return _ads_removed

# ── Google Play Billing ───────────────────────────────────────────────────────
func _setup_billing() -> void:
	if not Engine.has_singleton("GodotGooglePlayBilling"):
		return
	_billing = Engine.get_singleton("GodotGooglePlayBilling")
	_billing.connected.connect(_on_billing_connected)
	_billing.purchases_updated.connect(_on_purchases_updated)
	_billing.purchase_error.connect(_on_purchase_error)
	_billing.startConnection()

func _on_billing_connected() -> void:
	_billing_ready = true
	_restore_purchases()

func _restore_purchases() -> void:
	if not _billing_ready:
		return
	var result: Dictionary = _billing.queryPurchases("inapp")
	if result.get("status", -1) == 0:
		for purchase in result.get("purchases", []):
			if purchase.get("sku") == _sku_no_ads:
				_remove_ads_locally()

func purchase_no_ads() -> void:
	if _mock_mode:
		_mock_confirm_purchase("no_ads", _sku_no_ads)
		return
	if not _billing_ready:
		return
	_billing.purchase(_sku_no_ads)

func purchase_donate(sku: String) -> void:
	if sku not in _skus_donate:
		return
	if _mock_mode:
		_mock_confirm_purchase("donate", sku)
		return
	if not _billing_ready:
		return
	_billing.purchase(sku)

func get_banner_height() -> int:
	if _ads_removed or not _cfg.has("layout"):
		return 0
	return int(_cfg["layout"]["banner_height_px"])

func get_donate_tiers() -> Array:
	# .has("iap") alone wasn't enough — if "iap" was present but
	# "donate" or "tiers" was missing, the chained subscript still
	# crashed. Walk the path defensively.
	return _cfg.get("iap", {}).get("donate", {}).get("tiers", [])

func _on_purchases_updated(purchases: Array) -> void:
	for purchase in purchases:
		var sku: String = purchase.get("sku", "")
		if sku == _sku_no_ads:
			_billing.acknowledgePurchase(purchase.get("purchase_token", ""))
			_remove_ads_locally()
		elif sku in _skus_donate:
			_billing.consumePurchase(purchase.get("purchase_token", ""))
			donate_purchased.emit(sku)

func _on_purchase_error(error_code: int, error_message: String) -> void:
	push_warning("Purchase error %d: %s" % [error_code, error_message])

func is_mock_mode() -> bool:
	return _mock_mode

# ── Mock flow ─────────────────────────────────────────────────────────────────

func _show_mock_banner() -> void:
	if _mock_banner_layer:
		return
	_mock_banner_layer = CanvasLayer.new()
	_mock_banner_layer.layer = 90
	add_child(_mock_banner_layer)

	var banner := PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	banner.offset_top = -60.0
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.10, 0.18, 0.95)
	s.border_width_top = 1
	s.border_color = Color(0.35, 0.28, 0.50)
	banner.add_theme_stylebox_override("panel", s)

	var lbl := Label.new()
	lbl.text = "[Ad placeholder — mock mode]"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.52, 0.65))
	banner.add_child(lbl)

	_mock_banner_layer.add_child(banner)

func _hide_mock_banner() -> void:
	if _mock_banner_layer and is_instance_valid(_mock_banner_layer):
		_mock_banner_layer.queue_free()
		_mock_banner_layer = null

func _show_mock_interstitial() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 95
	add_child(layer)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)

	var lbl := Label.new()
	lbl.text = "[Interstitial ad preview]"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.52, 0.65))
	layer.add_child(lbl)

	# Auto-dismiss after 1.2s — same feel as a short test ad
	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free())

func _mock_confirm_purchase(kind: String, sku: String) -> void:
	# Simulate async billing with a tiny delay so the UI's "thanks" flow can
	# react to the signal rather than happen inside the button press.
	var tree := get_tree()
	if not tree:
		return
	var timer := tree.create_timer(0.25)
	timer.timeout.connect(func() -> void:
		if kind == "no_ads":
			_remove_ads_locally()
			_hide_mock_banner()
		else:
			donate_purchased.emit(sku))
