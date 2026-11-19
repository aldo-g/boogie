class_name CourseMapView
extends Control

# ---------------------------------------------------------
# Top-down hole map. The ground — fairway, green, hazards, scenery — is
# painted once per hole by a child node (CourseArt) from the HoleData;
# this node draws what moves over it: the ball's position and shot trail,
# and (during a shot) the ball itself actually flying along the aim
# arc — a small arcing hop with a growing motion trail — so the shot
# reads as the ball traveling across the screen, not just a marker
# jumping between two points.
# ---------------------------------------------------------

signal aim_picked(target: Vector2)  # yard-space point where the player pressed Confirm
signal aim_changed(target: Vector2)  # yard-space point the crosshair is now sitting on

var hole: HoleData
var ball_pos: Vector2 = Vector2.ZERO  # yard-space
var shot_path: Array = []             # yard-space points, tee to current ball_pos

# The OTHER players' balls in a hot-seat round (Section 7), as
# [{"pos": Vector2, "name": String, "index": int}, ...]. Empty in a solo
# round, so nothing extra is drawn. Drawn smaller and tinted by seat so
# the active player's own ball stays the one your eye goes to.
var other_balls: Array = []

# Set true to resolve shots with no tween at all — the ball jumps straight
# to where it lands and the callback fires immediately. Set by the headless
# flow harnesses (the animation is ~0.4-1.0s of real time per shot); in
# play, the "Instant" shot speed setting does the same thing.
var skip_animation: bool = false

var aiming: bool = false           # true while the player can move/set the aim crosshair
# True while a computer golfer is aiming: the crosshair and its line are
# drawn as usual, but the mouse can't move or commit them.
var input_locked: bool = false
var aim_target: Vector2 = Vector2.ZERO  # yard-space, current crosshair position
# Whether the last-committed aim is drawn while not aiming. Main turns it on
# only while the Form hand is read, so a stale aim never lingers into
# putting, the draft or another player's turn.
var show_last_aim: bool = false:
	set(v):
		if v != show_last_aim:
			show_last_aim = v
			queue_redraw()
var aim_min_range: float = 0.0     # yards — the selected club's min_yard
var aim_max_range: float = 999.0   # yards — the selected club's max_yard
var aim_club: Dictionary = {}      # the selected club dict, for drawing per-tier bands

var _hovering: bool = false        # true once the mouse has moved over the map while aiming

# Club-reach preview (bag hover). Set while the cursor rests on a bag
# card, cleared when it leaves. Draws exactly what committing to the club
# would draw — the same tier bands, via _draw_tier_bands() — so the
# preview is a true rehearsal of the shot rather than a second, different
# picture the player has to learn separately.
var preview_club: Dictionary = {}

# The painted ground — everything that holds still while a hole is played —
# lives in a child drawn behind this node (see CourseArt), so the redraws
# aiming and ball flight ask for never repaint it.
var _art: CourseArt

# The editor pins the framing while a handle is dragged, so the view doesn't
# rescale under the cursor as the hole's bounds grow. Zero size = follow
# the hole.
var fixed_extent: Rect2 = Rect2():
	set(value):
		fixed_extent = value
		# The framing moved, so the ground has to be repainted under it.
		if _art:
			_art.queue_redraw()

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
var _flight_hop_height: float = 0.0 # how high the ball is right now, in yards
var _flight_loft: float = 1.0       # how high this shot flies (ShotResolver.flight_height)
var _pending_roll: Array = []       # run-out path for the shot being animated
var _flight_sunk: bool = false      # it went in the water: nothing left to draw
var _bounce_apex: float = 0.0       # yards the first skip rises after this landing

# What the ground does when the ball arrives — a ring on turf, a puff out
# of sand, a splash — each a short-lived thing drawn over the map and gone
# again: { kind, pos (yards), age, life (seconds), seed }.
var _fx: Array = []

# Putts (and anything else that goes in the hole). The game moves the ball
# the instant a putt is struck; these are the rolls the map is still
# showing, oldest first: { from, to, holed, roll (seconds) }.
var _putts: Array = []
var _putt_t: float = 0.0            # the one under way: how far along, 0 to 1
var _putt_drop: float = 0.0         # ...and how far into the cup, 0 to 1
var _putt_tween: Tween
var _putt_busy_until: int = 0       # msec tick when the last of them will have dropped

const MARGIN := 16.0
# The ground's own colours — fairway, rough, sand, water, trees — belong to
# the course's terrain and live in CourseTheme. What's here is what moves.
const COLOR_BALL := Color(0.98, 0.98, 0.97)
# Seat tints for other players' balls, indexed by seat. Picked to read
# against both fairway green and sand, and to stay distinct from each
# other, from the white active ball, and from the red pin. None of them is
# white: the active player's ball is the white one, so a seat tint has to
# differ from it even for seat 1.
const COLOR_SEATS := [
	Color(0.839, 0.333, 0.333), # seat 1 — red
	Color(0.384, 0.502, 0.788), # seat 2 — blue
	Color(0.886, 0.620, 0.216), # seat 3 — amber
	Color(0.608, 0.420, 0.718), # seat 4 — violet
]
const COLOR_BALL_OUTLINE := Color(0.169, 0.227, 0.184)
# The map looks straight down, so a ball in the air is a ball coming
# toward you: it swells as it climbs and shrinks back as it drops, while
# its shadow stays on the ground, slides out from under it and thins. At
# rest and at the top of FLIGHT_FULL_RISE yards of air it is BALL_RADIUS
# and BALL_RADIUS * FLIGHT_SWELL pixels across.
const BALL_RADIUS := 5.0
const FLIGHT_APEX_SHARE := 0.06   # a stock shot peaks at this share of its carry
const FLIGHT_FULL_RISE := 12.0    # yards up — about a full drive — at which the ball is biggest
const FLIGHT_SWELL := 2.1

