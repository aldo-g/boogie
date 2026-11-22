class_name HoleData
extends RefCounted

# ---------------------------------------------------------
# Data-driven hole layout. Same public shape as before — par, yardage,
# tee_pos, pin_pos, fairway_polygon, green_polygon, hazards, terrain_at()
# and the hole(n) dispatcher — so Main.gd and CourseMapView need no
# changes. What's new is how the geometry is authored.
#
# Each hole is a CENTRELINE, not a rectangle: an array of
# Vector3(x_offset, yards_out, corridor_width) stations, plus an ellipse
# for the green and its bunkers. CourseShape turns that into flowing
# shapes — the fairway a ribbon along one curve through the stations, the
# water a shoreline through its corner points, greens and bunkers pulled
# off the oval — so doglegs sweep, pinched holes pinch, and the greens sit
# off-axis. The ground in play is shaped the same way: not a box round
# the hole but everything within reach of it (see "The ground in play").
# Yard-space is unchanged: (0,0) at the tee, +y to the pin.
#
# To reshape a hole, move its stations — widths and offsets in yards. To
# add one, add an entry to HOLES; the builder does the rest.
# ---------------------------------------------------------

# The built-in course's length. The course being PLAYED may be shorter —
# ask Course.hole_count(), not this. (The game's other courses are course
# files — see CourseLibrary.)
const HOLE_COUNT := 18

var par: int
var yardage: float
var tee_pos: Vector2
# Where the hole is cut. build() puts it in the middle of the green; a
# round moves it (for_round(), Pins.gd). Everything that plays to the hole
# reads this. Everything about the GREEN — its tilt, its shape, where the
# yardage markers measure to — hangs off green_pos, which never moves.
var pin_pos: Vector2
var green_pos: Vector2
var pin_name: String = ""   # "back left", once a round has cut it; "" before
var fairway_polygon: PackedVector2Array
var green_polygon: PackedVector2Array
var green_fringe_polygon: PackedVector2Array  # collar, for drawing only
var hazards: Array  # [{ "type": "bunker"/"water", "polygon": PackedVector2Array }, ...]
# The ground in play: one outline (more only if parts of a hole don't
# connect). Outside every one of them is out of bounds. `bounds` is the
# box that holds them — what the map frames and the aim is kept inside —
# and is NOT itself the edge of play any more. A hole made without a play
# area (HoleData.new() by hand) falls back to the box alone.
var play_polygons: Array = []
var bounds: Rect2

# Elevation (see height_at()). Authored in feet, because that's how golfers
# talk about it; everything the game computes with is in yards.
var elev_stations: Array = []     # Vector3(yards_out, height_ft, cross_grade_pct)
var spine_centres: Array = []     # Vector2(x, yards_out) — the centreline the cross-fall hangs off
var green_tilt: Vector2 = Vector2.ZERO  # grade % the green falls TOWARD, in yard-space
var green_radius: float = 20.0
var green_radii: Vector2 = Vector2(20, 20)   # across, along — before rotation
var green_rot: float = 0.0                   # degrees

# The terrain the course sits on (CourseTheme), stamped on by build().
# `roll_scale` is that terrain's firmness — the run-out multiplier — held
# here so a shot's outcome stays a pure function of the hole it's played
# on. `number` seeds what no two holes should share: the scenery, and
# the lie of the land (_lie()).
var theme: String = CourseTheme.DEFAULT
var roll_scale: float = 1.0
var number: int = 1

# This hole's wind for the current round: mph, pointing the way it BLOWS
# (yard-space, +y toward the pin). Not part of the hole's layout — it's
# drawn per round (see Wind.for_hole) and set by Main when the hole starts.
var wind: Vector2 = Vector2.ZERO


func _init(p_par: int, p_yardage: float, p_tee: Vector2, p_pin: Vector2,
		p_fairway: PackedVector2Array, p_green: PackedVector2Array, p_hazards: Array,
		p_fringe: PackedVector2Array = PackedVector2Array()) -> void:
	par = p_par
	yardage = p_yardage
	tee_pos = p_tee
	pin_pos = p_pin
	green_pos = p_pin
	fairway_polygon = p_fairway
	green_polygon = p_green
	hazards = p_hazards
	green_fringe_polygon = p_fringe
	bounds = _compute_bounds()


# --- The ground in play ----------------------------------------------
# Anything outside it is out of bounds (Rule 18 — stroke and distance).
#
# It is worked out from the hole's own shapes, never from the map view,
# which depends on the size of the Control it is drawn into: where the
# ball is out of play is a rule, and must not change when the window is
# resized. build() makes it by growing each part of the hole by a margin
# and merging the lot (see _play_area()); the map paints exactly that
# outline and plants the white stakes along it, so the ground painted as
# in play is the ground that counts as in play.
#
# This is the fallback box for a hole with no play area: the shapes'
# extent, at least 60 yards either side of the tee line.
func _compute_bounds() -> Rect2:
	var min_x: float = -60.0
	var max_x: float = 60.0
	for pt in fairway_polygon:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
	for pt in green_polygon:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
	for hazard in hazards:
		for pt in hazard.polygon:
			min_x = min(min_x, pt.x)
			max_x = max(max_x, pt.x)
	var min_y: float = -20.0
	var max_y: float = yardage + 30.0
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


