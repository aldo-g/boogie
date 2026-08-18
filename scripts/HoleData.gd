class_name HoleData
extends RefCounted

# ---------------------------------------------------------
# Data-driven hole layout: tee/pin points and terrain zones as polygons,
# all in yard-space with (0,0) at the tee and +y running toward the pin.
# This is the format future holes (Section 10's full 18) can be authored
# in without further code changes — just new HoleData.new() calls with
# different point data.
# ---------------------------------------------------------

var par: int
var yardage: float
var tee_pos: Vector2
var pin_pos: Vector2
var fairway_polygon: PackedVector2Array
var green_polygon: PackedVector2Array
var hazards: Array  # Array of { "type": "bunker"/"rough"/"water", "polygon": PackedVector2Array }


func _init(p_par: int, p_yardage: float, p_tee: Vector2, p_pin: Vector2,
		p_fairway: PackedVector2Array, p_green: PackedVector2Array, p_hazards: Array) -> void:
	par = p_par
	yardage = p_yardage
	tee_pos = p_tee
	pin_pos = p_pin
	fairway_polygon = p_fairway
	green_polygon = p_green
	hazards = p_hazards


# Which terrain a point (in the same yard-space as the polygons) falls in.
# Checked in priority order: green > hazards > fairway > rough (default miss).
func terrain_at(point: Vector2) -> String:
	if Geometry2D.is_point_in_polygon(point, green_polygon):
		return "green"
	for hazard in hazards:
		if Geometry2D.is_point_in_polygon(point, hazard.polygon):
			return hazard.type
	if Geometry2D.is_point_in_polygon(point, fairway_polygon):
		return "fairway"
	return "rough"


# --- Hole 1 — "Boogie Links", from GAME_DESIGN.md Section 10:
# Par 4, 380 yards. Straightaway opener, generous fairway, single pot
# bunker short-right — a calm on-ramp before the round gets teeth.
static func hole_1() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 380)

	# Generous fairway: a wide, gently tapering corridor from tee to green.
	var fairway := PackedVector2Array([
		Vector2(-45, 0), Vector2(45, 0),
		Vector2(38, 300), Vector2(-38, 300),
	])

	var green := PackedVector2Array([
		Vector2(-20, 360), Vector2(20, 360),
		Vector2(20, 400), Vector2(-20, 400),
	])

	# Single pot bunker, short-right of the green.
	var bunker := PackedVector2Array([
		Vector2(22, 330), Vector2(40, 330),
		Vector2(40, 350), Vector2(22, 350),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker},
	]

	return HoleData.new(4, 380.0, tee, pin, fairway, green, hazards)


# --- Hole 2 — Par 3, 165 yards.
# Coastal par 3, green guarded left by a deep pot bunker — tests
# Precision-brand Accuracy play.
static func hole_2() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 165)

	var fairway := PackedVector2Array([
		Vector2(-24, 0), Vector2(24, 0),
		Vector2(30, 120), Vector2(-30, 120),
	])

	var green := PackedVector2Array([
		Vector2(-24, 140), Vector2(22, 140),
		Vector2(22, 178), Vector2(-24, 178),
	])

	var bunker := PackedVector2Array([
		Vector2(-42, 138), Vector2(-24, 138),
		Vector2(-24, 172), Vector2(-42, 172),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker},
	]

	return HoleData.new(3, 165.0, tee, pin, fairway, green, hazards)


# --- Hole 3 — Par 5, 540 yards.
# Dogleg-left par 5 along the coastline — rewards the Aim Tool's free-aim
# layup line to bite off as much of the dogleg as the player dares.
static func hole_3() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(-60, 540)

	var fairway := PackedVector2Array([
		Vector2(-40, 0), Vector2(40, 0),
		Vector2(45, 200), Vector2(10, 340),
		Vector2(-20, 460),
		Vector2(-95, 460), Vector2(-95, 340),
		Vector2(-40, 200),
	])

	var green := PackedVector2Array([
		Vector2(-85, 500), Vector2(-35, 500),
		Vector2(-35, 540), Vector2(-85, 540),
	])

	var water := PackedVector2Array([
		Vector2(45, 180), Vector2(90, 180),
		Vector2(90, 380), Vector2(10, 340),
	])

	var hazards := [
		{"type": "water", "polygon": water},
	]

	return HoleData.new(5, 540.0, tee, pin, fairway, green, hazards)


