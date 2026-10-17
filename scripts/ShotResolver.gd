class_name ShotResolver
extends RefCounted

# ---------------------------------------------------------
# Section 4 — Form Card shot resolution.
# Pure math module: given a club, the player's own aimed-for distance, the
# current lie, and a fully-known FormCard, resolves the shot's actual
# distance and degree/side of deviation. No randomness here at all —
# everything the player didn't already see on the card is a deterministic
# function of club + aim + lie + card. Swing tier (see Tier below) governs
# how many Form cards get drawn to choose from — a separate concern from
# distance, handled in FormDeck — not the distance math itself.
# ---------------------------------------------------------

enum Tier { FULL, MID, FINESSE, EXTREME_FINESSE }
enum Side { DRAW, FADE, STRAIGHT }

# Club buffering (Section 4 "Club buffering"): how much of a Form card's
# degree deviation actually reaches the ball. A forgiving Wedge halves it;
# a Driver applies it at full severity.
const BUFFER_BY_TYPE := {
	"wood": 1.0,
	"iron": 0.75,
	"wedge": 0.5,
	"putter": 0.0,
}

# Terrain distance caps (Section 5), as a ratio of the tier's max yardage.
const TERRAIN_DISTANCE_CAP := {
	"tee": 1.0,
	"fairway": 1.0,
	"rough": 0.8,
	"bunker": 0.5,
}


# --- Holing out from off the green (the "cup radius") ------------------
# Landing inside this radius of the pin does NOT hole the ball. It earns
# you a d20, and only a natural 20 drops — everything else finishes stone
# dead next to the pin for a tap-in. Perfect aim plus a perfect card is
# what buys the roll; the roll is what decides.
#
# Deliberately split this way: the aim and the card are fully
# deterministic and fully visible (Section 4 — no hidden numbers), so if
# landing in the cup were itself the hole-out, a player who could read the
# cards could hole out on demand. The d20 is the one place the game says
# no, and it says it the same way to everyone.
#
# The radius scales with how far the ball actually travelled. A short,
# controlled shot earns a generous window; a monstrous one earns a much
# tighter one — so distance still decides how often you get to roll at
# all. The floor keeps the far end honest: small, but never zero, so no
# distance is ever excluded outright.
const CUP_RADIUS_NEAR := 3.0    # yards of cup at CUP_NEAR_YARDS or less
const CUP_RADIUS_FAR := 1.1     # yards of cup at CUP_FAR_YARDS or beyond
const CUP_NEAR_YARDS := 25.0
const CUP_FAR_YARDS := 260.0

# The hole-out roll. A d20 that only drops on a natural 20 — a flat 5%
# once the shot has already earned the roll.
const HOLE_OUT_DIE := 20
const HOLE_OUT_TARGET := 20


# How wide the cup plays for a shot of `shot_distance` yards. Used both to
# judge a real shot (did it earn the roll?) and to light the aim line
# yellow while the player is still choosing — one function, so the promise
# the aim line makes is the one the shot keeps.
static func cup_radius_for_distance(shot_distance: float) -> float:
	var t: float = clampf(
		(shot_distance - CUP_NEAR_YARDS) / (CUP_FAR_YARDS - CUP_NEAR_YARDS),
		0.0, 1.0)
	# Eased so the cup tightens fastest over the first stretch — the step
	# from a 30-yard pitch to a 90-yard wedge should matter more than the
	# step from 220 to 280, where it is a long shot either way.
	return lerpf(CUP_RADIUS_NEAR, CUP_RADIUS_FAR, sqrt(t))


# Whether a ball landing at `landing_pos`, having flown `shot_distance`
# yards, is close enough to the cup to earn the hole-out roll. Naming is
# deliberate: this is the chance at the hole, not the hole itself — see
# roll_for_hole_out() for the part that actually decides.
static func earns_hole_out_roll(landing_pos: Vector2, pin_pos: Vector2,
		shot_distance: float) -> bool:
	return landing_pos.distance_to(pin_pos) <= cup_radius_for_distance(shot_distance)