# How far the ground in play reaches beyond each part of a hole, in yards.
# Chosen to give about the room the old 120-yard box gave beside a
# fairway, a little less beside a green and a little more behind one.
const PLAY_LINE := 38.0      # either side of the line of play, tee to pin
const PLAY_FAIRWAY := 34.0   # beyond the fairway's edge
const PLAY_GREEN := 26.0     # beyond the green's
const PLAY_BUNKER := 12.0    # beyond a bunker's
const PLAY_WATER := 8.0      # beyond a shoreline...
const PLAY_WATER_REACH := 30.0  # ...but water only this far past the rest:
                                # a burn or the sea runs on out of play
const PLAY_NOTCH := 14.0        # notches in the outline narrower than twice this are filled
const PLAY_EDGE_STEP := 12.0    # yards between points on the outline
const PLAY_EDGE_WANDER := 6.0   # how far the outline strays, either way


# True when a point lies outside the ground in play.
func is_out_of_bounds(point: Vector2) -> bool:
	if not bounds.has_point(point):
		return true
	if play_polygons.is_empty():
		return false
	for poly in play_polygons:
		if Geometry2D.is_point_in_polygon(point, poly):
			return false
	return true


# The nearest spot in play to `point` — `point` itself if it already is.
# For keeping an aim on the course.
func nearest_in_bounds(point: Vector2) -> Vector2:
	if not is_out_of_bounds(point):
		return point
	if play_polygons.is_empty():
		return point.clamp(bounds.position, bounds.end)
	var best := point
	var best_d := INF
	for poly in play_polygons:
		var n: int = poly.size()
		for i in n:
			var c: Vector2 = Geometry2D.get_closest_point_to_segment(point, poly[i], poly[(i + 1) % n])
			var d: float = point.distance_squared_to(c)
			if d < best_d:
				best_d = d
				best = c
	# A step over the line, so the spot itself counts as in play.
	for nudge in [0.5, 1.5, 4.0]:
		var inside: Vector2 = best + (best - point).normalized() * nudge
		if not is_out_of_bounds(inside):
			return inside
	return best


# Which terrain a point falls in. Priority: green > hazards > fairway >
# rough. The fringe is cosmetic and plays as fairway.
func terrain_at(point: Vector2) -> String:
	if not bounds.has_point(point):
		return "out"
	# Green, sand and fairway are in play by construction — the play area
	# is built outward from them — so only water and open ground need
	# testing against its outline. (That test is the costly one, and this
	# runs for every half-yard a ball rolls.)
	if Geometry2D.is_point_in_polygon(point, green_polygon):
		return "green"
	for hazard in hazards:
		if Geometry2D.is_point_in_polygon(point, hazard.polygon):
			# Water can run on past the stakes: out there it's out of bounds.
			if hazard.type == "water" and is_out_of_bounds(point):
				return "out"
			return hazard.type
	if Geometry2D.is_point_in_polygon(point, fairway_polygon):
		return "fairway"
	return "out" if is_out_of_bounds(point) else "rough"


# --- Elevation -------------------------------------------------------
# One smooth height for any point on the hole, in yards. Pure function of
# the authored data, so every machine and every preview agrees on it.
#
# Four layers:
#   1. the long profile — station heights along the hole, eased so the
#      ground never kinks at a station;
#   2. cross-fall — the fairway tilted sideways about its own centreline;
#   3. the lie of the land — a hill doesn't run dead square across a hole.
#      Off the line of play the ground is a little further up or down the
#      profile than its yards-out says (_lie()), so a climb comes round a
#      shoulder or up a hollow and its contours bend with it;
#   4. the green — a flat tilted plane, blended in over its surrounds, so
#      a green reads one way and doesn't inherit the hill it sits on.
const FEET_PER_YARD := 3.0

# The lie of the land, in yards along the profile. Two swings, each
# changing slowly down the hole and each nothing at all on the line of
# play, so the profile a hole was given is exactly the profile it has
# there (and the one the elevation strip draws):
#   slant — contours cross the line of play at an angle, not square;
#   bow   — they curl forward or back as they run out to the sides.
# It only moves ground along the profile, so it adds no height the
# stations don't have, and level ground stays level.
const LIE_SLANT := 0.3         # the most a contour slants: yards along per yard across
const LIE_SLANT_REACH := 60.0  # yards off the line where the slant starts to level out
const LIE_BOW := 16.0          # the most a contour bows, far out to the side
const LIE_BOW_REACH := 28.0    # yards off the line where the bow is half grown
const LIE_SLANT_WAVE := 200.0  # yards down the hole for the slant to swing over and back
const LIE_BOW_WAVE := 260.0    # ...and the bow

