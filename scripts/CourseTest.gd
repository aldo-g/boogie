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
#   6. the round payload carries the course, its terrain and the wind seed
#      to a fresh instance
#   7. terrain: it survives the wire, garbage falls back to parkland, the
#      hole carries its firmness, and parkland plays exactly as it always
#      did (same wind, same roll)
#   8. the game's own courses: each file loads, is unchanged by the
#      sanitiser (so host and client play the same course), every hole is
#      sound — pin on the green, bunkers not buried, shapes drawable, the
#      lie of the land bending the contours without moving the line of
#      play — and a shipped course is recognised as itself (and keeps its
#      records key) when it arrives from an online host
#   9. what builds through a round: the wind gets up and the pins get
#      tucked away — always on the green with room round them, the same
#      for a given seed, different from one round to the next
#  10. the map draws promptly on a plate with no room for it (the editor's
#      first frame) instead of planting scenery to the horizon
# ---------------------------------------------------------

var failures: Array = []


func _initialize() -> void:
	_check_builtin_roundtrip()
	_check_sanitiser()
	_check_save_load()
	_check_overlay_edits()
	_check_custom_round()
	_check_payload()
	_check_terrain()
	_check_shipped_courses()
	_check_round_builds()
	await _check_no_room_to_draw()
	Course.use_builtin()
	if failures.is_empty():
		print("\nCOURSES: OK")
	else:
		for f in failures:
			print("  !! " + f)
		print("\nCOURSES: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)


# What changes from round to round and builds through one: the wind gets
# up and the pins get tucked away (Course.late, Wind, Pins).
func _check_round_builds() -> void:
	Course.use_builtin()
	# Nothing builds through the opening holes; it all has by the last.
	for n in range(1, 6):
		_expect(Course.late(n) == 0.0, "hole %d of 18 is already late in the round" % n)
		_expect(Wind.for_hole(77, n) == Wind.for_hole(77, n, "", 0.0), "the wind has got up by hole %d" % n)
	for n in range(6, 19):
		_expect(Course.late(n) > Course.late(n - 1), "hole %d is no later in the round than hole %d" % [n, n - 1])
	_expect(is_equal_approx(Course.late(18), 1.0), "the last hole isn't the end of the round")
	Course.use({"name": "One", "holes": [Course.blank_hole(3)]})
	_expect(Course.late(1) == 0.0, "a one-hole course builds")
	Course.use({"name": "Three", "holes": [Course.blank_hole(4), Course.blank_hole(3), Course.blank_hole(5)]})
	_expect(Course.late(1) == 0.0 and Course.late(2) > 0.0 and is_equal_approx(Course.late(3), 1.0),
		"a three-hole course doesn't build across its three holes")
	Course.use_builtin()

	# The wind gets up: more of it on the last hole than the first, and
	# never more than the terrain's ceiling.
	var first := 0.0
	var last := 0.0
	var most := 0.0
	for seed in range(1, 601):
		first += Wind.for_hole(seed, 1).length()
		last += Wind.for_hole(seed, 18).length()
		most = maxf(most, Wind.for_hole(seed, 18).length())
	_expect(last > first * 1.25, "the wind doesn't get up through the round (%.1f mph on the 1st, %.1f on the 18th)" % [first / 600.0, last / 600.0])
	_expect(most <= Wind.MAX_MPH + 0.5, "a late hole blew %.0f mph, past the ceiling" % most)

	# Pins, on every hole of every course the game ships.
	for c in CourseLibrary.all():
		Course.use_shipped(c.id)
		for n in range(1, Course.hole_count() + 1):
			var where := "%s hole %d" % [c.id, n]
			var bare := HoleData.hole(n)
			_expect(bare.pin_pos == bare.green_pos and bare.pin_name == "", "%s: a bare hole has a cut pin" % where)
			var spots := {}
			var off_middle := 0.0
			for seed in range(1, 31):
				var h := HoleData.for_round(n, seed)
				spots[h.pin_pos] = true
				off_middle += h.pin_pos.distance_to(h.green_pos)
				_expect(h.wind == Wind.for_hole(seed, n) and h.pin_pos == Pins.for_hole(seed, n, bare),
					"%s: for_round() isn't the wind and the pin of that seed" % where)
				_expect(h.terrain_at(h.pin_pos) == "green", "%s: seed %d cuts the hole off the green" % [where, seed])
				_expect(h.pin_name != "", "%s: the pin has no name" % where)
				if h.pin_pos != h.green_pos:
					for k in 8:
						var edge: Vector2 = h.pin_pos + Vector2.from_angle(TAU * float(k) / 8.0) * (HoleData.PIN_EDGE_MARGIN - 0.1)
						if not Geometry2D.is_point_in_polygon(edge, h.green_polygon):
							_expect(false, "%s: seed %d cuts the hole within %d yards of the edge" % [where, seed, int(HoleData.PIN_EDGE_MARGIN)])
							break
				# The green is the same green wherever the hole is cut on it.
				var probe: Vector2 = h.green_pos + Vector2(3, -2)
				_expect(is_equal_approx(h.height_at(probe), bare.height_at(probe)), "%s: moving the pin moved the green" % where)
			_expect(spots.size() >= 3, "%s: only %d pin positions in 30 rounds" % [where, spots.size()])
			if n == Course.hole_count():
				_expect(not spots.has(bare.green_pos), "%s: a pin in the middle on the last hole" % where)

	# Tucked away late: further from the middle, and toward the trouble.
	Course.use_builtin()
	var early_off := 0.0
	var late_off := 0.0
	for n in range(1, 19):
		var bare := HoleData.hole(n)
		for seed in range(1, 41):
			early_off += Pins.for_hole(seed, n, bare, 0.0).distance_to(bare.green_pos)
			late_off += Pins.for_hole(seed, n, bare, 1.0).distance_to(bare.green_pos)
	_expect(late_off > early_off * 1.4, "late pins aren't tucked further out than early ones (%.1f vs %.1f yds)" % [
		late_off / 720.0, early_off / 720.0])
	var guarded_holes := 0
	for n in range(1, 19):
		var bare := HoleData.hole(n)
		var sides := Pins.guarded(bare, Pins.DEPTH_LATE)
		if sides.is_empty():
			continue
		guarded_holes += 1
		var late_spots: Array = []
		var early_spots: Array = []
		for side in sides:
			late_spots.append(bare.pin_spot(Pins.SPOTS[side], Pins.DEPTH_LATE))
			early_spots.append(bare.pin_spot(Pins.SPOTS[side], Pins.DEPTH_EARLY))
		var late_hits := 0
		var early_hits := 0
		for seed in range(1, 201):
			var late_pin := Pins.for_hole(seed, n, bare, 1.0)
			var early_pin := Pins.for_hole(seed, n, bare, 0.0)
			for spot in late_spots:
				if late_pin.is_equal_approx(spot):
					late_hits += 1
					break
			for spot in early_spots:
				if early_pin.is_equal_approx(spot):
					early_hits += 1
					break
		# By chance alone a pin is on one of k guarded spots k times in 9
		# early on; by the last hole 70% are put there on purpose.
		_expect(late_hits >= 130, "hole %d: a last-hole pin is on the guarded side only %d times in 200" % [n, late_hits])
		_expect(early_hits <= 100, "hole %d: an opening-hole pin is on the guarded side %d times in 200" % [n, early_hits])
	_expect(guarded_holes >= 6, "only %d of the built-in greens have anything guarding them" % guarded_holes)

	# Named the way a golfer would say it.
	var named := HoleData.hole(1)
	for pair in [[Vector2(0, -8), "front"], [Vector2(0, 8), "back"], [Vector2(-8, 0), "left"], [Vector2(8, 0), "right"],
			[Vector2(-6, 6), "back left"], [Vector2(6, -6), "front right"], [Vector2(0.5, 0.5), "middle"]]:
		named.pin_pos = named.green_pos + pair[0]
		_expect(Pins.describe(named) == pair[1], "a pin %s off the middle is called '%s'" % [pair[0], Pins.describe(named)])


# The painted map has to cope with having no room. The course editor's
# first layout frame gives it a sliver 13 pixels tall; the scale is then
# nothing, and the scenery was once planted across every yard the sliver
# claimed to show — billions of cells, and an editor that never opened.
# (_draw() runs headless too, so this draws for real. If it ever regresses
# the likely symptom is this harness hanging here, not a tidy failure.)
func _check_no_room_to_draw() -> void:
	var hole := HoleData.build(Course.blank_hole(4), 1)
	for plate in [Vector2(368, 13), Vector2(20, 400), Vector2(2400, 40), Vector2(2400, 60), Vector2(368, 580)]:
		var map := CourseMapView.new()
		map.size = plate
		get_root().add_child(map)
		map.set_hole(hole)
		var began := Time.get_ticks_msec()
		await process_frame
		await process_frame
		var took := Time.get_ticks_msec() - began
		_expect(took < 3000, "drawing the map on a %dx%d plate took %d ms" % [int(plate.x), int(plate.y), took])
		map.queue_free()


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
				main.on_club_select(main.playable_club_indices().pick_random())
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
	Course.use(Course.from_wire(Course.to_wire({"name": "Payload Course", "theme": "links",
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
	# The terrain comes with it: the wind range and the firmness both hang
	# off it, so a client on the wrong terrain would play a different round.
	_expect(Course.active_theme == "links" and HoleData.hole(1).roll_scale == CourseTheme.roll_scale("links"),
		"payload didn't carry the terrain (got %s)" % Course.active_theme)
	_expect(client.wind_seed == host_seed, "payload didn't carry the wind seed")
	_expect(Wind.for_hole(client.wind_seed, 2) == Wind.for_hole(host_seed, 2), "wind differs between peers")
	client.free()


func _run_out(hole: HoleData) -> float:
	var res := {"distance": 200.0, "degree": 0, "side": 2, "roll_mult": 1.0, "extra_roll": 0.0}
	var o := ShotResolver.shot_outcome(hole, hole.tee_pos, Vector2(0, 1), res, {"type": "wood"}, false)
	return (o.rest as Vector2).distance_to(o.carry_pos)


func _check_terrain() -> void:
	# Over the wire, and through the sanitiser.
	var c := {"name": "Terrain Test", "theme": "links", "holes": [Course.blank_hole(4)]}
	var wire: Dictionary = JSON.parse_string(JSON.stringify(Course.to_wire(c)))
	_expect(Course.from_wire(wire).theme == "links", "terrain lost over the wire")
	wire["theme"] = "the moon"
	_expect(Course.from_wire(wire).theme == CourseTheme.DEFAULT, "unknown terrain not defaulted")
	wire["theme"] = 7
	_expect(Course.from_wire(wire).theme == CourseTheme.DEFAULT, "non-string terrain not defaulted")
	wire.erase("theme")
	_expect(Course.from_wire(wire).theme == CourseTheme.DEFAULT, "a file with no terrain isn't parkland")

	# The active course hands its terrain to every hole it builds.
	Course.use(c)
	var h := HoleData.hole(1)
	_expect(Course.active_theme == "links" and h.theme == "links", "the hole didn't take the course's terrain")
	_expect(is_equal_approx(h.roll_scale, CourseTheme.roll_scale("links")), "the hole doesn't carry its firmness")
	_expect(Course.active().theme == "links", "active() dropped the terrain")
	Course.use_builtin()
	_expect(Course.active_theme == CourseTheme.DEFAULT and HoleData.hole(1).roll_scale == 1.0,
		"the built-in course isn't plain parkland")

	# Firmness: the same shot on the same ground runs further on a links
	# and less far on a mountain.
	var def := Course.blank_hole(4)
	# (A hole drawn flat is flat everywhere — the lie of the land only
	# bends slopes that are there.)
	var level := HoleData.build(def, 7)
	for probe in [Vector2(0, 100), Vector2(-45, 180), Vector2(60, 260), level.pin_pos + Vector2(30, -40)]:
		_expect(level.height_at(probe) == 0.0, "a flat hole isn't flat at %s" % probe)
	var park := _run_out(HoleData.build(def, 1, "parkland"))
	_expect(_run_out(HoleData.build(def, 1)) == park, "build() without a terrain isn't parkland")
	_expect(_run_out(HoleData.build(def, 1, "links")) > park + 1.0, "links ground doesn't run")
	_expect(_run_out(HoleData.build(def, 1, "alpine")) < park - 1.0, "alpine ground doesn't hold")

	# Wind: early in a round (nothing has built yet — late = 0) parkland
	# draws exactly what the game always drew; a links blows harder than
	# that, a desert less.
	var sums := {"parkland": 0.0, "links": 0.0, "desert": 0.0}
	for n in range(1, 301):
		for id in sums:
			sums[id] += Wind.for_hole(4321, n, id, 0.0).length()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([4321, n, "wind"])
		var mph: float = Wind.MAX_MPH * pow(rng.randf(), Wind.CALM_SKEW)
		_expect(Wind.mph(Wind.for_hole(4321, n, "", 0.0)) == (int(round(mph)) if round(mph) >= 1.0 else 0),
			"parkland wind on hole %d changed" % n)
	_expect(sums.links > sums.parkland * 1.2, "a links isn't windier than parkland")
	_expect(sums.desert < sums.parkland * 0.8, "a desert isn't calmer than parkland")

	# Every terrain has everything the art and the picker read.
	for id in CourseTheme.ORDER:
		var t: Dictionary = CourseTheme.get_theme(id)
		for key in CourseTheme.get_theme(CourseTheme.DEFAULT):
			_expect(t.has(key), "terrain %s has no '%s'" % [id, key])
		_expect(CourseTheme.label(id) != "" and CourseTheme.play_summary(id) != "", "terrain %s has no label" % id)


# Numbers compare by value (a file says 4, the wire says 4.0).
func _same(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.001
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


func _check_hole_sound(theme: String, def: Dictionary, n: int, where: String) -> void:
	var h := HoleData.build(def, n, theme)
	_expect(h.terrain_at(h.pin_pos) == "green", "%s: the pin isn't on the green" % where)
	_expect(h.terrain_at(h.tee_pos + Vector2(0, 8)) == "fairway", "%s: no fairway in front of the tee" % where)
	var par: int = h.par
	var ok_length: bool = (par == 3 and h.yardage <= 260.0) or (par == 4 and h.yardage >= 240.0 and h.yardage <= 480.0) \
		or (par == 5 and h.yardage >= 450.0)
	_expect(ok_length, "%s: %d yards is an odd length for a par %d" % [where, int(h.yardage), par])
	_expect(not Geometry2D.triangulate_polygon(h.fairway_polygon).is_empty(), "%s: fairway can't be drawn" % where)
	_expect(not Geometry2D.triangulate_polygon(h.green_polygon).is_empty(), "%s: green can't be drawn" % where)
	# The ground in play: one connected piece, holding the tee and every
	# shape a ball can lie on, with room to spare.
	_expect(h.play_polygons.size() == 1, "%s: the ground in play is in %d pieces" % [where, h.play_polygons.size()])
	_expect(not h.is_out_of_bounds(h.tee_pos) and not h.is_out_of_bounds(h.tee_pos - Vector2(0, 10)),
		"%s: the tee is out of bounds" % where)
	var edge_ok := true
	for poly in [h.green_polygon, h.fairway_polygon, h.green_fringe_polygon]:
		for pt in poly:
			if h.is_out_of_bounds(pt):
				edge_ok = false
	_expect(edge_ok, "%s: part of the fairway or green is out of bounds" % where)
	for z in h.hazards:
		if z.type == "bunker":
			for pt in z.polygon:
				if h.is_out_of_bounds(pt):
					_expect(false, "%s: part of a bunker is out of bounds" % where)
					break
	# Halfway down the line of play is in play too (a par 3's carry).
	_expect(h.terrain_at(Vector2(h.centre_x_at(h.pin_pos.y * 0.5), h.pin_pos.y * 0.5)) != "out",
		"%s: the line of play leaves the course" % where)
	# And the nearest-in-bounds helper really lands in bounds.
	for probe in [h.bounds.position - Vector2(5, 5), h.bounds.end + Vector2(5, 5), Vector2(h.bounds.position.x, h.bounds.end.y)]:
		_expect(not h.is_out_of_bounds(h.nearest_in_bounds(probe)), "%s: nearest_in_bounds() lands out of bounds" % where)
	for i in h.hazards.size():
		_expect(not Geometry2D.triangulate_polygon(h.hazards[i].polygon).is_empty(),
			"%s: hazard %d can't be drawn" % [where, i + 1])
	for z in def.hazards:
		if z.type == "bunker":
			_expect(h.terrain_at(z.pos) == "bunker", "%s: the bunker at %s is buried or out of bounds" % [where, z.pos])
	_check_lie_of_land(h, where)


# The ground off the line of play (HoleData._lie): it bends the contours,
# and that's all it does.
func _check_lie_of_land(h: HoleData, where: String) -> void:
	var lo := INF
	var hi := -INF
	var cross_fall := false
	for st in h.elev_stations:
		lo = minf(lo, st.y)
		hi = maxf(hi, st.y)
		cross_fall = cross_fall or st.z != 0.0
	if h.elev_stations.is_empty():
		return
	var clear_of_green: float = h.green_radius * 1.8 + 1.0
	# On the line of play the hole has exactly the profile it was given.
	var y := 0.0
	while y < h.pin_pos.y:
		var on_line := Vector2(h.centre_x_at(y), y)
		if on_line.distance_to(h.pin_pos) > clear_of_green:
			_expect(absf(h.height_at(on_line) * HoleData.FEET_PER_YARD - h._profile_ft(y)) < 0.01,
				"%s: the line of play is off its profile at %d yards" % [where, int(y)])
		y += 10.0
	# Off it, over all the ground in play: the profile never doubles back,
	# no ground is higher or lower than the hole's own stations, and a hole
	# that climbs or drops isn't ruled dead straight across.
	var folded := false
	var out_of_range := false
	var most_bend := 0.0
	y = h.bounds.position.y
	while y < h.bounds.end.y:
		var x := h.bounds.position.x
		while x < h.bounds.end.x:
			var p := Vector2(x, y)
			x += 8.0
			if h.is_out_of_bounds(p):
				continue
			var here: float = p.y + h._lie(p.y, p.x - h.centre_x_at(p.y))
			var ahead: float = p.y + 2.0 + h._lie(p.y + 2.0, p.x - h.centre_x_at(p.y + 2.0))
			folded = folded or ahead <= here
			if cross_fall or p.distance_to(h.pin_pos) <= clear_of_green:
				continue
			var ft: float = h.height_at(p) * HoleData.FEET_PER_YARD
			out_of_range = out_of_range or ft < lo - 0.01 or ft > hi + 0.01
			most_bend = maxf(most_bend, absf(ft - h._profile_ft(p.y)))
		y += 8.0
	_expect(not folded, "%s: the lie of the land folds the hill back on itself" % where)
	_expect(not out_of_range, "%s: ground in play is higher or lower than any of the hole's stations" % where)
	if not cross_fall and hi - lo >= 5.0:
		_expect(most_bend >= 0.5, "%s: the contours run dead straight across the hole" % where)


func _check_shipped_courses() -> void:
	var all := CourseLibrary.all()
	_expect(all.size() == 1 + CourseLibrary.FILES.size(), "a shipped course failed to load")
	_expect(all[0].id == Course.BUILTIN_ID and all[0].theme == CourseTheme.DEFAULT, "the built-in isn't first")
	var names := {}
	for c in all:
		_expect(not names.has(str(c.name).to_lower()), "two shipped courses are called %s" % c.name)
		names[str(c.name).to_lower()] = true
		_expect(CourseLibrary.has_name(c.name), "has_name() misses %s" % c.name)
		if c.id == Course.BUILTIN_ID:
			for n in range(1, c.holes.size() + 1):
				_check_hole_sound(c.theme, c.holes[n - 1], n, "%s hole %d" % [c.id, n])
			continue
		# The file is exactly what the sanitiser makes of it: a client playing
		# the host's payload plays the course the host has on disk.
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CourseLibrary.path_for(c.id)))
		var again: Dictionary = JSON.parse_string(JSON.stringify(Course.to_wire(Course.from_wire(raw))))
		_expect(_same(raw.holes, again.holes), "%s is changed by the sanitiser" % c.id)
		_expect(str(raw.get("theme", "")) == c.theme and CourseTheme.THEMES.has(c.theme), "%s has no known terrain" % c.id)
		_expect(str(raw.get("blurb", "")) != "", "%s has no blurb" % c.id)
		_expect(c.holes.size() == 18, "%s has %d holes" % [c.id, c.holes.size()])
		for n in range(1, c.holes.size() + 1):
			_check_hole_sound(c.theme, c.holes[n - 1], n, "%s hole %d" % [c.id, n])
		_expect(Course.use_shipped(c.id) and Course.active_id == c.id and Course.active_name == c.name
			and Course.active_theme == c.theme and Course.hole_count() == c.holes.size() and not Course.is_builtin(),
			"use_shipped(%s) didn't make it the active course" % c.id)
		# The same course sent by an online host is still that course, with the
		# same records key — but not once it's renamed or reshaped.
		var local_key := Records.course_key()
		var sent := Course.from_wire(JSON.parse_string(JSON.stringify(Course.to_wire(Course.active()))))
		Course.use_builtin()
		Course.use(sent)
		_expect(Course.active_id == c.id and Records.course_key() == local_key,
			"%s isn't recognised when it arrives over the wire" % c.id)
		var renamed: Dictionary = sent.duplicate(true)
		renamed["name"] = "%s II" % c.name
		Course.use(renamed)
		_expect(Course.active_id == "" and Records.course_key().begins_with("custom:"),
			"a renamed copy of %s passes for the original" % c.id)
		var reshaped: Dictionary = sent.duplicate(true)
		reshaped.holes[0]["par"] = 5 if int(reshaped.holes[0].par) != 5 else 4
		Course.use(reshaped)
		_expect(Course.active_id == "", "a reshaped copy of %s passes for the original" % c.id)
	_expect(not Course.use_shipped("no-such-course"), "use_shipped() accepted a made-up id")
	# The built-in too: a client handed Bogey Links by its host is on Bogey Links.
	Course.use(Course.from_wire(JSON.parse_string(JSON.stringify(Course.to_wire(Course.builtin())))))
	_expect(Course.active_id == Course.BUILTIN_ID and Records.course_key() == "builtin",
		"the built-in isn't recognised when it arrives over the wire")
	Course.use_builtin()
	_expect(Course.active_id == Course.BUILTIN_ID and Course.is_shipped(), "the built-in isn't a shipped course")
	Course.use({"name": "Mine", "holes": [Course.blank_hole(3)]})
	_expect(Course.active_id == "" and not Course.is_shipped(), "a custom course claims to be shipped")
	Course.use_builtin()
