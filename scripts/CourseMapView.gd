class_name CourseMapView
extends Control

# ---------------------------------------------------------
# Top-down hole map: draws the fairway/green/hazard polygons from a
# HoleData, the ball's position and shot trail, and (during a shot)
# the Section 4 aim tool — a pivoting arm that rotates to the degree
# offset and extends to the roll distance, exactly like the physical
# tabletop prop the design doc describes.
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

const MARGIN := 16.0
const COLOR_FAIRWAY := Color(0.596, 0.749, 0.494)   # brighter fairway green
const COLOR_ROUGH := Color(0.435, 0.557, 0.373)     # darker rough green
const COLOR_GREEN := Color(0.702, 0.839, 0.596)     # putting green, lightest
const COLOR_BUNKER := Color(0.867, 0.784, 0.573)
const COLOR_WATER := Color(0.561, 0.663, 0.722)
const COLOR_BALL := Color(0.98, 0.98, 0.97)
const COLOR_BALL_OUTLINE := Color(0.169, 0.227, 0.184)
const COLOR_TRAIL := Color(0.169, 0.227, 0.184, 0.55)
const COLOR_PIN := Color(0.753, 0.278, 0.227)
const COLOR_AIM_LINE := Color(0.753, 0.278, 0.227, 0.85)


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


# Kicks off the aim-tool animation: rotates from straight-at-pin to the
# rolled degree offset, then extends out to the rolled distance, then
# calls on_done. All distances in yards; direction is computed from the
# current ball_pos toward the hole's pin.
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
	queue_redraw()

	var tw := create_tween()
	tw.tween_method(_set_aim_degree, 0.0, degree, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_aim_distance, 0.0, distance, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.15)
	tw.tween_callback(func():
		_aim_active = false
		on_done.call()
	)


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


func _to_px_polygon(yard_poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(yard_poly.size())
	for i in range(yard_poly.size()):
		out[i] = _to_px(yard_poly[i])
	return out


func _draw() -> void:
	if not hole:
		return

	# Rough is the base/background tone; fairway, green, and hazards draw over it.
	var rough_rect := PackedVector2Array([
		_to_px(Vector2(_yard_extent().position.x, _yard_extent().position.y)),
		_to_px(Vector2(_yard_extent().position.x, _yard_extent().position.y + _yard_extent().size.y)),
		_to_px(Vector2(_yard_extent().position.x + _yard_extent().size.x, _yard_extent().position.y + _yard_extent().size.y)),
		_to_px(Vector2(_yard_extent().position.x + _yard_extent().size.x, _yard_extent().position.y)),
	])
	draw_colored_polygon(rough_rect, COLOR_ROUGH)

	draw_colored_polygon(_to_px_polygon(hole.fairway_polygon), COLOR_FAIRWAY)

	for hazard in hole.hazards:
		var col: Color = COLOR_BUNKER
		if hazard.type == "water":
			col = COLOR_WATER
		draw_colored_polygon(_to_px_polygon(hazard.polygon), col)

	draw_colored_polygon(_to_px_polygon(hole.green_polygon), COLOR_GREEN)

	# Tee marker.
	var tee_px := _to_px(hole.tee_pos)
	draw_circle(tee_px, 4.0, BoogieTheme.INK_SOFT)

	# Pin/flag.
	var pin_px := _to_px(hole.pin_pos)
	draw_line(pin_px, pin_px + Vector2(0, -18), COLOR_PIN, 2.0)
	var flag_pts := PackedVector2Array([
		pin_px + Vector2(0, -18), pin_px + Vector2(10, -14), pin_px + Vector2(0, -10)])
	draw_colored_polygon(flag_pts, COLOR_PIN)
	draw_circle(pin_px, 2.5, BoogieTheme.INK)

	# Shot trail: tee -> each prior landing spot -> current ball position.
	if shot_path.size() >= 2:
		for i in range(shot_path.size() - 1):
			draw_line(_to_px(shot_path[i]), _to_px(shot_path[i + 1]), COLOR_TRAIL, 2.0)

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
		draw_line(origin_px, end_px, COLOR_AIM_LINE, 2.5)
		draw_circle(end_px, 5.0, COLOR_AIM_LINE)

	# Ball marker at its current resting position.
	var ball_px := _to_px(ball_pos)
	draw_circle(ball_px, 5.0, COLOR_BALL)
	draw_arc(ball_px, 5.0, 0, TAU, 16, COLOR_BALL_OUTLINE, 1.5)