func height_at(p: Vector2) -> float:
	var base := _ground_height(p)
	if green_tilt == Vector2.ZERO and elev_stations.is_empty():
		return base
	# Hung off the middle of the green, not the pin: the green is the same
	# green wherever the hole is cut on it.
	var d: float = p.distance_to(green_pos)
	# Fully the green plane out to its edge, fully the hillside by 1.8x.
	var w: float = 1.0 - smoothstep(green_radius, green_radius * 1.8, d)
	if w <= 0.0:
		return base
	var plane: float = _profile_ft(green_pos.y) / FEET_PER_YARD \
		- green_tilt.dot(p - green_pos) / 100.0
	return lerpf(base, plane, w)


# Downhill is -gradient. Grade as a fraction (0.05 = 5%).
func gradient_at(p: Vector2) -> Vector2:
	var e := 0.5
	return Vector2(
		(height_at(p + Vector2(e, 0)) - height_at(p - Vector2(e, 0))) / (2.0 * e),
		(height_at(p + Vector2(0, e)) - height_at(p - Vector2(0, e))) / (2.0 * e))


func _ground_height(p: Vector2) -> float:
	var off: float = p.x - centre_x_at(p.y)
	var out: float = p.y + _lie(p.y, off)
	return _profile_ft(out) / FEET_PER_YARD \
		- _station_lerp(out, 2) / 100.0 * off


# How many yards further along the profile (+) or back (-) the ground is,
# `off` yards to the side of the line of play at `y` yards out. `number`
# sets where along the hole each swing starts, so no two holes lie alike.
func _lie(y: float, off: float) -> float:
	if elev_stations.size() < 2:
		return 0.0
	var slant: float = off / LIE_SLANT_REACH
	var bow: float = off / LIE_BOW_REACH
	bow *= bow
	var turn: float = float(number) * 2.4
	return LIE_SLANT * sin(y * TAU / LIE_SLANT_WAVE + turn) * off / sqrt(1.0 + slant * slant) \
		+ LIE_BOW * sin(y * TAU / LIE_BOW_WAVE + turn * 1.7 + 1.0) * bow / (1.0 + bow)


func _profile_ft(y: float) -> float:
	return _station_lerp(y, 1)


# Eased (cosine) interpolation of one component of the elevation stations
# by yards out. Zero slope at each station, so a station is a crest, a
# hollow or a shelf — the shapes a course designer would draw.
func _station_lerp(y: float, comp: int) -> float:
	var n := elev_stations.size()
	if n == 0:
		return 0.0
	var first: Vector3 = elev_stations[0]
	if y <= first.x:
		return first[comp]
	for i in range(n - 1):
		var a: Vector3 = elev_stations[i]
		var b: Vector3 = elev_stations[i + 1]
		if y <= b.x:
			var t: float = (y - a.x) / max(b.x - a.x, 0.001)
			t = (1.0 - cos(t * PI)) * 0.5
			return lerpf(a[comp], b[comp], t)
	var last: Vector3 = elev_stations[n - 1]
	return last[comp]


func centre_x_at(y: float) -> float:
	var n := spine_centres.size()
	if n == 0:
		return 0.0
	if y <= spine_centres[0].y:
		return spine_centres[0].x
	for i in range(n - 1):
		var a: Vector2 = spine_centres[i]
		var b: Vector2 = spine_centres[i + 1]
		if y <= b.y:
			return lerpf(a.x, b.x, (y - a.y) / max(b.y - a.y, 0.001))
	return spine_centres[n - 1].x


# --- The pin ---------------------------------------------------------
# How much green is always left between the hole and the edge, in yards.
const PIN_EDGE_MARGIN := 4.0

# A place to cut the hole: `depth` of the way from the middle of the green
# to its edge (0 to 1) in direction `dir`, given in the green's own axes —
# x across it, y along it, before its rotation. Drawn back toward the
# middle until PIN_EDGE_MARGIN yards of green lie all round it, so on a
# small or pinched green a "tucked" pin is simply less tucked.
func pin_spot(dir: Vector2, depth: float) -> Vector2:
	if dir == Vector2.ZERO or green_polygon.is_empty():
		return green_pos
	var reach := Vector2(dir.x * green_radii.x, dir.y * green_radii.y).rotated(deg_to_rad(green_rot))
	var d := clampf(depth, 0.0, 1.0)
	while d > 0.049:
		var spot := green_pos + reach * d
		var room := true
		for k in 8:
			if not Geometry2D.is_point_in_polygon(spot + Vector2.from_angle(TAU * float(k) / 8.0) * PIN_EDGE_MARGIN, green_polygon):
				room = false
				break
		if room:
			return spot
		d -= 0.05
	return green_pos


