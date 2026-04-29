extends GutTest

# Tests for the Loc autoload — verify language_changed signal fires on
# load, t() works with parameters, and the keys used by the new
# UI components (HeroCard, MainMenu dynamic Play, router_titles) are
# present in BOTH translation files.

const LocScript := preload("res://scripts/managers/LocalizationManager.gd")

var loc: Node

func before_each() -> void:
	loc = LocScript.new()
	add_child_autofree(loc)
	# _ready loads the default language (uk).

# ── language_changed signal ───────────────────────────────────────────────────

func test_set_language_emits_changed() -> void:
	watch_signals(loc)
	loc.set_language("en")
	assert_signal_emitted(loc, "language_changed")

func test_set_language_to_same_is_noop() -> void:
	watch_signals(loc)
	# Default is "uk"; setting "uk" again should not re-emit.
	loc.set_language("uk")
	assert_signal_not_emitted(loc, "language_changed")

# ── t() basic ─────────────────────────────────────────────────────────────────

func test_t_resolves_dot_keys() -> void:
	var s: String = loc.t("ui.menu.play")
	assert_ne(s, "ui.menu.play", "key should resolve to a translation")

func test_t_substitutes_params() -> void:
	var s: String = loc.t("hero_card.circle_format", {"n": 3})
	assert_string_contains(s, "3")

func test_missing_key_returns_key_string() -> void:
	var s: String = loc.t("totally.bogus.key.zzz")
	assert_eq(s, "totally.bogus.key.zzz")

# ── Key audit — every newly-used key must exist in both UA + EN ───────────────

const REQUIRED_KEYS := [
	"hero_card.name_unknown",
	"hero_card.circle_format",
	"hero_card.level_format",
	"hero_card.stats_format",
	"hero_card.best_none",
	"hero_card.best_format",
	"hero_card.sin_format",
	"main_menu_dyn.play_first",
	"main_menu_dyn.play_continue",
	"router_title.statistics",
	"router_title.collection",
	"router_title.settings",
	"router_title.donate",
	"router_title.profile",
	"router_title.seed",
	"router_title.level_debug",
	"pause.title",
	"pause.resume",
	"pause.settings",
	"pause.main_menu",
	"pause.collection",
	"pause.statistics",
	"pause.exit_title",
	"pause.exit_message",
	"pause.exit_yes",
	"pause.exit_no",
	"pause.level_format",
	"pause.souls_format",
	"pause.sin_format",
	"level_complete.title_done",
	"level_complete.subtitle_format",
	"level_complete.new_best_badge",
	"level_complete.souls_format",
	"level_complete.deaths_format",
	"level_complete.time_format",
	"level_complete.best_none",
	"level_complete.best_format",
	"level_complete.sin_change_format",
	"level_complete.light_format",
	"level_complete.go_to_hub",
	"level_complete.next_level",
	"donate.title",
	"donate.tagline",
	"donate.btn_support",
	"donate.thanks",
	"seed.title",
	"seed.info_auto",
	"seed.info_format",
	"seed.placeholder",
	"seed.tt_random",
	"seed.tt_clear",
	"seed.btn_apply",
	"profile.title",
	"profile.warn_delete",
	"profile.progress_format",
	"profile.active_marker",
	"profile.empty_slot",
	"profile.name_prompt",
	"profile.name_placeholder",
	"profile.btn_play",
	"profile.btn_delete",
	"profile.btn_confirm",
	"profile.btn_create",
	"profile.btn_cancel",
	"main_menu_dyn.souls_counter",
	"collection.title",
	"collection.counter_named",
	"collection.counter_hidden",
	"collection.filter_all",
	"collection.circle_tab_format",
	"collection.circle_short",
	"collection.filter_not_found",
	"collection.complete_text",
	"collection.detail_not_found",
	"collection.detail_reward_format",
	"collection.detail_sin_format",
	"collection.detail_location_common",
	"collection.detail_location_hidden",
	"collection.not_found_label",
	"level_debug.title",
	"level_debug.filter_placeholder",
	"level_debug.no_config",
]

func test_all_required_keys_resolve_in_uk() -> void:
	loc.set_language("uk")
	for key in REQUIRED_KEYS:
		var s: String = loc.t(key)
		assert_ne(s, key,
				"uk.json missing key '%s'" % key)

func test_all_required_keys_resolve_in_en() -> void:
	loc.set_language("en")
	for key in REQUIRED_KEYS:
		var s: String = loc.t(key)
		assert_ne(s, key,
				"en.json missing key '%s'" % key)

# ── Language switch round-trip ────────────────────────────────────────────────

func test_language_switch_changes_translation() -> void:
	loc.set_language("uk")
	var ua: String = loc.t("router_title.statistics")
	loc.set_language("en")
	var en: String = loc.t("router_title.statistics")
	assert_ne(ua, en, "UA and EN translations should differ")
