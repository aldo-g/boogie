class_name CourseShape
extends RefCounted

# ---------------------------------------------------------
# Shape helpers for authoring holes as curves instead of rectangles.
# A hole is defined by a centreline (x offset, yards out, corridor width)
# plus an ellipse for the green and its bunkers; these functions turn that
# into the dense, smooth polygons HoleData hands to CourseMapView for
# drawing and to terrain_at() for lie resolution.
#
# The authored points are few and the shapes are meant to flow, so the
# work here is all about getting from one to the other without corners:
#   flow_open / flow_closed  a curve THROUGH the authored points
#   ribbon                   a fairway: that curve, given a width that
#                            swells and pinches, and round ends
#   lobed                    greens and bunkers: an ellipse pulled into a
#                            kidney or a pear
#   play_area                the ground in play: everything within reach
#                            of the hole, as one soft outline
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


# --- Flowing curves ----------------------------------------------------
# One point on a centripetal Catmull-Rom span from p1 to p2 (p0 and p3 are
# the neighbours that shape it). Centripetal, not the uniform kind
# cubic_interpolate() gives: a uniform spline overshoots wildly when a
# short edge sits next to a long one — the end of a long thin pond swells
# into a balloon — and this kind never does.
static func _flow_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var t1: float = maxf(sqrt(p0.distance_to(p1)), 0.001)
	var t2: float = t1 + maxf(sqrt(p1.distance_to(p2)), 0.001)
	var t3: float = t2 + maxf(sqrt(p2.distance_to(p3)), 0.001)
	var t: float = lerpf(t1, t2, u)
	var a1: Vector2 = p0 * ((t1 - t) / t1) + p1 * (t / t1)
	var a2: Vector2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	var a3: Vector2 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	var b1: Vector2 = a1 * ((t2 - t) / t2) + a2 * (t / t2)
	var b2: Vector2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))


