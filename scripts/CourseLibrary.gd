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
