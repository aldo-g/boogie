class_name CourseEditOverlay
extends Control

# ---------------------------------------------------------
# The editing layer laid over a CourseMapView in the course editor.
# Draws a handle for everything you can move and turns mouse input into
# edits on one hole definition (the Dictionary Course/HoleData use).
#
#   drag a handle        — move it (fairway point, width tab, green,
#                          bunker, water corner)
#   double-click grass   — add a fairway point there
#   right-click a handle — delete it (where the hole can spare it)
#   with a tool armed    — the next click places a bunker / water
#
# It edits the definition in place and says so through `edited`; the
# editor rebuilds the HoleData from it. `final` is false mid-drag (cheap
# rebuild) and true when the drag ends (full rebuild, slope shading too).
# ---------------------------------------------------------

signal edited(final: bool)
signal selection_changed
signal about_to_edit          # fired once before each change, for undo

var map: CourseMapView
var def: Dictionary = {}
var tool: String = ""         # "", "bunker", "water"
var sel: Dictionary = {"kind": "", "i": -1, "j": -1}

var _drag := false
var _drag_offset := Vector2.ZERO

const HIT_PX := 10.0
const MIN_STATION_GAP := 8.0

const C_HANDLE := Color(0.98, 0.98, 0.97)
const C_LINE := Color(0.125, 0.118, 0.114, 0.75)
const C_SEL := Color(0.776, 0.443, 0.224)
const C_WATER := Color(0.29, 0.42, 0.52)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_def(d: Dictionary) -> void:
	def = d
	sel = {"kind": "", "i": -1, "j": -1}
	tool = ""
	queue_redraw()


# --- Handles -----------------------------------------------------------

# Every handle as [kind, i, j, yard_pos], topmost last.
func _handles() -> Array:
	var out: Array = []
	if def.is_empty():
		return out
	var spine: Array = def.spine
	for i in spine.size():
		var st: Vector3 = spine[i]
		out.append(["spine", i, -1, Vector2(st.x, st.y)])
		out.append(["width", i, -1, Vector2(st.x + st.z * 0.5, st.y)])
	var hazards: Array = def.hazards
	for i in hazards.size():
		var z: Dictionary = hazards[i]
		if z.type == "water":
			var poly: PackedVector2Array = z.poly
			for j in poly.size():
				out.append(["water", i, j, poly[j]])
		else:
			out.append(["bunker", i, -1, z.pos])
	out.append(["green", -1, -1, def.green.pos])
	return out


func _hit(px: Vector2) -> Array:
	var best: Array = []
	var best_d := HIT_PX
	var handles := _handles()
	# Topmost first, so the green wins over a fairway point under it.
	for k in range(handles.size() - 1, -1, -1):
		var h: Array = handles[k]
		var d := map._to_px(h[3]).distance_to(px)
		if d <= best_d:
			best_d = d
			best = h
	return best


func _select(kind: String, i: int = -1, j: int = -1) -> void:
	sel = {"kind": kind, "i": i, "j": j}
	selection_changed.emit()
	queue_redraw()


# --- Input -------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if def.is_empty() or map == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var yard := map._px_to_yard(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if tool != "":
				_place(tool, yard)
				tool = ""
				accept_event()
				return
			var h := _hit(event.position)
			if h.is_empty():
				if event.double_click:
					_add_station(yard)
				else:
					_select("")
			else:
				_select(h[0], h[1], h[2])
				_drag = true
				_drag_offset = h[3] - yard
				# Pin the framing for the length of the drag.
				map.fixed_extent = map._yard_extent()
				about_to_edit.emit()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var h := _hit(event.position)
			if not h.is_empty():
				_delete(h[0], h[1], h[2])
			accept_event()
	elif event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _drag:
		_drag = false
		map.fixed_extent = Rect2()
		edited.emit(true)
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		_move(map._px_to_yard(event.position) + _drag_offset)
		edited.emit(false)
		queue_redraw()
		accept_event()


func _move(p: Vector2) -> void:
	p.x = clampf(p.x, -Course.X_LIMIT, Course.X_LIMIT)
	p.y = clampf(p.y, -20.0, Course.Y_LIMIT)
	var i: int = sel.i
	match sel.kind:
		"spine":
			var spine: Array = def.spine
			var st: Vector3 = spine[i]
			var y := p.y
			if i == 0:
				y = 0.0   # the tee stays on the tee line
			else:
				var lo: float = (spine[i - 1] as Vector3).y + MIN_STATION_GAP
				var hi: float = Course.Y_LIMIT if i == spine.size() - 1 else (spine[i + 1] as Vector3).y - MIN_STATION_GAP
				y = clampf(y, lo, hi)
			spine[i] = Vector3(p.x, y, st.z)
		"width":
			var st: Vector3 = def.spine[i]
			def.spine[i] = Vector3(st.x, st.y, clampf(absf(p.x - st.x) * 2.0, 8.0, 90.0))
		"green":
			def.green.pos = Vector2(p.x, maxf(p.y, Course.MIN_GREEN_Y))
			Course.refresh_yardage(def)
		"bunker":
			def.hazards[i].pos = Vector2(p.x, maxf(p.y, 0.0))
		"water":
			var poly: PackedVector2Array = def.hazards[i].poly
			poly[sel.j] = p
			def.hazards[i].poly = poly


