class_name Settings
extends RefCounted

# ---------------------------------------------------------
# Player settings, kept between sessions in user://settings.cfg.
#
# Class-level statics rather than an autoload, like GameSetup: plain
# values that need no node, readable from anywhere (Sound, the map, the
# putt meter's key) and loaded the first time anything asks.
#
#   volume     — master / music / sfx, 0..1 each
#   shot_speed — how shots animate: normal, fast, or instant
#   putt_key   — the key that strikes a putt (Space by default)
# ---------------------------------------------------------

const PATH := "user://settings.cfg"
static var path: String = PATH  # the harness points this at a scratch file

enum ShotSpeed { NORMAL, FAST, INSTANT }
const SHOT_SPEED_NAMES := ["Normal", "Fast", "Instant"]
const FAST_SCALE := 2.5   # tween speed multiplier for Fast

const DEFAULTS := {
	"master": 1.0,
	"music": 1.0,
	"sfx": 1.0,
	"shot_speed": ShotSpeed.NORMAL,
	"putt_key": KEY_SPACE,
}

static var _values: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key in DEFAULTS:
		var v: Variant = cfg.get_value("settings", key, DEFAULTS[key])
		# A hand-edited or old file can hold anything; keep the default
		# rather than a value of the wrong kind.
		if typeof(v) == typeof(DEFAULTS[key]) or (v is int and DEFAULTS[key] is float):
			_values[key] = v
	_values.master = clampf(float(_values.master), 0.0, 1.0)
	_values.music = clampf(float(_values.music), 0.0, 1.0)
	_values.sfx = clampf(float(_values.sfx), 0.0, 1.0)
	_values.shot_speed = clampi(int(_values.shot_speed), 0, ShotSpeed.size() - 1)


static func get_value(key: String) -> Variant:
	_ensure_loaded()
	return _values.get(key, DEFAULTS.get(key))


# Sets and saves one setting, and applies the audio ones straight away.
static func set_value(key: String, value: Variant) -> void:
	_ensure_loaded()
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown key '%s'" % key)
		return
	_values[key] = value
	save()
	if key == "master" or key == "music" or key == "sfx":
		apply_audio()


static func save() -> void:
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value("settings", key, _values[key])
	var err := cfg.save(path)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [path, err])


# Forget the cached values and read `path` again.
static func reload_from_disk() -> void:
	_loaded = false
	_ensure_loaded()


static func reset_to_defaults() -> void:
	_ensure_loaded()
	_values = DEFAULTS.duplicate()
	save()
	apply_audio()


# --- Audio ----------------------------------------------------------

# A 0..1 slider as decibels; 0 is silence rather than -inf maths.
static func volume_db(key: String) -> float:
	var v := float(get_value(key))
	return -80.0 if v <= 0.001 else linear_to_db(v)


static func is_muted(key: String) -> bool:
	return float(get_value(key)) <= 0.001


# Master goes on the audio bus; music and effects are applied by Sound.
static func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, volume_db("master"))
	AudioServer.set_bus_mute(0, is_muted("master"))
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sound := tree.root.get_node_or_null("Sound")
	if sound and sound.has_method("apply_volumes"):
		sound.apply_volumes()


# --- Shots ----------------------------------------------------------

static func shot_speed() -> int:
	return int(get_value("shot_speed"))


static func instant_shots() -> bool:
	return shot_speed() == ShotSpeed.INSTANT


# Tween speed scale for shot animations.
static func shot_speed_scale() -> float:
	return FAST_SCALE if shot_speed() == ShotSpeed.FAST else 1.0


# --- Keys -----------------------------------------------------------

static func putt_key() -> int:
	return int(get_value("putt_key"))


static func putt_key_name() -> String:
	return OS.get_keycode_string(putt_key())


# Keys a putt can't be bound to: Escape backs out of the key capture, and
# the dev mute toggles (M, N) are already taken.
static func key_allowed(keycode: int) -> bool:
	return keycode != KEY_ESCAPE and keycode != KEY_M and keycode != KEY_N and keycode != KEY_NONE