# Cuts the hole at `spot` (which must be on the green — pin_spot() gives
# such spots) and names where that is.
func cut_pin(spot: Vector2) -> void:
	pin_pos = spot
	pin_name = Pins.describe(self)


# Feet above (+) or below (-) the tee — for labels.
func feet_above_tee(p: Vector2) -> int:
	return int(round((height_at(p) - height_at(tee_pos)) * FEET_PER_YARD))


# --- Hole table ------------------------------------------------------
# spine:  Array[Vector3(x, yards, corridor width)] — the mown centreline.
#         A par 3 gets a short tee apron only; everything to the green is
#         a rough carry.
# green:  { "pos": Vector2, "radii": Vector2, "rot": degrees }
# hazards: bunkers as { "type", "pos", "radii", "rot" };
#          water as   { "type", "poly": PackedVector2Array } (coastlines
#          are authored by hand, then smoothed).
# elev:   Array[Vector3(yards out, height in feet, cross-fall %)] — the
#         long profile, eased between stations. Cross-fall tilts the
#         ground sideways: +3 means it falls 3% toward +x (right, looking
#         from the tee). Heights are relative; the tee is usually 0.
# green_tilt: Vector2 grade % the green falls toward. (0, -2.5) is the
#         classic back-to-front green, falling 2.5% toward the tee.
static var HOLES := {
	1: {
		"par": 4, "yardage": 380.0,
		"elev": [Vector3(0, 0, 0), Vector3(150, -6, 1.5), Vector3(260, -8, 2), Vector3(380, 0, 0)],
		"green_tilt": Vector2(0, -2.5),
		"spine": [Vector3(0, 0, 54), Vector3(17, 60, 52), Vector3(31, 120, 50), Vector3(37, 152, 48), Vector3(41, 185, 46), Vector3(43, 218, 44), Vector3(43, 250, 42), Vector3(35, 290, 37), Vector3(25, 330, 32)],
		"green": {"pos": Vector2(10, 380), "radii": Vector2(24, 19), "rot": -12.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(52, 344), "radii": Vector2(12, 9), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(0, 212), "radii": Vector2(9, 7), "rot": 0.0},
		],
	},
	2: {
		"par": 3, "yardage": 165.0,
		"elev": [Vector3(0, 0, 0), Vector3(165, -18, 0)],
		"green_tilt": Vector2(2, -1.5),
		"spine": [Vector3(0, 0, 26), Vector3(0, 42, 22)],
		"green": {"pos": Vector2(2, 165), "radii": Vector2(26, 20), "rot": 14.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-30, 157), "radii": Vector2(13, 11), "rot": 0.0},
			{"type": "water", "poly": PackedVector2Array([Vector2(36, 88), Vector2(72, 84), Vector2(74, 200), Vector2(34, 198)])},
		],
	},
	3: {
		"par": 5, "yardage": 540.0,
		"elev": [Vector3(0, 0, 0), Vector3(150, 4, 2.5), Vector3(300, 10, 2.5), Vector3(450, 6, 0), Vector3(540, 14, 0)],
		"green_tilt": Vector2(0, -2),
		"spine": [Vector3(0, 0, 46), Vector3(3, 38, 46), Vector3(6, 75, 45), Vector3(12, 150, 44), Vector3(15, 210, 42), Vector3(18, 270, 40), Vector3(1, 330, 39), Vector3(-23, 390, 38), Vector3(-51, 430, 36), Vector3(-80, 470, 34), Vector3(-97, 506, 30)],
		"green": {"pos": Vector2(-107, 540), "radii": Vector2(25, 20), "rot": 20.0},
		"hazards": [
			{"type": "water", "poly": PackedVector2Array([Vector2(42, 188), Vector2(92, 178), Vector2(94, 222), Vector2(95, 265), Vector2(96, 308), Vector2(95, 352), Vector2(34, 338), Vector2(37, 300), Vector2(39, 263), Vector2(40, 226)])},
			{"type": "bunker", "pos": Vector2(-50, 430), "radii": Vector2(10, 8), "rot": 0.0},
		],
	},
	4: {
		"par": 4, "yardage": 410.0,
		"elev": [Vector3(0, 0, 0), Vector3(200, 8, 0), Vector3(410, 24, 0)],
		"green_tilt": Vector2(0, -3),
		"spine": [Vector3(0, 0, 38), Vector3(-2, 32, 37), Vector3(-3, 65, 36), Vector3(-4, 98, 35), Vector3(-6, 130, 34), Vector3(-8, 163, 33), Vector3(-9, 196, 32), Vector3(-9, 229, 31), Vector3(-4, 262, 30), Vector3(12, 302, 28), Vector3(34, 342, 26)],
		"green": {"pos": Vector2(69, 410), "radii": Vector2(22, 18), "rot": -8.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(20, 372), "radii": Vector2(11, 9), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(27, 252), "radii": Vector2(8, 7), "rot": 0.0},
		],
	},
	5: {
		"par": 3, "yardage": 195.0,
		"elev": [Vector3(0, 0, 0), Vector3(195, -30, 0)],
		"green_tilt": Vector2(-2, 0),
		"spine": [Vector3(0, 0, 22), Vector3(0, 32, 18)],
		"green": {"pos": Vector2(0, 195), "radii": Vector2(28, 22), "rot": 0.0},
		"hazards": [],
	},
	6: {
		"par": 4, "yardage": 365.0,
		"elev": [Vector3(0, 0, 0), Vector3(120, -4, 0), Vector3(210, -10, 3), Vector3(330, -6, 2), Vector3(365, -4, 0)],
		"green_tilt": Vector2(1.5, -2),
		"spine": [Vector3(0, 0, 44), Vector3(3, 60, 42), Vector3(6, 120, 40), Vector3(16, 165, 37), Vector3(27, 210, 34), Vector3(44, 251, 33), Vector3(64, 292, 32), Vector3(78, 330, 28)],
		"green": {"pos": Vector2(88, 365), "radii": Vector2(23, 19), "rot": 24.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(34, 200), "radii": Vector2(11, 9), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(57, 236), "radii": Vector2(10, 8), "rot": 0.0},
		],
	},
	7: {
		"par": 4, "yardage": 425.0,
		"elev": [Vector3(0, 0, 0), Vector3(110, 6, 0), Vector3(225, 10, 0), Vector3(320, 2, 0), Vector3(425, -2, 0)],
		"green_tilt": Vector2(0, 1.5),
		"spine": [Vector3(0, 0, 40), Vector3(0, 55, 37), Vector3(0, 110, 34), Vector3(1, 168, 27), Vector3(2, 225, 20), Vector3(-3, 272, 25), Vector3(-22, 320, 30), Vector3(-50, 372, 28)],
		"green": {"pos": Vector2(-80, 425), "radii": Vector2(22, 19), "rot": 0.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-24, 228), "radii": Vector2(8, 15), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(24, 250), "radii": Vector2(8, 13), "rot": 0.0},
		],
	},
	8: {
		"par": 5, "yardage": 510.0,
		"elev": [Vector3(0, 0, 0), Vector3(250, -6, 0), Vector3(430, -14, 0), Vector3(510, -10, 0)],
		"green_tilt": Vector2(0, -2),
		"spine": [Vector3(0, 0, 50), Vector3(20, 32, 49), Vector3(37, 65, 48), Vector3(49, 98, 47), Vector3(56, 130, 46), Vector3(51, 190, 43), Vector3(30, 250, 40), Vector3(-6, 305, 38), Vector3(-32, 360, 36), Vector3(-40, 400, 34), Vector3(-38, 440, 32)],
		"green": {"pos": Vector2(-6, 510), "radii": Vector2(25, 20), "rot": -16.0},
		"hazards": [
			{"type": "water", "poly": PackedVector2Array([Vector2(-68, 452), Vector2(15, 460), Vector2(24, 494), Vector2(-47, 488)])},
			{"type": "bunker", "pos": Vector2(15, 300), "radii": Vector2(10, 9), "rot": 0.0},
		],
	},
	9: {
		"par": 4, "yardage": 395.0,
		"elev": [Vector3(0, 0, 0), Vector3(250, 6, -1.5), Vector3(395, 20, 0)],
		"green_tilt": Vector2(0, -3),
		"spine": [Vector3(0, 0, 48), Vector3(-19, 60, 45), Vector3(-34, 120, 42), Vector3(-38, 152, 40), Vector3(-39, 185, 37), Vector3(-38, 218, 34), Vector3(-34, 250, 32), Vector3(-27, 291, 29), Vector3(-17, 332, 26)],
		"green": {"pos": Vector2(2, 398), "radii": Vector2(20, 27), "rot": 0.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(15, 354), "radii": Vector2(11, 9), "rot": 0.0},
		],
	},
	10: {
		"par": 4, "yardage": 375.0,
		"elev": [Vector3(0, 0, 0), Vector3(110, -12, 0), Vector3(232, -20, -2), Vector3(375, -22, 0)],
		"green_tilt": Vector2(-1.5, -1.5),
		"spine": [Vector3(0, 0, 50), Vector3(-8, 55, 48), Vector3(-16, 110, 46), Vector3(-10, 140, 45), Vector3(-3, 171, 44), Vector3(6, 202, 43), Vector3(19, 232, 42), Vector3(28, 276, 37), Vector3(41, 320, 32)],
		"green": {"pos": Vector2(68, 375), "radii": Vector2(23, 19), "rot": 10.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(20, 340), "radii": Vector2(11, 9), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(27, 178), "radii": Vector2(9, 8), "rot": 0.0},
		],
	},
	11: {
		"par": 3, "yardage": 145.0,
		"elev": [Vector3(0, 0, 0), Vector3(145, 6, 0)],
		"green_tilt": Vector2(2.5, 0),
		"spine": [Vector3(0, 0, 22), Vector3(0, 38, 20)],
		"green": {"pos": Vector2(-2, 145), "radii": Vector2(18, 15), "rot": -10.0},
		"hazards": [
			{"type": "water", "poly": PackedVector2Array([Vector2(18, 18), Vector2(56, 22), Vector2(54, 168), Vector2(16, 158)])},
			{"type": "bunker", "pos": Vector2(-25, 140), "radii": Vector2(9, 8), "rot": 0.0},
		],
	},
	12: {
		"par": 5, "yardage": 560.0,
		"elev": [Vector3(0, 0, 0), Vector3(140, 8, 0), Vector3(290, 0, 2), Vector3(420, 10, -2), Vector3(560, 6, 0)],
		"green_tilt": Vector2(0, -2),
		"spine": [Vector3(0, 0, 46), Vector3(-5, 70, 45), Vector3(-10, 140, 44), Vector3(-6, 178, 43), Vector3(-1, 215, 42), Vector3(4, 252, 41), Vector3(8, 290, 40), Vector3(2, 355, 37), Vector3(11, 420, 34), Vector3(34, 461, 32), Vector3(59, 502, 30)],
		"green": {"pos": Vector2(90, 560), "radii": Vector2(24, 20), "rot": 0.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-46, 200), "radii": Vector2(13, 11), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(42, 340), "radii": Vector2(12, 10), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(34, 470), "radii": Vector2(9, 8), "rot": 0.0},
		],
	},
	13: {
		"par": 4, "yardage": 400.0,
		"elev": [Vector3(0, 0, 0), Vector3(242, -6, 2.5), Vector3(400, -2, 0)],
		"green_tilt": Vector2(2, -1),
		"spine": [Vector3(0, 0, 44), Vector3(5, 60, 41), Vector3(10, 120, 38), Vector3(12, 150, 36), Vector3(15, 181, 35), Vector3(18, 212, 34), Vector3(23, 242, 32), Vector3(34, 287, 30), Vector3(50, 332, 28)],
		"green": {"pos": Vector2(74, 400), "radii": Vector2(22, 18), "rot": 18.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(63, 300), "radii": Vector2(10, 9), "rot": 0.0},
		],
	},
	14: {
		"par": 4, "yardage": 355.0,
		"elev": [Vector3(0, 0, 0), Vector3(222, 4, 0), Vector3(355, 12, 0)],
		"green_tilt": Vector2(0, -1.5),
		"spine": [Vector3(0, 0, 52), Vector3(14, 55, 50), Vector3(23, 110, 48), Vector3(33, 166, 46), Vector3(33, 222, 44), Vector3(28, 257, 39), Vector3(20, 292, 34)],
		"green": {"pos": Vector2(0, 355), "radii": Vector2(16, 14), "rot": 0.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-24, 346), "radii": Vector2(11, 16), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(30, 346), "radii": Vector2(11, 16), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(0, 379), "radii": Vector2(14, 8), "rot": 0.0},
		],
	},
	15: {
		"par": 3, "yardage": 175.0,
		"elev": [Vector3(0, 0, 0), Vector3(175, -8, 0)],
		"green_tilt": Vector2(0, -2),
		"spine": [Vector3(0, 0, 24), Vector3(0, 34, 20)],
		"green": {"pos": Vector2(0, 175), "radii": Vector2(26, 17), "rot": -14.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-35, 166), "radii": Vector2(12, 11), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(35, 166), "radii": Vector2(12, 11), "rot": 0.0},
		],
	},
	16: {
		"par": 4, "yardage": 415.0,
		"elev": [Vector3(0, 0, 0), Vector3(130, 2, -2.5), Vector3(262, 6, -2.5), Vector3(415, 10, 0)],
		"green_tilt": Vector2(1, -2),
		"spine": [Vector3(0, 0, 34), Vector3(-2, 32, 32), Vector3(-4, 65, 30), Vector3(-6, 98, 28), Vector3(-8, 130, 26), Vector3(-6, 163, 25), Vector3(-5, 196, 24), Vector3(-5, 229, 22), Vector3(-10, 262, 21), Vector3(-22, 302, 22), Vector3(-40, 342, 22)],
		"green": {"pos": Vector2(-79, 415), "radii": Vector2(20, 17), "rot": 12.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-36, 374), "radii": Vector2(10, 9), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(-23, 232), "radii": Vector2(7, 13), "rot": 0.0},
		],
	},
	17: {
		"par": 3, "yardage": 155.0,
		"elev": [Vector3(0, 0, 0), Vector3(155, -10, 0)],
		"green_tilt": Vector2(0, -1.5),
		"spine": [Vector3(0, 0, 20), Vector3(0, 26, 18)],
		"green": {"pos": Vector2(0, 155), "radii": Vector2(24, 20), "rot": 0.0},
		"hazards": [
			{"type": "water", "poly": PackedVector2Array([
				Vector2(-52, 26), Vector2(52, 26), Vector2(54, 188), Vector2(27, 188),
				Vector2(26, 140), Vector2(-26, 140), Vector2(-27, 188), Vector2(-54, 188)])},
		],
	},
	18: {
		"par": 5, "yardage": 545.0,
		"elev": [Vector3(0, 0, 0), Vector3(140, -6, 0), Vector3(280, -2, 1.5), Vector3(400, 4, 0), Vector3(472, -4, 0), Vector3(545, 14, 0)],
		"green_tilt": Vector2(0, -3),
		"spine": [Vector3(0, 0, 56), Vector3(-10, 35, 55), Vector3(-17, 70, 54), Vector3(-21, 105, 53), Vector3(-18, 140, 52), Vector3(-10, 210, 49), Vector3(13, 280, 46), Vector3(24, 340, 43), Vector3(22, 400, 40), Vector3(23, 436, 37), Vector3(18, 472, 34)],
		"green": {"pos": Vector2(-8, 545), "radii": Vector2(26, 21), "rot": -14.0},
		"hazards": [
			{"type": "water", "poly": PackedVector2Array([Vector2(-21, 476), Vector2(67, 484), Vector2(48, 516), Vector2(-28, 508)])},
			{"type": "bunker", "pos": Vector2(68, 360), "radii": Vector2(11, 9), "rot": 0.0},
		],
	},
}


