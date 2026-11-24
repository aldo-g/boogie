class_name Records
extends RefCounted

# ---------------------------------------------------------
# What you've done on each course, kept between sessions in
# user://records.json — the replay hook for a game played on fixed,
# learnable courses.
#
# Per course:
#   best        — the lowest full round: strokes, vs par, who, when, mode
#   rounds      — full rounds finished
#   history     — the last HISTORY_LIMIT rounds, newest first
#   hole_bests  — the fewest strokes on each hole, from any round (even
#                 an unfinished one), so you can see where you've gone
#                 low before
#
# A custom course is identified by its contents, not its name or file:
# edit it and it starts a fresh record, because it's a different course.
# The game's own courses are identified by which course they are — the
# built-in is always "builtin", the others "course:<id>" — so their
# records survive an update that reshapes a hole.
#
# Only rounds played on this machine are recorded: solo, every hot-seat
# player, and your own seat online.
#
# And only rounds a player started. Recording is off until the title
# screen comes up as the scene the game is running (title_shown(), below),
# which is the one way a player reaches a round. A script that loads
# Main.tscn on its own — a test harness, a screenshot script, the capture
# tool — never passes through it, so it records nothing, in a window or
# headless. (It used to be "off when headless" only, and windowed
# screenshot scripts wrote faked rounds into the player's real records.)
# A harness that wants records sets `enabled` and a scratch `path` itself.
# ---------------------------------------------------------

const PATH := "user://records.json"
const HISTORY_LIMIT := 20

static var enabled: bool = false
static var path: String = PATH  # the harness points this at a scratch file

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_data = {"version": 1, "courses": {}}
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.get("courses") is Dictionary:
		_data = parsed


# The title screen calls this as it comes up. It turns recording on when
# `title` is the scene the game is running — not a title screen some other
# scene has loaded as a child to photograph — and the run has a display.
# It only ever turns recording on: a harness's own choice is left alone.
static func title_shown(title: Node) -> void:
	var running: bool = title != null and title.is_inside_tree() \
		and title.get_tree().current_scene == title
	var headless := DisplayServer.get_name() == "headless"
	if running and not headless:
		enabled = true
	print_verbose("Records: recording %s (title is the running scene: %s, headless: %s)" % [
		"on" if enabled else "off", running, headless])


# Forget the cached file, e.g. after pointing `path` somewhere else.
static func reload_from_disk() -> void:
	_loaded = false
	_ensure_loaded()


static func _save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Records: could not write %s" % path)
		return
	f.store_string(JSON.stringify(_data, "\t"))
	f.close()


# The active course's identity: "builtin" or "course:<id>" for one of the
# game's own, else a hash of a custom course's holes so an edited course
# doesn't inherit the old one's records.
static func course_key() -> String:
	if Course.active_id != "":
		return key_for(Course.active_id)
	return "custom:%x" % hash(JSON.stringify(Course.active().get("holes", [])))


# The key of one of the game's own courses, by its CourseLibrary id.
static func key_for(id: String) -> String:
	return "builtin" if id == Course.BUILTIN_ID else "course:%s" % id


static func course(key: String = "") -> Dictionary:
	_ensure_loaded()
	if key == "":
		key = course_key()
	return (_data.courses as Dictionary).get(key, {})


static func _course_for_write(key: String) -> Dictionary:
	var courses: Dictionary = _data.courses
	if not courses.has(key):
		courses[key] = {"name": Course.active_name, "rounds": 0, "history": [], "hole_bests": {}}
	var c: Dictionary = courses[key]
	c["name"] = Course.active_name  # follow a rename
	return c


# --- Writing ---------------------------------------------------------

# One finished hole. Returns the previous best on it (0 if none) so the
# caller can say "your best here was 5".
static func record_hole(hole_n: int, strokes: int) -> int:
	if not enabled:
		return 0
	_ensure_loaded()
	var c := _course_for_write(course_key())
	var bests: Dictionary = c.hole_bests
	var k := str(hole_n)
	var prev := int(bests.get(k, 0))
	if prev == 0 or strokes < prev:
		bests[k] = strokes
		_save()
	return prev


# One finished round for one player. Returns {new_best, previous_best,
# rounds}: previous_best is the old best entry (empty if there was none).
static func record_round(player_name: String, strokes: int, par: int, mode: String) -> Dictionary:
	if not enabled:
		return {"new_best": false, "previous_best": {}, "rounds": 0}
	_ensure_loaded()
	var c := _course_for_write(course_key())
	var entry := {
		"strokes": strokes, "diff": strokes - par, "player": player_name,
		"mode": mode, "date": Time.get_date_string_from_system(),
	}
	var prev: Dictionary = c.get("best", {})
	var new_best: bool = prev.is_empty() or strokes < int(prev.get("strokes", 0))
	if new_best:
		c["best"] = entry
	c["rounds"] = int(c.get("rounds", 0)) + 1
	var history: Array = c.get("history", [])
	history.push_front(entry)
	c["history"] = history.slice(0, HISTORY_LIMIT)
	_save()
	return {"new_best": new_best, "previous_best": prev, "rounds": c.rounds}


# --- Reading ---------------------------------------------------------

static func best_round(key: String = "") -> Dictionary:
	return course(key).get("best", {})


static func hole_best(hole_n: int, key: String = "") -> int:
	return int((course(key).get("hole_bests", {}) as Dictionary).get(str(hole_n), 0))


static func rounds_played(key: String = "") -> int:
	return int(course(key).get("rounds", 0))


static func history(key: String = "") -> Array:
	return course(key).get("history", [])


# The mean of the recorded history, or NAN with none.
static func average(key: String = "") -> float:
	var h := history(key)
	if h.is_empty():
		return NAN
	var total := 0.0
	for e in h:
		total += float(e.get("strokes", 0))
	return total / h.size()


static func diff_text(diff: int) -> String:
	if diff == 0:
		return "E"
	return ("+%d" % diff) if diff > 0 else str(diff)


# One line for the title screen's course box.
static func summary_line(key: String = "") -> String:
	var best := best_round(key)
	if best.is_empty():
		return "No rounds yet — set the first record"
	var n := rounds_played(key)
	return "Best %d (%s) · %d round%s played" % [
		int(best.strokes), diff_text(int(best.diff)), n, "" if n == 1 else "s"]


static func clear_course(key: String = "") -> void:
	_ensure_loaded()
	if key == "":
		key = course_key()
	(_data.courses as Dictionary).erase(key)
	_save()