# --- Hole 4 — Par 4, 410 yards.
# Into-the-wind hole (prevailing wind bias strongest here) — tests
# Tour/Players' distance-tier bonus against a stiff headwind. (Wind not
# yet simulated digitally — geometry only reflects a demanding, fairly
# narrow straightaway hole.)
static func hole_4() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 410)

	var fairway := PackedVector2Array([
		Vector2(-32, 0), Vector2(32, 0),
		Vector2(28, 330), Vector2(-28, 330),
	])

	var green := PackedVector2Array([
		Vector2(-22, 380), Vector2(22, 380),
		Vector2(22, 418), Vector2(-22, 418),
	])

	var bunker := PackedVector2Array([
		Vector2(-40, 355), Vector2(-22, 355),
		Vector2(-22, 385), Vector2(-40, 385),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker},
	]

	return HoleData.new(4, 410.0, tee, pin, fairway, green, hazards)


# --- Hole 5 — Par 3, 195 yards.
# Long par 3 over a waste/rough carry — no bunker, but undershoot lands in
# punishing Rough; a Forgiveness-brand showcase hole.
static func hole_5() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 195)

	# No hazards at all — the punishment is the default-to-rough fallback
	# for anything short of the green, per the identity text.
	var fairway := PackedVector2Array([
		Vector2(-20, 0), Vector2(20, 0),
		Vector2(24, 140), Vector2(-24, 140),
	])

	var green := PackedVector2Array([
		Vector2(-26, 160), Vector2(26, 160),
		Vector2(26, 200), Vector2(-26, 200),
	])

	return HoleData.new(3, 195.0, tee, pin, fairway, green, [])


# --- Hole 6 — Par 4, 365 yards.
# Short, sharp dogleg-right around a bunker cluster at the corner —
# risk/reward tee shot (cut the corner vs. lay up short).
static func hole_6() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(55, 365)

	var fairway := PackedVector2Array([
		Vector2(-35, 0), Vector2(35, 0),
		Vector2(40, 170), Vector2(75, 290),
		Vector2(90, 330),
		Vector2(20, 330), Vector2(20, 290),
		Vector2(-10, 170),
	])

	var green := PackedVector2Array([
		Vector2(35, 335), Vector2(80, 335),
		Vector2(80, 375), Vector2(35, 375),
	])

	# Bunker cluster guarding the inside corner of the dogleg.
	var bunker_a := PackedVector2Array([
		Vector2(30, 190), Vector2(52, 190),
		Vector2(52, 215), Vector2(30, 215),
	])
	var bunker_b := PackedVector2Array([
		Vector2(45, 220), Vector2(64, 220),
		Vector2(64, 242), Vector2(45, 242),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker_a},
		{"type": "bunker", "polygon": bunker_b},
	]

	return HoleData.new(4, 365.0, tee, pin, fairway, green, hazards)


# --- Hole 7 — Par 4, 425 yards.
# Longest par 4 on the front nine, fairway pinched by rough both sides —
# a "hit the number, not just the direction" test hole.
static func hole_7() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 425)

	# Pinched corridor: noticeably narrower than hole 1's generous fairway.
	var fairway := PackedVector2Array([
		Vector2(-30, 0), Vector2(30, 0),
		Vector2(20, 200), Vector2(20, 340), Vector2(-20, 340), Vector2(-20, 200),
	])

	var green := PackedVector2Array([
		Vector2(-22, 388), Vector2(22, 388),
		Vector2(22, 428), Vector2(-22, 428),
	])

	return HoleData.new(4, 425.0, tee, pin, fairway, green, [])


