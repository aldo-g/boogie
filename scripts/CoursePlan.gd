extends CourseArt

# ---------------------------------------------------------
# The whole course on one sheet: every hole of the active course laid out
# as a routing — each tee a short walk from the last green — and painted
# on one piece of ground. The title screen's picture of the course.
#
# It is a CourseArt so that it paints with the same brushes: fairway,
# sand, water, green, tee, flag and scenery are CourseArt's own, drawn
# through _to_px(), which here also turns each hole to lie where the
# routing put it.
#
# The holes are the real ones. Where they lie on the property is made up
# here (see route()): a course file describes each hole from its own tee
# and says nothing about where the next one starts.
#
# No class_name: it is loaded by path (Title.gd, CourseTest.gd), so it
# works in a tree whose class cache was built before this file existed.
# ---------------------------------------------------------

const SHARED := 20.0        # yards of its rough a hole shares with the hole beside it
const FOOT_STEP := 30.0     # yards between the points of a hole's footprint
const CLUBHOUSE := 64.0     # yards kept clear behind the first tee, for the clubhouse
const WALKS := [70.0, 100.0]   # yards from a pin to the next tee, if there's room (less never clears the green)
const WALK_TURNS := 8       # compass points tried for that walk
const TURNS := 16           # ...and for the way the hole plays
const TURN_COST := 70.0     # yards further out a hole may lie to turn off the last one's line
const WAY_OUT_TRIES := 48   # how many of the best places for a hole are checked for a way on
const LONG_WALK := 180.0    # yards: a walk between holes longer than this isn't drawn
const SHEET_EDGE := 26.0    # pixels of country left round the course
const SCENERY_PX := 16.0    # pixels: one piece of scenery per cell this size at most
const STAND_PX := 110.0     # pixels across one wood, or one clearing between two
const WATER_SHOWN := 16.0   # yards past the ground in play that a hole's water is drawn
# Terrains that lie by the sea: pixels of the sheet's left side, and of
# its foot, given to it.
const COAST := {"links": 84.0}
const HEADLAND := 190.0     # yards from the corner of the land to the first seaside hole either way
const OPEN_WATER := 230.0   # yards off the line: water authored out this far, on one side, is the sea
const COAST_START := 330.0  # yards in from the shore that a seaside course's first tee stands
const COAST_ROUND := 12.0   # pixels: how round the corners of the coast are worn
const SHORE_GAP := 200.0    # yards of shore between one seaside hole and the next: room for a hole in and a hole out
const SHORE_DEPTH := 260.0  # yards in from the sea that a hole off the shore should get, at the least
const INLAND := 2.0         # yards of sheet each yard short of that costs it
const DUE_COST := 2.5       # yards of sheet it is worth to finish a yard nearer where the round is due
const COAST_REACH := 110.0  # yards from the shore within which a seaside hole's water is the sea itself
# Terrains under high ground: pixels of the sheet's top left to the snow.
const SNOWS := {"alpine": 112.0}

var _holes: Array = []      # HoleData, in playing order
var _places: Array = []     # Transform2D each: that hole's yards -> the sheet's (y down)
var _m := Transform2D()     # yards -> pixels for whatever is being painted


func _init() -> void:
	super()
	show_behind_parent = false
	clip_contents = true


# Shows the active course (see Course.gd).
func show_course() -> void:
	_holes = []
	for n in range(1, Course.hole_count() + 1):
		_holes.append(HoleData.hole(n))
	_places = []
	queue_redraw()


func _to_px(yard_pt: Vector2) -> Vector2:
	return _m * yard_pt


