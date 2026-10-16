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
# for the green and its bunkers. CourseShape turns that into smooth,
# curving polygons, so doglegs dogleg, pinched holes pinch, and the greens
# sit off-axis. Yard-space is unchanged: (0,0) at the tee, +y to the pin.
#
# To reshape a hole, move its stations — widths and offsets in yards. To
# add one, add an entry to HOLES; the builder does the rest.
# ---------------------------------------------------------

# The built-in course's length. The course being PLAYED may be shorter —
# ask Course.hole_count(), not this.
const HOLE_COUNT := 18

var par: int
var yardage: float
var tee_pos: Vector2
var pin_pos: Vector2
var fairway_polygon: PackedVector2Array
var green_polygon: PackedVector2Array
var green_fringe_polygon: PackedVector2Array  # collar, for drawing only
var hazards: Array  # [{ "type": "bunker"/"water", "polygon": PackedVector2Array }, ...]
var bounds: Rect2   # playable extent in yards; outside it is out of bounds

# Elevation (see height_at()). Authored in feet, because that's how golfers
# talk about it; everything the game computes with is in yards.
var elev_stations: Array = []     # Vector3(yards_out, height_ft, cross_grade_pct)
var spine_centres: Array = []     # Vector2(x, yards_out) — the centreline the cross-fall hangs off
var green_tilt: Vector2 = Vector2.ZERO  # grade % the green falls TOWARD, in yard-space
var green_radius: float = 20.0

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
	fairway_polygon = p_fairway
	green_polygon = p_green
	hazards = p_hazards
	green_fringe_polygon = p_fringe
	bounds = _compute_bounds()


# The playable extent of the hole, in yards. Anything outside is out of
# bounds (Rule 18 — stroke and distance).
#
# Computed from the hole's own geometry rather than from the map view's
# _yard_extent(), which depends on the size of the Control it is drawn
# into: where the ball is out of play is a rule, and must not change when
# the window is resized. The two are deliberately kept in agreement — the
# view uses the same -60/+60 x floor and the same tee/pin margins — so the
# green painted on screen is exactly the ground that counts as in play.
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


# True when a point lies outside the hole's playable extent.
func is_out_of_bounds(point: Vector2) -> bool:
	return not bounds.has_point(point)


# Which terrain a point falls in. Priority: green > hazards > fairway >
# rough. The fringe is cosmetic and plays as fairway.
func terrain_at(point: Vector2) -> String:
	# Checked first: a point off the course is out of bounds even if it
	# would otherwise fall inside a polygon that extends past the edge.
	if is_out_of_bounds(point):
		return "out"
	if Geometry2D.is_point_in_polygon(point, green_polygon):
		return "green"
	for hazard in hazards:
		if Geometry2D.is_point_in_polygon(point, hazard.polygon):
			return hazard.type
	if Geometry2D.is_point_in_polygon(point, fairway_polygon):
		return "fairway"
	return "rough"


# --- Elevation -------------------------------------------------------
# One smooth height for any point on the hole, in yards. Pure function of
# the authored data, so every machine and every preview agrees on it.
#
# Three layers:
#   1. the long profile — station heights along the hole, eased so the
#      ground never kinks at a station;
#   2. cross-fall — the fairway tilted sideways about its own centreline;
#   3. the green — a flat tilted plane, blended in over its surrounds, so
#      a green reads one way and doesn't inherit the hill it sits on.
const FEET_PER_YARD := 3.0

func height_at(p: Vector2) -> float:
	var base := _ground_height(p)
	if green_tilt == Vector2.ZERO and elev_stations.is_empty():
		return base
	var d: float = p.distance_to(pin_pos)
	# Fully the green plane out to its edge, fully the hillside by 1.8x.
	var w: float = 1.0 - smoothstep(green_radius, green_radius * 1.8, d)
	if w <= 0.0:
		return base
	var plane: float = _profile_ft(pin_pos.y) / FEET_PER_YARD \
		- green_tilt.dot(p - pin_pos) / 100.0
	return lerpf(base, plane, w)


# Downhill is -gradient. Grade as a fraction (0.05 = 5%).
func gradient_at(p: Vector2) -> Vector2:
	var e := 0.5
	return Vector2(
		(height_at(p + Vector2(e, 0)) - height_at(p - Vector2(e, 0))) / (2.0 * e),
		(height_at(p + Vector2(0, e)) - height_at(p - Vector2(0, e))) / (2.0 * e))


