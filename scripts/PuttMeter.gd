class_name PuttMeter
extends Control

# ---------------------------------------------------------
# The putting QTE (Section 7). A marker sweeps back and forth across a
# bar; the player stops it and the landing band decides the putt.
#
# Difficulty is driven entirely by distance to the pin: a tap-in gives a
# wide sweet spot and a slow sweep, a long lag putt gives a sliver of a
# sweet spot and a marker moving fast enough that you're committing to a
# rhythm rather than reacting to a position.
#
# Three concentric bands, centred on the bar:
#   SUNK   — dead centre, holes the putt
#   CLOSE  — flanking the centre, leaves a tap-in
#   MISS   — everything outside, a genuine miss
# ---------------------------------------------------------

signal stopped(result: String, accuracy: float)

const BAR_HEIGHT := 34.0
const MARKER_WIDTH := 3.0

# Difficulty curve endpoints, in yards from the pin. Inside NEAR_YARDS the
# putt is at its most forgiving; past FAR_YARDS it stops getting harder, so
# a monstrous 40-yard putt is brutal but never literally impossible.
const NEAR_YARDS := 2.0
const FAR_YARDS := 30.0

# Half-width of each band as a fraction of the bar, at the near/far ends of
# the curve. Tuned so a tap-in is nearly free and a long putt demands real
# timing — Section 10 flags these as playtest numbers.
const SUNK_HALF_NEAR := 0.20
const SUNK_HALF_FAR := 0.06
const CLOSE_HALF_NEAR := 0.42
const CLOSE_HALF_FAR := 0.13

# Sweeps per second across the full bar width, near and far. The far-end
# numbers are floored deliberately: at the hardest putt the marker is still
# inside the sunk band for ~95ms (about six frames at 60fps), so a long putt
# is a demanding read rather than a coin flip the player can't actually hit.
const SPEED_NEAR := 0.55
const SPEED_FAR := 1.25

var distance_yards: float = 10.0
var active: bool = false

var _pos: float = 0.0        # 0..1 across the bar
var _dir: float = 1.0
var _speed: float = 0.8
var _sunk_half: float = 0.1
var _close_half: float = 0.25
var _result: String = ""     # last result, kept so the bar can show where it landed
var _flash: float = 0.0      # post-stop highlight, fades out


func _ready() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT + 26)
	set_process(false)


# Configure for a putt of the given length and start the marker sweeping.
func begin(dist_yards: float) -> void:
	distance_yards = dist_yards
	var t: float = clampf(
		(dist_yards - NEAR_YARDS) / (FAR_YARDS - NEAR_YARDS), 0.0, 1.0)
	# Ease the curve so difficulty ramps hardest over the first stretch —
	# the jump from a 3-footer to a 12-footer should bite more than the
	# jump from 25 to 34 yards, where it's already a lag putt either way.
	var eased: float = sqrt(t)
	_sunk_half = lerpf(SUNK_HALF_NEAR, SUNK_HALF_FAR, eased)
	_close_half = lerpf(CLOSE_HALF_NEAR, CLOSE_HALF_FAR, eased)
	_speed = lerpf(SPEED_NEAR, SPEED_FAR, eased)

	_pos = randf() * 0.35          # vary the start so it can't be muscle-memoried
	_dir = 1.0 if randf() < 0.5 else -1.0
	_result = ""
	_flash = 0.0
	active = true
	set_process(true)
	queue_redraw()


func stop_putt() -> void:
	if not active:
		return
	active = false
	set_process(false)

	var offset: float = absf(_pos - 0.5)
	if offset <= _sunk_half:
		_result = "sunk"
	elif offset <= _close_half:
		_result = "close"
	else:
		_result = "miss"

	# Accuracy as 1.0 at dead centre falling to 0.0 at the bar's edge —
	# lets the caller scale a miss's leave-distance by how wild it was.
	var accuracy: float = clampf(1.0 - (offset / 0.5), 0.0, 1.0)
	_flash = 1.0
	queue_redraw()
	stopped.emit(_result, accuracy)


func _process(delta: float) -> void:
	_pos += _dir * _speed * delta
	if _pos >= 1.0:
		_pos = 1.0
		_dir = -1.0
	elif _pos <= 0.0:
		_pos = 0.0
		_dir = 1.0
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	if w <= 0.0:
		return
	var top: float = 20.0
	var bar := Rect2(0, top, w, BAR_HEIGHT)

	# Miss ground — the whole bar, then the friendlier bands painted over it.
	draw_rect(bar, Color(BoogieTheme.INK, 0.10))

	var close_w: float = _close_half * 2.0 * w
	draw_rect(Rect2(w * 0.5 - close_w * 0.5, top, close_w, BAR_HEIGHT),
		Color(BoogieTheme.SAND, 0.55))

	var sunk_w: float = maxf(_sunk_half * 2.0 * w, 2.0)
	draw_rect(Rect2(w * 0.5 - sunk_w * 0.5, top, sunk_w, BAR_HEIGHT),
		Color(BoogieTheme.FAIRWAY, 0.95))

	# Hairline frame, matching the sheet's ruled panels.
	draw_rect(bar, Color(BoogieTheme.INK, 0.35), false, 1.0)

	# Centre tick above the bar, so the target reads even when the sunk
	# band is only a couple of pixels wide on a long putt.
	draw_line(Vector2(w * 0.5, top - 6), Vector2(w * 0.5, top - 1),
		Color(BoogieTheme.INK, 0.5), 1.0)

	# The marker.
	var mx: float = _pos * w
	var marker_col: Color = BoogieTheme.INK
	if not active and _flash > 0.0:
		match _result:
			"sunk": marker_col = BoogieTheme.FAIRWAY_DEEP
			"close": marker_col = BoogieTheme.SAND_DEEP
			_: marker_col = BoogieTheme.FLAG
	draw_rect(Rect2(mx - MARKER_WIDTH * 0.5, top - 4, MARKER_WIDTH, BAR_HEIGHT + 8),
		marker_col)