# --- The routing -------------------------------------------------------
# Where each hole lies, as one Transform2D per hole. Hole by hole: the tee
# goes a short walk from the last green, and the hole is pointed whichever
# way keeps it closest in to the holes already there — on a sheet `aspect`
# times as wide as it is tall — without lying across any of them. So the
# course winds outward round its first tee. Two things temper that:
#   - a hole that runs straight back beside the last one packs tightest,
#     and a course of nothing but that is a ploughed field, so turning off
#     the line is worth a little room (TURN_COST);
#   - a hole isn't put where the next one would have no way out from its
#     green, if there's anywhere else for it.
# A `coastal` course lies on a headland: the land is x >= 0 and y <= 0,
# with the sea down its left and along its foot. The holes with the sea
# beside them (sea_of) are laid down first, one after another along the
# shore — down the left of it and then along the foot — each with its
# water to the sea. The rest are then routed between them as above, except
# that the round has to get from each of them to the next.
# The same course always routes the same way.
static func route(holes: Array, aspect: float = 1.0, coastal: bool = false) -> Array:
	var out: Array = []
	out.resize(holes.size())
	var turns: Array = []        # which way each hole was pointed, in TURNS
	turns.resize(holes.size())
	var taken: Array = []        # each placed hole's footprint, in sheet yards
	var taken_box: Array = []    # ...and the box round it
	var all := Rect2()
	var middle := Vector2.ZERO   # the mean of those boxes' centres

	# The order they're laid down in. Inland it is the order they're
	# played in. By the sea: the seaside holes; then, for each, the hole
	# that arrives at its tee and the hole that leaves its green, while
	# there is still room by the shore to do either; then the rest.
	var order: Array = []
	var seaside: Array = []
	for j in holes.size() if coastal else 0:
		if not sea_of(holes[j]).is_empty():
			seaside.append(j)
	order.append_array(seaside)
	var backward: Array = []     # the ones laid from their green back to their tee
	for j: int in seaside:
		if j > 0 and not order.has(j - 1):
			order.append(j - 1)
			backward.append(j - 1)
		if j + 1 < holes.size() and not order.has(j + 1):
			order.append(j + 1)
	var by_shore: Array = order.duplicate()   # those, which also head inland rather than along the shore
	for i in holes.size():
		if not order.has(i):
			order.append(i)

	# How much shore each seaside hole takes, and which of them go down the
	# left: as many as make the two shores most nearly the same length.
	var frontage: Array = []
	var whole := 0.0
	for j: int in seaside:
		frontage.append(_rect_of(footprint(holes[j], j == 0, true)).size.y + SHORE_GAP)
		whole += frontage[-1]
	var down_left := 0           # how many
	var left_shore := 0.0
	while down_left < seaside.size() and absf(whole - 2.0 * (left_shore + frontage[down_left])) <= absf(whole - 2.0 * left_shore):
		left_shore += frontage[down_left]
		down_left += 1
	var shore := Vector2(HEADLAND, -HEADLAND - left_shore + SHORE_GAP)   # where the next goes: x along the foot, y down the left
	for i: int in order:
		var hole: HoleData = holes[i]
		var foot := footprint(hole, i == 0, coastal)
		var pick: Array = []     # [cost, Transform2D, footprint on the sheet, turn]
		if seaside.has(i):
			# Down the left shore a hole with the sea on its right plays
			# down the sheet, and one with the sea on its left, up it;
			# along the foot they play to the right and to the left.
			var left: bool = seaside.find(i) < down_left
			var turn: int = (TURNS / 2 if sea_of(hole)[0] > 0.0 else 0) + (0 if left else -TURNS / 4)
			turn = posmod(turn, TURNS)
			var turned := _place(hole, Vector2.ZERO, TAU * turn / TURNS)
			var box := _rect_of(turned * foot)
			var corner := Vector2(1.0, shore.y) if left else Vector2(shore.x, -1.0 - box.size.y)
			var xf := Transform2D(0.0, corner - box.position) * turned
			pick = [0.0, xf, xf * foot, turn]
			if left:
				shore.y += box.size.y + SHORE_GAP
			else:
				shore.x += box.size.x + SHORE_GAP
		else:
			var back: bool = backward.has(i)
			# The nearest holes already down before and after this one, the
			# points of them the round passes through, and how far apart
			# the holes still to come between can be (_slack).
			var before := i - 1
			while before >= 0 and out[before] == null:
				before -= 1
			var after := i + 1
			while after < holes.size() and out[after] == null:
				after += 1
			var from := Vector2.ZERO       # the green the round comes from
			var to := Vector2.ZERO         # the tee it is due at
			if before >= 0:
				from = (out[before] as Transform2D) * (holes[before] as HoleData).pin_pos
			if after < holes.size():
				to = (out[after] as Transform2D) * (holes[after] as HoleData).tee_pos
			# One end of it is a short walk from a hole that's down: its tee
			# from the last green, or (backward) its green from the next
			# tee. Opening a seaside round, it starts as far inland of
			# where it's due as it has to go.
			var anchor := to if back else from
			var joined: bool = (after == i + 1) if back else (before == i - 1)
			if not joined and coastal:
				anchor = to + Vector2(maxf(_slack(holes, i - 1, after)[1], COAST_START), 0.0)
				anchor.y = minf(anchor.y, -COAST_START)
			var beside: int = turns[i + 1] if back else (turns[i - 1] if i > 0 else 0)
			var slack: Array = []          # [least, most] this hole's far end may be from where it must connect
			var far := Vector2.ZERO
			if back and before >= 0:
				slack = _slack(holes, before, i)
				far = from
			elif not back and after < holes.size():
				slack = _slack(holes, i, after)
				far = to
			var options: Array = []
			var walks: Array = WALKS if joined else [0.0]
			# Further each time round, so there is always somewhere to go.
			while options.is_empty():
				for w in walks.size() * (WALK_TURNS if joined else 1):
					var walk: float = walks[w % walks.size()]
					var near := anchor + Vector2.UP.rotated(TAU * (w / walks.size()) / WALK_TURNS) * walk
					for b in TURNS:
						var xf := _place(hole, near, TAU * b / TURNS)
						if back:
							xf = _place(hole, near + near - xf * hole.pin_pos, TAU * b / TURNS)   # its green at `near`, not its tee
						var poly: PackedVector2Array = xf * foot
						var box := _rect_of(poly)
						if (coastal and not _on_land(box)) or not _is_free(poly, box, taken, taken_box):
							continue
						var grown := box if taken.is_empty() else all.merge(box)
						var off := box.get_center() - middle
						var along: float = absf(cos(TAU * (b - beside) / TURNS))
						var cost: float = Vector2(off.x / aspect, off.y).length() + maxf(grown.size.x / aspect, grown.size.y) \
							+ TURN_COST * along * along + walk
						if by_shore.has(i):
							cost += INLAND * maxf(SHORE_DEPTH - from_sea(xf * (hole.tee_pos if back else hole.pin_pos)), 0.0)
						if not slack.is_empty():
							var gap: float = (xf * (hole.tee_pos if back else hole.pin_pos)).distance_to(far)
							cost += DUE_COST * maxf(maxf(gap - slack[1], slack[0] - gap), 0.0)
						options.append([cost, xf, poly, b])
				walks = [walks[-1] * 1.4, walks[-1] * 2.0]
			options.sort_custom(func(p, q): return p[0] < q[0])
			pick = options[0]
			# The hole to come at its open end — the next from its green or,
			# laid backward, the one before to its tee — if that isn't down.
			var other: int = i - 1 if back else i + 1
			if other >= 0 and other < holes.size() and out[other] == null:
				var other_foot := footprint(holes[other], other == 0, coastal)
				for option in options.slice(0, WAY_OUT_TRIES):
					if _has_way_out((option[1] as Transform2D) * (hole.tee_pos if back else hole.pin_pos), holes[other], other_foot,
							taken + [option[2]], taken_box + [_rect_of(option[2])], coastal):
						pick = option
						break
		out[i] = pick[1]
		turns[i] = pick[3]
		var room: Rect2 = _rect_of(pick[2])
		all = room if taken.is_empty() else all.merge(room)
		middle = (middle * taken.size() + room.get_center()) / float(taken.size() + 1)
		taken.append(pick[2])
		taken_box.append(room)
	return out