# --- Builder ---------------------------------------------------------
# Hole n of the active course (see Course.gd) — built-in or custom.
static func hole(n: int) -> HoleData:
	if n < 1 or n > Course.hole_count():
		push_error("HoleData.hole(): no hole defined for index %d" % n)
		n = 1
	return build(Course.hole_def(n), n, Course.active_theme)


# Hole n of the active course as it plays in ONE round: the hole itself,
# plus the two things that change from round to round — the wind, and
# where the pin is cut. Both are pure functions of the round's seed and
# the hole number (Wind.gd, Pins.gd), so every machine in an online round
# builds the same hole from the one seed it was sent. Anything that plays
# a hole should build it with this; hole() is the bare layout.
static func for_round(n: int, seed: int) -> HoleData:
	var h := hole(n)
	h.wind = Wind.for_hole(seed, n)
	h.cut_pin(Pins.for_hole(seed, n, h))
	return h


# Builds a playable hole from one definition. `n` seeds the organic edge
# wobble and the lie of the land, so the same definition as the same hole
# number always makes the same hole.
# `p_theme` is the course's terrain: it sets the firmness and the look,
# never the shape.
static func build(d: Dictionary, n: int, p_theme: String = CourseTheme.DEFAULT) -> HoleData:
	var seed: float = float(n) * 1.7
	var spine: Array = d.spine
	var g: Dictionary = d.green

	# The fairway runs on into the mouth of the green: one more station,
	# just short of the pin and about as wide as the green. Only where a
	# fairway actually runs in — the par 3s play a rough carry from the tee
	# apron, which is what their identity text calls for.
	var stations: Array = spine.duplicate()
	var last: Vector3 = spine[spine.size() - 1]
	if last.y > 60.0:
		var mouth := Vector3(g.pos.x, g.pos.y - g.radii.y * 0.35,
			clampf(g.radii.x * 1.15, 14.0, maxf(last.z, 14.0)))
		if mouth.y > last.y + 12.0:
			stations.append(mouth)
	var ribbon := CourseShape.ribbon(stations, 8.0, 3.5, seed, 5.0)
	var fairway: PackedVector2Array = ribbon.poly
	var green := CourseShape.smooth(CourseShape.lobed(g.pos, g.radii, g.rot, 24, 0.05, 0.07, seed + 3.0), 4)
	var fringe := CourseShape.grow(green, 6.0)

	var hazards: Array = []
	var index := 0
	for h in d.hazards:
		if h.type == "water":
			hazards.append({"type": "water", "polygon": _shoreline(h.poly, seed + 5.0 + float(index))})
		else:
			hazards.append({
				"type": "bunker",
				"polygon": CourseShape.smooth(CourseShape.lobed(h.pos, h.radii, h.rot, 15, 0.10, 0.14, seed + 9.0 + float(index)), 3),
			})
		index += 1

	var h := HoleData.new(d.par, d.yardage, Vector2(spine[0].x, 0.0), g.pos, fairway, green, hazards, fringe)
	h._play_area(ribbon.centre, seed + 21.0)
	h.elev_stations = d.get("elev", [])
	h.green_tilt = d.get("green_tilt", Vector2.ZERO)
	h.green_radius = max(g.radii.x, g.radii.y)
	h.green_radii = g.radii
	h.green_rot = float(g.rot)
	h.theme = CourseTheme.sanitise(p_theme)
	h.roll_scale = CourseTheme.roll_scale(h.theme)
	h.number = n
	for st in spine:
		h.spine_centres.append(Vector2(st.x, st.y))
	h.spine_centres.append(g.pos)
	return h