func _ground_height(p: Vector2) -> float:
	var cross_pct: float = _station_lerp(p.y, 2)
	return _profile_ft(p.y) / FEET_PER_YARD \
		- cross_pct / 100.0 * (p.x - centre_x_at(p.y))


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
		"spine": [Vector3(0, 0, 54), Vector3(8, 120, 50), Vector3(18, 250, 42), Vector3(14, 330, 32)],
		"green": {"pos": Vector2(10, 380), "radii": Vector2(24, 19), "rot": -12.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(44, 344), "radii": Vector2(12, 9), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(-28, 212), "radii": Vector2(9, 7), "rot": 0.0},
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
		"spine": [Vector3(0, 0, 46), Vector3(12, 150, 44), Vector3(18, 270, 40), Vector3(-14, 390, 38), Vector3(-52, 470, 34), Vector3(-60, 506, 30)],
		"green": {"pos": Vector2(-62, 540), "radii": Vector2(25, 20), "rot": 20.0},
		"hazards": [
			{"type": "water", "poly": PackedVector2Array([Vector2(42, 188), Vector2(92, 178), Vector2(98, 352), Vector2(36, 338)])},
			{"type": "bunker", "pos": Vector2(-32, 430), "radii": Vector2(10, 8), "rot": 0.0},
		],
	},
	4: {
		"par": 4, "yardage": 410.0,
		"elev": [Vector3(0, 0, 0), Vector3(200, 8, 0), Vector3(410, 24, 0)],
		"green_tilt": Vector2(0, -3),
		"spine": [Vector3(0, 0, 38), Vector3(-6, 130, 34), Vector3(-12, 262, 30), Vector3(-8, 342, 26)],
		"green": {"pos": Vector2(-6, 410), "radii": Vector2(22, 18), "rot": -8.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-36, 372), "radii": Vector2(11, 9), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(22, 252), "radii": Vector2(8, 7), "rot": 0.0},
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
		"spine": [Vector3(0, 0, 44), Vector3(6, 120, 40), Vector3(26, 210, 34), Vector3(50, 292, 32), Vector3(56, 330, 28)],
		"green": {"pos": Vector2(58, 365), "radii": Vector2(23, 19), "rot": 24.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(34, 200), "radii": Vector2(11, 9), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(54, 236), "radii": Vector2(10, 8), "rot": 0.0},
		],
	},
	7: {
		"par": 4, "yardage": 425.0,
		"elev": [Vector3(0, 0, 0), Vector3(110, 6, 0), Vector3(225, 10, 0), Vector3(320, 2, 0), Vector3(425, -2, 0)],
		"green_tilt": Vector2(0, 1.5),
		"spine": [Vector3(0, 0, 40), Vector3(0, 110, 34), Vector3(2, 225, 20), Vector3(0, 320, 30), Vector3(0, 372, 28)],
		"green": {"pos": Vector2(0, 425), "radii": Vector2(22, 19), "rot": 0.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-24, 228), "radii": Vector2(8, 15), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(25, 250), "radii": Vector2(8, 13), "rot": 0.0},
		],
	},
	8: {
		"par": 5, "yardage": 510.0,
		"elev": [Vector3(0, 0, 0), Vector3(250, -6, 0), Vector3(430, -14, 0), Vector3(510, -10, 0)],
		"green_tilt": Vector2(0, -2),
		"spine": [Vector3(0, 0, 50), Vector3(16, 130, 46), Vector3(28, 250, 40), Vector3(6, 360, 36), Vector3(-8, 440, 32)],
		"green": {"pos": Vector2(-6, 510), "radii": Vector2(25, 20), "rot": -16.0},
		"hazards": [
			{"type": "water", "poly": PackedVector2Array([Vector2(-42, 452), Vector2(38, 460), Vector2(32, 494), Vector2(-36, 488)])},
			{"type": "bunker", "pos": Vector2(36, 300), "radii": Vector2(10, 9), "rot": 0.0},
		],
	},
	9: {
		"par": 4, "yardage": 395.0,
		"elev": [Vector3(0, 0, 0), Vector3(250, 6, -1.5), Vector3(395, 20, 0)],
		"green_tilt": Vector2(0, -3),
		"spine": [Vector3(0, 0, 48), Vector3(-6, 120, 42), Vector3(-2, 250, 32), Vector3(0, 332, 26)],
		"green": {"pos": Vector2(2, 398), "radii": Vector2(20, 27), "rot": 0.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(27, 354), "radii": Vector2(11, 9), "rot": 0.0},
		],
	},
	10: {
		"par": 4, "yardage": 375.0,
		"elev": [Vector3(0, 0, 0), Vector3(110, -12, 0), Vector3(232, -20, -2), Vector3(375, -22, 0)],
		"green_tilt": Vector2(-1.5, -1.5),
		"spine": [Vector3(0, 0, 50), Vector3(-16, 110, 46), Vector3(10, 232, 42), Vector3(-4, 320, 32)],
		"green": {"pos": Vector2(-2, 375), "radii": Vector2(23, 19), "rot": 10.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-34, 340), "radii": Vector2(11, 9), "rot": 0.0},
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
		"spine": [Vector3(0, 0, 46), Vector3(-10, 140, 44), Vector3(8, 290, 40), Vector3(-6, 420, 34), Vector3(0, 502, 30)],
		"green": {"pos": Vector2(0, 560), "radii": Vector2(24, 20), "rot": 0.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-46, 200), "radii": Vector2(13, 11), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(42, 340), "radii": Vector2(12, 10), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(-8, 470), "radii": Vector2(9, 8), "rot": 0.0},
		],
	},
	13: {
		"par": 4, "yardage": 400.0,
		"elev": [Vector3(0, 0, 0), Vector3(242, -6, 2.5), Vector3(400, -2, 0)],
		"green_tilt": Vector2(2, -1),
		"spine": [Vector3(0, 0, 44), Vector3(10, 120, 38), Vector3(20, 242, 32), Vector3(23, 332, 28)],
		"green": {"pos": Vector2(24, 400), "radii": Vector2(22, 18), "rot": 18.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(46, 300), "radii": Vector2(10, 9), "rot": 0.0},
		],
	},
	14: {
		"par": 4, "yardage": 355.0,
		"elev": [Vector3(0, 0, 0), Vector3(222, 4, 0), Vector3(355, 12, 0)],
		"green_tilt": Vector2(0, -1.5),
		"spine": [Vector3(0, 0, 52), Vector3(-8, 110, 48), Vector3(-2, 222, 44), Vector3(0, 292, 34)],
		"green": {"pos": Vector2(0, 355), "radii": Vector2(16, 14), "rot": 0.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(-27, 346), "radii": Vector2(11, 16), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(27, 346), "radii": Vector2(11, 16), "rot": 0.0},
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
		"spine": [Vector3(0, 0, 34), Vector3(-8, 130, 26), Vector3(-2, 262, 21), Vector3(5, 342, 22)],
		"green": {"pos": Vector2(6, 415), "radii": Vector2(20, 17), "rot": 12.0},
		"hazards": [
			{"type": "bunker", "pos": Vector2(27, 374), "radii": Vector2(10, 9), "rot": 0.0},
			{"type": "bunker", "pos": Vector2(-21, 232), "radii": Vector2(7, 13), "rot": 0.0},
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
		"spine": [Vector3(0, 0, 56), Vector3(20, 140, 52), Vector3(10, 280, 46), Vector3(-16, 400, 40), Vector3(-10, 472, 34)],
		"green": {"pos": Vector2(-8, 545), "radii": Vector2(26, 21), "rot": -14.0},
		"hazards": [
			{"type": "water", "poly": PackedVector2Array([Vector2(-48, 476), Vector2(42, 484), Vector2(36, 516), Vector2(-44, 508)])},
			{"type": "bunker", "pos": Vector2(36, 360), "radii": Vector2(11, 9), "rot": 0.0},
		],
	},
}