# How far apart two points of the round can be with holes `a` and `b`
# both down and the holes between them still to come, as [least, most]: a
# hundred yards for the walk if there are none; otherwise no further than
# they reach end to end, and no nearer than the longest of them overshoots
# the rest.
static func _slack(holes: Array, a: int, b: int) -> Array:
	var total := 0.0
	var longest := 0.0
	for k in range(a + 1, b):
		total += (holes[k] as HoleData).pin_pos.y
		longest = maxf(longest, (holes[k] as HoleData).pin_pos.y)
	return [maxf(2.0 * longest - total - 100.0, 0.0), 0.6 * total + 100.0]


static func _is_free(poly: PackedVector2Array, box: Rect2, taken: Array, taken_box: Array) -> bool:
	for k in taken.size():
		if box.intersects(taken_box[k]) and not Geometry2D.intersect_polygons(poly, taken[k]).is_empty():
			return false
	return true


# Whether `next` could start a short walk from `green` at all. (Also asked
# of the hole before and a tee: not the same question, but the same room.)
static func _has_way_out(green: Vector2, next: HoleData, foot: PackedVector2Array, taken: Array, taken_box: Array,
		coastal: bool = false) -> bool:
	for w in WALKS.size() * WALK_TURNS:
		var tee := green + Vector2.UP.rotated(TAU * (w / WALKS.size()) / WALK_TURNS) * float(WALKS[w % WALKS.size()])
		for b in TURNS:
			var poly: PackedVector2Array = _place(next, tee, TAU * b / TURNS) * foot
			var box := _rect_of(poly)
			if (not coastal or _on_land(box)) and _is_free(poly, box, taken, taken_box):
				return true
	return false


