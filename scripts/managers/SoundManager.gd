extends Node

# Autoload: SoundManager
# Central SFX + music routing.
#
# SFX: lookups resolve audio_config.json paths like
#   "sfx/player/jump_whoosh" → "res://audio/sfx/player/jump_whoosh.ogg"
# and play through a small pool of AudioStreamPlayer so overlapping
# hits don't cut each other off.
#
# Music: one AudioStreamPlayer with crossfade on track change.
#
# Audio files ship later (see doc/assets_status.md — ~64 SFX + ~48
# music tracks planned). Until then every play_sfx/play_music call is
# a no-op that logs at most one warning per missing path.

const CONFIG_PATH     := "res://audio_config.json"
const SFX_POOL_SIZE   := 6
const SFX_ROOT        := "res://audio/"
const MUSIC_CROSSFADE := 1.5

var _cfg:        Dictionary = {}
var _sfx_pool:   Array      = []   # Array[AudioStreamPlayer]
var _music:      AudioStreamPlayer = null
var _current_music: String = ""
var _warned:     Dictionary = {}   # path → true (avoids log spam)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	_build_pools()
	# Universal UI click sound: every BaseButton anywhere in the scene tree
	# gets `pressed → play_sfx("ui", "button_click")` wired automatically,
	# so we don't have to remember it on each new button. Existing nodes are
	# walked once at startup; future ones are caught by `node_added`.
	if get_tree():
		get_tree().node_added.connect(_on_node_added)
		_wire_existing_buttons(get_tree().root)

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_cfg = parsed

func _build_pools() -> void:
	# The Godot editor keeps rewriting project.godot and dropping the
	# custom [audio] bus-layout registration, so the Music/SFX buses
	# can't be relied on existing. Create them at runtime — then audio
	# routing (and the volume sliders in Settings) work no matter what
	# state project.godot is in.
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for _i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx: int = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

# ── Public API ────────────────────────────────────────────────────────────────

## Play a SFX by audio_config.json key path, e.g.
## SoundManager.play_sfx("player", "jump") → looks up sfx.player.jump
## and plays "res://audio/sfx/player/jump_whoosh.ogg".
func play_sfx(category: String, key: String) -> void:
	var path: String = _resolve_sfx(category, key)
	if path == "":
		return
	var stream: AudioStream = _try_load_stream(path)
	if not stream:
		return
	var p: AudioStreamPlayer = _free_sfx_slot()
	if not p:
		return
	p.stream = stream
	p.play()

## Crossfade to the music track configured for a circle. Reads
## music.circles.circle_<n>.file_base from audio_config.json so the
## mapping stays data-driven — drop the file at res://audio/<file_base>.<ext>.
func play_circle_music(circle: int) -> void:
	var circles: Dictionary = _cfg.get("music", {}).get("tracks", {}).get("circles", {})
	var entry: Dictionary = circles.get("circle_%d" % circle, {})
	var file_base: String = String(entry.get("file_base", ""))
	if file_base == "":
		return
	play_music(file_base)

## Crossfade to a music track. Pass the audio_config.json path like
## "music/circle_01_antechamber". No-op if already playing this track.
## The stream is forced to loop so level music never falls silent
## regardless of the file's import settings.
func play_music(path: String) -> void:
	if path == _current_music:
		return
	_current_music = path
	var stream: AudioStream = _try_load_stream(_resolve_music(path))
	if not stream:
		return
	_ensure_loop(stream)
	if _music.playing:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", -40.0, MUSIC_CROSSFADE * 0.5)
		tw.tween_callback(func() -> void:
			_music.stream = stream
			_music.play())
		tw.tween_property(_music, "volume_db", 0.0, MUSIC_CROSSFADE * 0.5)
	else:
		_music.stream = stream
		_music.volume_db = 0.0
		_music.play()

func stop_music() -> void:
	_current_music = ""
	_music.stop()

# ── Internals ─────────────────────────────────────────────────────────────────

func _resolve_sfx(category: String, key: String) -> String:
	var sfx_cfg: Dictionary = _cfg.get("sfx", {}).get(category, {})
	var raw: String = String(sfx_cfg.get(key, ""))
	if raw == "":
		return ""
	# Returned without extension — _try_load_stream tries .ogg, .mp3, .wav.
	return SFX_ROOT + raw

func _resolve_music(rel_path: String) -> String:
	return SFX_ROOT + rel_path

# Audio files in res://audio/ may be ogg, mp3, or wav depending on source —
# Kenney ships ogg, freesound packs often ship mp3, custom recordings wav.
# Try each extension before giving up so callers don't need to know.
const _AUDIO_EXTS: Array[String] = [".ogg", ".mp3", ".wav"]

func _try_load_stream(path: String) -> AudioStream:
	for ext in _AUDIO_EXTS:
		var full: String = path + ext
		if ResourceLoader.exists(full):
			return load(full) as AudioStream
	if not _warned.has(path):
		_warned[path] = true
		_report_warn("SoundManager: audio not found — " + path + " (tried .ogg/.mp3/.wav)")
	return null

# Loop is a per-stream-type property, not an AudioStreamPlayer flag, so
# a missing import setting silently makes music play once and stop. Force
# it on for every music stream so callers don't depend on the .import file.
func _ensure_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD

func _report_warn(msg: String) -> void:
	var d: Node = get_node_or_null("/root/DebugOverlay")
	if d and d.has_method("warn"):
		d.warn(msg)
	else:
		push_warning(msg)

func _free_sfx_slot() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	# All busy — reuse the oldest (first).
	return _sfx_pool[0]

# ── UI click auto-wiring ──────────────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node)

func _wire_existing_buttons(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node)
	for child in node.get_children():
		_wire_existing_buttons(child)

func _wire_button(btn: BaseButton) -> void:
	if not btn.pressed.is_connected(_on_ui_button_pressed):
		btn.pressed.connect(_on_ui_button_pressed)

func _on_ui_button_pressed() -> void:
	play_sfx("ui", "button_click")
