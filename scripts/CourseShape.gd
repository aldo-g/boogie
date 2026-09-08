class_name CourseShape
extends RefCounted

# ---------------------------------------------------------
# Shape helpers for authoring holes as curves instead of rectangles.
# A hole is defined by a centreline (x offset, yards out, corridor width)
# plus an ellipse for the green and its bunkers; these functions turn that
# into the dense, smooth polygons HoleData hands to CourseMapView for
# drawing and to terrain_at() for lie resolution.
#
# Everything is deterministic: the same hole always produces the same
# outline, so a green never wobbles between frames or between runs.
# ---------------------------------------------------------


# Low-frequency noise in [-1, 1]. Two sines, no randomness.
static func wobble(i: int, seed: float) -> float:
	return sin(i * 0.8 + seed) * 0.62 + sin(i * 1.73 + seed * 1.4) * 0.38


# Resamples a polygon so every edge carries a station roughly every
# `step` yards — the wobble below needs points to push around.
static func densify(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var n: int = max(1, int(round(a.distance_to(b) / step)))
		for k in range(n):
			out.append(a.lerp(b, float(k) / float(n)))
	return out


# Pushes each station in or out along its own radial, so a blocked-out
# rectangle grows a natural edge.
static func organic(poly: PackedVector2Array, step: float, amp: float, seed: float) -> PackedVector2Array:
	var pts := densify(poly, step)
	if pts.is_empty():
		return pts
	var center := Vector2.ZERO
	for p in pts:
		center += p
	center /= float(pts.size())
	var out := PackedVector2Array()
	for i in range(pts.size()):
		var dir: Vector2 = pts[i] - center
		if dir.length_squared() < 0.0001:
			dir = Vector2.UP
		out.append(pts[i] + dir.normalized() * wobble(i, seed) * amp)
	return out


# Corridor from a centreline: spine entries are Vector3(x, yards, width).
# Walks up the right edge and back down the left.
static func corridor(spine: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for s in spine:
		out.append(Vector2(s.x + s.z * 0.5, s.y))
	for i in range(spine.size() - 1, -1, -1):
		var s: Vector3 = spine[i]
		out.append(Vector2(s.x - s.z * 0.5, s.y))
	return out


# Greens and bunkers: an ellipse, rotated, with the same wobble applied.
static func ellipse(center: Vector2, radii: Vector2, rot_deg: float, n: int, amp: float, seed: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rot := deg_to_rad(rot_deg)
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var k: float = 1.0 + wobble(i, seed) * amp
		var e := Vector2(cos(a) * radii.x * k, sin(a) * radii.y * k)
		out.append(center + e.rotated(rot))
	return out


# Offsets a closed shape outward — used for the green's fringe collar.
static func grow(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var center := Vector2.ZERO
	for p in poly:
		center += p
	center /= float(poly.size())
	var out := PackedVector2Array()
	for p in poly:
		var dir: Vector2 = p - center
		if dir.length_squared() < 0.0001:
			dir = Vector2.UP
		out.append(p + dir.normalized() * amount)
	return out


# Samples a closed Catmull-Rom spline through the points, returning a dense
# polygon. Godot draws and hit-tests polygons, so the curve is baked into
# points rather than kept as beziers.
static func smooth(poly: PackedVector2Array, samples: int = 5) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	var out := PackedVector2Array()
	for i in range(n):
		var p0: Vector2 = poly[(i - 1 + n) % n]
		var p1: Vector2 = poly[i]
		var p2: Vector2 = poly[(i + 1) % n]
		var p3: Vector2 = poly[(i + 2) % n]
		for s in range(samples):
			var t: float = float(s) / float(samples)
			out.append(p1.cubic_interpolate(p2, p0, p3, t))
	return out


# Unions the approach neck into the fairway so the game resolves it as
# fairway, keeping HoleData's public shape (one fairway polygon) intact.
static func union_largest(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	if b.is_empty():
		return a
	var merged := Geometry2D.merge_polygons(a, b)
	var best := a
	var best_area := 0.0
	for piece in merged:
		var area: float = abs(polygon_area(piece))
		if area > best_area:
			best_area = area
			best = piece
	return best


static func polygon_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5