# Rolls the d20. Returns the face value so the caller can show the player
# the actual number — a hole-out that just says "yes/no" hides the near
# miss, and the 19 is most of the drama.
static func roll_for_hole_out() -> int:
	return randi_range(1, HOLE_OUT_DIE)


# --- Aim clamping ------------------------------------------------------
# Where an aim actually lands once the club's reach and the hole's own
# playable extent are applied.
#
# This used to live in CourseMapView, which made the *view* the authority
# on a gameplay value: the clamped point was computed during drawing and
# read back out. That is fine with one screen and wrong with several —
# two machines would clamp against their own view state and disagree about
# where the ball was aimed. It lives here now, with the rest of the shot
# math, so every machine computes the same answer from the same data.
#
# Note the deliberate asymmetry: the distance is capped at the club's
# max reach but NOT floored at its minimum. Aiming inside a club's band
# is legal — that is exactly what Section 4's Extreme Finesse tier is, a
# punishing draw rather than a blocked shot.
static func clamp_aim(target: Vector2, ball_pos: Vector2, max_reach: float,
		bounds: Rect2) -> Vector2:
	var offset := target - ball_pos
	var dist := offset.length()
	if dist < 0.0001:
		return ball_pos
	var clamped_dist: float = min(dist, max_reach)
	var point: Vector2 = ball_pos + offset.normalized() * clamped_dist
	return clamp_to_bounds(point, bounds)


