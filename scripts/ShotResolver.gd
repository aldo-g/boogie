class_name ShotResolver
extends RefCounted

# ---------------------------------------------------------
# Section 4 — Aim & Roll System
# Pure math module: given a club, a chosen swing tier, and the
# current lie, resolves a Power roll (distance) and an Accuracy
# roll (direction/degree-offset) against d20 Sweet Spot zones.
# No UI, no state — call resolve_shot() and read the result dict.
# ---------------------------------------------------------

enum Tier { FULL, MID, FINESSE, EXTREME_FINESSE }
enum Side { DRAW, FADE, STRAIGHT }

const DIE_SIDES := 20
const CENTER_LOW := 10   # Sweet Spot is centered on 10-11
const CENTER_HIGH := 11
const DOWN_RATIO := 0.6  # 60% of width extends downward (undershoot side)
const UP_RATIO := 0.4    # 40% extends upward (overshoot side)

# Base Sweet Spot width by club type (Section 4)
const BASE_WIDTH := {
	"wood": 4,
	"iron": 6,
	"wedge": 10,
}

# Swing tier modifier to width (Section 4 table)
const TIER_WIDTH_MOD := {
	Tier.FULL: 2,
	Tier.MID: 0,
	Tier.FINESSE: -2,
	Tier.EXTREME_FINESSE: -4,
}

# Terrain modifiers (Section 5)
# width_mod: flat change to Sweet Spot width
# distance_cap_ratio: cap on this tier's max yardage (1.0 = no cap)
# accuracy_tier_shift: how many bands worse the Accuracy roll reads (0/1/2)
const TERRAIN := {
	"tee":     {"width_mod": 0, "distance_cap_ratio": 1.0, "accuracy_tier_shift": 0},
	"fairway": {"width_mod": 0, "distance_cap_ratio": 1.0, "accuracy_tier_shift": 0},
	"rough":   {"width_mod": -1, "distance_cap_ratio": 0.8, "accuracy_tier_shift": 1},
	"bunker":  {"width_mod": -2, "distance_cap_ratio": 0.5, "accuracy_tier_shift": 1},
}

const DEGREE_BANDS := [
	{"name": "PERFECT", "max_deg": 2},
	{"name": "GOOD", "max_deg": 8},
	{"name": "OFF", "max_deg": 20},
	{"name": "MISS", "max_deg": 40},
]


static func tier_name(tier: int) -> String:
	match tier:
		Tier.FULL: return "Full swing"
		Tier.MID: return "Mid-range"
		Tier.FINESSE: return "Finesse"
		Tier.EXTREME_FINESSE: return "Extreme Finesse"
	return "?"


# Which tiers are actually offered depend on the club's yardage band vs.
# the target distance-to-pin — but per design decision, the player
# explicitly declares the tier themselves, so this just reports the
# yardage sub-range each tier implies for a given club (for UI display).
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
			# Below the club's own minimum — a Hail Mary short shot.
			return Vector2(max(0.0, lo * 0.5), lo)
	return Vector2(lo, hi)


# Compute the [low, high] d20 bounds of a Sweet Spot of a given width,
# split 60% down / 40% up around the 10-11 center, clamped to 1..20.
static func sweet_spot_bounds(width: int) -> Vector2i:
	var w: int = max(width, 1)
	var down: int = int(round(w * DOWN_RATIO))
	var up: int = w - down
	var low: int = CENTER_LOW - down
	var high: int = CENTER_HIGH + up
	low = clamp(low, 1, DIE_SIDES)
	high = clamp(high, 1, DIE_SIDES)
	if high < low:
		high = low
	return Vector2i(low, high)


static func base_width_for_club(club: Dictionary) -> int:
	return BASE_WIDTH.get(club.type, 6)


# Full Sweet Spot width for this club + tier + lie, before any
# overshoot/bad-card shrink is applied.
static func compute_width(club: Dictionary, tier: int, lie: String) -> int:
	var w: int = base_width_for_club(club) + TIER_WIDTH_MOD[tier]
	var terrain: Dictionary = TERRAIN.get(lie, TERRAIN.fairway)
	w += terrain.width_mod
	return max(w, 1)


# --- Power roll: d20 vs Sweet Spot -> clean / undershoot / overshoot ---
static func roll_power(club: Dictionary, tier: int, lie: String, extra_width_mod: int = 0) -> Dictionary:
	var width := compute_width(club, tier, lie) + extra_width_mod
	width = max(width, 1)
	var bounds := sweet_spot_bounds(width)
	var roll := randi_range(1, DIE_SIDES)

	var tier_range := tier_yardage_range(club, tier)
	var terrain: Dictionary = TERRAIN.get(lie, TERRAIN.fairway)
	var capped_max: float = tier_range.y * terrain.distance_cap_ratio

	var outcome: String
	var distance: float
	if roll < bounds.x:
		outcome = "undershoot"
		var t: float = float(roll) / float(max(bounds.x - 1, 1))
		distance = lerp(tier_range.x * 0.5, tier_range.x, clamp(t, 0.0, 1.0))
	elif roll > bounds.y:
		outcome = "overshoot"
		var over_amount: float = float(roll - bounds.y) / float(max(DIE_SIDES - bounds.y, 1))
		distance = lerp(capped_max, capped_max * 1.15, clamp(over_amount, 0.0, 1.0))
	else:
		outcome = "clean"
		distance = capped_max

	return {
		"roll": roll,
		"bounds": bounds,
		"width": width,
		"outcome": outcome,
		"distance": max(distance, 0.0),
	}