# Whether a hole's room on a coastal course is all on the land.
static func _on_land(box: Rect2) -> bool:
	return box.position.x >= 0.0 and box.end.y <= 0.0


# How far a point of a coastal course is from the sea.
static func from_sea(at: Vector2) -> float:
	return minf(at.x, -at.y)


# The sea beside a hole, if it has one: water authored out to the edge of
# the hole's box on one side only (a burn runs out both ways). As [which side —
# 1 the right, looking from the tee, -1 the left; how far off the line the
# shore comes; the water's outline], or [] for a hole inland.
static func sea_of(hole: HoleData) -> Array:
	for hazard in hole.hazards:
		if hazard.type != "water":
			continue
		var box := _rect_of(hazard.polygon)
		var right: bool = box.end.x >= OPEN_WATER and box.position.x > -OPEN_WATER * 0.5
		var left: bool = box.position.x <= -OPEN_WATER and box.end.x < OPEN_WATER * 0.5
		if right != left:
			return [1.0 if right else -1.0, box.position.x if right else box.end.x, hazard.polygon]
	return []


# The room a hole takes on the sheet, in its own yards: its ground in
# play, less the edge of it that it shares with its neighbours — holes on
# a course lie rough to rough, and a dogleg leaves room in its elbow for
# another. (Coarsened: this is tried against every other hole in a great
# many places.) The first hole's has the clubhouse's plot behind the tee.
# On a coastal course its sea is left out: that is the sea's own room.
static func footprint(hole: HoleData, first: bool = false, coastal: bool = false) -> PackedVector2Array:
	var parts: Array = []
	for outline in hole.play_polygons:
		parts.append_array(_grown(CourseShape.resample(outline, FOOT_STEP), -SHARED))
	# Its water is all its own, with enough bank to join it to the rest.
	for water in shown_water(hole, not coastal):
		parts.append_array(_grown(CourseShape.resample(water, FOOT_STEP), SHARED + 2.0))
	if first:
		var tee := hole.tee_pos
		parts.append(PackedVector2Array([tee + Vector2(-28, -CLUBHOUSE), tee + Vector2(28, -CLUBHOUSE),
			tee + Vector2(28, 8), tee + Vector2(-28, 8)]))
	var whole := CourseShape.union_all(parts)
	if whole.size() == 1:
		return whole[0]
	# In pieces, or a hole made without ground of its own: the hull round
	# all there is of it.
	var points := PackedVector2Array([hole.tee_pos, hole.pin_pos])
	for piece in parts + [hole.fairway_polygon, hole.green_fringe_polygon]:
		points.append_array(piece)
	var hull := Geometry2D.convex_hull(points)
	hull.remove_at(hull.size() - 1)   # it comes back closed
	return hull


