extends Control

# ---------------------------------------------------------
# COURSE EDITOR
# Build a course of 1-18 holes, save it, and play it.
#
#   left   — the holes: pick one, add, duplicate, reorder, delete
#   centre — the hole map with editing handles (CourseEditOverlay), and
#            the elevation strip under it, both live
#   right  — par, add bunker/water, the selected thing's numbers, the
#            green, and the elevation stations
#
# The map is the real CourseMapView and the hole is built by the real
# HoleData.build(), so what you see here is exactly what plays.
#
# Courses save as JSON under user://courses (see Course.gd). The course in
# progress also survives a test round in a static, so "Test play" and the
# round's Editor button bring you back to where you were, saved or not.
# ---------------------------------------------------------

const TITLE_SCENE := "res://scenes/Title.tscn"
const MAIN_SCENE := "res://scenes/Main.tscn"
const UNDO_LIMIT := 60

static var _session: Dictionary = {}   # { course, index, dirty } across a test round

var course: Dictionary = {}    # runtime-shaped: { name, holes }
var index := 0                 # 0-based hole being edited
var dirty := false
var _undo: Array = []

var map: CourseMapView
var overlay: CourseEditOverlay
var name_field: LineEdit
var status: Label
var hole_list: VBoxContainer
var props: VBoxContainer
var open_menu: MenuButton
var _building_props := false


func _ready() -> void:
	if not _session.is_empty():
		course = _session.course
		index = _session.index
		dirty = _session.dirty
		_session = {}
	elif not Course.is_builtin():
		course = Course.active()
	else:
		course = {"name": "New course", "holes": [Course.blank_hole(4), Course.blank_hole(3), Course.blank_hole(5)]}
		dirty = true
	index = clampi(index, 0, course.holes.size() - 1)
	_build_ui()
	_show_hole(true)


# --- Layout ------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BogeyTheme.PARCHMENT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# Header: title, name, file actions.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)
	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 0)
	title_col.add_child(BogeyUI.heading("Course editor", 24))
	title_col.add_child(BogeyUI.kicker("Build · save · play"))
	title_col.custom_minimum_size = Vector2(230, 0)
	head.add_child(title_col)

	name_field = BogeyUI.style_line_edit(LineEdit.new())
	name_field.text = str(course.name)
	name_field.max_length = 40
	name_field.placeholder_text = "Course name"
	name_field.custom_minimum_size = Vector2(300, 42)
	name_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_field.text_changed.connect(func(t):
		course.name = t
		_mark_dirty())
	head.add_child(name_field)

	head.add_child(_btn("New", _on_new))
	open_menu = MenuButton.new()
	open_menu.text = "Open"
	open_menu.flat = false
	BogeyUI.style_button(open_menu)
	open_menu.custom_minimum_size = Vector2(0, 42)
	open_menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	open_menu.about_to_popup.connect(_fill_open_menu)
	open_menu.get_popup().id_pressed.connect(_on_open_picked)
	head.add_child(open_menu)
	head.add_child(_btn("Save", _on_save))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	status = BogeyUI.body("", 13, BogeyTheme.NEUTRAL_700)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(status)
	head.add_child(_btn("Test play", _on_test_play, true))
	head.add_child(_btn("Back", _on_back))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# Left: holes.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(BogeyUI.kicker("Holes"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	hole_list = VBoxContainer.new()
	hole_list.add_theme_constant_override("separation", 4)
	hole_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hole_list)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for spec in [["Add hole", _on_add_hole], ["Duplicate", _on_duplicate_hole],
			["Move up", _on_move_hole.bind(-1)], ["Move down", _on_move_hole.bind(1)]]:
		var b := _btn(spec[0], spec[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	var del := _btn("Delete hole", _on_delete_hole)
	left.add_child(del)

	# Centre: the hole.
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 8)
	body.add_child(centre)
	centre.add_child(BogeyUI.body(
		"Drag to move · drag the square tabs to widen the fairway · double-click to add a fairway point · right-click to delete · Ctrl+Z to undo",
		12, BogeyTheme.NEUTRAL_600))
	map = CourseMapView.new()
	var plate := BogeyUI.plate(map)
	plate.custom_minimum_size = Vector2(380, 0)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(plate)
	overlay = CourseEditOverlay.new()
	overlay.map = map
	map.add_child(overlay)
	overlay.edited.connect(_on_overlay_edited)
	overlay.selection_changed.connect(_rebuild_props)
	overlay.about_to_edit.connect(_push_undo)
	var profile := ElevationProfileView.new()
	profile.map = map
	profile.custom_minimum_size = Vector2(380, 74)
	profile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(profile)
	plate.resized.connect(func(): profile.custom_minimum_size.x = plate.size.x)

	# Right: properties.
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(360, 0)
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right_scroll)
	props = VBoxContainer.new()
	props.add_theme_constant_override("separation", 8)
	props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(props)


