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