# A hole's water as the sheet shows it: the part beside the ground in
# play. A burn is authored from one side of the hole's box to the other
# and a shore runs well off into the country (HoleData treats all that as
# scenery too); drawn whole, every hole would need a field to itself.
# `with_sea` = false leaves out the sea beside it (sea_of).
static func shown_water(hole: HoleData, with_sea: bool = true) -> Array:
	var sea: Array = [] if with_sea else sea_of(hole)
	var near: Array = []
	for outline in hole.play_polygons:
		near.append_array(_grown(outline, WATER_SHOWN))
	var out: Array = []
	for hazard in hole.hazards:
		if hazard.type != "water" or (not sea.is_empty() and hazard.polygon == sea[2]):
			continue
		if near.is_empty():
			out.append(hazard.polygon)
		for ground in near:
			for piece in Geometry2D.intersect_polygons(hazard.polygon, ground):
				if _drawable(piece) and not Geometry2D.is_polygon_clockwise(piece):
					out.append(piece)
	return out


# A hole with its tee at `tee` on the sheet, playing `angle` round from
# straight up it. Hole yards run toward the pin and the sheet's run down,
# hence the flip — which keeps a dogleg left a dogleg left.
static func _place(hole: HoleData, tee: Vector2, angle: float) -> Transform2D:
	return Transform2D(angle, tee) * Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2(-hole.tee_pos.x, hole.tee_pos.y))


# --- The painting ------------------------------------------------------

