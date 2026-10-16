class_name Course
extends RefCounted

# ---------------------------------------------------------
# The course being played: a name and 1-18 hole definitions.
#
# A hole definition is the same Dictionary HoleData.HOLES uses (spine,
# green, hazards, elev, green_tilt — Vector-typed), so HoleData builds a
# custom hole exactly the way it builds a built-in one. The built-in
# course is just HOLES under the name "Bogey Links".
#
# Two shapes of the same data:
#   runtime — Vector2/Vector3 values, what the game reads
#   wire    — plain numbers and arrays, what goes in a .json file or over
#             the network. from_wire() also SANITISES: a course can come
#             from a hand-edited file or another player's machine, so every
#             count and number is clamped to something the game can play.
#
# Class-level statics, like GameSetup: the choice made on the title screen
# survives the scene change into the round.
# ---------------------------------------------------------

const BUILTIN_NAME := "Bogey Links"
const SAVE_DIR := "user://courses"
const MAX_HOLES := 18
const FORMAT_VERSION := 1

# Limits for sanitising. Generous enough for anything sensible, tight
# enough that nothing breaks the map, the bounds or the roll sim.
const MAX_SPINE := 12
const MAX_BUNKERS := 8
const MAX_WATERS := 4
const MAX_WATER_POINTS := 16
const MAX_ELEV := 12
const X_LIMIT := 150.0
const Y_LIMIT := 700.0
const MIN_GREEN_Y := 40.0

static var active_name: String = BUILTIN_NAME
static var _active_holes: Array = []   # runtime hole defs; empty = built-in
static var active_path: String = ""     # the saved file it came from, if any


# --- The active course -------------------------------------------------

static func hole_count() -> int:
	return HoleData.HOLES.size() if _active_holes.is_empty() else _active_holes.size()


# 1-based, matching current_hole_index.
static func hole_def(n: int) -> Dictionary:
	if _active_holes.is_empty():
		return HoleData.HOLES.get(n, HoleData.HOLES[1])
	return _active_holes[clampi(n, 1, _active_holes.size()) - 1]


static func is_builtin() -> bool:
	return _active_holes.is_empty()


static func use_builtin() -> void:
	active_name = BUILTIN_NAME
	_active_holes = []
	active_path = ""


# `course` is runtime-shaped: { "name": String, "holes": Array }.
static func use(course: Dictionary) -> void:
	var holes: Array = course.get("holes", [])
	if holes.is_empty():
		use_builtin()
		return
	active_name = str(course.get("name", "Custom course"))
	_active_holes = holes.duplicate(true)
	active_path = ""


static func use_file(path: String) -> bool:
	var c := load_file(path)
	if c.is_empty():
		return false
	use(c)
	active_path = path
	return true


# "9 holes · par 36" — for pickers and headers.
static func summary(course: Dictionary) -> String:
	var holes: Array = course.get("holes", [])
	var par := 0
	for h in holes:
		par += int(h.par)
	return "%d hole%s · par %d" % [holes.size(), "" if holes.size() == 1 else "s", par]


static func active() -> Dictionary:
	if is_builtin():
		return builtin()
	return {"name": active_name, "holes": _active_holes.duplicate(true)}


static func builtin() -> Dictionary:
	var holes: Array = []
	for n in range(1, HoleData.HOLES.size() + 1):
		holes.append((HoleData.HOLES[n] as Dictionary).duplicate(true))
	return {"name": BUILTIN_NAME, "holes": holes}


# A plain starter hole for the editor: a straight par 4 with a flat green.
static func blank_hole(par: int = 4) -> Dictionary:
	var length: float = {3: 160.0, 4: 380.0, 5: 520.0}.get(par, 380.0)
	var spine: Array = [Vector3(0, 0, 44 if par > 3 else 22)]
	if par > 3:
		spine.append(Vector3(0, length * 0.45, 40))
		spine.append(Vector3(0, length - 60.0, 30))
	else:
		spine.append(Vector3(0, 34, 20))
	return {
		"par": par,
		"yardage": length,
		"spine": spine,
		"green": {"pos": Vector2(0, length), "radii": Vector2(24, 19), "rot": 0.0},
		"hazards": [],
		"elev": [Vector3(0, 0, 0), Vector3(length, 0, 0)],
		"green_tilt": Vector2(0, -2),
	}


