class_name CourseLibrary
extends RefCounted

# ---------------------------------------------------------
# The courses that ship with the game.
#
# The first is the built-in 18 (HoleData.HOLES). The rest are course
# files under res://assets/courses — the SAME format the course editor
# saves and the network sends (Course.to_wire), read through the same
# sanitiser. So a shipped course is a custom course that happens to live
# in the game folder: build one in the editor, copy its .json here, add
# its file name to FILES, and it ships.
#
# Two rules for a file in here, both checked by CourseTest:
#   - it must come out of the sanitiser unchanged (numbers to one decimal,
#     inside Course.gd's limits). The host plays the file; a client plays
#     what the sanitiser made of it. Those have to be the same course.
#   - its name must be unique — the course picker and the records key on it.
#
# A file may carry one extra field the wire format ignores:
#   "blurb"  one line about the course, for the picker
# ---------------------------------------------------------

const DIR := "res://assets/courses"
# File names without ".json" — also the course ids. In picker order.
const FILES := ["windlestraw-links", "mirage-mesa", "thin-air-ridge"]

static var _courses: Array = []   # [{ id, name, theme, blurb, holes }] (+ holes_key, once asked for)


# Every shipped course, built-in first. Runtime-shaped, like Course.active().
static func all() -> Array:
	if _courses.is_empty():
		var first := Course.builtin()
		first["id"] = Course.BUILTIN_ID
		first["blurb"] = "The home course. Eighteen holes through the trees, a little of everything."
		_courses.append(first)
		for id in FILES:
			var c := _load(id)
			if not c.is_empty():
				_courses.append(c)
	return _courses


# --- The ladder ---------------------------------------------------------
# The game's courses open one at a time, in picker order: a course is
# locked until a finished round on the one before it came in at that
# rung's target over par or better (Records: any round recorded on this
# machine). The first is always open, and so is anything saved from the
# editor. Settings' "open_all" opens the lot.
#
# The targets step down the ladder (2026-11-25; one figure of 5 before):
# 5 over on the first course opens the second, 3 over there the third,
# and level par the fourth. The courses play about equally hard, so the
# target is what climbs. A course past the end of the list takes the last.
const QUALIFY := [5, 3, 0]


# Strokes over par a round on the `rung`th course (0 is the first) has to
# match to open the next one.
static func target(rung: int) -> int:
	return int(QUALIFY[clampi(rung, 0, QUALIFY.size() - 1)])


# ...and the same for a course by its id.
static func target_on(id: String) -> int:
	var list := all()
	for i in range(list.size()):
		if list[i].id == id:
			return target(i)
	return target(0)


# What stands between the player and course `id`: {} if it is open, else
# { name, id, target, best } — the course to score on, the strokes over par
# to match, and the best round there so far ({} with none).
static func lock_on(id: String) -> Dictionary:
	if bool(Settings.get_value("open_all")):
		return {}
	var list := all()
	for i in range(1, list.size()):
		if list[i].id != id:
			continue
		# A course that has been played stays open: nothing earned under an
		# easier target is taken back when a target moves.
		var own := Records.key_for(id)
		if Records.rounds_played(own) > 0 or Records.hole_best(1, own) > 0:
			return {}
		var best := Records.best_round(Records.key_for(str(list[i - 1].id)))
		if not best.is_empty() and int(best.diff) <= target(i - 1):
			return {}
		return {"name": list[i - 1].name, "id": list[i - 1].id, "target": target(i - 1), "best": best}
	return {}


# The course after `id` in the ladder ({} after the last, or for a course
# that isn't one of the game's).
static func next_after(id: String) -> Dictionary:
	var list := all()
	for i in range(list.size() - 1):
		if list[i].id == id:
			return list[i + 1]
	return {}


# The first course still locked, as lock_on() gives it, or {} with every
# course open. The tour plays them all, so it waits for this to be empty.
static func first_lock() -> Dictionary:
	for c in all():
		var lock := lock_on(str(c.id))
		if not lock.is_empty():
			return lock
	return {}


# "5 over par or better", "level par or better".
static func target_text(over: int) -> String:
	return "%s or better" % ("level par" if over == 0 else "%d %s par" % [absi(over), "over" if over > 0 else "under"])


# A fresh copy of one course, or {} if there's no course with that id.
static func course(id: String) -> Dictionary:
	for c in all():
		if c.id == id:
			return (c as Dictionary).duplicate(true)
	return {}


# Which shipped course `course` is, or "" if it's none of them. It is one
# when its name, terrain and holes are all the same — the test is on the
# contents, so it holds for a course picked here and for the same course
# sent by an online host alike. A renamed or reshaped copy is its own
# course.
static func id_of(course: Dictionary) -> String:
	var name := str(course.get("name", ""))
	var theme := CourseTheme.sanitise(course.get("theme", CourseTheme.DEFAULT))
	var key := ""
	for c in all():
		if str(c.name) != name or str(c.theme) != theme:
			continue
		# Only now is the comparison worth paying for.
		if key == "":
			key = _holes_key(course.get("holes", []))
		if not c.has("holes_key"):
			c["holes_key"] = _holes_key(c.holes)
		if c.holes_key == key:
			return c.id
	return ""


# Holes as the wire sees them — one string two courses share only if they
# play identically.
static func _holes_key(holes: Array) -> String:
	return JSON.stringify(Course.to_wire({"holes": holes}).holes)


static func has_name(name: String) -> bool:
	var want := name.strip_edges().to_lower()
	for c in all():
		if str(c.name).to_lower() == want:
			return true
	return false


static func blurb(id: String) -> String:
	for c in all():
		if c.id == id:
			return str(c.get("blurb", ""))
	return ""


static func path_for(id: String) -> String:
	return "%s/%s.json" % [DIR, id]


static func _load(id: String) -> Dictionary:
	var path := path_for(id)
	if not FileAccess.file_exists(path):
		push_warning("CourseLibrary: %s is missing" % path)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var c := Course.from_wire(raw)
	if c.is_empty():
		push_warning("CourseLibrary: %s has no playable holes" % path)
		return {}
	c["id"] = id
	c["blurb"] = str(raw.get("blurb", "")) if raw is Dictionary else ""
	return c
