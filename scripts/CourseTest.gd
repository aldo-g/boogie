extends SceneTree

# ---------------------------------------------------------
# COURSE HARNESS — custom courses, end to end. Dev tool, not shipped.
#
#   godot --headless --script res://scripts/CourseTest.gd
#
# Checks:
#   1. the built-in course survives the wire format unchanged — what a
#      client builds from the host's payload is the host's geometry
#   2. the sanitiser turns hostile/garbage data into something playable
#      (or nothing), never a crash
#   3. save -> list -> load round-trips
#   4. the editor overlay's drag / add / delete edits keep a hole valid
#   5. a 3-hole custom course plays to the end for 2 players
#   6. the round payload carries the course and the wind seed to a fresh
#      instance
# ---------------------------------------------------------

var failures: Array = []


func _initialize() -> void:
	_check_builtin_roundtrip()
	_check_sanitiser()
	_check_save_load()
	_check_overlay_edits()
	_check_custom_round()
	_check_payload()
	Course.use_builtin()
	if failures.is_empty():
		print("\nCOURSES: OK")
	else:
		for f in failures:
			print("  !! " + f)
		print("\nCOURSES: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _hole_signature(h: HoleData) -> String:
	return "%s|%s|%s|%d|%d|%.3f|%.3f" % [h.par, h.yardage, h.pin_pos, h.fairway_polygon.size(),
		h.hazards.size(), h.height_at(Vector2(5, 150)), h.height_at(h.pin_pos + Vector2(4, 3))]


func _check_builtin_roundtrip() -> void:
	var wired := Course.from_wire(JSON.parse_string(JSON.stringify(Course.to_wire(Course.builtin()))))
	_expect(wired.holes.size() == 18, "built-in round trip lost holes")
	for n in range(1, 19):
		var a := HoleData.build(HoleData.HOLES[n], n)
		var b := HoleData.build(wired.holes[n - 1], n)
		_expect(_hole_signature(a) == _hole_signature(b), "built-in hole %d changed over the wire" % n)


func _check_sanitiser() -> void:
	_expect(Course.from_wire(null).is_empty(), "null accepted")
	_expect(Course.from_wire({"holes": "nope"}).is_empty(), "string holes accepted")
	_expect(Course.from_wire({"holes": [{"par": 4}]}).is_empty(), "hole without spine accepted")
	var many: Array = []
	for i in 40:
		many.append(Course.to_wire({"holes": [Course.blank_hole(4)]}).holes[0])
	_expect(Course.from_wire({"holes": many}).holes.size() == 18, "more than 18 holes kept")

	var wild := Course.to_wire({"name": "x", "holes": [Course.blank_hole(4)]})
	var h: Dictionary = wild.holes[0]
	h.par = 11
	h.spine = [[9999, 300, 500], [-9999, -50, -3], [0, 120, "w"]]
	h.green = {"pos": [0, 5], "radii": [900, 0], "rot": "spin"}
	h.hazards = [{"type": "water", "poly": [[0, 0], [1, 1]]}, {"type": "bunker", "pos": [1e9, 1e9], "radii": [-5, 99]}]
	h.elev = [[0, 9999, 99]]
	var c := Course.from_wire(wild)
	_expect(not c.is_empty(), "clampable hole rejected")
	if not c.is_empty():
		var s: Dictionary = c.holes[0]
		_expect(s.par == 5, "par not clamped")
		_expect((s.spine[0] as Vector3).y == 0.0, "tee not pinned to y=0")
		_expect(absf((s.spine[2] as Vector3).x) <= Course.X_LIMIT, "spine x not clamped")
		_expect((s.green.pos as Vector2).y >= Course.MIN_GREEN_Y, "green y not clamped")
		_expect(s.hazards.size() == 1, "degenerate water kept")
		_expect(absf((s.elev[0] as Vector3).y) <= 80.0, "elevation not clamped")
		# And it must build and resolve a shot without blowing up.
		var built := HoleData.build(s, 1)
		var res := {"distance": 200.0, "degree": 0, "side": 2, "roll_mult": 1.0, "extra_roll": 0.0}
		var o := ShotResolver.shot_outcome(built, built.tee_pos, Vector2(0, 1), res, {"type": "wood"})
		_expect(o.has("rest"), "sanitised hole can't resolve a shot")


func _check_save_load() -> void:
	var course := {"name": "Harness Test Course", "holes": [Course.blank_hole(3), Course.blank_hole(5)]}
	_expect(Course.save(course) == "", "save failed")
	var path := Course.path_for(course.name)
	var found := false
	for e in Course.list_saved():
		if e.path == path:
			found = true
	_expect(found, "saved course not listed")
	var back := Course.load_file(path)
	_expect(not back.is_empty() and back.holes.size() == 2 and back.name == course.name, "load mismatch")
	_expect(Course.use_file(path) and Course.hole_count() == 2, "use_file failed")
	Course.delete_file(path)
	Course.use_builtin()


func _click(o: CourseEditOverlay, yard: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, dbl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.double_click = dbl
	e.position = o.map._to_px(yard)
	o._gui_input(e)


func _motion(o: CourseEditOverlay, yard: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = o.map._to_px(yard)
	o._gui_input(e)


func _check_overlay_edits() -> void:
	var map := CourseMapView.new()
	map.size = Vector2(400, 800)
	get_root().add_child(map)
	var def := Course.blank_hole(4)
	map.set_hole(HoleData.build(def, 1))
	var o := CourseEditOverlay.new()
	o.map = map
	map.add_child(o)
	o.set_def(def)

	# Drag the middle fairway point sideways and past the next one: it moves
	# across but stays in order.
	var st: Vector3 = def.spine[1]
	_click(o, Vector2(st.x, st.y), true)
	_motion(o, Vector2(st.x + 20, 600))
	_click(o, Vector2(st.x + 20, 600), false)
	var moved: Vector3 = def.spine[1]
	_expect(absf(moved.x - (st.x + 20)) < 1.0, "fairway point didn't move across")
	_expect(moved.y < (def.spine[2] as Vector3).y, "fairway points fell out of order")

	# Tee can't leave the tee line.
	_click(o, Vector2(0, 0), true)
	_motion(o, Vector2(10, 60))
	_click(o, Vector2(10, 60), false)
	_expect((def.spine[0] as Vector3).y == 0.0, "tee left y=0")

	# Double-click adds a point; right-click removes it again.
	var before: int = def.spine.size()
	_click(o, Vector2(-5, 100), true, MOUSE_BUTTON_LEFT, true)
	_expect(def.spine.size() == before + 1, "double-click didn't add a fairway point")
	map.set_hole(HoleData.build(def, 1))
	_click(o, Vector2(-5, 100), true, MOUSE_BUTTON_RIGHT)
	_expect(def.spine.size() == before, "right-click didn't delete the point")

	# Place a bunker and water with the tools.
	o.tool = "bunker"
	_click(o, Vector2(30, 250), true)
	o.tool = "water"
	_click(o, Vector2(-40, 300), true)
	_expect(def.hazards.size() == 2, "tools didn't place hazards")
	o.add_water_point()
	_expect((def.hazards[1].poly as PackedVector2Array).size() == 5, "water point not added")

	# Moving the green updates the yardage.
	_click(o, def.green.pos, true)
	_motion(o, Vector2(0, 420))
	_click(o, Vector2(0, 420), false)
	_expect(int(def.yardage) == 420, "yardage didn't follow the green")

	# The edited hole still builds and survives the sanitiser.
	var wired := Course.from_wire(Course.to_wire({"name": "e", "holes": [def]}))
	_expect(not wired.is_empty() and wired.holes[0].hazards.size() == 2, "edited hole failed the sanitiser")
	map.free()


func _play_round(main) -> bool:
	main.map_view.skip_animation = true
	var actions := 0
	while main.state != main.State.DONE and actions < 50000:
		actions += 1
		match main.state:
			main.State.CLUB_SELECT:
				main.on_club_select(randi() % main.hand.size())
			main.State.AIM:
				main._on_aim_picked(main.map_view.aim_target)
			main.State.FORM_DRAW:
				main.on_form_pick(randi() % main.current_form_options.size())
			main.State.DRAFT:
				main.on_draft_pick(randi() % main.current_draft_options.size())
			main.State.DISCARD_FOR_DRAFT, main.State.DISCARD_FOR_HAZARD:
				main.on_discard_pick(randi() % main.hand.size())
			main.State.PUTTING:
				main.on_putt_stopped("sunk" if randf() < 0.45 else "miss", randf())
			_:
				return false
	return main.state == main.State.DONE


func _new_main(count: int):
	GameSetup.reset_to_local(count)
	var main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(main)
	main.player_count = count
	main.build_ui()
	return main


func _check_custom_round() -> void:
	var h1 := Course.blank_hole(4)
	h1.hazards.append({"type": "water", "poly": PackedVector2Array([Vector2(-60, 150), Vector2(60, 150), Vector2(60, 190), Vector2(-60, 190)])})
	Course.use(Course.from_wire(Course.to_wire({"name": "Three Holer",
		"holes": [h1, Course.blank_hole(3), Course.blank_hole(5)]})))
	var main = _new_main(2)
	main.init_game()
	main.start_hole()
	var done := _play_round(main)
	_expect(done, "3-hole custom round didn't finish")
	for p in main.players:
		_expect(p.round_scores.size() == 3, "%s scored %d holes on a 3-hole course" % [p.name, p.round_scores.size()])
	main.free()


func _check_payload() -> void:
	Course.use(Course.from_wire(Course.to_wire({"name": "Payload Course",
		"holes": [Course.blank_hole(3), Course.blank_hole(4)]})))
	var host = _new_main(2)
	host.init_game()
	var payload: Dictionary = host.build_round_payload()
	var host_seed: int = host.wind_seed
	host.free()
	# A fresh peer on the built-in course adopts the host's.
	Course.use_builtin()
	var client = _new_main(2)
	client.apply_round_payload(JSON.parse_string(JSON.stringify(payload)))
	_expect(Course.active_name == "Payload Course" and Course.hole_count() == 2,
		"payload didn't carry the course (got %s, %d holes)" % [Course.active_name, Course.hole_count()])
	_expect(client.wind_seed == host_seed, "payload didn't carry the wind seed")
	_expect(Wind.for_hole(client.wind_seed, 2) == Wind.for_hole(host_seed, 2), "wind differs between peers")
	client.free()