# --- Hole 8 — Par 5, 510 yards.
# Reachable-in-two par 5 for a big Tour/Players drive, but green is
# water-guarded — high risk/reward closer to the front nine's turn.
static func hole_8() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 510)

	var fairway := PackedVector2Array([
		Vector2(-42, 0), Vector2(42, 0),
		Vector2(38, 420), Vector2(-38, 420),
	])

	var green := PackedVector2Array([
		Vector2(-26, 478), Vector2(26, 478),
		Vector2(26, 513), Vector2(-26, 513),
	])

	# Water guards the green on the approach side.
	var water := PackedVector2Array([
		Vector2(-38, 420), Vector2(38, 420),
		Vector2(34, 450), Vector2(-34, 450),
	])

	var hazards := [
		{"type": "water", "polygon": water},
	]

	return HoleData.new(5, 510.0, tee, pin, fairway, green, hazards)


# --- Hole 9 — Par 4, 395 yards.
# Uphill finish to the front nine, slope marker kicks approach shots
# toward a back-shelf green — first real Slope showcase hole. (Slope not
# yet simulated digitally — geometry only reflects the straightaway hole.)
static func hole_9() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 395)

	var fairway := PackedVector2Array([
		Vector2(-36, 0), Vector2(36, 0),
		Vector2(30, 320), Vector2(-30, 320),
	])

	var green := PackedVector2Array([
		Vector2(-24, 358), Vector2(24, 358),
		Vector2(24, 398), Vector2(-24, 398),
	])

	var bunker := PackedVector2Array([
		Vector2(26, 340), Vector2(44, 340),
		Vector2(44, 362), Vector2(26, 362),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker},
	]

	return HoleData.new(4, 395.0, tee, pin, fairway, green, hazards)


# --- Hole 10 — Par 4, 375 yards.
# Back nine opener, downwind — mirror of hole 1's calm energy but with a
# tailwind distance boost. (Wind not yet simulated digitally.)
static func hole_10() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 375)

	var fairway := PackedVector2Array([
		Vector2(-44, 0), Vector2(44, 0),
		Vector2(38, 300), Vector2(-38, 300),
	])

	var green := PackedVector2Array([
		Vector2(-20, 358), Vector2(20, 358),
		Vector2(20, 396), Vector2(-20, 396),
	])

	var bunker := PackedVector2Array([
		Vector2(-40, 330), Vector2(-22, 330),
		Vector2(-22, 350), Vector2(-40, 350),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker},
	]

	return HoleData.new(4, 375.0, tee, pin, fairway, green, hazards)


# --- Hole 11 — Par 3, 145 yards.
# Short, exposed par 3 right on the coastline — heaviest wind bias on the
# course, small green. (Wind not yet simulated digitally.)
static func hole_11() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 145)

	var fairway := PackedVector2Array([
		Vector2(-18, 0), Vector2(18, 0),
		Vector2(22, 100), Vector2(-22, 100),
	])

	# Small green, per the identity text.
	var green := PackedVector2Array([
		Vector2(-18, 118), Vector2(18, 118),
		Vector2(18, 148), Vector2(-18, 148),
	])

	# Coastline water along one side, echoing hole 17's later signature hazard.
	var water := PackedVector2Array([
		Vector2(22, 90), Vector2(50, 90),
		Vector2(50, 150), Vector2(22, 150),
	])

	var hazards := [
		{"type": "water", "polygon": water},
	]

	return HoleData.new(3, 145.0, tee, pin, fairway, green, hazards)


