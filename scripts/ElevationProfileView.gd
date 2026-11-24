class_name ElevationProfileView
extends Control

# ---------------------------------------------------------
# The hole in side view: ground height along the centreline from tee to
# pin, with the ball and flag marked. Sits under the hole plate so "is the
# green above me?" is one glance, not a guess from the shading.
#
# Follows a CourseMapView rather than being told about every move: the map
# already hears about every hole change and ball move, so this just
# redraws when either changes.
# ---------------------------------------------------------

var map: CourseMapView
# Set before it enters the tree: a 24px strip with no words of its own —
# the caller says what it shows (the yardage book's game screen).
var compact: bool = false

var _hole: HoleData = null
var _ball: Vector2 = Vector2.INF
var _samples: PackedVector2Array = PackedVector2Array()  # (yards out, height yd)
var _lo := 0.0
var _hi := 1.0

const PAD_X := 10.0
const PAD_TOP := 16.0
const PAD_BOTTOM := 14.0
const SAMPLE_STEP := 4.0
# Never draw less than this much vertical range, so a near-flat hole
# looks near-flat instead of having its 2 ft wobble blown up to fill the box.
const MIN_RANGE_YD := 6.0

const COLOR_PIN := Color(0.753, 0.278, 0.227)
# Which of the terrain's colours (CourseTheme) each lie is drawn in.
const LIE_ROLE := {"fairway": "fairway", "green": "green", "rough": "rough",
	"bunker": "sand", "water": "water", "out": "surround"}


func _ready() -> void:
	custom_minimum_size.y = 24.0 if compact else 74.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if map == null:
		return
	if map.hole != _hole:
		_hole = map.hole
		_resample()
		queue_redraw()
	if map.ball_pos != _ball:
		_ball = map.ball_pos
		queue_redraw()


func _resample() -> void:
	_samples = PackedVector2Array()
	if _hole == null:
		return
	var end_y: float = _hole.green_pos.y + _hole.green_radius
	var y := 0.0
	while y <= end_y:
		_samples.append(Vector2(y, _hole.height_at(Vector2(_hole.centre_x_at(y), y))))
		y += SAMPLE_STEP
	_lo = INF
	_hi = -INF
	for p in _samples:
		_lo = min(_lo, p.y)
		_hi = max(_hi, p.y)
	if _hi - _lo < MIN_RANGE_YD:
		var mid := (_hi + _lo) * 0.5
		_lo = mid - MIN_RANGE_YD * 0.5
		_hi = mid + MIN_RANGE_YD * 0.5


func _to_px(yards_out: float, height: float) -> Vector2:
	var end_y: float = _samples[_samples.size() - 1].x
	var pad_x: float = 4.0 if compact else PAD_X
	var top: float = 4.0 if compact else PAD_TOP
	var bottom: float = 2.0 if compact else PAD_BOTTOM
	var w: float = size.x - pad_x * 2.0
	var h: float = size.y - top - bottom
	return Vector2(
		pad_x + yards_out / max(end_y, 1.0) * w,
		top + (1.0 - (height - _lo) / max(_hi - _lo, 0.001)) * h)


func _draw() -> void:
	if _hole == null or _samples.size() < 2:
		return
	var font := get_theme_default_font()

	# Ground: filled down to the bottom edge, with a darker crest line. Each
	# slice takes the colour of what the centreline crosses there — fairway,
	# rough, sand, water, green — in the course's own terrain palette, so a
	# burn across the fairway or a carry over rough shows in the side view
	# at the yardage it sits at.
	var line := PackedVector2Array()
	for p in _samples:
		line.append(_to_px(p.x, p.y))
	var floor_y: float = size.y if compact else size.y - PAD_BOTTOM + 4
	for i in line.size() - 1:
		var mid_y: float = (_samples[i].x + _samples[i + 1].x) * 0.5
		var lie := _hole.terrain_at(Vector2(_hole.centre_x_at(mid_y), mid_y))
		var role: String = LIE_ROLE.get(lie, "rough")
		# A hair of overlap, so no seam shows between slices (and opaque,
		# so the overlap itself doesn't show either).
		draw_colored_polygon(PackedVector2Array([line[i], line[i + 1] + Vector2(0.5, 0),
			Vector2(line[i + 1].x + 0.5, floor_y), Vector2(line[i].x, floor_y)]),
			CourseTheme.color(_hole.theme, role).lerp(BogeyTheme.PARCHMENT, 0.12))
	draw_polyline(line, CourseTheme.color(_hole.theme, "canopy_dark"), 1.5, true)

	# Flag.
	var pin_px := _to_px(_hole.pin_pos.y, _hole.height_at(_hole.pin_pos))
	var pole: float = 10.0 if compact else 14.0
	draw_line(pin_px, pin_px + Vector2(0, -pole), COLOR_PIN, 1.5)
	if not compact:
		draw_colored_polygon(PackedVector2Array([
			pin_px + Vector2(0, -14), pin_px + Vector2(8, -11), pin_px + Vector2(0, -8)]), COLOR_PIN)

	# Ball, at its real height (it may be off the centreline).
	if _ball != Vector2.INF:
		var ball_px := _to_px(clampf(_ball.y, 0.0, _samples[_samples.size() - 1].x), _hole.height_at(_ball))
		draw_circle(ball_px, 4.0, Color(0.98, 0.98, 0.97))
		draw_arc(ball_px, 4.0, 0, TAU, 14, BogeyTheme.INK, 1.2)
		if compact:
			return

		# How far the flag sits above or below the ball, in feet.
		var ft: int = int(round((_hole.height_at(_hole.pin_pos) - _hole.height_at(_ball)) * HoleData.FEET_PER_YARD))
		var text := "Flag level with you"
		if ft > 0:
			text = "Flag %d ft above you" % ft
		elif ft < 0:
			text = "Flag %d ft below you" % -ft
		draw_string(font, Vector2(PAD_X, 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BogeyTheme.NEUTRAL_700)

	draw_string(font, Vector2(PAD_X, size.y - 2), "TEE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, BogeyTheme.NEUTRAL_600)
	draw_string(font, Vector2(size.x - PAD_X - 40, size.y - 2), "GREEN", HORIZONTAL_ALIGNMENT_RIGHT, 40, 9, BogeyTheme.NEUTRAL_600)