# Hole length is where the green sits: keeps the scorecard honest after
# the green is dragged.
static func refresh_yardage(hole: Dictionary) -> void:
	hole["yardage"] = float(round((hole.green.pos as Vector2).y))


# --- Wire format -------------------------------------------------------

static func to_wire(course: Dictionary) -> Dictionary:
	var holes: Array = []
	for h in course.get("holes", []):
		var hazards: Array = []
		for z in h.get("hazards", []):
			if z.type == "water":
				hazards.append({"type": "water", "poly": _pts_out(z.poly)})
			else:
				hazards.append({"type": "bunker", "pos": _v2_out(z.pos),
					"radii": _v2_out(z.radii), "rot": float(z.get("rot", 0.0))})
		holes.append({
			"par": int(h.par),
			"yardage": float(h.yardage),
			"spine": _v3s_out(h.spine),
			"green": {"pos": _v2_out(h.green.pos), "radii": _v2_out(h.green.radii),
				"rot": float(h.green.get("rot", 0.0))},
			"hazards": hazards,
			"elev": _v3s_out(h.get("elev", [])),
			"green_tilt": _v2_out(h.get("green_tilt", Vector2.ZERO)),
		})
	return {"version": FORMAT_VERSION, "name": str(course.get("name", "Custom course")), "holes": holes}


# Returns a runtime course, or {} if there's nothing playable in `d`.
static func from_wire(d) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var raw_holes = d.get("holes", [])
	if not (raw_holes is Array):
		return {}
	var holes: Array = []
	for rh in raw_holes:
		if holes.size() >= MAX_HOLES:
			break
		var h := _hole_from_wire(rh)
		if not h.is_empty():
			holes.append(h)
	if holes.is_empty():
		return {}
	var name := str(d.get("name", "Custom course")).strip_edges().left(40)
	if name == "":
		name = "Custom course"
	return {"name": name, "holes": holes}