# A ball that pitches on turf skips before it runs: the first skip rises
# BOUNCE_SHARE of the flight's own apex (kept between MIN and MAX yards, so
# a chip still skips and a drive doesn't leap), the second a third of
# that, and the two are over in BOUNCE_TIME seconds. How lively depends on
# what it lands on — and sand and water don't give it back at all.
const BOUNCE_SHARE := 0.28
const BOUNCE_MIN := 1.0
const BOUNCE_MAX := 3.5
const BOUNCE_TIME := 0.40
const BOUNCE_BY_GROUND := {"fairway": 1.0, "green": 0.7, "rough": 0.45}
# How long the map holds on a splash before the game moves on.
const SPLASH_HOLD := 0.38
const FX_LIFE := {"thump": 0.30, "rough": 0.38, "sand": 0.55, "splash": 0.80, "cup": 0.45}
# A putt: yards rolled per second of animation (within the limits), then
# the drop into the cup, then a beat before the fanfare.
const PUTT_YARDS_PER_SEC := 11.0
const PUTT_ROLL_MIN := 0.22
const PUTT_ROLL_MAX := 0.85
const PUTT_DROP_TIME := 0.20
const PUTT_BEAT := 0.28
const COLOR_BALL_SHADOW := Color(0.106, 0.129, 0.110, 0.35)
const COLOR_TRAIL := Color(0.169, 0.227, 0.184, 0.55)
const COLOR_FLIGHT_TRAIL := Color(0.98, 0.98, 0.97, 0.9)
const COLOR_PIN := Color(0.753, 0.278, 0.227)


func _init() -> void:
	# Made here rather than in _ready(): set_hole() can be called on a map
	# that isn't in the tree yet.
	_art = CourseArt.new()
	_art.view = self
	add_child(_art)