func _btn(text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BogeyUI.style_button(b, primary, 14)
	b.pressed.connect(cb)
	return b


# --- The hole on screen ------------------------------------------------

func _hole() -> Dictionary:
	return course.holes[index]


# `bake` = false while a handle is mid-drag (see CourseMapView.set_hole).
func _show_hole(bake: bool) -> void:
	var h := HoleData.build(_hole(), index + 1)
	map.set_hole(h, bake)
	map.set_ball(h.tee_pos, [])
	map.set_aim_target(h.tee_pos)
	if overlay.def != _hole():
		overlay.set_def(_hole())
	overlay.queue_redraw()
	if bake:
		_rebuild_hole_list()
		_rebuild_props()
	_update_status()


func _on_overlay_edited(final: bool) -> void:
	_mark_dirty()
	_show_hole(final)


func _rebuild_hole_list() -> void:
	for c in hole_list.get_children():
		c.queue_free()
	for i in course.holes.size():
		var h: Dictionary = course.holes[i]
		var b := Button.new()
		b.text = "%d    Par %d    %d yds" % [i + 1, int(h.par), int(h.yardage)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 36)
		BogeyUI.style_button(b, i == index, 14)
		b.pressed.connect(_select_hole.bind(i))
		hole_list.add_child(b)
	var total := BogeyUI.body(Course.summary(course), 12, BogeyTheme.NEUTRAL_600)
	hole_list.add_child(total)


func _select_hole(i: int) -> void:
	Sound.play("ui_click")
	index = i
	_show_hole(true)


func _update_status() -> void:
	var where := "Unsaved changes" if dirty else "Saved"
	status.text = where


func _mark_dirty() -> void:
	dirty = true
	_update_status()


# --- Properties panel --------------------------------------------------

func _rebuild_props() -> void:
	if props == null:
		return
	_building_props = true
	for c in props.get_children():
		c.queue_free()
	var h := _hole()

	props.add_child(BogeyUI.heading("Hole %d" % (index + 1), 20))
	props.add_child(BogeyUI.body("%d yards · flag %+d ft from the tee" % [
		int(h.yardage), map.hole.feet_above_tee(map.hole.pin_pos)], 13))

	var par_row := HBoxContainer.new()
	par_row.add_theme_constant_override("separation", 6)
	props.add_child(par_row)
	par_row.add_child(_caption("Par"))
	for p in [3, 4, 5]:
		var b := _btn(str(p), _on_par.bind(p), int(h.par) == p)
		b.custom_minimum_size = Vector2(52, 36)
		par_row.add_child(b)

	props.add_child(_section("Add"))
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	props.add_child(add_row)
	var bunker_btn := _btn("Bunker", _arm_tool.bind("bunker"), overlay.tool == "bunker")
	bunker_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(bunker_btn)
	var water_btn := _btn("Water", _arm_tool.bind("water"), overlay.tool == "water")
	water_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(water_btn)

	_build_selected_props()

	props.add_child(_section("Green"))
	var g: Dictionary = h.green
	props.add_child(_num_row("Width", g.radii.x * 2.0, 16, 80, 1, func(v):
		g.radii = Vector2(v * 0.5, g.radii.y)))
	props.add_child(_num_row("Depth", g.radii.y * 2.0, 16, 80, 1, func(v):
		g.radii = Vector2(g.radii.x, v * 0.5)))
	props.add_child(_num_row("Rotation °", g.rot, -90, 90, 1, func(v): g.rot = v))
	props.add_child(_num_row("Falls right %", h.green_tilt.x, -4, 4, 0.5, func(v):
		h.green_tilt = Vector2(v, h.green_tilt.y)))
	props.add_child(_num_row("Falls to tee %", -h.green_tilt.y, -4, 4, 0.5, func(v):
		h.green_tilt = Vector2(h.green_tilt.x, -v)))

	_build_elevation_props()
	_building_props = false


func _build_selected_props() -> void:
	var s: Dictionary = overlay.sel
	if s.kind == "":
		return
	var h := _hole()
	var names := {"spine": "Fairway point", "width": "Fairway point", "green": "Green",
		"bunker": "Bunker", "water": "Water"}
	props.add_child(_section("Selected · %s" % names.get(s.kind, s.kind)))
	match s.kind:
		"spine", "width":
			var i: int = s.i
			var st: Vector3 = h.spine[i]
			props.add_child(_num_row("Fairway width", st.z, 8, 90, 1, func(v):
				var cur: Vector3 = h.spine[i]
				h.spine[i] = Vector3(cur.x, cur.y, v)))
			if i == 0:
				props.add_child(BogeyUI.body("The tee — this point always sits on the tee line.", 12))
		"bunker":
			var z: Dictionary = h.hazards[s.i]
			props.add_child(_num_row("Width", z.radii.x * 2.0, 8, 50, 1, func(v):
				z.radii = Vector2(v * 0.5, z.radii.y)))
			props.add_child(_num_row("Depth", z.radii.y * 2.0, 8, 50, 1, func(v):
				z.radii = Vector2(z.radii.x, v * 0.5)))
			props.add_child(_num_row("Rotation °", z.rot, -90, 90, 1, func(v): z.rot = v))
		"water":
			props.add_child(_btn("Add a shore point", func(): overlay.add_water_point()))
	if s.kind != "green":
		var del := _btn("Delete", func(): overlay.delete_selected())
		props.add_child(del)


func _build_elevation_props() -> void:
	var h := _hole()
	props.add_child(_section("Elevation"))
	props.add_child(BogeyUI.body(
		"Heights along the hole, eased between points. Cross-fall tilts the fairway: + falls to the right.", 12))
	var head := HBoxContainer.new()
	for t in ["Yards out", "Height ft", "Cross %", ""]:
		var l := _caption(t)
		l.custom_minimum_size = Vector2(80, 0)
		head.add_child(l)
	props.add_child(head)

	var elev: Array = h.elev
	for i in elev.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		props.add_child(row)
		var st: Vector3 = elev[i]
		row.add_child(_spin(st.x, 0, Course.Y_LIMIT, 5, func(v):
			var c: Vector3 = elev[i]
			elev[i] = Vector3(v, c.y, c.z), true))
		row.add_child(_spin(st.y, -80, 80, 1, func(v):
			var c: Vector3 = elev[i]
			elev[i] = Vector3(c.x, v, c.z)))
		row.add_child(_spin(st.z, -8, 8, 0.5, func(v):
			var c: Vector3 = elev[i]
			elev[i] = Vector3(c.x, c.y, v)))
		var x := _btn("×", _on_remove_elev.bind(i))
		x.custom_minimum_size = Vector2(36, 32)
		row.add_child(x)
	if elev.size() < Course.MAX_ELEV:
		props.add_child(_btn("Add elevation point", _on_add_elev))


func _section(text: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	col.add_child(gap)
	col.add_child(BogeyUI.hairline(0.15))
	col.add_child(BogeyUI.kicker(text))
	return col


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", BogeyTheme.NEUTRAL_700)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _num_row(label: String, value: float, lo: float, hi: float, step: float, apply: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _caption(label)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(_spin(value, lo, hi, step, apply))
	return row


# `resort` re-sorts the elevation stations after the change (yards out
# moved), which reorders the rows — so the panel rebuilds.
func _spin(value: float, lo: float, hi: float, step: float, apply: Callable, resort: bool = false) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = value
	sb.custom_minimum_size = Vector2(96, 0)
	BogeyUI.style_line_edit(sb.get_line_edit(), 13)
	sb.value_changed.connect(func(v):
		if _building_props:
			return
		_push_undo()
		apply.call(v)
		if resort:
			_hole().elev.sort_custom(func(a, b): return a.x < b.x)
		_mark_dirty()
		var h := HoleData.build(_hole(), index + 1)
		map.set_hole(h, true)
		overlay.queue_redraw()
		if resort:
			_rebuild_props.call_deferred())
	return sb


# --- Hole actions ------------------------------------------------------

func _on_par(p: int) -> void:
	_push_undo()
	_hole().par = p
	_mark_dirty()
	_show_hole(true)


func _arm_tool(t: String) -> void:
	overlay.tool = "" if overlay.tool == t else t
	overlay.queue_redraw()
	_rebuild_props()


func _on_add_elev() -> void:
	_push_undo()
	var elev: Array = _hole().elev
	var last_x: float = (elev[elev.size() - 1] as Vector3).x if not elev.is_empty() else 0.0
	var y: float = minf(last_x + 50.0, Course.Y_LIMIT)
	elev.append(Vector3(y, map.hole.height_at(Vector2(map.hole.centre_x_at(y), y)) * HoleData.FEET_PER_YARD, 0))
	_mark_dirty()
	_show_hole(true)


func _on_remove_elev(i: int) -> void:
	_push_undo()
	_hole().elev.remove_at(i)
	_mark_dirty()
	_show_hole(true)


func _on_add_hole() -> void:
	if course.holes.size() >= Course.MAX_HOLES:
		status.text = "A course holds 18 holes at most."
		return
	_push_undo()
	course.holes.insert(index + 1, Course.blank_hole(4))
	index += 1
	_mark_dirty()
	_show_hole(true)


func _on_duplicate_hole() -> void:
	if course.holes.size() >= Course.MAX_HOLES:
		status.text = "A course holds 18 holes at most."
		return
	_push_undo()
	course.holes.insert(index + 1, _hole().duplicate(true))
	index += 1
	_mark_dirty()
	_show_hole(true)


func _on_move_hole(step: int) -> void:
	var to := index + step
	if to < 0 or to >= course.holes.size():
		return
	_push_undo()
	var h = course.holes[index]
	course.holes.remove_at(index)
	course.holes.insert(to, h)
	index = to
	_mark_dirty()
	_show_hole(true)


func _on_delete_hole() -> void:
	if course.holes.size() <= 1:
		status.text = "A course needs at least one hole."
		return
	_push_undo()
	course.holes.remove_at(index)
	index = mini(index, course.holes.size() - 1)
	_mark_dirty()
	_show_hole(true)


# --- Undo --------------------------------------------------------------

func _push_undo() -> void:
	_undo.append({"course": course.duplicate(true), "index": index})
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed):
		_undo_last()
		get_viewport().set_input_as_handled()


func _undo_last() -> void:
	if _undo.is_empty():
		return
	var snap: Dictionary = _undo.pop_back()
	course = snap.course
	index = clampi(snap.index, 0, course.holes.size() - 1)
	name_field.text = str(course.name)
	overlay.set_def({})
	_mark_dirty()
	_show_hole(true)


# --- File actions ------------------------------------------------------

func _on_new() -> void:
	_push_undo()
	course = {"name": "New course", "holes": [Course.blank_hole(4)]}
	index = 0
	name_field.text = course.name
	overlay.set_def({})
	_mark_dirty()
	_show_hole(true)


func _on_save() -> void:
	var name := str(course.name).strip_edges()
	if name == "" or name == Course.BUILTIN_NAME:
		status.text = "Give the course its own name first."
		return
	for h in course.holes:
		Course.refresh_yardage(h)
	var err := Course.save(course)
	if err != "":
		status.text = err
		return
	Sound.play("ui_confirm")
	dirty = false
	_update_status()
	status.text = "Saved to %s" % Course.path_for(name).get_file()
	_rebuild_hole_list()


func _fill_open_menu() -> void:
	var pop := open_menu.get_popup()
	pop.clear()
	pop.add_item("Copy of %s" % Course.BUILTIN_NAME, 0)
	var saved := Course.list_saved()
	if not saved.is_empty():
		pop.add_separator()
	for i in saved.size():
		pop.add_item(str(saved[i].name), i + 1)
	pop.set_meta("saved", saved)


func _on_open_picked(id: int) -> void:
	var pop := open_menu.get_popup()
	var saved: Array = pop.get_meta("saved", [])
	var loaded: Dictionary
	if id == 0:
		loaded = Course.builtin()
		loaded.name = "%s copy" % Course.BUILTIN_NAME
	elif id - 1 < saved.size():
		loaded = Course.load_file(str(saved[id - 1].path))
	if loaded.is_empty():
		status.text = "Couldn't open that course."
		return
	_push_undo()
	course = loaded
	index = 0
	name_field.text = str(course.name)
	overlay.set_def({})
	dirty = id == 0
	_show_hole(true)


func _on_test_play() -> void:
	Sound.play("ui_confirm")
	for h in course.holes:
		Course.refresh_yardage(h)
	# Round-trip through the sanitiser, so a test round plays exactly what
	# a saved file or a network peer would.
	var playable := Course.from_wire(Course.to_wire(course))
	if playable.is_empty():
		status.text = "This course can't be played yet."
		return
	_session = {"course": course.duplicate(true), "index": index, "dirty": dirty}
	Course.use(playable)
	GameSetup.reset_to_local(1)
	GameSetup.return_to_editor = true
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_back() -> void:
	Sound.play("ui_back")
	# Leave the title on a playable course: the saved version of this one
	# if it's been saved, else whatever was chosen before.
	if not dirty and str(course.name) != Course.BUILTIN_NAME:
		Course.use_file(Course.path_for(str(course.name)))
	get_tree().change_scene_to_file(TITLE_SCENE)