# A closed curve through every point of `poly`, sampled about every `step`
# yards. The authored corners stay ON the outline — which is where the
# editor draws their handles — and the edges between them bow.
static func flow_closed(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	var out := PackedVector2Array()
	for i in n:
		var p1: Vector2 = poly[i]
		var p2: Vector2 = poly[(i + 1) % n]
		var m: int = maxi(2, int(ceil(p1.distance_to(p2) / step)))
		for k in m:
			out.append(_flow_point(poly[(i - 1 + n) % n], p1, p2, poly[(i + 2) % n], float(k) / float(m)))
	return out


# The same, for a line with two ends: through every point, first to last.
static func flow_open(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var n := points.size()
	if n < 3:
		return points
	var out := PackedVector2Array()
	for i in n - 1:
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		# Past either end, carry on the way the line was already going.
		var p0: Vector2 = points[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3: Vector2 = points[i + 2] if i + 2 < n else p2 * 2.0 - p1
		var m: int = maxi(2, int(ceil(p1.distance_to(p2) / step)))
		for k in m:
			out.append(_flow_point(p0, p1, p2, p3, float(k) / float(m)))
	out.append(points[n - 1])
	return out


# --- Fairways ----------------------------------------------------------
# A fairway as a ribbon: the stations (Vector3(x, yards out, width)) are
# joined by one flowing centreline, the width eases from each station's to
# the next, the edges are set off square to the line of play rather than
# sideways on the map — so a dogleg keeps its width through the turn — and
# both ends are rounded off. `edge_amp` yards of slow wander is added to
# each edge separately, so the two sides aren't mirror images, and each
# stretch between stations bows up to `sway` yards off the straight, one
# way then the other — nothing mown by hand runs dead straight for two
# hundred yards. The line still passes through every station, so the
# editor's handles stay on the fairway they move.
#
# Returns { "poly": the outline, "centre": the sampled centreline }.
# A centreline bent back on itself can make the inside edge cross over; if
# the outline won't triangulate, the plain corridor is used instead, so a
# hole dragged into a knot in the editor still plays and draws.
static func ribbon(stations: Array, step: float, edge_amp: float, seed: float, sway: float = 0.0) -> Dictionary:
	var pts := PackedVector2Array()
	for s in stations:
		pts.append(Vector2(s.x, s.y))
	var centre := PackedVector2Array()
	var widths := PackedFloat32Array()
	for i in stations.size() - 1:
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p0: Vector2 = pts[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3: Vector2 = pts[i + 2] if i + 2 < pts.size() else p2 * 2.0 - p1
		var span: float = p1.distance_to(p2)
		var m: int = maxi(2, int(ceil(span / step)))
		var across: Vector2 = (p2 - p1).normalized()
		across = Vector2(across.y, -across.x)
		# Longer stretches bow further; alternate stretches bow opposite ways.
		var bow: float = minf(sway, span * 0.035) * (1.0 if (i + int(seed)) % 2 == 0 else -1.0)
		for k in m:
			var u: float = float(k) / float(m)
			centre.append(_flow_point(p0, p1, p2, p3, u) + across * bow * sin(u * PI))
			# Eased, like the elevation stations: a station is where the
			# fairway is at its widest or its tightest, not a corner.
			widths.append(lerpf(stations[i].z, stations[i + 1].z, (1.0 - cos(u * PI)) * 0.5))
	centre.append(pts[pts.size() - 1])
	widths.append(stations[stations.size() - 1].z)

	var n := centre.size()
	var right := PackedVector2Array()
	var left := PackedVector2Array()
	var tangents := PackedVector2Array()
	for k in n:
		var t: Vector2 = (centre[mini(k + 1, n - 1)] - centre[maxi(k - 1, 0)]).normalized()
		if t == Vector2.ZERO:
			t = Vector2(0, 1)
		tangents.append(t)
		var normal := Vector2(t.y, -t.x)   # to the right, looking up the hole
		right.append(centre[k] + normal * maxf(4.0, widths[k] * 0.5 + wobble(k, seed) * edge_amp))
		left.append(centre[k] - normal * maxf(4.0, widths[k] * 0.5 + wobble(k, seed + 11.0) * edge_amp))

	var poly := PackedVector2Array()
	poly.append_array(right)
	_append_cap(poly, right[n - 1], left[n - 1], tangents[n - 1])
	for k in range(n - 1, -1, -1):
		poly.append(left[k])
	_append_cap(poly, left[0], right[0], -tangents[0])

	if Geometry2D.triangulate_polygon(poly).is_empty():
		poly = smooth(organic(corridor(stations), 26.0, 5.0, seed), 5)
	return {"poly": poly, "centre": centre}


# Rounds off the end of a ribbon: a shallow arc from `from` to `to`,
# bulging the way `forward` points.
static func _append_cap(poly: PackedVector2Array, from: Vector2, to: Vector2, forward: Vector2) -> void:
	var mid := (from + to) * 0.5
	var half := (from - mid)
	for k in range(1, 6):
		var a: float = PI * float(k) / 6.0
		poly.append(mid + half * cos(a) + forward * half.length() * 0.62 * sin(a))


# --- Greens and bunkers ------------------------------------------------
# An ellipse pulled out of true: two slow lobes round it make a kidney, a
# pear or a bean rather than an oval, and a little of the usual wobble
# roughens the edge. `lobes` is how far in or out a lobe goes, as a share
# of the radius; which way round they fall comes from the seed, so every
# green on a course is its own shape and always the same one.
static func lobed(center: Vector2, radii: Vector2, rot_deg: float, n: int, amp: float,
		lobes: float, seed: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rot := deg_to_rad(rot_deg)
	var phase2: float = seed * 2.39
	var phase3: float = seed * 1.31 + 1.7
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		var k: float = 1.0 + wobble(i, seed) * amp \
			+ lobes * (0.6 * cos(2.0 * a + phase2) + 0.8 * cos(3.0 * a + phase3))
		var e := Vector2(cos(a) * radii.x * k, sin(a) * radii.y * k)
		out.append(center + e.rotated(rot))
	return out


# --- The ground in play ------------------------------------------------
# Evenly spaced points round a closed shape, about `step` yards apart.
static func resample(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	var total := 0.0
	for i in n:
		total += poly[i].distance_to(poly[(i + 1) % n])
	var count: int = maxi(8, int(round(total / step)))
	var gap: float = total / float(count)
	var out := PackedVector2Array()
	var want := 0.0
	var walked := 0.0
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var seg := a.distance_to(b)
		while want < walked + seg and out.size() < count:
			out.append(a.lerp(b, (want - walked) / maxf(seg, 0.0001)))
			want += gap
		walked += seg
	return out


# Of the pieces Clipper hands back, the ones that are outlines rather than
# holes: a hole winds the other way from the biggest piece.
static func outlines(pieces: Array) -> Array:
	var turn := false
	var biggest := 0.0
	for piece in pieces:
		var area: float = absf(polygon_area(piece))
		if area > biggest:
			biggest = area
			turn = Geometry2D.is_polygon_clockwise(piece)
	var out: Array = []
	for piece in pieces:
		if piece.size() >= 3 and Geometry2D.is_polygon_clockwise(piece) == turn:
			out.append(piece)
	return out


# Every shape in `polys` merged into as few outlines as it takes — one,
# unless some of them don't touch.
static func union_all(polys: Array) -> Array:
	var acc: Array = []
	for p in polys:
		if p.size() < 3:
			continue
		var grown: PackedVector2Array = p
		var merged := true
		while merged:
			merged = false
			for i in acc.size():
				var both := outlines(Geometry2D.merge_polygons(grown, acc[i]))
				if both.size() == 1:
					grown = both[0]
					acc.remove_at(i)
					merged = true
					break
		acc.append(grown)
	return acc


# A shape grown by `by` yards, corners rounded. Outlines only.
static func grown(poly: PackedVector2Array, by: float) -> Array:
	if poly.size() < 3:
		return []
	return outlines(Geometry2D.offset_polygon(poly, by, Geometry2D.JOIN_ROUND))


# A line fattened to `by` yards either side, ends rounded.
static func corridor_round(line: PackedVector2Array, by: float) -> Array:
	if line.size() < 2:
		return []
	return outlines(Geometry2D.offset_polyline(line, by, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))


# Tidies a merged outline into the edge of the playing ground: evenly
# spaced points (few enough to test a ball against cheaply), each eased in
# or out a little along the edge's own normal so it wanders like a tree
# line instead of running parallel to the fairway.
static func soft_edge(poly: PackedVector2Array, step: float, amp: float, seed: float) -> PackedVector2Array:
	var pts := resample(poly, step)
	var n := pts.size()
	if n < 3:
		return pts
	var out := PackedVector2Array()
	for i in n:
		var along: Vector2 = (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		out.append(pts[i] + Vector2(along.y, -along.x) * wobble(i, seed) * amp)
	return out