func _ready() -> void:
	set_process(false)   # only while a landing effect is in the air
	custom_minimum_size = Vector2(220, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Hard-clips every _draw() call (course art, swing-tier bands, aim
	# crosshair) to this Control's own rect — the hole plate is the
	# course's viewport, so nothing drawn here should ever bleed past it
	# into neighboring panels.
	clip_contents = true


# `bake` = false skips the slope shading — the course editor rebuilds the
# hole on every drag step and bakes once when the drag ends.
func set_hole(p_hole: HoleData, bake: bool = true) -> void:
	if hole != p_hole:
		hole = p_hole
		_art.refresh(bake)
		# Nothing from the last hole is still landing on this one.
		_fx = []
		_putts = []
		_putt_busy_until = 0
		if _putt_tween != null and _putt_tween.is_valid():
			_putt_tween.kill()
	queue_redraw()


func set_ball(p_pos: Vector2, p_path: Array) -> void:
	ball_pos = p_pos
	shot_path = p_path
	queue_redraw()


func set_other_balls(p_others: Array) -> void:
	other_balls = p_others
	queue_redraw()


# The tint for a seat index, wrapping rather than erroring if a round ever
# seats more players than there are colors.
static func seat_color(index: int) -> Color:
	if COLOR_SEATS.is_empty():
		return COLOR_BALL
	return COLOR_SEATS[index % COLOR_SEATS.size()]


# Enables/disables click-to-aim, locked to the selected club's max yardage —
# the crosshair's direction is free, and its distance from the ball is
# capped at max_range (you can't aim somewhere the club can't reach), but
# NOT floored at min_range: aiming inside a club's normal band is legal
# and is exactly what Section 4's "Extreme Finesse" tier is — a heavily
# bad-card-biased Form draw, not a blocked shot. min_range is kept only
# for the faint reference ring drawn in _draw() and the tier math in
# Main.gd, never as a movement floor.
# While aiming, moving the mouse over the map live-previews the crosshair
# (no button needs to be held) and fires aim_changed each time so the shot
# outlook panel can warn about tier odds before anything commits. A
# left-click commits immediately at the cursor's spot via aim_picked —
# there's no separate confirm step, so the preview is the only chance to
# see the risk before playing. club is the full club dict (needed to draw
# the four swing-tier bands via ShotResolver.tier_yardage_range()).
# Called by the bag row as the cursor enters/leaves a club card. Pass an
# empty dictionary to clear. Suppressed while aiming: once a club is
# chosen the map is already showing that club's full tier breakdown, and
# a second ring over the top would be noise.
# One club's yardages, drawn the way a yardage book prints carry arcs: short
# arcs across the line of play, each with its number, rather than coloured
# rings all the way round the ball.
#
#   - the club's shortest yardage: a dashed hairline (below it is Extreme
#     Finesse, where the crosshair turns claret);
#   - the sweet spot (the Mid tier, best odds): a pair of solid arcs with
#     fine hatching between them;
#   - the club's longest yardage: a plain hairline.
#
# Lines are paper-white over a soft ink shadow so they read on fairway and
# dark rough alike. The putter (a band starting at 0) gets just its reach
# arc, in the same hand. Shared by the live aim and the bag-hover preview so
# the two can never show a club differently.
#
# `facing` is the line of play in yard-space (toward the crosshair, or the
# pin on a hover); `fallback_max` is the aim's own reach for the putter.
const ARC_HALF_ANGLE := 0.663   # 38° either side of the line of play
const ARC_INK := Color(1.0, 1.0, 0.98, 0.92)
const ARC_SHADOW := Color(0.08, 0.09, 0.08, 0.35)


func _draw_tier_bands(club: Dictionary, origin_px: Vector2, scale_px: float,
		fallback_max: float = 0.0, facing: Vector2 = Vector2.UP) -> void:
	if club.is_empty():
		return
	# Yard-space +y is screen-up, so flip y to get the screen angle.
	var f := Vector2(facing.x, -facing.y)
	if f.length_squared() < 0.0001:
		f = Vector2(0, -1)
	var mid_angle := f.angle()
	var a0 := mid_angle - ARC_HALF_ANGLE
	var a1 := mid_angle + ARC_HALF_ANGLE
	var labels: Array = []   # [radius_px, yards], drawn last so arcs never cover them

	var lo_yd: float = float(club.get("min_yard", 0.0))
	var hi_yd: float = float(club.get("max_yard", 0.0))
	if lo_yd <= 0.0:
		var reach: float = fallback_max if fallback_max > 0.0 else hi_yd
		if reach > 0.0 and reach < 900.0:
			_yardage_arc(origin_px, reach * scale_px, a0, a1, 1.2, false)
			labels.append([reach * scale_px, reach])
	else:
		var sweet := ShotResolver.tier_yardage_range(club, ShotResolver.Tier.MID)
		var r_lo := lo_yd * scale_px
		var r_s0 := sweet.x * scale_px
		var r_s1 := sweet.y * scale_px
		var r_hi := hi_yd * scale_px
		_yardage_arc(origin_px, r_lo, a0, a1, 1.0, true)
		# Sweet-spot hatching: short radial strokes across the band.
		var steps := maxi(int((a1 - a0) / deg_to_rad(2.5)), 1)
		for i in range(steps + 1):
			var a := a0 + (a1 - a0) * float(i) / float(steps)
			var d := Vector2.from_angle(a)
			draw_line(origin_px + d * r_s0, origin_px + d * r_s1, Color(ARC_INK, 0.28), 1.0)
		_yardage_arc(origin_px, r_s0, a0, a1, 1.6, false)
		_yardage_arc(origin_px, r_s1, a0, a1, 1.6, false)
		_yardage_arc(origin_px, r_hi, a0, a1, 1.0, false)
		labels.append([r_lo, lo_yd])
		labels.append([r_s0, sweet.x])
		labels.append([r_s1, sweet.y])
		labels.append([r_hi, hi_yd])

	# Numbers at the clockwise end of each arc, on a slip of card. The
	# club's own shortest and longest always get theirs; a sweet-spot edge
	# is numbered only if it has room, never stacked over another.
	var end_dir := Vector2.from_angle(a1)
	var order: Array = [labels[0]]
	if labels.size() == 4:
		order = [labels[0], labels[3], labels[1], labels[2]]
	var placed: Array = []
	for l in order:
		var clear := true
		for r in placed:
			if absf(l[0] - r) < 14.0:
				clear = false
		if not clear:
			continue
		placed.append(l[0])
		_yardage_slip(origin_px + end_dir * l[0] + end_dir * 4.0, "%d" % roundi(l[1]), BogeyTheme.INK)


# The aim line and crosshair: paper-white over an ink shadow so it reads on
# any ground; dashed once committed, solid while the cursor still moves it.
func _draw_aim_mark(from_px: Vector2, to_px: Vector2, col: Color, dashed: bool) -> void:
	var sh := Vector2(0, 1)
	if dashed:
		_draw_dashed_line(from_px + sh, to_px + sh, ARC_SHADOW, 2.5, 5.0, 4.0)
		_draw_dashed_line(from_px, to_px, col, 1.5, 5.0, 4.0)
	else:
		draw_line(from_px + sh, to_px + sh, ARC_SHADOW, 3.0, true)
		draw_line(from_px, to_px, col, 1.6, true)
	draw_arc(from_px, 9.0, 0, TAU, 20, Color(col, 0.8), 1.5, true)
	draw_arc(to_px + sh, 7.0, 0, TAU, 18, ARC_SHADOW, 2.5, true)
	draw_arc(to_px, 7.0, 0, TAU, 18, col, 1.5, true)
	for d in [Vector2(1, 0), Vector2(0, 1)]:
		draw_line(to_px - d * 11.0 + sh, to_px + d * 11.0 + sh, ARC_SHADOW, 2.5)
		draw_line(to_px - d * 11.0, to_px + d * 11.0, col, 1.2)


func _yardage_arc(c: Vector2, r: float, a0: float, a1: float, w: float, dashed: bool) -> void:
	if r < 2.0:
		return
	var pts := maxi(int((a1 - a0) * r / 6.0), 8)
	if not dashed:
		draw_arc(c + Vector2(0, 1), r, a0, a1, pts, ARC_SHADOW, w + 1.0, true)
		draw_arc(c, r, a0, a1, pts, ARC_INK, w, true)
		return
	# Dashes of about 6 px with 5 px gaps along the arc.
	var step := 11.0 / r
	var a := a0
	while a < a1:
		var b := minf(a + 6.0 / r, a1)
		draw_arc(c + Vector2(0, 1), r, a, b, 4, ARC_SHADOW, w + 1.0, true)
		draw_arc(c, r, a, b, 4, ARC_INK, w, true)
		a += step


# A small number on a slip of card, centred on `at` — the same paper slip
# the wind dial and the pin note sit on.
func _yardage_slip(at: Vector2, text: String, col: Color) -> void:
	var font := BogeyUI.sans(500)
	var fs := 10
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rect := Rect2(at - Vector2(w * 0.5 + 4.0, 7.0), Vector2(w + 8.0, 14.0))
	draw_rect(rect, Color(BogeyTheme.CARD_BG, 0.9))
	draw_string(font, Vector2(rect.position.x + 4.0, rect.position.y + 10.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func set_preview_club(club: Dictionary) -> void:
	if preview_club == club:
		return
	preview_club = club
	queue_redraw()


func set_aiming(enabled: bool, min_range: float = 0.0, max_range: float = 999.0, club: Dictionary = {}) -> void:
	# A live aim supersedes any hover preview: the card that was hovered is
	# usually the one just picked, and its mouse_exited never fires once the
	# bag row is rebuilt out from under the cursor.
	if enabled:
		preview_club = {}
	aiming = enabled
	aim_min_range = max(min_range, 0.0)
	aim_max_range = max(max_range, 0.01)
	aim_club = club
	_hovering = false
	queue_redraw()


func set_aim_target(p_target: Vector2) -> void:
	aim_target = _clamp_to_range(p_target) if aiming else p_target
	queue_redraw()


# Keeps the aim direction from the ball, capping its distance at
# aim_max_range (a club simply cannot reach further than that — aiming
# closer than aim_min_range is always allowed, that's Extreme Finesse),
# then pulls the point back inside the hole's own drawn extent so the
# crosshair, its line, and the range rings can never reach out into the
# dead space beyond the mapped course art.
func _clamp_to_range(p: Vector2) -> Vector2:
	# Delegates to ShotResolver so the crosshair and the authoritative
	# gameplay value can never drift apart.
	var q := ShotResolver.clamp_aim(p, ball_pos, aim_max_range, _yard_extent())
	# The ground in play is a shape inside that box, not the box itself. A
	# cursor over the trees slides the crosshair along the stakes rather
	# than letting it be set down out of bounds. (Still inside the box, so
	# the authoritative clamp leaves it exactly where it is.)
	if hole and fixed_extent.size == Vector2.ZERO and hole.is_out_of_bounds(q):
		var on_course := hole.nearest_in_bounds(q)
		if on_course.distance_to(ball_pos) <= aim_max_range + 0.01:
			q = on_course
	return q


# Clamps a yard-space point to stay within the rectangle _yard_extent()
# actually draws terrain in, so the aim crosshair can never sit visibly
# off the course.
func _clamp_to_extent(p: Vector2) -> Vector2:
	return ShotResolver.clamp_to_bounds(p, _yard_extent())


func _gui_input(event: InputEvent) -> void:
	if not aiming or input_locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		aim_target = _clamp_to_range(_px_to_yard(event.position))
		aiming = false
		_hovering = false
		aim_picked.emit(aim_target)
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		_hovering = true
		aim_target = _clamp_to_range(_px_to_yard(event.position))
		aim_changed.emit(aim_target)
		queue_redraw()


# Kicks off the full shot animation: the aim arm rotates to the degree
# offset and extends to show the intended line, then the ball itself
# flies along that same line with a little arc and a fading trail, so
# the ball is visibly traceable across the map rather than teleporting.
# All distances in yards; base_dir is the player's chosen aim line (from
# the click-to-aim step), not necessarily toward the pin.
# `loft` is how high the shot flies against a stock iron's 1.0
# (ShotResolver.flight_height): it sets how far the ball lifts off its
# shadow and how much it swells on the way up. 0 runs along the ground.
func play_aim_animation(base_dir: Vector2, distance: float, degree: float, side: int, max_distance: float, on_done: Callable, roll_path: Array = [], loft: float = 1.0) -> void:
	if not hole:
		on_done.call()
		return
	_flight_loft = maxf(loft, 0.0)
	if skip_animation or Settings.instant_shots():
		# No tween: land the shot now. Nothing here needs frames, so a
		# caller driving the game in a loop makes real progress.
		_aim_active = false
		_flight_active = false
		_flight_trail = []
		# No pictures, but still the sound of where it finished.
		if not roll_path.is_empty():
			_sound_landing(hole.terrain_at(roll_path[roll_path.size() - 1]))
		on_done.call()
		return
	_pending_roll = roll_path
	_aim_active = true
	_aim_origin = ball_pos
	_aim_base_dir = base_dir.normalized()
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
	tw.set_speed_scale(Settings.shot_speed_scale())
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
	# The resolved landing (wind and elevation included) is the first point
	# of the run-out path — fly there, not to the end of the aimed line.
	if not _pending_roll.is_empty():
		end_yard = _pending_roll[0]

	_flight_active = true
	_flight_sunk = false
	_flight_pos = start_yard
	_flight_trail = [start_yard]
	_flight_hop_height = 0.0

	# Duration scales gently with distance so a 30-yard chip feels quick
	# and a 260-yard drive still reads as a real flight, not a blink.
	var duration: float = clamp(distance / 260.0, 0.28, 0.85)

	var tw := create_tween()
	tw.set_speed_scale(Settings.shot_speed_scale())
	tw.tween_method(func(t: float): _update_ball_flight(start_yard, end_yard, t),
		0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# It lands: the sound and the mark of whatever it landed on, and on
	# turf a skip or two — higher off a high shot, livelier off short grass.
	var path: Array = _pending_roll
	_pending_roll = []
	var roll_len := _path_length(path)
	var rest_yard: Vector2 = path[path.size() - 1] if not path.is_empty() else end_yard
	var touched := hole.terrain_at(end_yard)
	var rested := hole.terrain_at(rest_yard)
	var apex: float = start_yard.distance_to(end_yard) * FLIGHT_APEX_SHARE * _flight_loft
	var spring: float = float(BOUNCE_BY_GROUND.get(touched, 0.0)) if _flight_loft > 0.0 else 0.0
	tw.tween_callback(func():
		_flight_hop_height = 0.0
		_flight_trail = [_flight_pos]
		_bounce_apex = clampf(apex * BOUNCE_SHARE, BOUNCE_MIN, BOUNCE_MAX) * spring
		_touch_down(end_yard, touched))

	# Then the run-out along the exact path ShotResolver rolled, easing to
	# a stop so it reads as the ball losing pace — skipping as it sets off.
	if roll_len >= 1.0:
		var roll_time: float = clamp(roll_len / 40.0, 0.25, 1.1)
		tw.tween_method(func(t: float): _update_ball_roll(path, roll_len, t),
			0.0, 1.0, roll_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if spring > 0.0:
			tw.parallel().tween_method(_set_bounce, 0.0, 1.0, minf(BOUNCE_TIME, roll_time))
	elif spring > 0.0:
		# It stops where it pitched: one hop on the spot, half the height.
		tw.tween_method(func(u: float): _set_bounce(u * 0.62 * 0.999, 0.5), 0.0, 1.0, BOUNCE_TIME * 0.6)

	# Where it stopped, if that's somewhere worse than where it landed: a
	# ball that ran on into the sand or the water.
	tw.tween_callback(func():
		_flight_hop_height = 0.0
		if rested != touched:
			_touch_down(rest_yard, rested))
	if touched == "water" or rested == "water":
		tw.tween_interval(SPLASH_HOLD)

	tw.tween_callback(func():
		_flight_active = false
		_flight_sunk = false
		_flight_trail = []
		on_done.call()
	)


# The Sound autoload, found by path and called by name. Not written as
# `Sound.…`: the dev harnesses compile this script (through its class
# name) before any autoload exists, and a bare `Sound` would not compile.
func _sound_landing(ground: String) -> void:
	var sound := get_node_or_null("/root/Sound") if is_inside_tree() else null
	if sound:
		sound.call("landing", ground)


func _sound_play(group: String) -> void:
	var sound := get_node_or_null("/root/Sound") if is_inside_tree() else null
	if sound:
		sound.call("play", group)


# The ball meets the ground at `at`, which is `ground`: its sound, and
# its mark. Water takes the ball with it.
func _touch_down(at: Vector2, ground: String) -> void:
	_sound_landing(ground)
	match ground:
		"water":
			_flight_sunk = true
			_spawn_fx("splash", at)
		"bunker":
			_spawn_fx("sand", at)
		"rough":
			_spawn_fx("rough", at)
		"fairway", "green":
			_spawn_fx("thump", at)
	queue_redraw()


# The skips after a landing: `u` runs 0 to 1 over the two of them, the
# second a third the height of the first. They ride on whatever the ball
# is doing along the ground, so it skips forward along its run-out.
func _set_bounce(u: float, scale: float = 1.0) -> void:
	var h: float = sin(PI * u / 0.62) if u < 0.62 else 0.34 * sin(PI * (u - 0.62) / 0.38)
	_flight_hop_height = _bounce_apex * scale * maxf(h, 0.0)
	queue_redraw()


func _spawn_fx(kind: String, at: Vector2) -> void:
	_fx.append({"kind": kind, "pos": at, "age": 0.0, "life": float(FX_LIFE.get(kind, 0.4)), "seed": randi()})
	set_process(true)
	queue_redraw()


# Only running while an effect is in the air (see _spawn_fx).
func _process(delta: float) -> void:
	var live: Array = []
	for fx in _fx:
		fx.age += delta
		if fx.age < fx.life:
			live.append(fx)
	_fx = live
	if _fx.is_empty():
		set_process(false)
	queue_redraw()


# --- Putts ------------------------------------------------------------
# The game decides a putt the moment it's struck and moves the ball there
# and then. The map shows it happening: the ball rolls from where it was to
# where it finished, and if that's the hole it drops — the cup's rattle on
# the drop, not before. Purely a picture: nothing waits on it except the
# fanfare, which asks putt_beat() how long to hold off.
func play_putt(from: Vector2, to: Vector2, holed: bool) -> void:
	if skip_animation or Settings.instant_shots() or hole == null or not is_inside_tree():
		if holed:
			_sound_play("cup")
		return
	var roll: float = 0.0
	if from.distance_to(to) > 0.05:
		roll = clampf(from.distance_to(to) / PUTT_YARDS_PER_SEC, PUTT_ROLL_MIN, PUTT_ROLL_MAX)
	_putts.append({"from": from, "to": to, "holed": holed, "roll": roll})
	var takes: float = (roll + (PUTT_DROP_TIME + PUTT_BEAT if holed else 0.0)) / maxf(Settings.shot_speed_scale(), 0.01)
	_putt_busy_until = maxi(_putt_busy_until, Time.get_ticks_msec()) + int(takes * 1000.0)
	if _putts.size() == 1:
		_run_putt()


# A ball that has just arrived at the hole some other way — holed from off
# the green — drops in like a putt that got there.
func drop_in_cup() -> void:
	if hole:
		play_putt(hole.pin_pos, hole.pin_pos, true)


# Seconds until every putt on the map has finished (and, if it was holed,
# dropped and been given its beat). 0 when nothing is rolling.
func putt_beat() -> float:
	if _putts.is_empty():
		return 0.0
	return maxf(0.0, float(_putt_busy_until - Time.get_ticks_msec()) / 1000.0)


func _run_putt() -> void:
	queue_redraw()
	if _putts.is_empty():
		return
	var p: Dictionary = _putts[0]
	_putt_t = 0.0 if float(p.roll) > 0.0 else 1.0
	_putt_drop = 0.0
	_putt_tween = create_tween()
	_putt_tween.set_speed_scale(Settings.shot_speed_scale())
	if float(p.roll) > 0.0:
		# Dying into the hole, the way a putt does.
		_putt_tween.tween_method(_set_putt_t, 0.0, 1.0, float(p.roll)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if bool(p.holed):
		_putt_tween.tween_callback(func():
			_sound_play("cup")
			_spawn_fx("cup", p.to))
		_putt_tween.tween_method(_set_putt_drop, 0.0, 1.0, PUTT_DROP_TIME)
		_putt_tween.tween_interval(PUTT_BEAT)
	_putt_tween.tween_callback(func():
		_putts.pop_front()
		_run_putt())


func _set_putt_t(t: float) -> void:
	_putt_t = t
	queue_redraw()


func _set_putt_drop(d: float) -> void:
	_putt_drop = d
	queue_redraw()


# A ball marker isn't drawn where a putt is still rolling to, nor in the
# hole itself: a ball at the pin has been holed, and it's in the cup.
func _marker_hidden(at: Vector2) -> bool:
	if hole and at.distance_to(hole.pin_pos) < 0.05:
		return true
	for p in _putts:
		if at.distance_to(p.to) < 0.05:
			return true
	return false


func _path_length(path: Array) -> float:
	var total := 0.0
	for i in range(path.size() - 1):
		total += (path[i] as Vector2).distance_to(path[i + 1])
	return total


func _update_ball_roll(path: Array, total: float, t: float) -> void:
	var want: float = total * t
	var acc := 0.0
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var seg := a.distance_to(b)
		if acc + seg >= want:
			_flight_pos = a.lerp(b, (want - acc) / max(seg, 0.0001))
			break
		acc += seg
		_flight_pos = b
	_flight_trail.append(_flight_pos)
	if _flight_trail.size() > 6:
		_flight_trail.pop_front()
	queue_redraw()


func _update_ball_flight(start_yard: Vector2, end_yard: Vector2, t: float) -> void:
	_flight_pos = start_yard.lerp(end_yard, t)
	# Up and down again over the carry: nothing at either end, the apex in
	# the middle. Higher for a longer shot and for a loftier one.
	_flight_hop_height = sin(t * PI) * start_yard.distance_to(end_yard) * FLIGHT_APEX_SHARE * _flight_loft
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
	if fixed_extent.has_area():
		return fixed_extent
	if not hole:
		return Rect2(-50, -20, 100, 440)
	# The drawn extent IS the playable extent: the rough rect painted from
	# this rectangle is the ground that counts as in bounds, so the picture
	# and the rule are the same number rather than two that happen to agree.
	return hole.bounds


func _to_px(yard_pt: Vector2) -> Vector2:
	var extent := _yard_extent()
	var avail := size - Vector2(MARGIN, MARGIN) * 2.0
	var scale_x: float = avail.x / max(extent.size.x, 1.0)
	var scale_y: float = avail.y / max(extent.size.y, 1.0)
	var s: float = min(scale_x, scale_y)
	# The hole is always much taller than it is wide, so one axis has slack
	# left over after fitting the other — center the drawing in that slack
	# rather than pinning it to the top-left corner.
	var drawn_size: Vector2 = extent.size * s
	var origin: Vector2 = Vector2(MARGIN, MARGIN) + (avail - drawn_size) * 0.5
	var px_x: float = origin.x + (yard_pt.x - extent.position.x) * s
	# Flip Y: yard-space +y (toward pin) should go UP on screen.
	var y_from_top: float = extent.size.y - (yard_pt.y - extent.position.y)
	var px_y: float = origin.y + y_from_top * s
	return Vector2(px_x, px_y)


# Inverse of _to_px(): screen pixel -> yard-space, for turning a click into
# an aim target. Mirrors _to_px()'s centering/scale math exactly.
func _px_to_yard(px_pt: Vector2) -> Vector2:
	var extent := _yard_extent()
	var avail := size - Vector2(MARGIN, MARGIN) * 2.0
	var scale_x: float = avail.x / max(extent.size.x, 1.0)
	var scale_y: float = avail.y / max(extent.size.y, 1.0)
	var s: float = max(min(scale_x, scale_y), 0.0001)
	var drawn_size: Vector2 = extent.size * s
	var origin: Vector2 = Vector2(MARGIN, MARGIN) + (avail - drawn_size) * 0.5
	var yard_x: float = (px_pt.x - origin.x) / s + extent.position.x
	var y_from_top: float = (px_pt.y - origin.y) / s
	var yard_y: float = extent.position.y + extent.size.y - y_from_top
	return Vector2(yard_x, yard_y)


func _px_scale() -> float:
	var extent := _yard_extent()
	var avail := size - Vector2(MARGIN, MARGIN) * 2.0
	var scale_x: float = avail.x / max(extent.size.x, 1.0)
	var scale_y: float = avail.y / max(extent.size.y, 1.0)
	return min(scale_x, scale_y)


func _draw() -> void:
	if not hole:
		return

	# The ground itself — rough, fairway, hazards, green, slope shading,
	# scenery, tee and flag — is already on screen: CourseArt painted it
	# behind this node. From here down is only what changes during a hole.

	# Shot trail: tee -> each prior landing spot -> current ball position,
	# drawn as short dashes so it reads as a path etched into the grass
	# rather than a solid line competing with the live flight trail.
	if shot_path.size() >= 2:
		for i in range(shot_path.size() - 1):
			_draw_dashed_line(_to_px(shot_path[i]), _to_px(shot_path[i + 1]), COLOR_TRAIL, 2.0, 6.0, 5.0)

	# --- Club yardages: hovering a bag card, and while aiming -----------
	# The same arcs, drawn by the same function, so hovering a club and
	# committing to it can never disagree about its yardages.
	if not aiming and not preview_club.is_empty() and not _flight_active:
		var prev_origin := _to_px(ball_pos)
		_draw_tier_bands(preview_club, prev_origin, _px_scale(), 0.0, hole.pin_pos - ball_pos)

	if aiming:
		# Arcs are drawn at their real radius and simply clip at the
		# Control's edge; the crosshair is what's clamped inside the course.
		_draw_tier_bands(aim_club, _to_px(ball_pos), _px_scale(), aim_max_range,
			aim_target - ball_pos)

	# The guide shows where you are aiming and nothing more. Wind, slope,
	# run-out and the Form card all act on the shot, but reading them is the
	# player's job: nothing on the map works out where the ball will finish.
	if aiming and (_hovering or input_locked):
		# Live crosshair: follows the cursor; a click commits at this spot.
		# Claret below the club's shortest yardage (Extreme Finesse, where the
		# Form draw is forced bad), paper-white otherwise.
		var dist_now: float = ball_pos.distance_to(aim_target)
		var out_of_band: bool = dist_now < aim_min_range
		var col: Color = BogeyTheme.FLAG if out_of_band else ARC_INK
		var target_px := _to_px(aim_target)
		_draw_aim_mark(_to_px(ball_pos), target_px, col, false)
		_yardage_slip(target_px + Vector2(0, 17), "%d yds" % roundi(dist_now),
			BogeyTheme.FLAG if out_of_band else BogeyTheme.INK)
	elif show_last_aim and not aiming and not _aim_active and not _flight_active and aim_target.distance_to(ball_pos) > 0.5:
		# Last-committed aim, shown while the Form hand is read.
		_draw_aim_mark(_to_px(ball_pos), _to_px(aim_target), ARC_INK, true)

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
		draw_line(origin_px + Vector2(0, 1), end_px + Vector2(0, 1), ARC_SHADOW, 3.0, true)
		draw_line(origin_px, end_px, ARC_INK, 1.6, true)
		draw_circle(end_px, 3.5, ARC_INK)

	if hole.wind != Vector2.ZERO or aiming:
		_draw_wind_dial()
	if hole.pin_name != "":
		_draw_pin_note()

	# The other players' balls first, so the active player's own ball
	# draws over the top of them and stays unambiguous.
	for other in other_balls:
		if _marker_hidden(other.pos):
			continue
		var other_px := _to_px(other.pos)
		draw_circle(other_px + Vector2(0, 2), 3.0, COLOR_BALL_SHADOW)
		draw_circle(other_px, 4.0, seat_color(int(other.index)))
		draw_arc(other_px, 4.0, 0, TAU, 14, COLOR_BALL_OUTLINE, 1.2)

	# What the last landing left behind goes under the ball.
	_draw_fx()

	# Ball in flight: a fading motion trail behind the current flight
	# position, plus a drop shadow offset from the ball to sell a hop/arc,
	# so the ball is visibly traceable across the screen mid-shot.
	if _flight_active:
		if not _flight_sunk:
			var n := _flight_trail.size()
			for i in range(n - 1):
				var a: float = float(i + 1) / float(n)
				var c := COLOR_FLIGHT_TRAIL
				c.a *= a * 0.6
				var r: float = lerp(1.0, 4.0, a)
				draw_circle(_to_px(_flight_trail[i]), r, c)
			# How far up it is, 0 on the ground to 1 at the height of a full
			# drive (a ballooned one goes a little past, and is capped).
			var rise: float = clampf(_flight_hop_height / FLIGHT_FULL_RISE, 0.0, 1.25)
			var shadow_px := _to_px(_flight_pos)
			draw_circle(shadow_px + Vector2(0, 2), lerpf(3.5, 2.6, minf(rise, 1.0)),
				Color(COLOR_BALL_SHADOW, COLOR_BALL_SHADOW.a * lerpf(1.0, 0.55, minf(rise, 1.0))))
			var lift_px: float = _flight_hop_height * _px_scale()
			var ball_px := shadow_px + Vector2(0, -lift_px)
			var ball_r: float = BALL_RADIUS * lerpf(1.0, FLIGHT_SWELL, rise)
			draw_circle(ball_px, ball_r, COLOR_BALL)
			draw_arc(ball_px, ball_r, 0, TAU, 24, COLOR_BALL_OUTLINE, 1.5)
	elif not _marker_hidden(ball_pos):
		# Ball marker at its current resting position.
		var ball_px := _to_px(ball_pos)
		draw_circle(ball_px + Vector2(0, 2), 3.5, COLOR_BALL_SHADOW)
		draw_circle(ball_px, BALL_RADIUS, COLOR_BALL)
		draw_arc(ball_px, BALL_RADIUS, 0, TAU, 16, COLOR_BALL_OUTLINE, 1.5)

	_draw_putt()


# A putt on its way (see play_putt): the ball rolling to where it finished
# and, if that's the hole, going down into it.
func _draw_putt() -> void:
	if _putts.is_empty():
		return
	var p: Dictionary = _putts[0]
	var px := _to_px((p.from as Vector2).lerp(p.to, _putt_t))
	if bool(p.holed) and _putt_drop > 0.0:
		# Over the lip: the cup shows dark, and the ball sinks into it,
		# shrinking and losing the light.
		draw_circle(px, 3.6, Color(BogeyTheme.INK, 0.9))
		if _putt_drop < 1.0:
			var r: float = BALL_RADIUS * lerpf(1.0, 0.4, _putt_drop)
			draw_circle(px + Vector2(0, 1.4 * _putt_drop), r, COLOR_BALL.darkened(0.55 * _putt_drop))
		return
	draw_circle(px + Vector2(0, 2), 3.5, COLOR_BALL_SHADOW)
	draw_circle(px, BALL_RADIUS, COLOR_BALL)
	draw_arc(px, BALL_RADIUS, 0, TAU, 16, COLOR_BALL_OUTLINE, 1.5)


# The mark a landing leaves, for the fraction of a second it lasts. Sizes
# are in pixels: these are gestures, not ground.
func _draw_fx() -> void:
	if _fx.is_empty():
		return
	var theme_id: String = hole.theme if hole else CourseTheme.DEFAULT
	for fx in _fx:
		var c := _to_px(fx.pos)
		var k: float = clampf(float(fx.age) / float(fx.life), 0.0, 1.0)
		var fade: float = 1.0 - k
		var out: float = 1.0 - (1.0 - k) * (1.0 - k)   # fast out, slowing
		var rng := RandomNumberGenerator.new()
		rng.seed = int(fx.seed)
		match fx.kind:
			"thump":
				# Short grass: a pitch mark's worth of ring.
				draw_arc(c, lerpf(3.0, 13.0, out), 0, TAU, 28, Color(1.0, 1.0, 0.96, 0.75 * fade), 1.8)
			"rough":
				# Long grass: less ring, and blades thrown up that fall back.
				draw_arc(c, lerpf(3.0, 10.0, out), 0, TAU, 24, Color(1.0, 1.0, 0.96, 0.5 * fade), 1.5)
				var blade := CourseTheme.color(theme_id, "fairway").lightened(0.5)
				for i in 9:
					var dir := Vector2.from_angle(rng.randf_range(-PI * 0.95, -PI * 0.05))
					var at := c + dir * rng.randf_range(8.0, 19.0) * out + Vector2(0, 10.0 * k * k)
					draw_line(at, at + dir.rotated(rng.randf_range(-0.7, 0.7)) * 5.0, Color(blade, fade), 2.0)
			"sand":
				# A puff: a pale cloud spreading low over the crater, and
				# grains thrown up and out that fall back as they fade. Paler
				# than the bunker, or sand on sand wouldn't show.
				var sand := CourseTheme.color(theme_id, "sand")
				draw_arc(c, lerpf(3.0, 9.0, out), 0, TAU, 20, Color(sand.darkened(0.3), 0.6 * fade), 2.0)
				draw_circle(c, lerpf(5.0, 17.0, out), Color(sand.lightened(0.4), 0.62 * fade))
				for i in 15:
					var dir := Vector2.from_angle(rng.randf_range(-PI * 0.95, -PI * 0.05))
					var at := c + dir * rng.randf_range(11.0, 30.0) * out + Vector2(0, 18.0 * k * k)
					draw_circle(at, rng.randf_range(1.4, 2.8) * lerpf(1.0, 0.6, k), Color(sand.lightened(0.55), fade))
			"splash":
				# Rings going out one after another, a white flash where it
				# went in, and drops thrown up that fall back.
				var light := CourseTheme.color(theme_id, "water_light").lightened(0.45)
				for i in 3:
					var late: float = float(i) * 0.16
					if k <= late:
						continue
					var rk: float = (k - late) / (1.0 - late)
					draw_arc(c, lerpf(3.0, 15.0 + 6.0 * float(i), 1.0 - (1.0 - rk) * (1.0 - rk)), 0, TAU, 32,
						Color(light, 0.85 * (1.0 - rk)), 1.8)
				if k < 0.3:
					draw_circle(c, lerpf(5.5, 1.0, k / 0.3), Color(1, 1, 1, 0.9 * (1.0 - k / 0.3)))
				for i in 8:
					var dir := Vector2.from_angle(rng.randf_range(-PI, 0.0) if i < 6 else rng.randf_range(0.0, PI))
					var reach: float = rng.randf_range(8.0, 19.0)
					var at := c + dir * reach * out + Vector2(0, -11.0 * sin(PI * minf(k * 1.25, 1.0)))
					draw_circle(at, rng.randf_range(1.1, 1.9), Color(1, 1, 1, 0.95 * fade))
			"cup":
				# In: one clean ring off the hole.
				draw_arc(c, lerpf(4.0, 13.0, out), 0, TAU, 28, Color(1.0, 1.0, 0.96, 0.7 * fade), 1.6)


# Wind dial in the top-left corner: an arrow the way it blows, and the
# speed. Screen-up is toward the pin, so the arrow reads straight off the map.
func _draw_wind_dial() -> void:
	var speed := Wind.mph(hole.wind)
	var c := Vector2(MARGIN + 22, MARGIN + 22)
	draw_circle(c, 18.0, Color(BogeyTheme.CARD_BG, 0.88))
	draw_arc(c, 18.0, 0, TAU, 28, Color(BogeyTheme.INK, 0.35), 1.0)
	var font := get_theme_default_font()
	if speed < Wind.CALM_MPH:
		draw_string(font, c + Vector2(-18, 4), "Calm", HORIZONTAL_ALIGNMENT_CENTER, 36, 10, BogeyTheme.INK_SOFT)
		return
	var dir_px := Vector2(hole.wind.x, -hole.wind.y).normalized()
	var col: Color = BogeyTheme.INK if speed < 18 else BogeyTheme.FLAG
	var tail := c - dir_px * 11.0
	var tip := c + dir_px * 11.0
	draw_line(tail, tip, col, 2.0)
	var side := Vector2(-dir_px.y, dir_px.x)
	draw_colored_polygon(PackedVector2Array([tip + dir_px * 2.0, tip - dir_px * 6.0 + side * 4.5,
		tip - dir_px * 6.0 - side * 4.5]), col)
	var label := "%d mph" % speed
	# On its own slip of card: the dial sits over whatever country the
	# course is cut through, and ink on dark forest can't be read.
	var slip := Rect2(c + Vector2(-19, 22), Vector2(38, 15))
	draw_circle(slip.position + Vector2(0, 7.5), 7.5, Color(BogeyTheme.CARD_BG, 0.88))
	draw_circle(slip.position + Vector2(slip.size.x, 7.5), 7.5, Color(BogeyTheme.CARD_BG, 0.88))
	draw_rect(slip, Color(BogeyTheme.CARD_BG, 0.88))
	draw_string(font, c + Vector2(-26, 33), label, HORIZONTAL_ALIGNMENT_CENTER, 52, 11, col)


# Where today's pin is cut, in words, under the wind dial: the flag shows
# it, but at the size a whole hole is drawn a pin eight yards off the
# middle is easy to miss — and it's a club's difference.
func _draw_pin_note() -> void:
	var font := get_theme_default_font()
	var label := "Pin · %s" % hole.pin_name
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var slip := Rect2(Vector2(MARGIN + 3 + 7.5, MARGIN + 64), Vector2(w - 3.0, 15))
	draw_circle(slip.position + Vector2(0, 7.5), 7.5, Color(BogeyTheme.CARD_BG, 0.88))
	draw_circle(slip.position + Vector2(slip.size.x, 7.5), 7.5, Color(BogeyTheme.CARD_BG, 0.88))
	draw_rect(slip, Color(BogeyTheme.CARD_BG, 0.88))
	draw_string(font, slip.position + Vector2(-1.5, 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BogeyTheme.INK)


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
