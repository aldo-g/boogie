class_name CourseMapView
extends Control

# ---------------------------------------------------------
# Top-down hole map: draws the fairway/green/hazard polygons from a
# HoleData, mowed-stripe texture, the ball's position and shot trail,
# and (during a shot) the ball itself actually flying along the aim
# arc — a small arcing hop with a growing motion trail — so the shot
# reads as the ball traveling across the screen, not just a marker
# jumping between two points.
# ---------------------------------------------------------

var hole: HoleData
var ball_pos: Vector2 = Vector2.ZERO  # yard-space
var shot_path: Array = []             # yard-space points, tee to current ball_pos

# Aim-tool animation state (yard-space): set by play_aim_animation(), cleared after.
var _aim_active: bool = false
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_base_dir: Vector2 = Vector2.UP
var _aim_current_degree: float = 0.0
var _aim_current_side: int = 0  # ShotResolver.Side
var _aim_current_distance: float = 0.0
var _aim_max_distance: float = 1.0

# Ball-flight animation state (yard-space): the ball's own position while
# a shot is resolving, plus a fading trail of recent points behind it.
var _flight_active: bool = false
var _flight_pos: Vector2 = Vector2.ZERO
var _flight_trail: Array = []       # recent yard-space points, most recent last
var _flight_hop_height: float = 0.0 # current arc height in yards, for the shadow offset

const MARGIN := 16.0
const COLOR_FAIRWAY := Color(0.596, 0.749, 0.494)   # brighter fairway green
const COLOR_FAIRWAY_STRIPE := Color(0.561, 0.718, 0.455) # subtle mow-stripe alt tone
const COLOR_ROUGH := Color(0.435, 0.557, 0.373)     # darker rough green
const COLOR_ROUGH_STRIPE := Color(0.404, 0.522, 0.345)
const COLOR_GREEN := Color(0.702, 0.839, 0.596)     # putting green, lightest
const COLOR_GREEN_STRIPE := Color(0.663, 0.808, 0.553)
const COLOR_BUNKER := Color(0.867, 0.784, 0.573)
const COLOR_BUNKER_EDGE := Color(0.745, 0.651, 0.435)
const COLOR_WATER := Color(0.561, 0.663, 0.722)
const COLOR_WATER_RIPPLE := Color(0.702, 0.784, 0.831, 0.6)
const COLOR_BALL := Color(0.98, 0.98, 0.97)
const COLOR_BALL_OUTLINE := Color(0.169, 0.227, 0.184)
const COLOR_BALL_SHADOW := Color(0.106, 0.129, 0.110, 0.35)
const COLOR_TRAIL := Color(0.169, 0.227, 0.184, 0.55)
const COLOR_FLIGHT_TRAIL := Color(0.98, 0.98, 0.97, 0.9)
const COLOR_PIN := Color(0.753, 0.278, 0.227)
const COLOR_AIM_LINE := Color(0.753, 0.278, 0.227, 0.55)
const COLOR_TREE_CANOPY := Color(0.325, 0.443, 0.271)
const COLOR_TREE_CANOPY_DARK := Color(0.267, 0.373, 0.220)
const COLOR_TREE_SHADOW := Color(0.106, 0.129, 0.110, 0.16)
const COLOR_GREEN_FRINGE := Color(0.639, 0.780, 0.529)
const COLOR_MARKER := Color(0.169, 0.227, 0.184, 0.4)