func _draw() -> void:
	if _holes.is_empty() or size.x < 80.0 or size.y < 80.0:
		return
	var t: Dictionary = CourseTheme.get_theme((_holes[0] as HoleData).theme)

	# Fit the routing to the sheet — against the sea, if the terrain has one.
	var sea: float = COAST.get((_holes[0] as HoleData).theme, 0.0)
	var snow: float = SNOWS.get((_holes[0] as HoleData).theme, 0.0)
	var coastal := sea > 0.0
	var room := Rect2(Vector2(sea if coastal else SHEET_EDGE, SHEET_EDGE + snow), Vector2.ZERO)
	room.end = size - Vector2(SHEET_EDGE, sea if coastal else SHEET_EDGE)
	if _places.is_empty():
		_places = route(_holes, room.size.x / room.size.y, coastal)
	var extent := Rect2()
	for i in _holes.size():
		var box := _rect_of((_places[i] as Transform2D) * footprint(_holes[i], i == 0, coastal))
		extent = box if i == 0 else extent.merge(box)
	if coastal:
		extent = extent.expand(Vector2.ZERO)   # the corner of the land
	var s: float = minf(room.size.x / extent.size.x, room.size.y / extent.size.y)
	var origin := room.get_center() - extent.get_center() * s
	if coastal:
		origin = Vector2(room.position.x, room.end.y) - Vector2(extent.position.x, extent.end.y) * s   # into the corner
	var sheet := Transform2D(0.0, Vector2(s, s), 0.0, origin)
	var mats: Array = []
	for place in _places:
		mats.append(sheet * (place as Transform2D))

	# The country the course is cut through.
	_m = sheet
	var frame := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	draw_colored_polygon(frame, t.surround)
	_fill_through(frame, Color(t.surround_alt, 0.85), _mottle(), MOTTLE_TILE * 1.4 * s, Vector2(37, 91))
	var bare: Array = []   # where no scenery goes: snow and sea, then every hole's ground
	if snow > 0.0:
		bare.append(_draw_snow(snow, t))

	# Every hole's rough before anything else of any hole, so one hole's
	# rough never lies over its neighbour's fairway.
	var roughs: Array = []
	for i in _holes.size():
		_m = mats[i]
		for poly in _play_outlines(_holes[i]):
			roughs.append(_px_poly(poly))
	_m = sheet
	for ground in roughs:
		_outline(ground, Color(t.rough, 0.28), maxf(11.0 * s, 5.0))
		_outline(ground, Color(t.rough, 0.45), maxf(5.0 * s, 2.5))
	for ground in roughs:
		draw_colored_polygon(ground, t.rough)
		_fill_through(ground, Color(t.rough_alt, 0.8), _mottle(), MOTTLE_TILE * s)

	# The sea goes over the rough: a seaside hole's ground in play runs out
	# into the water. Where such a hole has come to the shore its water is
	# the sea itself, as far along as the hole runs.
	var by_sea: Array = []   # per hole: whether its water was drawn as the sea
	by_sea.resize(_holes.size())
	by_sea.fill(false)
	if coastal:
		var inlets: Array = []
		for i in _holes.size():
			var hole: HoleData = _holes[i]
			var side: Array = sea_of(hole)
			if side.is_empty() or from_sea((_places[i] as Transform2D) * Vector2(side[1], hole.pin_pos.y * 0.5)) > COAST_REACH:
				continue
			by_sea[i] = true
			var reach := Rect2(-400.0, hole.tee_pos.y - 30.0, 800.0, hole.pin_pos.y - hole.tee_pos.y + 60.0)
			var band := PackedVector2Array([reach.position, Vector2(reach.end.x, reach.position.y), reach.end, Vector2(reach.position.x, reach.end.y)])
			for piece in CourseShape.outlines(Geometry2D.intersect_polygons(side[2], band)):
				inlets.append((mats[i] as Transform2D) * piece)
		bare.append_array(_draw_sea(sea, t, inlets))

	_draw_country(bare + roughs, t)

	# The walk from each green to the next tee.
	for i in range(1, _holes.size()):
		var from: Vector2 = (mats[i - 1] as Transform2D) * (_holes[i - 1] as HoleData).pin_pos
		var to: Vector2 = (mats[i] as Transform2D) * (_holes[i] as HoleData).tee_pos
		# Not the long ones. Beside the sea the round can't always be brought
		# to the next tee, and a line across three fairways says less than
		# the numbers on the tees do.
		if from.distance_to(to) <= LONG_WALK * s:
			draw_dashed_line(from, to, Color(BogeyTheme.PARCHMENT, 0.6), 1.2, 3.0, true, true)

	for i in _holes.size():
		var hole: HoleData = _holes[i]
		_m = mats[i]
		_draw_fairway(hole, t, s)
		for water in shown_water(hole, not by_sea[i]):
			_draw_water(water, t, s)
		for hazard in hole.hazards:
			if hazard.type != "water":
				_draw_bunker(hazard.polygon, t, s)
		_draw_green(hole, t, s)

	# What stands on the course goes on last: nothing of one hole is under
	# another's turf.
	_m = mats[0]
	var first: HoleData = _holes[0]
	_draw_clubhouse(_to_px(first.tee_pos + Vector2(0, -CLUBHOUSE * 0.62)), mats[0])
	var font := BogeyUI.sans(600)
	for i in _holes.size():
		var hole: HoleData = _holes[i]
		_m = mats[i]
		_draw_pin(hole)
		# The hole's number, on its tee.
		var tee := _to_px(hole.tee_pos)
		draw_circle(tee + Vector2(0.6, 1.0), 8.2, Color(COLOR_SHADOW, 0.3))
		draw_circle(tee, 7.6, BogeyTheme.CARD_BG)
		draw_arc(tee, 7.6, 0.0, TAU, 20, Color(BogeyTheme.INK, 0.55), 1.0, true)
		draw_string(font, tee + Vector2(-10, 3.6), str(hole.number), HORIZONTAL_ALIGNMENT_CENTER, 20, 10, BogeyTheme.INK)

	_draw_scale(s, font)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color(BogeyTheme.INK, 0.22), false, 1.0)
	draw_rect(Rect2(Vector2(1.5, 1.5), size - Vector2(3, 3)), Color(BogeyTheme.INK, 0.07), false, 1.0)


# Water as a chart draws it: a bank, a pale margin and two depths. None of
# CourseArt's wavelets — at this scale they are a hatch over the whole pond.
func _draw_water(poly: PackedVector2Array, t: Dictionary, s: float) -> void:
	var w := _px_poly(poly)
	if not _drawable(w):
		return
	for piece in _grown(w, maxf(1.7 * s, 1.2)):
		draw_colored_polygon(piece, t.bank)
	var water: Color = t.water
	draw_colored_polygon(w, water.lerp(t.water_light, 0.55))
	for band in [[1.8, water], [5.0, water.lerp(t.water_deep, 0.6)], [10.0, t.water_deep]]:
		for piece in _grown(w, -float(band[0])):
			draw_colored_polygon(piece, band[1])