# Water: a shoreline through the authored corner points, with a little
# wander — less on a narrow burn than on a lake, so a stream can't be
# pinched shut. Falls back to plainer shapes if one won't triangulate.
static func _shoreline(corners: PackedVector2Array, seed: float) -> PackedVector2Array:
	var shore := CourseShape.flow_closed(corners, 11.0)
	# A curve through the corners bows out past the straight edges between
	# them, which would make every pond bigger than it was drawn. Drawn in
	# about its middle until it covers what the corners enclose, the water
	# is as much hazard as its author meant and no more.
	var meant: float = absf(CourseShape.polygon_area(corners))
	var made: float = absf(CourseShape.polygon_area(shore))
	if made > meant and meant > 1.0:
		var middle := Vector2.ZERO
		for pt in shore:
			middle += pt
		middle /= float(shore.size())
		var k: float = maxf(sqrt(meant / made), 0.8)
		for i in shore.size():
			shore[i] = middle + (shore[i] - middle) * k
	var around := 0.0
	for i in shore.size():
		around += shore[i].distance_to(shore[(i + 1) % shore.size()])
	# Twice the area over the distance round: about the width of a long
	# thin shape, about the radius of a round one.
	var breadth: float = 2.0 * absf(CourseShape.polygon_area(shore)) / maxf(around, 1.0)
	var wandering := CourseShape.smooth(CourseShape.soft_edge(shore, 11.0, minf(6.0, breadth * 0.16), seed), 3)
	for candidate in [wandering, shore]:
		if not Geometry2D.triangulate_polygon(candidate).is_empty():
			return candidate
	return corners


