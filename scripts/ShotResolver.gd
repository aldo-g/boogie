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

	# Slazinger deepens a bad card's distance loss; a good card is left
	# alone, so the drawback only ever bites on the cards you'd rather not
	# have played.
	var dist_mult: float = card.distance_mult
	if not card.good and severity_mult > 1.0 and dist_mult < 1.0:
		dist_mult = max(0.0, 1.0 - (1.0 - dist_mult) * severity_mult)

	var distance: float = base_distance * dist_mult
	distance += card.extra_roll
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
	}


static func lie_downgrade(lie: String) -> String:
	match lie:
		"fairway": return "rough"
		"rough": return "bunker"
	return lie