# A line wandering along one side of the sheet — SIDE_LEFT, SIDE_TOP or
# SIDE_BOTTOM — between `least` and `most` of `width` pixels in, with the
# ground outside it: what the sea and the snow are made from. Returns [the
# line, that ground's outline].
func _margin(width: float, side: int, least: float, most: float) -> Array:
	var line := PackedVector2Array()
	var v := -24.0
	while v < (size.y if side == SIDE_LEFT else size.x) + 24.0:
		# A long swing in and out, and a shorter wobble on it.
		var d: float = width * lerpf(least, most, 0.78 * _lumps(Vector2(7.0 + side, v), 230.0, 31) + 0.22 * _lumps(Vector2(7.0 + side, v), 60.0, 32))
		line.append(Vector2(d, v) if side == SIDE_LEFT else Vector2(v, d if side == SIDE_TOP else size.y - d))
		v += 8.0
	var outside := Vector2(-24.0, -24.0) if side != SIDE_BOTTOM else Vector2(-24.0, size.y + 24.0)
	var area := PackedVector2Array(line)
	area.append(Vector2(outside.x, v) if side == SIDE_LEFT else Vector2(v, outside.y))
	area.append(outside)
	# One way round always, so that growing it grows it.
	if Geometry2D.is_polygon_clockwise(area):
		area.reverse()
	return [line, area]


# The sea down the left of the sheet and along its foot, and up to the
# shore of every hole in `inlets` (their water, in pixels), with its
# beach. Returns the beach's outlines: nothing grows on it.
func _draw_sea(width: float, t: Dictionary, inlets: Array) -> Array:
	var waters: Array = []
	for water in CourseShape.union_all([_margin(width, SIDE_LEFT, 0.7, 0.96)[1], _margin(width, SIDE_BOTTOM, 0.7, 0.96)[1]] + inlets):
		# Where a hole's water meets the open sea it meets it square. Fill
		# the corners that leaves in the land, then round off the ones it
		# leaves in the water.
		for filled in _grown(water, COAST_ROUND):
			for worn in _grown(filled, -2.0 * COAST_ROUND):
				waters.append_array(_grown(worn, COAST_ROUND))
	var sand: Color = t.sand
	var sea: Color = t.water
	var beaches: Array = []
	for layer in [[13.0, sand.lerp(t.surround, 0.45)], [9.0, sand], [2.5, sand.lightened(0.3)], [0.0, sea.lerp(t.water_light, 0.5)],
			[-4.0, sea], [-15.0, sea.lerp(t.water_deep, 0.55)], [-34.0, t.water_deep]]:
		for water in waters:
			for piece in (_grown(water, layer[0]) if layer[0] != 0.0 else [water]):
				draw_colored_polygon(piece, layer[1])
				if layer[0] == 13.0:
					beaches.append(piece)
	# The surf: a white edge, and a fainter line of it further out.
	for water in waters:
		_outline(water, Color(1, 1, 1, 0.8), 1.3)
		for piece in _grown(water, -6.0):
			_outline(piece, Color(1, 1, 1, 0.3), 1.0)
	return beaches


# The snows across the top of the sheet, above the course: scree where
# they give out, and blue shadow under the lip. Returns the outline of all
# of it.
func _draw_snow(width: float, t: Dictionary) -> PackedVector2Array:
	var edge := _margin(width, SIDE_TOP, 0.2, 0.9)
	var field: PackedVector2Array = edge[1]
	var scree := field
	for piece in _grown(field, 12.0):
		scree = piece
		draw_colored_polygon(piece, Color(t.rock, 0.5))
	for piece in _grown(field, 4.0):
		draw_colored_polygon(piece, Color(0.55, 0.64, 0.70))
	draw_colored_polygon(field, Color(0.89, 0.92, 0.93))
	for piece in _grown(field, -16.0):
		draw_colored_polygon(piece, Color(0.95, 0.97, 0.98))
	return scree