# --- Hole 12 — Par 5, 560 yards.
# Longest hole on the course, three-shot par 5 threading between two
# bunker clusters — a genuine "what's your bag missing" test.
static func hole_12() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 560)

	var fairway := PackedVector2Array([
		Vector2(-38, 0), Vector2(38, 0),
		Vector2(34, 470), Vector2(-34, 470),
	])

	var green := PackedVector2Array([
		Vector2(-24, 528), Vector2(24, 528),
		Vector2(24, 563), Vector2(-24, 563),
	])

	# Two bunker clusters pinching the fairway partway down each shot.
	var bunker_a := PackedVector2Array([
		Vector2(-56, 190), Vector2(-34, 190),
		Vector2(-34, 225), Vector2(-56, 225),
	])
	var bunker_b := PackedVector2Array([
		Vector2(34, 330), Vector2(56, 330),
		Vector2(56, 365), Vector2(34, 365),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker_a},
		{"type": "bunker", "polygon": bunker_b},
	]

	return HoleData.new(5, 560.0, tee, pin, fairway, green, hazards)


# --- Hole 13 — Par 4, 400 yards.
# Crosswind hole, fairway slopes toward rough on the low side — Slope +
# Wind stacking. (Slope/Wind not yet simulated digitally — geometry
# reflects a fairway pinched on one side to echo the "low side" text.)
static func hole_13() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 400)

	var fairway := PackedVector2Array([
		Vector2(-34, 0), Vector2(30, 0),
		Vector2(24, 330), Vector2(-28, 330),
	])

	var green := PackedVector2Array([
		Vector2(-22, 368), Vector2(22, 368),
		Vector2(22, 406), Vector2(-22, 406),
	])

	return HoleData.new(4, 400.0, tee, pin, fairway, green, [])


# --- Hole 14 — Par 4, 355 yards.
# Short par 4, driveable for a full-send Tour/Players tee shot, but the
# green is tiny and bunker-ringed — classic risk/reward.
static func hole_14() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 355)

	var fairway := PackedVector2Array([
		Vector2(-34, 0), Vector2(34, 0),
		Vector2(30, 280), Vector2(-30, 280),
	])

	# Tiny green, per the identity text.
	var green := PackedVector2Array([
		Vector2(-16, 322), Vector2(16, 322),
		Vector2(16, 359), Vector2(-16, 359),
	])

	# Bunkers ringing the green on three sides.
	var bunker_left := PackedVector2Array([
		Vector2(-30, 316), Vector2(-16, 316),
		Vector2(-16, 363), Vector2(-30, 363),
	])
	var bunker_right := PackedVector2Array([
		Vector2(16, 316), Vector2(30, 316),
		Vector2(30, 363), Vector2(16, 363),
	])
	var bunker_back := PackedVector2Array([
		Vector2(-16, 359), Vector2(16, 359),
		Vector2(16, 370), Vector2(-16, 370),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker_left},
		{"type": "bunker", "polygon": bunker_right},
		{"type": "bunker", "polygon": bunker_back},
	]

	return HoleData.new(4, 355.0, tee, pin, fairway, green, hazards)


# --- Hole 15 — Par 3, 175 yards.
# Elevated tee to a well-bunkered green — Value/Classic's lie-penalty
# forgiveness matters if you miss into rough short.
static func hole_15() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 175)

	var fairway := PackedVector2Array([
		Vector2(-20, 0), Vector2(20, 0),
		Vector2(24, 130), Vector2(-24, 130),
	])

	var green := PackedVector2Array([
		Vector2(-24, 148), Vector2(24, 148),
		Vector2(24, 182), Vector2(-24, 182),
	])

	var bunker_left := PackedVector2Array([
		Vector2(-42, 146), Vector2(-24, 146),
		Vector2(-24, 178), Vector2(-42, 178),
	])
	var bunker_right := PackedVector2Array([
		Vector2(24, 146), Vector2(42, 146),
		Vector2(42, 178), Vector2(24, 178),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker_left},
		{"type": "bunker", "polygon": bunker_right},
	]

	return HoleData.new(3, 175.0, tee, pin, fairway, green, hazards)