func _ready() -> void:
	custom_minimum_size = Vector2(220, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_hole(p_hole: HoleData) -> void:
	hole = p_hole
	queue_redraw()


func set_ball(p_pos: Vector2, p_path: Array) -> void:
	ball_pos = p_pos
	shot_path = p_path
	queue_redraw()


# Kicks off the full shot animation: the aim arm rotates to the degree
# offset and extends to show the intended line, then the ball itself
# flies along that same line with a little arc and a fading trail, so
# the ball is visibly traceable across the map rather than teleporting.
# All distances in yards; direction is computed from the current
# ball_pos toward the hole's pin.
func play_aim_animation(distance: float, degree: float, side: int, max_distance: float, on_done: Callable) -> void:
	if not hole:
		on_done.call()
		return
	_aim_active = true
	_aim_origin = ball_pos
	_aim_base_dir = (hole.pin_pos - ball_pos).normalized()
	if _aim_base_dir.length_squared() < 0.0001:
		_aim_base_dir = Vector2.UP
	_aim_max_distance = max(max_distance, distance, 1.0)
	_aim_current_degree = 0.0
	_aim_current_side = side
	_aim_current_distance = 0.0
	_flight_active = false
	_flight_trail = []
	queue_redraw()

	var tw := create_tween()
	tw.tween_method(_set_aim_degree, 0.0, degree, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_aim_distance, 0.0, distance, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_aim_active = false
		_start_ball_flight(distance, degree, side, on_done)
	)


func _start_ball_flight(distance: float, degree: float, side: int, on_done: Callable) -> void:
	var sign: float = 0.0
	if side == 0:  # ShotResolver.Side.DRAW
		sign = 1.0
	elif side == 1:  # ShotResolver.Side.FADE
		sign = -1.0
	var angle_rad: float = deg_to_rad(degree) * sign
	var dir := _aim_base_dir.rotated(angle_rad)
	var start_yard: Vector2 = _aim_origin
	var end_yard: Vector2 = _aim_origin + dir * distance

	_flight_active = true
	_flight_pos = start_yard
	_flight_trail = [start_yard]
	_flight_hop_height = 0.0

	# Duration scales gently with distance so a 30-yard chip feels quick
	# and a 260-yard drive still reads as a real flight, not a blink.
	var duration: float = clamp(distance / 260.0, 0.28, 0.85)

	var tw := create_tween()
	tw.tween_method(func(t: float): _update_ball_flight(start_yard, end_yard, t),
		0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		_flight_active = false
		_flight_trail = []
		on_done.call()
	)


func _update_ball_flight(start_yard: Vector2, end_yard: Vector2, t: float) -> void:
	_flight_pos = start_yard.lerp(end_yard, t)
	# Simple parabolic hop for the shadow-offset "height" cue (unitless 0..1 * a few yards).
	_flight_hop_height = sin(t * PI) * (start_yard.distance_to(end_yard) * 0.06)
	_flight_trail.append(_flight_pos)
	if _flight_trail.size() > 10:
		_flight_trail.pop_front()
	queue_redraw()


func _set_aim_degree(d: float) -> void:
	_aim_current_degree = d
	queue_redraw()


func _set_aim_distance(d: float) -> void:
	_aim_current_distance = d
	queue_redraw()


# --- Yard-space <-> pixel-space conversion ---
# Fits the hole's yardage (tee at y=0 to pin at hole.yardage, plus a little
# margin) into the available Control rect, preserving aspect ratio and
# flipping Y so "up" on screen is "toward the pin."
func _yard_extent() -> Rect2:
	if not hole:
		return Rect2(-50, -20, 100, 440)
	var min_x: float = -60.0
	var max_x: float = 60.0
	var min_y: float = -20.0
	var max_y: float = hole.yardage + 30.0
	for pt in hole.fairway_polygon:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
	for hazard in hole.hazards:
		for pt in hazard.polygon:
			min_x = min(min_x, pt.x)
			max_x = max(max_x, pt.x)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


func _to_px(yard_pt: Vector2) -> Vector2:
	var extent := _yard_extent()
	var avail := size - Vector2(MARGIN, MARGIN) * 2.0
	var scale_x: float = avail.x / max(extent.size.x, 1.0)
	var scale_y: float = avail.y / max(extent.size.y, 1.0)
	var s: float = min(scale_x, scale_y)
	var px_x: float = MARGIN + (yard_pt.x - extent.position.x) * s
	# Flip Y: yard-space +y (toward pin) should go UP on screen.
	var y_from_top: float = extent.size.y - (yard_pt.y - extent.position.y)
	var px_y: float = MARGIN + y_from_top * s
	return Vector2(px_x, px_y)


func _px_scale() -> float:
	var extent := _yard_extent()
	var avail := size - Vector2(MARGIN, MARGIN) * 2.0
	var scale_x: float = avail.x / max(extent.size.x, 1.0)
	var scale_y: float = avail.y / max(extent.size.y, 1.0)
	return min(scale_x, scale_y)


func _to_px_polygon(yard_poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(yard_poly.size())
	for i in range(yard_poly.size()):
		out[i] = _to_px(yard_poly[i])
	return out


# Draws horizontal mow-stripe bands (alternating tone) clipped to a polygon's
# bounding box, giving the turf a groundskept, textured look instead of a
# flat fill. Cheap approximation: draws full-width stripe rects then relies
# on being layered under nothing else, so slight overdraw beyond the
# polygon edge is fine since the surrounding tone is close in value.
func _draw_mow_stripes(yard_poly: PackedVector2Array, base_col: Color, stripe_col: Color) -> void:
	if yard_poly.is_empty():
		return
	var min_y: float = yard_poly[0].y
	var max_y: float = yard_poly[0].y
	var min_x: float = yard_poly[0].x
	var max_x: float = yard_poly[0].x
	for pt in yard_poly:
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)

	draw_colored_polygon(_to_px_polygon(yard_poly), base_col)

	var stripe_width: float = 18.0  # yards per stripe band
	var y: float = floor(min_y / stripe_width) * stripe_width
	var band_index := 0
	while y < max_y:
		if band_index % 2 == 1:
			var band_poly := PackedVector2Array([
				Vector2(min_x, y), Vector2(max_x, y),
				Vector2(max_x, min(y + stripe_width, max_y)), Vector2(min_x, min(y + stripe_width, max_y)),
			])
			_draw_clipped_polygon(band_poly, yard_poly, stripe_col)
		y += stripe_width
		band_index += 1


# Intersects a rect-ish band with the target polygon before drawing, so
# stripes stay inside the fairway/green/rough shape.
func _draw_clipped_polygon(band: PackedVector2Array, clip_poly: PackedVector2Array, col: Color) -> void:
	var clipped := Geometry2D.intersect_polygons(band, clip_poly)
	for piece in clipped:
		draw_colored_polygon(_to_px_polygon(piece), col)


func _draw() -> void:
	if not hole:
		return

	var extent := _yard_extent()

	# Rough is the base/background tone; fairway, green, and hazards draw over it.
	var rough_rect := PackedVector2Array([
		Vector2(extent.position.x, extent.position.y),
		Vector2(extent.position.x, extent.position.y + extent.size.y),
		Vector2(extent.position.x + extent.size.x, extent.position.y + extent.size.y),
		Vector2(extent.position.x + extent.size.x, extent.position.y),
	])
	_draw_mow_stripes(rough_rect, COLOR_ROUGH, COLOR_ROUGH_STRIPE)

	_draw_mow_stripes(hole.fairway_polygon, COLOR_FAIRWAY, COLOR_FAIRWAY_STRIPE)
	_draw_tree_line(hole.fairway_polygon, extent)
	_draw_yardage_markers()

	for hazard in hole.hazards:
		var poly_px := _to_px_polygon(hazard.polygon)
		if hazard.type == "water":
			draw_colored_polygon(poly_px, COLOR_WATER)
			_draw_water_ripples(hazard.polygon)
		else:
			draw_colored_polygon(poly_px, COLOR_BUNKER)
			_draw_bunker_texture(hazard.polygon)
			# Sandy edge outline so the bunker reads as a dug-out hazard.
			var closed := poly_px.duplicate()
			closed.append(poly_px[0])
			draw_polyline(closed, COLOR_BUNKER_EDGE, 1.5)

	_draw_green_fringe(hole.green_polygon)
	_draw_mow_stripes(hole.green_polygon, COLOR_GREEN, COLOR_GREEN_STRIPE)

	# Tee marker: a small pair of tee-box pegs.
	var tee_px := _to_px(hole.tee_pos)
	draw_circle(tee_px + Vector2(-3, 0), 2.2, BoogieTheme.INK_SOFT)
	draw_circle(tee_px + Vector2(3, 0), 2.2, BoogieTheme.INK_SOFT)

	# Pin/flag with a soft ground shadow so it feels planted on the green.
	var pin_px := _to_px(hole.pin_pos)
	draw_circle(pin_px + Vector2(0, 2), 3.0, Color(0, 0, 0, 0.12))
	draw_line(pin_px, pin_px + Vector2(0, -18), COLOR_PIN, 2.0)
	var flag_pts := PackedVector2Array([
		pin_px + Vector2(0, -18), pin_px + Vector2(10, -14), pin_px + Vector2(0, -10)])
	draw_colored_polygon(flag_pts, COLOR_PIN)
	draw_circle(pin_px, 2.5, BoogieTheme.INK)

	# Shot trail: tee -> each prior landing spot -> current ball position,
	# drawn as short dashes so it reads as a path etched into the grass
	# rather than a solid line competing with the live flight trail.
	if shot_path.size() >= 2:
		for i in range(shot_path.size() - 1):
			_draw_dashed_line(_to_px(shot_path[i]), _to_px(shot_path[i + 1]), COLOR_TRAIL, 2.0, 6.0, 5.0)

	# Aim tool: pivots at the ball's position, rotates to the degree offset,
	# extends to the rolled distance. Sign convention must match Main.gd's
	# _resolve_shot_landing() so the drawn arm lands where the ball actually
	# ends up: Draw (curves left) is a positive rotation in Godot's rotated().
	if _aim_active:
		var sign: float = 0.0
		if _aim_current_side == 0:  # ShotResolver.Side.DRAW
			sign = 1.0
		elif _aim_current_side == 1:  # ShotResolver.Side.FADE
			sign = -1.0
		var angle_rad: float = deg_to_rad(_aim_current_degree) * sign
		var dir := _aim_base_dir.rotated(angle_rad)
		var end_yard: Vector2 = _aim_origin + dir * _aim_current_distance
		var origin_px := _to_px(_aim_origin)
		var end_px := _to_px(end_yard)
		draw_line(origin_px, end_px, COLOR_AIM_LINE, 2.0)
		draw_circle(end_px, 3.5, COLOR_AIM_LINE)

	# Ball in flight: a fading motion trail behind the current flight
	# position, plus a drop shadow offset from the ball to sell a hop/arc,
	# so the ball is visibly traceable across the screen mid-shot.
	if _flight_active:
		var n := _flight_trail.size()
		for i in range(n - 1):
			var a: float = float(i + 1) / float(n)
			var c := COLOR_FLIGHT_TRAIL
			c.a *= a * 0.6
			var r: float = lerp(1.0, 4.0, a)
			draw_circle(_to_px(_flight_trail[i]), r, c)
		var shadow_px := _to_px(_flight_pos)
		draw_circle(shadow_px, 4.0, COLOR_BALL_SHADOW)
		var lift_px: float = _flight_hop_height * _px_scale()
		var ball_px := shadow_px + Vector2(0, -lift_px)
		draw_circle(ball_px, 4.5, COLOR_BALL)
		draw_arc(ball_px, 4.5, 0, TAU, 14, COLOR_BALL_OUTLINE, 1.2)
	else:
		# Ball marker at its current resting position.
		var ball_px := _to_px(ball_pos)
		draw_circle(ball_px + Vector2(0, 2), 3.5, COLOR_BALL_SHADOW)
		draw_circle(ball_px, 5.0, COLOR_BALL)
		draw_arc(ball_px, 5.0, 0, TAU, 16, COLOR_BALL_OUTLINE, 1.5)


func _draw_dashed_line(from_px: Vector2, to_px: Vector2, col: Color, width: float, dash: float, gap: float) -> void:
	var total := from_px.distance_to(to_px)
	if total < 0.01:
		return
	var dir := (to_px - from_px) / total
	var travelled := 0.0
	while travelled < total:
		var seg_end: float = min(travelled + dash, total)
		draw_line(from_px + dir * travelled, from_px + dir * seg_end, col, width)
		travelled += dash + gap


func _draw_water_ripples(yard_poly: PackedVector2Array) -> void:
	var min_y: float = yard_poly[0].y
	var max_y: float = yard_poly[0].y
	var min_x: float = yard_poly[0].x
	var max_x: float = yard_poly[0].x
	for pt in yard_poly:
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
	var step: float = 10.0
	var y: float = min_y + step * 0.5
	var row := 0
	while y < max_y:
		var offset: float = 4.0 if row % 2 == 0 else 0.0
		var x: float = min_x + offset
		while x < max_x:
			var pt := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(pt, yard_poly):
				var p := _to_px(pt)
				draw_arc(p, 2.0, 0, PI, 6, COLOR_WATER_RIPPLE, 1.0)
			x += step
		y += step
		row += 1


func _draw_bunker_texture(yard_poly: PackedVector2Array) -> void:
	var min_y: float = yard_poly[0].y
	var max_y: float = yard_poly[0].y
	var min_x: float = yard_poly[0].x
	var max_x: float = yard_poly[0].x
	for pt in yard_poly:
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
	var step: float = 7.0
	var y: float = min_y + step * 0.5
	var row := 0
	while y < max_y:
		var x: float = min_x + step * 0.5
		while x < max_x:
			var pt := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(pt, yard_poly):
				var p := _to_px(pt)
				draw_circle(p, 0.9, COLOR_BUNKER_EDGE)
			x += step
		y += step
		row += 1


# Scatters simple two-tone tree clusters along the rough just outside the
# fairway polygon, so the hole reads as a corridor cut through woods
# rather than a flat green shape floating on parchment. Trees are placed
# at fixed offsets from sampled fairway edge points (deterministic per
# hole, not randomized per redraw) so they don't jitter every frame.
func _draw_tree_line(fairway_poly: PackedVector2Array, extent: Rect2) -> void:
	var scale_px := _px_scale()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337  # fixed seed: stable tree placement across redraws

	var step_y: float = 26.0
	var y: float = extent.position.y + 14.0
	while y < extent.position.y + extent.size.y - 10.0:
		var half_width := _fairway_half_width_at_y(fairway_poly, y)
		if half_width > 0.0:
			for side in [-1.0, 1.0]:
				# Base offset clears the fairway edge with real margin; the
				# per-cluster jitter below is small and always additive (never
				# subtracted), so a tree can never jitter back onto the fairway.
				var base_offset: float = rng.randf_range(14.0, 30.0)
				var jitter_y: float = rng.randf_range(-8.0, 8.0)
				var tree_yard := Vector2(side * (half_width + base_offset), y + jitter_y)
				if tree_yard.x < extent.position.x or tree_yard.x > extent.position.x + extent.size.x:
					continue
				var cluster_size := rng.randi_range(1, 2)
				for k in range(cluster_size):
					var extra_out: float = rng.randf_range(0.0, 8.0)
					var along: float = rng.randf_range(-5.0, 5.0)
					var offset := Vector2(side * extra_out, along)
					_draw_tree(_to_px(tree_yard + offset), scale_px, rng.randf_range(0.75, 1.15))
		y += step_y


# Finds the fairway polygon's approximate half-width at a given yard-space
# y by scanning a horizontal ray for the fairway edge; returns 0 if y is
# outside the fairway's vertical span (so trees don't spawn in the void
# past the green or behind the tee).
func _fairway_half_width_at_y(fairway_poly: PackedVector2Array, y: float) -> float:
	var min_y: float = fairway_poly[0].y
	var max_y: float = fairway_poly[0].y
	for pt in fairway_poly:
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)
	if y < min_y or y > max_y:
		return 0.0
	var max_x: float = 0.0
	var probe_x: float = 0.0
	while probe_x < 100.0:
		if not Geometry2D.is_point_in_polygon(Vector2(probe_x, y), fairway_poly):
			max_x = probe_x
			break
		probe_x += 2.0
	return max(max_x, 8.0)