# A smooth 0..1 across the sheet, `cell` pixels to a lump.
static func _lumps(px: Vector2, cell: float, salt: int) -> float:
	var q := px / cell
	var i := floori(q.x)
	var j := floori(q.y)
	var f := q - Vector2(i, j)
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	return lerpf(lerpf(_rand(i, j, salt), _rand(i + 1, j, salt), f.x),
		lerpf(_rand(i, j + 1, salt), _rand(i + 1, j + 1, salt), f.x), f.y)


# The terrain's scenery (CourseTheme's "outside" list) everywhere that
# isn't in `bare`: CourseArt's own trees, dunes and rocks, but
#   - on a grid measured in pixels, not yards — a big course drawn small
#     gets the same number of bigger trees, not a great many specks (which
#     is also most of what this painting costs);
#   - and in stands, with open ground between: woods and clearings, lines
#     of dunes, not one even carpet from edge to edge.
func _draw_country(bare: Array, t: Dictionary) -> void:
	var boxes: Array = []
	for ground in bare:
		boxes.append(_rect_of(ground).grow(3.0))
	var grain: float = SCENERY_PX / SCENERY_CELL
	var standing: Array = []
	for j in range(-1, int(size.y / SCENERY_PX) + 2):
		for i in range(-1, int(size.x / SCENERY_PX) + 2):
			var px := Vector2(float(i) + 0.15 + 0.7 * _rand(i, j, 0), float(j) + 0.15 + 0.7 * _rand(i, j, 1)) * SCENERY_PX
			var lump: float = _lumps(px, STAND_PX, 9)
			var kind := _pick(t.outside, _rand(i, j, 2) / lerpf(0.16, 1.25, smoothstep(0.36, 0.6, lump)))
			if kind == "":
				continue
			var clear := true
			for k in bare.size():
				if (boxes[k] as Rect2).has_point(px) and Geometry2D.is_point_in_polygon(px, bare[k]):
					clear = false
					break
			if not clear:
				continue
			var item := [kind, px, lerpf(0.7, 1.3, _rand(i, j, 3)), hash(Vector3i(i, j, 4))]
			# What lies on the ground goes down now; what stands on it waits.
			if kind in _FLAT:
				_draw_item(kind, px, grain, item[2], item[3], t)
			else:
				standing.append(item)
	for item in standing:
		_draw_item(item[0], item[1], grain, item[2], item[3], t)


# A scale in the bottom margin, where no hole reaches: a hundred yards to
# a division.
func _draw_scale(s: float, font: Font) -> void:
	var at := Vector2(size.x - 14.0 - 300.0 * s, size.y - 11.0)
	var ink := Color(BogeyTheme.CARD_BG, 0.9)
	for k in 3:
		var a := at + Vector2(100.0 * s * k, 0)
		var block := Rect2(a + Vector2(0, -2), Vector2(100.0 * s, 4))
		if k % 2 == 0:
			draw_rect(block, ink)
		else:
			draw_rect(block, ink, false, 1.0)
	draw_string(font, at + Vector2(-64, 3.5), "300 yds", HORIZONTAL_ALIGNMENT_RIGHT, 58, 9, ink)


# A roof behind the first tee, square to the hole.
func _draw_clubhouse(at: Vector2, mat: Transform2D) -> void:
	var along := (mat.basis_xform(Vector2(1, 0))).normalized()
	var up := Vector2(along.y, -along.x)
	var roof := PackedVector2Array()
	for c in [Vector2(-13, -7), Vector2(13, -7), Vector2(13, 7), Vector2(-13, 7)]:
		roof.append(at + along * c.x + up * c.y)
	draw_colored_polygon(_shifted(roof, SHADOW_DIR * 4.0), Color(COLOR_SHADOW, 0.25))
	draw_colored_polygon(roof, BogeyTheme.CARD_BG)
	_outline(roof, Color(BogeyTheme.INK, 0.7), 1.0)
	draw_line(at - along * 13.0, at + along * 13.0, Color(BogeyTheme.INK, 0.45), 1.0, true)
