extends SceneTree

# ---------------------------------------------------------
# RECORDS & SETTINGS HARNESS — what persists between sessions. Dev tool,
# not shipped. Works on scratch files, never the player's own.
#
#   godot --headless --script res://scripts/RecordsTest.gd
#
# Checks:
#   1. a hole best only ever goes down
#   2. a round best only ever goes down; history is newest first and capped
#   3. records survive a reload from disk
#   4. editing a custom course gives it a fresh record
#   5. settings save, reload, clamp bad values and reset
#   6. headless runs record nothing unless a harness opts in
# ---------------------------------------------------------

# Held so the scripts stay loaded. GDScript statics live on the script
# resource, and a class nothing references is freed and reloaded between
# calls — which resets every static, including the scratch paths below.
# In the game, Main.gd and Title.gd hold them.
const _KEEP := [preload("res://scripts/Records.gd"), preload("res://scripts/Settings.gd")]

const RECORDS_FILE := "user://records_test.json"
const SETTINGS_FILE := "user://settings_test.cfg"

var failures: Array = []


func _initialize() -> void:
	_expect(not Records.enabled, "headless runs don't record by default")
	Records.enabled = true
	Records.path = RECORDS_FILE
	Settings.path = SETTINGS_FILE
	_wipe()

	_check_holes()
	_check_rounds()
	_check_course_identity()
	_check_settings()

	_wipe()
	if failures.is_empty():
		print("\nRECORDS: OK")
	else:
		for f in failures:
			print("  !! " + f)
		print("\nRECORDS: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _wipe() -> void:
	for f in [RECORDS_FILE, SETTINGS_FILE]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Course.use_builtin()
	Records.reload_from_disk()
	Settings.reload_from_disk()


func _check_holes() -> void:
	_expect(Records.hole_best(3) == 0, "no hole best before any play")
	_expect(Records.record_hole(3, 5) == 0, "the first score has no previous best")
	_expect(Records.hole_best(3) == 5, "it becomes the best")
	_expect(Records.record_hole(3, 6) == 5, "a worse score reports the best...")
	_expect(Records.hole_best(3) == 5, "...and doesn't replace it")
	Records.record_hole(3, 4)
	_expect(Records.hole_best(3) == 4, "a better score does")


func _check_rounds() -> void:
	var r := Records.record_round("You", 80, 72, "solo")
	_expect(r.new_best and (r.previous_best as Dictionary).is_empty(), "the first round is the record")
	r = Records.record_round("You", 84, 72, "solo")
	_expect(not r.new_best and int(r.previous_best.strokes) == 80, "a worse round isn't")
	r = Records.record_round("Player 2", 75, 72, "hot-seat")
	_expect(r.new_best, "a better round is")
	var best := Records.best_round()
	_expect(int(best.strokes) == 75 and int(best.diff) == 3 and best.player == "Player 2", "the best round keeps who and how")
	_expect(Records.rounds_played() == 3, "three rounds counted")
	_expect(int(Records.history()[0].strokes) == 75, "history is newest first")
	_expect(is_equal_approx(Records.average(), (80.0 + 84.0 + 75.0) / 3.0), "the average is over the history")
	for i in range(Records.HISTORY_LIMIT + 5):
		Records.record_round("You", 90, 72, "solo")
	_expect(Records.history().size() == Records.HISTORY_LIMIT, "history is capped")
	_expect(int(Records.best_round().strokes) == 75, "the best survives the history rolling over")

	Records.reload_from_disk()
	_expect(int(Records.best_round().strokes) == 75 and Records.hole_best(3) == 4, "records survive a reload")
	_expect(Records.summary_line().begins_with("Best 75 (+3)"), "the title line reads the best (%s)" % Records.summary_line())


func _check_course_identity() -> void:
	_expect(Records.course_key() == "builtin", "the built-in course is 'builtin'")
	var custom := {"name": "Test Links", "holes": [Course.blank_hole(3)]}
	Course.use(custom)
	var key := Records.course_key()
	_expect(key != "builtin", "a custom course has its own key")
	_expect(Records.best_round().is_empty(), "and its own, empty, record")
	Records.record_round("You", 3, 3, "solo")
	var edited := custom.duplicate(true)
	edited.holes[0]["par"] = 4
	Course.use(edited)
	_expect(Records.course_key() != key, "editing the course changes its key")
	_expect(Records.best_round().is_empty(), "so the edited course starts fresh")
	Course.use(custom)
	_expect(int(Records.best_round().strokes) == 3, "and the original keeps its record")
	Course.use_builtin()


func _check_settings() -> void:
	_expect(is_equal_approx(float(Settings.get_value("music")), 1.0), "music defaults to full")
	_expect(Settings.putt_key() == KEY_SPACE, "the putt key defaults to Space")
	Settings.set_value("music", 0.4)
	Settings.set_value("shot_speed", Settings.ShotSpeed.INSTANT)
	Settings.set_value("putt_key", KEY_P)
	Settings.reload_from_disk()
	_expect(is_equal_approx(float(Settings.get_value("music")), 0.4), "volume survives a reload")
	_expect(Settings.instant_shots(), "shot speed survives a reload")
	_expect(Settings.putt_key() == KEY_P and Settings.putt_key_name() == "P", "the putt key survives a reload")
	_expect(Settings.volume_db("music") < 0.0, "40% is quieter than full")

	Settings.set_value("sfx", 0.0)
	_expect(Settings.is_muted("sfx") and Settings.volume_db("sfx") <= -79.0, "0 is silence")
	_expect(not Settings.key_allowed(KEY_ESCAPE) and Settings.key_allowed(KEY_ENTER), "Escape can't be the putt key")

	# A hand-edited file with nonsense in it falls back or clamps.
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "music", 7.5)
	cfg.set_value("settings", "shot_speed", 99)
	cfg.set_value("settings", "putt_key", "space bar")
	cfg.save(SETTINGS_FILE)
	Settings.reload_from_disk()
	_expect(is_equal_approx(float(Settings.get_value("music")), 1.0), "an out-of-range volume clamps")
	_expect(Settings.shot_speed() == Settings.ShotSpeed.INSTANT, "an out-of-range speed clamps")
	_expect(Settings.putt_key() == KEY_SPACE, "a wrongly typed key falls back to the default")

	Settings.reset_to_defaults()
	_expect(Settings.shot_speed() == Settings.ShotSpeed.NORMAL and Settings.putt_key() == KEY_SPACE, "reset restores the defaults")