# --- Accuracy roll: d20 vs Sweet Spot -> degree offset + side ---
# A roll landing inside the Sweet Spot's bounds is PERFECT/GOOD (scaled by
# proximity to true center); a roll outside it is OFF/MISS (scaled by how
# far past the edge it landed, relative to how much of the die is "outside"
# for this width). A wide Sweet Spot (forgiving club) both lands inside more
# often AND softens how bad an outside roll reads — a narrow one (Driver)
# does the opposite, so the same die is far less forgiving on a Driver.
static func roll_accuracy(club: Dictionary, tier: int, lie: String, overshoot: bool, extra_width_mod: int = 0, extra_tier_shift: int = 0) -> Dictionary:
	var width := compute_width(club, tier, lie) + extra_width_mod
	if overshoot:
		width -= 2  # overshooting the Power roll shrinks the Accuracy Sweet Spot further
	width = max(width, 1)
	var bounds := sweet_spot_bounds(width)
	var roll := randi_range(1, DIE_SIDES)

	var terrain: Dictionary = TERRAIN.get(lie, TERRAIN.fairway)
	var tier_shift: int = terrain.accuracy_tier_shift + extra_tier_shift

	var side: int = Side.STRAIGHT
	var degree: float
	if roll >= bounds.x and roll <= bounds.y:
		# Inside the zone -> PERFECT/GOOD, scaled by proximity to true center.
		var dist_from_true_center: float = 0.0
		if roll < CENTER_LOW:
			side = Side.DRAW
			dist_from_true_center = float(CENTER_LOW - roll)
		elif roll > CENTER_HIGH:
			side = Side.FADE
			dist_from_true_center = float(roll - CENTER_HIGH)
		var max_inside_dist: float = float(max(CENTER_LOW - bounds.x, bounds.y - CENTER_HIGH, 1))
		degree = (dist_from_true_center / max_inside_dist) * DEGREE_BANDS[1].max_deg
	else:
		# Outside the zone -> OFF/MISS, scaled by distance past the edge
		# relative to however much of the die lies outside on that side.
		var dist_past_edge: float
		var side_span: float
		if roll < bounds.x:
			side = Side.DRAW
			dist_past_edge = float(bounds.x - roll)
			side_span = float(max(bounds.x - 1, 1))
		else:
			side = Side.FADE
			dist_past_edge = float(roll - bounds.y)
			side_span = float(max(DIE_SIDES - bounds.y, 1))
		# First 60% of the outside-span reads as OFF, the deeper 40% as MISS —
		# mirrors OFF being the common "just missed" outcome and MISS being
		# the rarer, truly bad shank.
		var off_span: float = side_span * 0.6
		var off_max: float = DEGREE_BANDS[1].max_deg
		var miss_max: float = DEGREE_BANDS[3].max_deg
		if dist_past_edge <= off_span:
			degree = off_max + (dist_past_edge / max(off_span, 0.01)) * (DEGREE_BANDS[2].max_deg - off_max)
		else:
			var miss_frac: float = (dist_past_edge - off_span) / max(side_span - off_span, 0.01)
			degree = DEGREE_BANDS[2].max_deg + miss_frac * (miss_max - DEGREE_BANDS[2].max_deg)

	var degree_i: int = int(round(clamp(degree, 0.0, 40.0)))
	var band_index: int = band_index_for_degree(degree_i)
	band_index = min(band_index + tier_shift, DEGREE_BANDS.size() - 1)
	var band: Dictionary = DEGREE_BANDS[band_index]
	degree_i = min(degree_i, band.max_deg)

	return {
		"roll": roll,
		"bounds": bounds,
		"width": width,
		"side": side,
		"band": band.name,
		"degree": degree_i,
	}


static func band_index_for_degree(degree: int) -> int:
	for i in range(DEGREE_BANDS.size()):
		if degree <= DEGREE_BANDS[i].max_deg:
			return i
	return DEGREE_BANDS.size() - 1


# --- Full shot resolution combining Power + Accuracy ---
static func resolve_shot(club: Dictionary, tier: int, lie: String, power_width_mod: int = 0, accuracy_width_mod: int = 0, accuracy_tier_shift: int = 0) -> Dictionary:
	var power := roll_power(club, tier, lie, power_width_mod)
	var overshoot: bool = power.outcome == "overshoot"
	var accuracy := roll_accuracy(club, tier, lie, overshoot, accuracy_width_mod, accuracy_tier_shift)
	return {
		"power": power,
		"accuracy": accuracy,
	}


static func side_label(side: int) -> String:
	match side:
		Side.DRAW: return "Draw (left)"
		Side.FADE: return "Fade (right)"
	return "Straight"