# Keeps a yard-space point inside the hole's playable rectangle. The drawn
# extent IS the playable extent (see HoleData.bounds), so the picture and
# the rule are the same number.
static func clamp_to_bounds(p: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(
		clamp(p.x, bounds.position.x, bounds.position.x + bounds.size.x),
		clamp(p.y, bounds.position.y, bounds.position.y + bounds.size.y)
	)


static func tier_name(tier: int) -> String:
	match tier:
		Tier.FULL: return "Full swing"
		Tier.MID: return "Mid-range"
		Tier.FINESSE: return "Finesse"
		Tier.EXTREME_FINESSE: return "Extreme Finesse"
	return "?"


# Reports the yardage sub-range each tier implies for a given club — used
# for UI display (shot outlook text, the on-map tier bands), not for
# resolving an actual shot's distance (see resolve_shot(), which uses the
# player's real aimed-for distance instead).
static func tier_yardage_range(club: Dictionary, tier: int) -> Vector2:
	var lo: float = club.min_yard
	var hi: float = club.max_yard
	var span := hi - lo
	match tier:
		Tier.FULL:
			return Vector2(lo + span * (2.0 / 3.0), hi)
		Tier.MID:
			return Vector2(lo + span * (1.0 / 3.0), lo + span * (2.0 / 3.0))
		Tier.FINESSE:
			return Vector2(lo, lo + span * (1.0 / 3.0))
		Tier.EXTREME_FINESSE:
			return Vector2(max(0.0, lo * 0.5), lo)
	return Vector2(lo, hi)


static func buffer_for_club(club: Dictionary) -> float:
	return BUFFER_BY_TYPE.get(club.get("type", "iron"), 0.75)


# --- Full shot resolution: club + lie + the player's own aimed distance +
# the one chosen FormCard --- Returns a dict shaped like the old dice
# result so CourseMapView's play_aim_animation() (distance, degree, side)
# needs no changes: { "distance": float, "degree": int, "side": Side,
# "downgrades_lie": bool }
#
# Distance is built from what the player actually aimed for, not an
# abstract tier ceiling — terrain then applies its own ratio on top (e.g.
# rough saps 20% off whatever distance you were going for), and the Form
# card's own multiplier/flat bonuses apply last.
# Brand set bonuses (Section 3A) reach the math through the last three
# arguments, all defaulted so callers that don't care are unaffected:
#   ignore_terrain — Callowell 4 / MacGregorian 4: terrain takes no cut
#   deviation_mult — Callowell 2/7: a bad card's deviation is blunted
#   severity_mult  — Slazinger 2/4: bad cards hit HARDER, the price paid
#                    for those brands' extra Form draws
# severity applies to deviation and to distance loss alike, so Slazinger's
# extra cards are never free.
static func resolve_shot(club: Dictionary, aimed_distance: float, lie: String, card: FormCard,
		ignore_terrain: bool = false, deviation_mult: float = 1.0,
		severity_mult: float = 1.0) -> Dictionary:
	var cap_ratio: float = TERRAIN_DISTANCE_CAP.get(lie, 1.0)
	if ignore_terrain:
		cap_ratio = 1.0
	var base_distance: float = aimed_distance * cap_ratio
	if card.ignores_hazard_penalty:
		# Flop Shot: ignores the terrain's distance penalty entirely.
		base_distance = aimed_distance

	# Slazinger deepens a bad card's distance loss (and Callowell's
	# softening, below 1, lessens it); a good card is left alone, so the
	# drawback only ever bites on the cards you'd rather not have played.
	var dist_mult: float = card.distance_mult
	if not card.good and severity_mult != 1.0 and dist_mult < 1.0:
		dist_mult = max(0.0, 1.0 - (1.0 - dist_mult) * severity_mult)

	var distance: float = base_distance * dist_mult
	distance = max(distance, 0.0)

	var buffer := buffer_for_club(club)
	var effective_degrees: float = card.degrees * buffer * deviation_mult
	if not card.good:
		effective_degrees *= severity_mult

	var side: int = Side.STRAIGHT
	if card.side < 0:
		side = Side.DRAW
	elif card.side > 0:
		side = Side.FADE

	return {
		"distance": distance,
		"degree": int(round(effective_degrees)),
		"side": side,
		"downgrades_lie": card.downgrades_lie,
		# Roll is resolved after landing, against the ground (see
		# shot_outcome()), so the card only hands over its modifiers.
		"roll_mult": card.roll_mult,
		"extra_roll": card.extra_roll,
		"flight": card.flight,
		"run_share": card.run_share,
	}


# Where a resolved shot actually comes down, given where it started and
# the direction it was aimed. Extracted so the landing preview shown while
# hovering a Form card and the real shot share one implementation — a
# preview that can drift from the shot it predicts is worse than none.
#
# Vector2.rotated() turns clockwise for +angle in Godot's Y-down
# convention, so Draw (curves left) needs a positive angle to end up on -x.
static func landing_position(from_pos: Vector2, aim_dir: Vector2,
		result: Dictionary) -> Vector2:
	return from_pos + shot_direction(aim_dir, result) * float(result.distance)


# --- Elevation & roll -------------------------------------------------
# A shot is a carry and then a run-out. Both are pure functions of the
# hole's ground (HoleData.height_at) and the resolved shot, so the Form-card
# preview shows exactly where the ball will stop — roll included — and
# every machine in an online round computes the same rest spot.
#
# Club yardage is CARRY. Roll is extra, on top.

# --- Wind --------------------------------------------------------------
# A known, per-hole wind (HoleData.wind, mph, the way it blows). It acts on
# the flight only — the run-out is on the ground and ignores it — and how
# much it acts depends on how high the ball goes: club loft times the Form
# card's flight (Stinger 0.4 punches under it, Flop Shot 1.6 balloons).
#
# Into the wind costs more than downwind gives, as it does for real.
const WIND_TAIL_PER_MPH := 0.0035   # carry gained per mph of tailwind
const WIND_HEAD_PER_MPH := 0.006    # carry lost per mph of headwind
const WIND_DRIFT_PER_MPH := 0.004   # yards of drift per yard flown per mph across
const CLUB_LOFT := {"wood": 0.9, "iron": 1.0, "wedge": 1.2, "putter": 0.0}


# Returns { "distance": flat carry after wind, "drift": Vector2 sideways push }.
static func apply_wind(wind: Vector2, dir: Vector2, flat: float, club: Dictionary, result: Dictionary) -> Dictionary:
	var height: float = CLUB_LOFT.get(club.get("type", "iron"), 1.0) * float(result.get("flight", 1.0))
	if wind == Vector2.ZERO or flat <= 0.0 or height <= 0.0:
		return {"distance": flat, "drift": Vector2.ZERO}
	var along: float = wind.dot(dir)
	var across: Vector2 = wind - dir * along
	var per: float = WIND_TAIL_PER_MPH if along > 0.0 else WIND_HEAD_PER_MPH
	var distance: float = flat * clampf(1.0 + along * per * height, 0.5, 1.4)
	return {"distance": distance, "drift": across * WIND_DRIFT_PER_MPH * distance * height}


# Carry lost per yard the landing sits above the launch point (and gained
# per yard below). The golfer's rule of thumb: one yard per three feet.
const CARRY_PER_YARD_RISE := 1.0

# Flat-fairway run-out as a share of carry, by club: a driver chases, a
# wedge checks up.
const ROLL_SHARE := {
	"wood": 0.12,
	"iron": 0.05,
	"wedge": 0.02,
	"putter": 0.0,
}

# Rolling resistance, relative to fairway. Greens are quick, so their tilt
# bends a rolling ball; rough grabs it; sand stops it outright.
const ROLL_FRICTION := {
	"tee": 1.0,
	"fairway": 1.0,
	"green": 0.4,
	"rough": 3.0,
}

# A ball that pitches straight onto the green arrives with backspin and
# checks: it keeps only this share of its run-out. One that lands short and
# runs on (a bump-and-run) keeps all of it — that's the point of the shot.
const GREEN_CHECK := 0.35

# How hard slope pulls relative to fairway friction: on a 1/SLOPE_PULL
# grade (12.5%) a ball on fairway never stops rolling downhill.
const SLOPE_PULL := 8.0

# A rolling ball that passes this close to the pin has found the cup and
# earns the hole-out d20, same as a carry that lands on it.
const ROLL_CUP_RADIUS := 1.2

const ROLL_STEP := 0.5          # yards per integration step
const ROLL_MAX_STEPS := 2000    # 1000 yards of rolling — a safety net, never reached in play
const ROLL_STOP_SPEED := 0.15


# Everything that happens between strike and rest. Returns:
#   carry        — yards flown, after wind and elevation
#   carry_pos    — where it first touches down
#   rest         — where it finally stops
#   roll_path    — carry_pos .. rest, for drawing (just [carry_pos] if no roll)
#   cup          — finished on the cup: earns the hole-out roll
# `with_wind` = false reads the shot as if it were calm — for the aim-time
# guides, which must leave reading the wind to the player.
static func shot_outcome(hole: HoleData, from_pos: Vector2, aim_dir: Vector2,
		result: Dictionary, club: Dictionary, with_wind: bool = true) -> Dictionary:
	var wind: Vector2 = hole.wind if with_wind else Vector2.ZERO
	var dir := shot_direction(aim_dir, result)
	var run_share: float = clampf(float(result.get("run_share", 0.0)), 0.0, 0.9)
	if run_share > 0.0:
		return _run_outcome(hole, from_pos, dir, result, club, run_share, wind)
	var blown := apply_wind(wind, dir, float(result.distance), club, result)
	var flat: float = blown.distance
	var carry_pos: Vector2 = from_pos + dir * elevated_carry(hole, from_pos, dir, flat) + blown.drift
	var carry: float = from_pos.distance_to(carry_pos)
	# The ball runs on the way it was travelling when it came down.
	if carry > 0.01:
		dir = (carry_pos - from_pos) / carry

	var out := {
		"carry": carry, "carry_pos": carry_pos, "rest": carry_pos,
		"roll_path": [carry_pos], "cup": false,
	}
	# The cup judged on the carry first: the existing generous window for a
	# ball that pitches on the hole.
	if earns_hole_out_roll(carry_pos, hole.pin_pos, carry):
		out.cup = true
		return out
	var land_terrain := hole.terrain_at(carry_pos)
	if land_terrain in ["out", "water", "bunker"]:
		return out

	var budget: float = carry * ROLL_SHARE.get(club.get("type", "iron"), 0.05) \
		* float(result.get("roll_mult", 1.0)) + float(result.get("extra_roll", 0.0))
	if land_terrain == "green":
		budget *= GREEN_CHECK
	var roll := simulate_roll(hole, carry_pos, dir, budget)
	out.rest = roll.rest
	out.roll_path = roll.path
	out.cup = roll.cup
	return out


# A bump-and-run: pitched low to land part of the way, then run along the
# ground to the target. The player judges the run — it's struck with the
# pace the ground between landing and target asks for (slope included) —
# but only up to RUN_JUDGE_MAX of the planned run: a long stretch of rough
# in the way still leaves it short, and sand or water in its path still
# stops it. No green check: a low runner arrives without backspin.
const RUN_JUDGE_MAX := 1.6
const RUN_SEARCH_STEPS := 14

static func _run_outcome(hole: HoleData, from_pos: Vector2, dir: Vector2,
		result: Dictionary, club: Dictionary, run_share: float, wind: Vector2) -> Dictionary:
	var total: float = float(result.distance)
	var blown := apply_wind(wind, dir, total * (1.0 - run_share), club, result)
	var carry_pos: Vector2 = from_pos + dir * elevated_carry(hole, from_pos, dir, blown.distance) + blown.drift
	var carry: float = from_pos.distance_to(carry_pos)
	var out := {"carry": carry, "carry_pos": carry_pos, "rest": carry_pos,
		"roll_path": [carry_pos], "cup": false}
	if earns_hole_out_roll(carry_pos, hole.pin_pos, carry):
		out.cup = true
		return out
	if hole.terrain_at(carry_pos) in ["out", "water", "bunker"]:
		return out

	# Run it out toward the target: the aimed spot, shifted by the same
	# drift the flight took.
	var target: Vector2 = from_pos + dir * total + blown.drift
	var to_target: Vector2 = target - carry_pos
	var want: float = to_target.length()
	if want < 0.5:
		return out
	var run_dir: Vector2 = to_target / want
	# Search for the pace that stops it on the target. Progress along the
	# line grows with pace, so bisection settles it; a cup found on the way
	# is taken at once.
	var lo := 0.0
	var hi: float = total * run_share * RUN_JUDGE_MAX
	var best := simulate_roll(hole, carry_pos, run_dir, hi)
	if not best.cup and (best.rest - carry_pos).dot(run_dir) > want:
		for i in RUN_SEARCH_STEPS:
			var mid := (lo + hi) * 0.5
			var r := simulate_roll(hole, carry_pos, run_dir, mid)
			if r.cup:
				best = r
				break
			if (r.rest - carry_pos).dot(run_dir) < want:
				lo = mid
			else:
				hi = mid
				best = r
	out.rest = best.rest
	out.roll_path = best.path
	out.cup = best.cup
	return out


# Flat carry adjusted for the height of the landing spot relative to the
# launch. Landing height depends on where it lands, which depends on the
# carry — a few fixed-point passes settle it.
static func elevated_carry(hole: HoleData, from_pos: Vector2, dir: Vector2, flat: float) -> float:
	if flat <= 0.0:
		return 0.0
	var h0: float = hole.height_at(from_pos)
	var carry := flat
	for i in 4:
		var rise: float = hole.height_at(from_pos + dir * carry) - h0
		carry = clampf(flat - rise * CARRY_PER_YARD_RISE, flat * 0.5, flat * 1.5)
	return carry


# Rolls a ball out from `start`, heading `dir`, with enough pace to run
# `budget` yards on flat fairway. Friction comes from the turf under the
# ball, pull from the slope. Stops on: losing pace on ground that can hold
# it, entering sand/water/out of bounds, or finding the cup.
#
# Units are chosen so fairway friction decelerates at 1: then pace² / 2 is
# exactly the flat-fairway yards left in the ball.
static func simulate_roll(hole: HoleData, start: Vector2, dir: Vector2, budget: float) -> Dictionary:
	var pos := start
	var path: Array = [start]
	if budget <= 0.05:
		return {"rest": pos, "path": path, "cup": false}
	var vel: Vector2 = dir.normalized() * sqrt(2.0 * budget)
	var since_point := 0.0

	for i in ROLL_MAX_STEPS:
		var terrain := hole.terrain_at(pos)
		if terrain in ["bunker", "water", "out"]:
			break
		if pos.distance_to(hole.pin_pos) <= ROLL_CUP_RADIUS:
			path.append(pos)
			return {"rest": pos, "path": path, "cup": true}

		var friction: float = ROLL_FRICTION.get(terrain, 1.0)
		var pull: Vector2 = -hole.gradient_at(pos) * SLOPE_PULL
		var speed: float = vel.length()

		if speed < ROLL_STOP_SPEED:
			# Nearly stopped: does the ground hold it, or does it trickle on?
			if pull.length() <= friction:
				break
			vel = pull.normalized() * ROLL_STOP_SPEED

		speed = vel.length()
		var dt: float = ROLL_STEP / speed
		var accel: Vector2 = pull - vel / speed * friction
		var next_vel: Vector2 = vel + accel * dt
		# Friction can slow a ball to rest but never push it backwards.
		if next_vel.dot(vel) <= 0.0 and pull.length() <= friction:
			break
		vel = next_vel
		var step: Vector2 = vel * dt
		pos += step
		since_point += step.length()
		if since_point >= 2.0:
			path.append(pos)
			since_point = 0.0

	if path[path.size() - 1] != pos:
		path.append(pos)
	return {"rest": pos, "path": path, "cup": false}


# --- Reading a putt -----------------------------------------------------
# The green's tilt, resolved against the putt line and averaged along it.
#   along  — grade toward the hole: + uphill (slower, more forgiving),
#            - downhill (quick, the bands tighten)
#   fall   — grade falling to the RIGHT of the line, looking at the hole;
#            the ball breaks toward the low side, so you aim at the high side
#   shift  — where the meter's sweet spot sits, as a fraction of the bar
#            from centre (- left, + right): the visible "aim here" of a read
#   band_mult — scale on the meter's bands from pace
# Pure function of the hole's ground: every machine reads the same putt.
const PUTT_SHIFT_PER_PCT_YD := 1.0 / 120.0  # bar fraction per (% grade x yard)
const PUTT_SHIFT_MAX := 0.28
const PUTT_PACE_PER_PCT := 0.06
const PUTT_FLAT := 0.008  # below this grade a putt reads as straight / level

static func putt_read(hole: HoleData, ball: Vector2) -> Dictionary:
	var to_hole: Vector2 = hole.pin_pos - ball
	var dist: float = to_hole.length()
	if dist < 0.01:
		return {"along": 0.0, "fall": 0.0, "shift": 0.0, "band_mult": 1.0}
	var d: Vector2 = to_hole / dist
	var right := Vector2(d.y, -d.x)
	var g := Vector2.ZERO
	for i in 5:
		g += hole.gradient_at(ball.lerp(hole.pin_pos, (float(i) + 0.5) / 5.0))
	g /= 5.0
	var along: float = g.dot(d)
	var fall: float = -g.dot(right)
	return {
		"along": along,
		"fall": fall,
		# Falls right -> aim left of centre.
		"shift": clampf(-fall * 100.0 * dist * PUTT_SHIFT_PER_PCT_YD, -PUTT_SHIFT_MAX, PUTT_SHIFT_MAX),
		"band_mult": clampf(1.0 + along * 100.0 * PUTT_PACE_PER_PCT, 0.7, 1.15),
	}


static func putt_read_text(read: Dictionary) -> String:
	var bits: Array = []
	var fall: float = read.fall
	if absf(fall) < PUTT_FLAT:
		bits.append("Straight putt")
	else:
		var how := "Breaks" if absf(fall) < 0.02 else "Big break"
		bits.append("%s %s" % [how, "left to right" if fall > 0.0 else "right to left"])
	var along: float = read.along
	if along < -PUTT_FLAT:
		bits.append("downhill — quick, tighter window")
	elif along > PUTT_FLAT:
		bits.append("uphill — slower, a touch more forgiving")
	return " · ".join(bits)


# The post-curve direction of a resolved shot.
static func shot_direction(aim_dir: Vector2, result: Dictionary) -> Vector2:
	var sign: float = 0.0
	if result.side == Side.DRAW:
		sign = 1.0
	elif result.side == Side.FADE:
		sign = -1.0
	return aim_dir.rotated(deg_to_rad(float(result.degree)) * sign)


static func lie_downgrade(lie: String) -> String:
	match lie:
		"fairway": return "rough"
		"rough": return "bunker"
	return lie