func _add_station(yard: Vector2) -> void:
	var spine: Array = def.spine
	if spine.size() >= Course.MAX_SPINE or yard.y <= MIN_STATION_GAP:
		return
	about_to_edit.emit()
	var at := spine.size()
	for k in spine.size():
		if (spine[k] as Vector3).y > yard.y:
			at = k
			break
	# Borrow the corridor width from the neighbouring point.
	var w: float = (spine[at - 1] as Vector3).z
	spine.insert(at, Vector3(yard.x, yard.y, w))
	_select("spine", at)
	edited.emit(true)


func _place(kind: String, yard: Vector2) -> void:
	about_to_edit.emit()
	var hazards: Array = def.hazards
	if kind == "bunker":
		hazards.append({"type": "bunker", "pos": yard, "radii": Vector2(11, 9), "rot": 0.0})
		_select("bunker", hazards.size() - 1)
	else:
		var poly := PackedVector2Array([
			yard + Vector2(-20, -25), yard + Vector2(20, -25),
			yard + Vector2(20, 25), yard + Vector2(-20, 25)])
		hazards.append({"type": "water", "poly": poly})
		_select("water", hazards.size() - 1, 0)
	edited.emit(true)


func _delete(kind: String, i: int, j: int) -> void:
	match kind:
		"spine":
			# The tee point can't go, and a hole needs two points.
			if i == 0 or def.spine.size() <= 2:
				return
			about_to_edit.emit()
			def.spine.remove_at(i)
		"bunker":
			about_to_edit.emit()
			def.hazards.remove_at(i)
		"water":
			about_to_edit.emit()
			var poly: PackedVector2Array = def.hazards[i].poly
			if poly.size() <= 3:
				def.hazards.remove_at(i)
			else:
				poly.remove_at(j)
				def.hazards[i].poly = poly
		_:
			return
	_select("")
	edited.emit(true)


# Called by the editor's "Delete" button: same rules as a right-click.
func delete_selected() -> void:
	if sel.kind != "":
		_delete(sel.kind, sel.i, sel.j)


# Splits the water edge after the selected corner, for a more detailed
# shoreline.
func add_water_point() -> void:
	if sel.kind != "water":
		return
	var poly: PackedVector2Array = def.hazards[sel.i].poly
	if poly.size() >= Course.MAX_WATER_POINTS:
		return
	about_to_edit.emit()
	var a: Vector2 = poly[sel.j]
	var b: Vector2 = poly[(sel.j + 1) % poly.size()]
	poly.insert(sel.j + 1, (a + b) * 0.5)
	def.hazards[sel.i].poly = poly
	_select("water", sel.i, sel.j + 1)
	edited.emit(true)


# --- Drawing -----------------------------------------------------------

func _draw() -> void:
	if def.is_empty() or map == null or map.hole == null:
		return
	var spine: Array = def.spine

	# The centreline the fairway is built around, on into the green.
	var line := PackedVector2Array()
	for st in spine:
		line.append(map._to_px(Vector2(st.x, st.y)))
	line.append(map._to_px(def.green.pos))
	for k in line.size() - 1:
		_dashed(line[k], line[k + 1], C_LINE)

	for i in spine.size():
		var st: Vector3 = spine[i]
		var c := map._to_px(Vector2(st.x, st.y))
		var l := map._to_px(Vector2(st.x - st.z * 0.5, st.y))
		var r := map._to_px(Vector2(st.x + st.z * 0.5, st.y))
		draw_line(l, r, Color(C_LINE, 0.45), 1.0)
		var tab_sel: bool = sel.kind == "width" and sel.i == i
		draw_rect(Rect2(r - Vector2(4, 4), Vector2(8, 8)), C_SEL if tab_sel else C_HANDLE)
		draw_rect(Rect2(r - Vector2(4, 4), Vector2(8, 8)), C_LINE, false, 1.0)
		_ring(c, 6.5 if i > 0 else 7.5, sel.kind == "spine" and sel.i == i)

	var hazards: Array = def.hazards
	for i in hazards.size():
		var z: Dictionary = hazards[i]
		if z.type == "water":
			var poly: PackedVector2Array = z.poly
			var pts := PackedVector2Array()
			for p in poly:
				pts.append(map._to_px(p))
			pts.append(pts[0])
			draw_polyline(pts, Color(C_WATER, 0.9), 1.5)
			for j in poly.size():
				var on: bool = sel.kind == "water" and sel.i == i and sel.j == j
				var c := map._to_px(poly[j])
				draw_rect(Rect2(c - Vector2(4.5, 4.5), Vector2(9, 9)), C_SEL if on else C_HANDLE)
				draw_rect(Rect2(c - Vector2(4.5, 4.5), Vector2(9, 9)), C_WATER, false, 1.5)
		else:
			_ring(map._to_px(z.pos), 5.5, sel.kind == "bunker" and sel.i == i)

	var g := map._to_px(def.green.pos)
	_ring(g, 8.0, sel.kind == "green")
	draw_arc(g, 12.0, 0, TAU, 24, Color(C_LINE, 0.5), 1.0)

	if tool != "":
		var label := "Click to place a bunker" if tool == "bunker" else "Click to place water"
		draw_string(get_theme_default_font(), Vector2(10, 18), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_SEL)


func _ring(c: Vector2, r: float, selected: bool) -> void:
	draw_circle(c, r, C_SEL if selected else C_HANDLE)
	draw_arc(c, r, 0, TAU, 20, C_LINE, 1.5)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var dir := (b - a) / len
	var t := 0.0
	while t < len:
		draw_line(a + dir * t, a + dir * minf(t + 6.0, len), col, 1.2)
		t += 10.0
