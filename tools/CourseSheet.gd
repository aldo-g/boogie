extends Node

# Dev-only contact sheet: paints every hole of a course side by side and
# writes one PNG per course. Not shipped with the game.
#
# It's how you look at a whole course at once — after reshaping holes, or
# changing a terrain's palette or scenery in CourseTheme — without playing
# eighteen holes to see them. The holes are the real CourseMapView on the
# real HoleData, so the sheet is what the game draws.
#
#   godot --path . res://tools/CourseSheet.tscn
#
#   SHEET_COURSE=mirage-mesa   one course (a CourseLibrary id; default: all)
#   SHEET_FILE=/path/x.json    a course file instead (e.g. one saved by the editor)
#   SHEET_HOLES=1-6            only these holes
#   SHEET_COLS=6               holes per row
#   SHEET_W=300 SHEET_H=470    size of one hole's plate, in pixels
#   SHEET_OUT=/some/dir        where the PNGs go (default user://sheets)

const LABEL_H := 26


func _ready() -> void:
	var out_dir := _env("SHEET_OUT", "user://sheets")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var courses: Array = []
	var file := _env("SHEET_FILE", "")
	if file != "":
		var c := Course.load_file(file)
		if c.is_empty():
			printerr("CourseSheet: nothing playable in %s" % file)
		else:
			c["id"] = file.get_file().get_basename()
			courses.append(c)
	else:
		var want := _env("SHEET_COURSE", "")
		for c in CourseLibrary.all():
			if want == "" or c.id == want:
				courses.append(c)
	if courses.is_empty():
		printerr("CourseSheet: no course to draw")
	for c in courses:
		await _sheet(c, out_dir)
	get_tree().quit()


func _sheet(course: Dictionary, out_dir: String) -> void:
	var holes: Array = course.holes
	var first := 1
	var last := holes.size()
	var span := _env("SHEET_HOLES", "").split("-", false)
	if span.size() >= 1:
		first = clampi(int(span[0]), 1, holes.size())
		last = clampi(int(span[span.size() - 1]), first, holes.size())
	var count := last - first + 1
	var cols: int = clampi(int(_env("SHEET_COLS", "6")), 1, count)
	var rows: int = ceili(float(count) / float(cols))
	var cell := Vector2(float(_env("SHEET_W", "300")), float(_env("SHEET_H", "470")))
	var theme := str(course.get("theme", CourseTheme.DEFAULT))

	var vp := SubViewport.new()
	vp.size = Vector2i(int(cell.x) * cols, int(cell.y + LABEL_H) * rows + 40)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	add_child(vp)

	var bg := ColorRect.new()
	bg.color = BogeyTheme.PARCHMENT
	bg.size = Vector2(vp.size)
	vp.add_child(bg)

	var par := 0
	var yards := 0
	for h in holes:
		par += int(h.par)
		yards += int(h.yardage)
	var title := BogeyUI.heading("%s  ·  %s  ·  par %d  ·  %d yards" % [
		course.name, CourseTheme.label(theme), par, yards], 20)
	title.position = Vector2(12, 6)
	vp.add_child(title)

	for k in count:
		var n := first + k
		var origin := Vector2((k % cols) * cell.x, 40 + (k / cols) * (cell.y + LABEL_H))
		var d: Dictionary = holes[n - 1]
		var label := BogeyUI.body("%d   ·   par %d   ·   %d yds" % [n, int(d.par), int(d.yardage)], 14, BogeyTheme.INK)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.position = origin + Vector2(10, 2)
		vp.add_child(label)
		var map := CourseMapView.new()
		map.position = origin + Vector2(4, LABEL_H)
		map.size = cell - Vector2(8, 4)
		vp.add_child(map)
		var hole := HoleData.build(d, n, theme)
		map.set_hole(hole)
		map.set_ball(hole.tee_pos, [])
		map.set_aim_target(hole.tee_pos)

	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out_dir, str(course.id)]
	vp.get_texture().get_image().save_png(path)
	print("SHEET ", path, " ", vp.size.x, "x", vp.size.y)
	vp.queue_free()


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return fallback if v.is_empty() else v
