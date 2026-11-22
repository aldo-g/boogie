class_name Pins
extends RefCounted

# ---------------------------------------------------------
# Where the hole is cut. A green has nine places for it — the middle, the
# four sides and the four corners — and each round cuts one per green, so
# the same hole asks for a different shot from one round to the next: a
# front pin and a back pin are a club apart, and a pin on the left makes
# the left the side not to miss on.
#
# Like the wind (Wind.gd) it is a pure function of the round's seed and
# the hole number, so every machine in an online round cuts the same
# holes without anything extra to send, and like the wind it is known
# before you play: the flag on the map is where the hole is.
#
# The pins get tucked away as the round goes on (Course.late()):
#   - further from the middle — DEPTH_EARLY of the way to the edge on the
#     opening holes, DEPTH_LATE on the last;
#   - never the middle by the end, where early on it is one spot in nine;
#   - and more and more often on the green's guarded side: one of the
#     three spots nearest sand or water.
# So a late green is a smaller target with trouble beside it — the course
# pushing back as the bag fills up.
# ---------------------------------------------------------

# In the green's own axes: x across it, y along it (HoleData.pin_spot()).
const SPOTS := [
	Vector2.ZERO,
	Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0),
	Vector2(-0.707, -0.707), Vector2(0.707, -0.707), Vector2(-0.707, 0.707), Vector2(0.707, 0.707),
]
const DEPTH_EARLY := 0.40
const DEPTH_LATE := 0.85   # 0.70 until 2026-11-20
# On the last hole, the chance the pin goes on the guarded side (scaled by
# how late the hole is; never on the opening holes) — and how many spots
# count as that side, so even the last green has more than one Sunday pin.
const GUARDED_LATE := 0.9  # 0.7 until 2026-11-20
const GUARDED_SPOTS := 3
# Trouble further than this from a spot isn't guarding it.
const GUARD_REACH := 25.0


# The pin for hole `hole_n` of the round seeded `seed`. `late` is how far
# through the round the hole is, 0 to 1; left at -1 it is worked out from
# the course being played.
static func for_hole(seed: int, hole_n: int, hole: HoleData, late: float = -1.0) -> Vector2:
	if late < 0.0:
		late = Course.late(hole_n)
	late = clampf(late, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, hole_n, "pin"])
	var depth: float = lerpf(DEPTH_EARLY, DEPTH_LATE, late)
	# Both rolls are always made, used or not, so the same seed gives the
	# same answer however the branches fall.
	var guarded_roll: float = rng.randf()
	var spot_roll: float = rng.randf()
	if guarded_roll < GUARDED_LATE * late:
		var sides := guarded(hole, depth)
		if not sides.is_empty():
			return hole.pin_spot(SPOTS[sides[mini(int(spot_roll * float(sides.size())), sides.size() - 1)]], depth)
	# The middle is one spot in nine to begin with and fades out as the
	# round goes on.
	var middle: float = (1.0 - late) / float(SPOTS.size())
	if spot_roll < middle:
		return hole.green_pos
	var k: int = 1 + mini(int((spot_roll - middle) / (1.0 - middle) * float(SPOTS.size() - 1)), SPOTS.size() - 2)
	return hole.pin_spot(SPOTS[k], depth)


# The spots of SPOTS that sit nearest sand or water at `depth` — up to
# GUARDED_SPOTS of them, nearest first, none further than GUARD_REACH from
# trouble. Empty when nothing guards the green.
static func guarded(hole: HoleData, depth: float) -> Array:
	var found: Array = []   # [distance to trouble, index into SPOTS]
	for k in range(1, SPOTS.size()):
		var spot := hole.pin_spot(SPOTS[k], depth)
		var nearest := GUARD_REACH
		for hazard in hole.hazards:
			var poly: PackedVector2Array = hazard.polygon
			for i in poly.size():
				nearest = minf(nearest, spot.distance_to(
					Geometry2D.get_closest_point_to_segment(spot, poly[i], poly[(i + 1) % poly.size()])))
		if nearest < GUARD_REACH:
			found.append([nearest, k])
	found.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array = []
	for entry in found.slice(0, GUARDED_SPOTS):
		out.append(entry[1])
	return out


# "back left", "front", "middle" — where the pin is on its green, as a
# golfer says it: front is the tee's side, left and right as you look up
# the hole.
static func describe(hole: HoleData) -> String:
	var off: Vector2 = hole.pin_pos - hole.green_pos
	if off.length() < 2.0:
		return "middle"
	var dir := off.normalized()
	var parts: Array = []
	if dir.y <= -0.38:
		parts.append("front")
	elif dir.y >= 0.38:
		parts.append("back")
	if dir.x <= -0.38:
		parts.append("left")
	elif dir.x >= 0.38:
		parts.append("right")
	return " ".join(PackedStringArray(parts))
