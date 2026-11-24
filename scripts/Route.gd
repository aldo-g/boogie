extends RefCounted

# ---------------------------------------------------------
# THE ROUTE (Section 3F — the way round)
#
# Between a green and the next tee there is a fork: the pro shop, or one
# other stop. Which other stop follows each hole is fixed for the round
# and known from the first tee, so a round can be planned: "the fitting
# bay is after the 7th; mend the driver there".
#
#   Pro shop    — the rack: draw three clubs, keep one (DraftRules.gd)
#   Fitting bay — three boosts on the bench; one, for a club you hold
#   Range       — work the worst bad cards out of the Form deck
#   The hut     — something happens there: take it or walk on (EVENTS)
#
# Pure functions of the round's seed and the hole number, like the wind
# and the pins — so every machine in an online round sees the same route
# and nothing extra has to be sent. Loaded by preload:
#   const Route := preload("res://scripts/Route.gd")
# ---------------------------------------------------------

const SHOP := "shop"
const FIT := "fit"
const RANGE := "range"
const HUT := "hut"

const STOPS := {
	SHOP: {"name": "Pro shop", "does": "Three clubs on the rack: keep one"},
	FIT: {"name": "Fitting bay", "does": "Three boosts on the bench: one, for a club you hold"},
	RANGE: {"name": "Range", "does": "Work the two worst bad cards out of your Form deck"},
	HUT: {"name": "The hut", "does": "Something happens there. Take it or walk on"},
}

# How often the stop beside the pro shop is each of the others.
const FIT_SHARE := 0.4
const RANGE_SHARE := 0.3

# How many boosts a fitting bay has on the bench.
const BENCH := 3

# What can happen at the hut. `keeps` marks the ones that pay or cost
# strokes in hand, which only a round played for keeps has (Main).
const EVENTS := {
	"gorse": {"title": "A club in the gorse", "take": "Take it",
		"text": "Somebody's lost property: a limited edition, already worn in, and something is wrong with it."},
	"tip": {"title": "A stranger's tip", "take": "Listen",
		"text": "He has watched you hit three. Your most-used club has a shot grooved on the spot. The swing thought that comes with it is a bad card in that club's family."},
	"cart": {"title": "The drinks cart", "take": "Have one", "keeps": true,
		"text": "Two strokes in hand. A Top joins your wood form."},
	"hustler": {"title": "The hustler", "take": "Play him", "keeps": true,
		"text": "One putt on the practice green, from five yards. Hole it and it is three strokes in hand. Miss and it is two gone."},
}
const CART_STROKES := 2
const HUSTLER_WIN := 3
const HUSTLER_LOSS := 2
const HUSTLER_YARDS := 5.0


static func _rng(round_seed: int, hole_n: int, what: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([round_seed, hole_n, what])
	return rng


# The two stops after hole `hole_n`: the pro shop, and one other.
static func stops(round_seed: int, hole_n: int) -> Array:
	var r := _rng(round_seed, hole_n, "route").randf()
	return [SHOP, FIT if r < FIT_SHARE else (RANGE if r < FIT_SHARE + RANGE_SHARE else HUT)]


# What happens at the hut after hole `hole_n` (an EVENTS id). `keeps` is
# whether the round is played for strokes in hand.
static func event(round_seed: int, hole_n: int, keeps: bool) -> String:
	var ids: Array = EVENTS.keys().filter(func(id): return keeps or not EVENTS[id].has("keeps"))
	return ids[_rng(round_seed, hole_n, "event").randi_range(0, ids.size() - 1)]


# The stops ahead, in words: "after 5 Range · after 6 The hut". `count`
# holes from `from_hole`, stopping before the last hole (nothing follows it).
static func ahead_text(round_seed: int, from_hole: int, last_hole: int, count: int = 3) -> String:
	var bits := PackedStringArray()
	for n in range(from_hole, mini(from_hole + count, last_hole)):
		bits.append("after %d %s" % [n, STOPS[stops(round_seed, n)[1]].name])
	return " · ".join(bits)