static func _hole_from_wire(rh) -> Dictionary:
	if not (rh is Dictionary):
		return {}
	var par := clampi(int(_num(rh.get("par", 4), 4)), 3, 5)

	# Spine: sorted by distance out, tee pinned to y = 0.
	var spine: Array = []
	for p in _list(rh.get("spine", [])).slice(0, MAX_SPINE):
		var v := _v3_in(p)
		spine.append(Vector3(clampf(v.x, -X_LIMIT, X_LIMIT), clampf(v.y, 0.0, Y_LIMIT), clampf(v.z, 8.0, 90.0)))
	spine.sort_custom(func(a, b): return a.y < b.y)
	if spine.size() < 2:
		return {}
	spine[0] = Vector3(spine[0].x, 0.0, spine[0].z)

	var rg = rh.get("green", {})
	if not (rg is Dictionary):
		return {}
	var gpos := _v2_in(rg.get("pos", []))
	gpos = Vector2(clampf(gpos.x, -X_LIMIT, X_LIMIT), clampf(gpos.y, MIN_GREEN_Y, Y_LIMIT))
	var gr := _v2_in(rg.get("radii", []))
	var green := {"pos": gpos, "radii": Vector2(clampf(gr.x, 8.0, 40.0), clampf(gr.y, 8.0, 40.0)),
		"rot": clampf(_num(rg.get("rot", 0.0), 0.0), -180.0, 180.0)}

	var hazards: Array = []
	var bunkers := 0
	var waters := 0
	for z in _list(rh.get("hazards", [])):
		if not (z is Dictionary):
			continue
		if str(z.get("type", "")) == "water":
			if waters >= MAX_WATERS:
				continue
			var poly := PackedVector2Array()
			for p in _list(z.get("poly", [])).slice(0, MAX_WATER_POINTS):
				var v := _v2_in(p)
				poly.append(Vector2(clampf(v.x, -X_LIMIT, X_LIMIT), clampf(v.y, -20.0, Y_LIMIT)))
			if poly.size() >= 3:
				hazards.append({"type": "water", "poly": poly})
				waters += 1
		elif bunkers < MAX_BUNKERS:
			var bp := _v2_in(z.get("pos", []))
			var br := _v2_in(z.get("radii", []))
			hazards.append({"type": "bunker",
				"pos": Vector2(clampf(bp.x, -X_LIMIT, X_LIMIT), clampf(bp.y, 0.0, Y_LIMIT)),
				"radii": Vector2(clampf(br.x, 4.0, 25.0), clampf(br.y, 4.0, 25.0)),
				"rot": clampf(_num(z.get("rot", 0.0), 0.0), -180.0, 180.0)})
			bunkers += 1

	var elev: Array = []
	for p in _list(rh.get("elev", [])).slice(0, MAX_ELEV):
		var v := _v3_in(p)
		elev.append(Vector3(clampf(v.x, 0.0, Y_LIMIT), clampf(v.y, -80.0, 80.0), clampf(v.z, -8.0, 8.0)))
	elev.sort_custom(func(a, b): return a.x < b.x)

	var tilt := _v2_in(rh.get("green_tilt", []))
	var h := {
		"par": par,
		"spine": spine,
		"green": green,
		"hazards": hazards,
		"elev": elev,
		"green_tilt": Vector2(clampf(tilt.x, -4.0, 4.0), clampf(tilt.y, -4.0, 4.0)),
	}
	# Keep an authored yardage (the built-in card says 395 on a hole whose
	# green sits at 398); fall back to the green's position.
	var yd := _num(rh.get("yardage", -1.0), -1.0)
	if yd > 0.0:
		h["yardage"] = clampf(yd, MIN_GREEN_Y, Y_LIMIT)
	else:
		refresh_yardage(h)
	return h


# --- Saving ------------------------------------------------------------

# Returns "" on success, or a reason it failed.
static func save(course: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := path_for(str(course.get("name", "course")))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Couldn't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(to_wire(course), "\t"))
	return ""


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return from_wire(JSON.parse_string(FileAccess.get_file_as_string(path)))


static func delete_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# Every saved course, as [{ "name", "path" }], sorted by name.
static func list_saved() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var path := SAVE_DIR + "/" + file
		var c := load_file(path)
		if not c.is_empty():
			out.append({"name": c.name, "path": path})
	out.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


static func path_for(name: String) -> String:
	var slug := ""
	for ch in name.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			slug += ch
		elif not slug.ends_with("-"):
			slug += "-"
	slug = slug.trim_prefix("-").trim_suffix("-")
	if slug == "":
		slug = "course"
	return SAVE_DIR + "/" + slug + ".json"


# --- Conversion helpers ------------------------------------------------

static func _num(v, fallback: float) -> float:
	if v is float or v is int:
		return float(v) if is_finite(float(v)) else fallback
	return fallback


static func _list(v) -> Array:
	return v if v is Array else []


static func _v2_in(v) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(_num(v[0], 0.0), _num(v[1], 0.0))
	return Vector2.ZERO


static func _v3_in(v) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(_num(v[0], 0.0), _num(v[1], 0.0), _num(v[2], 0.0))
	return Vector3.ZERO


static func _v2_out(v: Vector2) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1)]


static func _v3s_out(list: Array) -> Array:
	var out: Array = []
	for v in list:
		out.append([snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)])
	return out


static func _pts_out(poly) -> Array:
	var out: Array = []
	for p in poly:
		out.append(_v2_out(p))
	return out