func _draw_tree(px: Vector2, scale_px: float, size_mult: float) -> void:
	var r: float = clamp(3.2 * scale_px * size_mult, 2.0, 9.0)
	draw_circle(px + Vector2(1.5, 2.0), r * 0.85, COLOR_TREE_SHADOW)
	draw_circle(px, r, COLOR_TREE_CANOPY_DARK)
	draw_circle(px - Vector2(r * 0.28, r * 0.28), r * 0.7, COLOR_TREE_CANOPY)


# Small tick marks + labels along the fairway's left rough at 100/150/200
# yard-to-pin distances, like painted yardage markers on a real course.
func _draw_yardage_markers() -> void:
	if not hole:
		return
	var font := ThemeDB.fallback_font
	for dist_to_pin in [100, 150, 200]:
		var y: float = hole.pin_pos.y - dist_to_pin
		if y <= hole.tee_pos.y + 5.0 or y >= hole.pin_pos.y - 5.0:
			continue
		var extent := _yard_extent()
		var mark_yard := Vector2(extent.position.x + 4.0, y)
		var p := _to_px(mark_yard)
		draw_line(p + Vector2(0, -5), p + Vector2(0, 5), COLOR_MARKER, 1.5)
		draw_string(font, p + Vector2(6, 4), "%d" % dist_to_pin, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_MARKER)


# A slightly darker-than-fairway fringe ring around the green, mowed
# tighter than the rough but not yet putting-green height — the collar
# real courses have between fairway/rough and the green surface proper.
func _draw_green_fringe(green_poly: PackedVector2Array) -> void:
	var center := Vector2.ZERO
	for pt in green_poly:
		center += pt
	center /= green_poly.size()
	var expanded := PackedVector2Array()
	for pt in green_poly:
		var dir := (pt - center)
		expanded.append(pt + dir.normalized() * 6.0)
	draw_colored_polygon(_to_px_polygon(expanded), COLOR_GREEN_FRINGE)
