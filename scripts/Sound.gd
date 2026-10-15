extends Node

# ---------------------------------------------------------
# SOUND — autoload ("Sound" in project.godot).
#
# One place that owns every audio file the game plays. Gameplay code
# never touches file paths: it calls Sound.play("splash") or
# Sound.jingle(diff) and this script decides which file, at what pitch.
#
# Every entry in SFX is a *group*: play() picks one at random so a sound
# that fires forty times a round (card slides, strikes) doesn't wear a
# groove. Files and licences are listed in assets/audio/CREDITS.md.
# ---------------------------------------------------------

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"

# Group name -> list of files under SFX_DIR. Edit freely: anything in
# assets/audio/sfx can be slotted in here.
const SFX := {
	# Interface
	"ui_click": ["ui/click_001.ogg", "ui/click_002.ogg", "ui/click_003.ogg", "ui/click_004.ogg", "ui/click_005.ogg"],
	"ui_confirm": ["ui/confirmation_001.ogg", "ui/confirmation_002.ogg", "ui/confirmation_003.ogg", "ui/confirmation_004.ogg"],
	"ui_back": ["ui/back_001.ogg", "ui/back_002.ogg", "ui/back_003.ogg", "ui/back_004.ogg"],
	"ui_error": ["ui/error_001.ogg", "ui/error_002.ogg", "ui/error_003.ogg", "ui/error_004.ogg"],
	"ui_bong": ["ui/bong_001.ogg"],

	# Cards — club bag and Form hand
	"card_slide": ["cards/card-slide-1.ogg", "cards/card-slide-2.ogg", "cards/card-slide-3.ogg", "cards/card-slide-4.ogg",
		"cards/card-slide-5.ogg", "cards/card-slide-6.ogg", "cards/card-slide-7.ogg", "cards/card-slide-8.ogg"],
	"card_draw": ["cards/card-fan-1.ogg", "cards/card-fan-2.ogg"],
	"card_place": ["cards/card-place-1.ogg", "cards/card-place-2.ogg", "cards/card-place-3.ogg", "cards/card-place-4.ogg"],
	"card_discard": ["cards/card-shove-1.ogg", "cards/card-shove-2.ogg", "cards/card-shove-3.ogg", "cards/card-shove-4.ogg"],
	"card_shuffle": ["cards/card-shuffle.ogg"],

	# Swings, by club type
	"swing_wood": ["golf/strike_powerful.mp3", "golf/strike_hard.mp3", "golf/strike_hitting_ball.mp3"],
	"swing_iron": ["golf/strike_sharp.mp3", "golf/strike_quick.mp3", "golf/strike_metal.mp3", "golf/strike_ball_hit.mp3"],
	"swing_short": ["golf/strike_short.mp3", "golf/strike_quick_shot.mp3"],
	"putt": ["impacts/impactGeneric_light_000.ogg", "impacts/impactGeneric_light_001.ogg",
		"impacts/impactGeneric_light_002.ogg", "impacts/impactGeneric_light_003.ogg", "impacts/impactGeneric_light_004.ogg"],

	# Landings
	"land_grass": ["impacts/impactSoft_medium_000.ogg", "impacts/impactSoft_medium_001.ogg", "impacts/impactSoft_medium_002.ogg",
		"impacts/impactSoft_medium_003.ogg", "impacts/impactSoft_medium_004.ogg"],
	"land_sand": ["impacts/impactSoft_heavy_000.ogg", "impacts/impactSoft_heavy_001.ogg", "impacts/impactSoft_heavy_002.ogg",
		"impacts/impactSoft_heavy_003.ogg", "impacts/impactSoft_heavy_004.ogg"],
	"splash": ["water/splash_01.ogg", "water/splash_02.ogg", "water/splash_03.ogg", "water/splash_04.ogg", "water/splash_05.ogg",
		"water/splash_06.ogg", "water/splash_07.ogg", "water/splash_08.ogg"],
	"cup": ["impacts/impactPlate_light_000.ogg", "impacts/impactPlate_light_001.ogg", "impacts/impactPlate_light_002.ogg",
		"impacts/impactPlate_light_003.ogg", "impacts/impactPlate_light_004.ogg"],
	"rim_out": ["impacts/impactWood_light_000.ogg", "impacts/impactWood_light_001.ogg", "impacts/impactWood_light_002.ogg"],

	# Jingles — see jingle(). Kenney's sets are numbered rather than named,
	# so these are picks to taste; swap the numbers if one reads wrong.
	"jingle_eagle": ["jingles/jingles_STEEL00.ogg"],
	"jingle_birdie": ["jingles/jingles_PIZZI00.ogg"],
	"jingle_par": ["jingles/jingles_PIZZI03.ogg"],
	"jingle_bogey": ["jingles/jingles_PIZZI07.ogg"],
	"jingle_double": ["jingles/jingles_PIZZI10.ogg"],
	"jingle_round": ["jingles/jingles_SAX00.ogg"],
}