# Works out the ground in play (see "The ground in play", above) and the
# box that frames it. `line` is the fairway's centreline, tee end first.
func _play_area(line: PackedVector2Array, seed: float) -> void:
	var to_pin := PackedVector2Array(line)
	to_pin.append(pin_pos)
	var land_parts: Array = []
	land_parts.append_array(CourseShape.corridor_round(to_pin, PLAY_LINE))
	land_parts.append_array(CourseShape.grown(fairway_polygon, PLAY_FAIRWAY))
	land_parts.append_array(CourseShape.grown(green_polygon, PLAY_GREEN))
	for hazard in hazards:
		if hazard.type != "water":
			land_parts.append_array(CourseShape.grown(hazard.polygon, PLAY_BUNKER))
	var land := CourseShape.union_all(land_parts)

	# Water joins in only where it's near the rest. A burn across the
	# fairway is a hazard; the same burn a hundred yards off in the trees
	# is just scenery, and out of bounds.
	var parts: Array = land.duplicate()
	var reach: Array = []
	for piece in land:
		reach.append_array(CourseShape.grown(piece, PLAY_WATER_REACH))
	for hazard in hazards:
		if hazard.type != "water":
			continue
		for shore in CourseShape.grown(hazard.polygon, PLAY_WATER):
			for near in reach:
				parts.append_array(CourseShape.outlines(Geometry2D.intersect_polygons(shore, near)))

	play_polygons = []
	for piece in CourseShape.union_all(parts):
		# Where two parts meet they leave a notch, and a notch is both ugly
		# and the place an outline is likeliest to cross itself once it's
		# made to wander. Growing the shape and shrinking it back by the
		# same amount fills every notch narrower than twice that.
		var filled: PackedVector2Array = piece
		for out in CourseShape.grown(piece, PLAY_NOTCH):
			for back in CourseShape.grown(out, -PLAY_NOTCH):
				if absf(CourseShape.polygon_area(back)) > absf(CourseShape.polygon_area(filled)) * 0.5:
					filled = back
		# Wander as far as it safely can: less, or not at all, if the full
		# amount would tangle it.
		for wander in [PLAY_EDGE_WANDER, PLAY_EDGE_WANDER * 0.5, 0.0]:
			var edge := CourseShape.soft_edge(filled, PLAY_EDGE_STEP, wander, seed)
			if edge.size() >= 3 and not Geometry2D.triangulate_polygon(edge).is_empty():
				play_polygons.append(edge)
				break
	if play_polygons.is_empty():
		return   # keep the fallback box
	var box := Rect2(play_polygons[0][0], Vector2.ZERO)
	for poly in play_polygons:
		for pt in poly:
			box = box.expand(pt)
	bounds = box.grow(1.0)
