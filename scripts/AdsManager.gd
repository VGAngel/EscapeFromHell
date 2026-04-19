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

func _ready() -> void:
	_load_config()
	_ads_removed = SaveManager.get_flag(_cfg["iap"]["no_ads"]["save_key"]) if SaveManager else false
	_setup_admob()
	_setup_billing()

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_error("AdsManager: monetization_config.json not found")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("AdsManager: failed to parse monetization_config.json")
		return
	_cfg = json.get_data()
	_sku_no_ads  = _cfg["iap"]["no_ads"]["sku"]
	_skus_donate = _cfg["iap"]["donate"]["tiers"].map(func(t): return t["sku"])
	_interstitial_cooldown  = float(_cfg["admob"]["interstitial"]["cooldown_seconds"])
	_interstitial_triggers  = _cfg["admob"]["interstitial"]["show_on"]

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
	if _ads_removed or not _admob:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_interstitial < _interstitial_cooldown:
		return
	if not _interstitial_ready:
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
			if purchase.get("sku") == SKU_NO_ADS:
				_remove_ads_locally()

func purchase_no_ads() -> void:
	if not _billing_ready:
		return
	_billing.purchase(_sku_no_ads)

func purchase_donate(sku: String) -> void:
	if not _billing_ready or sku not in _skus_donate:
		return
	_billing.purchase(sku)

func get_banner_height() -> int:
	if _ads_removed or not _cfg.has("layout"):
		return 0
	return int(_cfg["layout"]["banner_height_px"])

func get_donate_tiers() -> Array:
	return _cfg["iap"]["donate"]["tiers"] if _cfg.has("iap") else []

func _on_purchases_updated(purchases: Array) -> void:
	for purchase in purchases:
		var sku: String = purchase.get("sku", "")
		if sku == SKU_NO_ADS:
			_billing.acknowledgePurchase(purchase.get("purchase_token", ""))
			_remove_ads_locally()
		elif sku in SKUS_DONATE:
			_billing.consumePurchase(purchase.get("purchase_token", ""))
			donate_purchased.emit(sku)

func _on_purchase_error(error_code: int, error_message: String) -> void:
	push_warning("Purchase error %d: %s" % [error_code, error_message])