# Background playlist, shuffled once per launch. Short seamless loops are
# repeated so they get a fair run before the next track.
const MUSIC := [
	"jazz_improv_looped.mp3",
	"just_you_and_me.mp3",
	"gone_fishin.mp3",
	"swinging_sweet.ogg",
	"a_brand_new_wisdom.ogg",
	"just_saying_tho.ogg",
	"winter_dust.ogg",
]
const SHORT_LOOP_SECONDS := 40.0
const SHORT_LOOP_REPEATS := 4

const SFX_DB := -4.0
const MUSIC_DB := -14.0
const VOICES := 8  # simultaneous sound effects

var sfx_enabled := true
var music_enabled := true

var _streams: Dictionary = {}       # group -> Array[AudioStream]
var _voices: Array = []             # Array[AudioStreamPlayer]
var _next_voice := 0
var _music: AudioStreamPlayer
var _playlist: Array = []
var _track_index := -1
var _repeats_left := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for group in SFX:
		var list: Array = []
		for rel in SFX[group]:
			var stream = load(SFX_DIR + rel)
			if stream:
				list.append(stream)
			else:
				push_warning("Sound: missing %s" % rel)
		_streams[group] = list
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.volume_db = SFX_DB
		add_child(p)
		_voices.append(p)

	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	_music.finished.connect(_on_track_finished)
	add_child(_music)
	_playlist = MUSIC.duplicate()
	_playlist.shuffle()
	_next_track()


# Plays one random file from `group`. `pitch_spread` widens the random
# pitch shift (0.0 = exact); the default is just enough that two slides in
# a row don't sound identical.
func play(group: String, pitch_spread: float = 0.06, db: float = 0.0) -> void:
	if not sfx_enabled:
		return
	var list: Array = _streams.get(group, [])
	if list.is_empty():
		push_warning("Sound: unknown group '%s'" % group)
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = list[randi() % list.size()]
	voice.pitch_scale = randf_range(1.0 - pitch_spread, 1.0 + pitch_spread)
	voice.volume_db = SFX_DB + db
	voice.play()


# Swing sound for a club card ("wood", "iron", "wedge", "putter"...).
func swing(club_type: String) -> void:
	match club_type:
		"wood":
			play("swing_wood", 0.04)
		"putter", "wedge":
			play("swing_short", 0.05)
		_:
			play("swing_iron", 0.05)


# Landing sound for the terrain the ball finished on.
func landing(lie: String) -> void:
	match lie:
		"water":
			play("splash", 0.1)
		"out":
			play("ui_bong", 0.0)
		"bunker":
			play("land_sand", 0.08)
		_:
			play("land_grass", 0.08, -6.0)


# End-of-hole sting, from strokes relative to par.
func jingle(diff: int) -> void:
	if diff <= -2:
		play("jingle_eagle", 0.0)
	elif diff == -1:
		play("jingle_birdie", 0.0)
	elif diff == 0:
		play("jingle_par", 0.0)
	elif diff == 1:
		play("jingle_bogey", 0.0)
	else:
		play("jingle_double", 0.0)


func set_music_enabled(on: bool) -> void:
	music_enabled = on
	if on and not _music.playing:
		_next_track()
	elif not on:
		_music.stop()


func _next_track() -> void:
	if not music_enabled or _playlist.is_empty():
		return
	_track_index = (_track_index + 1) % _playlist.size()
	var stream = load(MUSIC_DIR + _playlist[_track_index])
	if stream == null:
		push_warning("Sound: missing music %s" % _playlist[_track_index])
		return
	_repeats_left = SHORT_LOOP_REPEATS if stream.get_length() < SHORT_LOOP_SECONDS else 1
	_music.stream = stream
	_music.play()


func _on_track_finished() -> void:
	_repeats_left -= 1
	if _repeats_left > 0:
		_music.play()
	else:
		_next_track()


# M mutes/unmutes music, N mutes/unmutes effects. Dev conveniences that
# cost nothing to keep.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			set_music_enabled(not music_enabled)
		elif event.keycode == KEY_N:
			sfx_enabled = not sfx_enabled