# --- Builder ---------------------------------------------------------
# Hole n of the active course (see Course.gd) — built-in or custom.
static func hole(n: int) -> HoleData:
	if n < 1 or n > Course.hole_count():
		push_error("HoleData.hole(): no hole defined for index %d" % n)
		n = 1
	return build(Course.hole_def(n), n)


# Builds a playable hole from one definition. `n` only seeds the organic
# edge wobble, so the same definition always draws the same outline.
static func build(d: Dictionary, n: int) -> HoleData:
	var seed: float = float(n) * 1.7
	var spine: Array = d.spine
	var g: Dictionary = d.green

	var fairway := CourseShape.smooth(CourseShape.organic(CourseShape.corridor(spine), 26.0, 5.0, seed), 5)
	var green := CourseShape.smooth(CourseShape.ellipse(g.pos, g.radii, g.rot, 24, 0.07, seed + 3.0), 4)
	var fringe := CourseShape.grow(green, 6.0)

	# Approach neck: only where a fairway actually runs in. The par 3s
	# play a rough carry from the tee apron, which is what their identity
	# text calls for.
	var last: Vector3 = spine[spine.size() - 1]
	if last.y > 60.0:
		var neck := PackedVector2Array([
			Vector2(last.x - last.z * 0.46, last.y - 14.0),
			Vector2(last.x + last.z * 0.46, last.y - 14.0),
			Vector2(g.pos.x + g.radii.x * 0.6, g.pos.y - g.radii.y * 0.5),
			Vector2(g.pos.x - g.radii.x * 0.6, g.pos.y - g.radii.y * 0.5),
		])
		var neck_shape := CourseShape.smooth(CourseShape.organic(neck, 22.0, 3.5, seed + 17.0), 4)
		fairway = CourseShape.union_largest(fairway, neck_shape)

	var hazards: Array = []
	var index := 0
	for h in d.hazards:
		if h.type == "water":
			hazards.append({
				"type": "water",
				"polygon": CourseShape.smooth(CourseShape.organic(h.poly, 13.0, 9.5, seed + 5.0 + float(index)), 4),
			})
		else:
			hazards.append({
				"type": "bunker",
				"polygon": CourseShape.smooth(CourseShape.ellipse(h.pos, h.radii, h.rot, 15, 0.16, seed + 9.0 + float(index)), 3),
			})
		index += 1

	var h := HoleData.new(d.par, d.yardage, Vector2(spine[0].x, 0.0), g.pos, fairway, green, hazards, fringe)
	h.elev_stations = d.get("elev", [])
	h.green_tilt = d.get("green_tilt", Vector2.ZERO)
	h.green_radius = max(g.radii.x, g.radii.y)
	for st in spine:
		h.spine_centres.append(Vector2(st.x, st.y))
	h.spine_centres.append(g.pos)
	return h