# --- Hole 16 — Par 4, 415 yards.
# Into the prevailing wind again, tightest fairway on the course — the
# round's most demanding ballstriking hole. (Wind not yet simulated
# digitally — geometry reflects the tightest fairway of the 18.)
static func hole_16() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 415)

	# Tightest fairway on the course — narrower than hole 7's pinched corridor.
	var fairway := PackedVector2Array([
		Vector2(-24, 0), Vector2(24, 0),
		Vector2(16, 210), Vector2(16, 335), Vector2(-16, 335), Vector2(-16, 210),
	])

	var green := PackedVector2Array([
		Vector2(-20, 380), Vector2(20, 380),
		Vector2(20, 418), Vector2(-20, 418),
	])

	var bunker := PackedVector2Array([
		Vector2(20, 355), Vector2(38, 355),
		Vector2(38, 378), Vector2(20, 378),
	])

	var hazards := [
		{"type": "bunker", "polygon": bunker},
	]

	return HoleData.new(4, 415.0, tee, pin, fairway, green, hazards)


# --- Hole 17 — Par 3, 155 yards.
# Island-style green surrounded by water on three sides — the course's
# signature hole, a genuine card-in-hand gamble late in the round.
static func hole_17() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 155)

	# Minimal tee apron only — almost the entire carry is over water, so
	# there's effectively no fairway "safety" corridor on this hole.
	var fairway := PackedVector2Array([
		Vector2(-14, 0), Vector2(14, 0),
		Vector2(14, 20), Vector2(-14, 20),
	])

	var green := PackedVector2Array([
		Vector2(-22, 135), Vector2(22, 135),
		Vector2(22, 172), Vector2(-22, 172),
	])

	# Water wraps front/left/right of the green, with a notch cut out at
	# the back (north) side so a bailout apron is reachable — "island-style
	# ... on three sides", not all four, per the identity text.
	var water := PackedVector2Array([
		Vector2(-55, 20), Vector2(55, 20),
		Vector2(55, 172), Vector2(30, 172),
		Vector2(30, 132), Vector2(-30, 132),
		Vector2(-30, 172), Vector2(-55, 172),
	])

	var hazards := [
		{"type": "water", "polygon": water},
	]

	return HoleData.new(3, 155.0, tee, pin, fairway, green, hazards)


# --- Hole 18 — Par 5, 545 yards.
# Closing par 5 along the coastline back to the clubhouse, wide fairway
# but a water hazard guards the green in two — a "how much do you need
# this birdie" decision to close the round.
static func hole_18() -> HoleData:
	var tee := Vector2(0, 0)
	var pin := Vector2(0, 545)

	# Wide fairway, per the identity text.
	var fairway := PackedVector2Array([
		Vector2(-48, 0), Vector2(48, 0),
		Vector2(42, 450), Vector2(-42, 450),
	])

	var green := PackedVector2Array([
		Vector2(-26, 510), Vector2(26, 510),
		Vector2(26, 548), Vector2(-26, 548),
	])

	# Water guards the green on the approach for a second-shot go — the
	# closing risk/reward decision.
	var water := PackedVector2Array([
		Vector2(-42, 450), Vector2(42, 450),
		Vector2(36, 480), Vector2(-36, 480),
	])

	var hazards := [
		{"type": "water", "polygon": water},
	]

	return HoleData.new(5, 545.0, tee, pin, fairway, green, hazards)


# --- Dispatcher: looks up any of the 18 base-course holes by number. ---
const HOLE_COUNT := 18


static func hole(n: int) -> HoleData:
	match n:
		1: return hole_1()
		2: return hole_2()
		3: return hole_3()
		4: return hole_4()
		5: return hole_5()
		6: return hole_6()
		7: return hole_7()
		8: return hole_8()
		9: return hole_9()
		10: return hole_10()
		11: return hole_11()
		12: return hole_12()
		13: return hole_13()
		14: return hole_14()
		15: return hole_15()
		16: return hole_16()
		17: return hole_17()
		18: return hole_18()
	push_error("HoleData.hole(): no hole defined for index %d" % n)
	return hole_1()
