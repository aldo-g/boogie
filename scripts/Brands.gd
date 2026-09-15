class_name Brands
extends RefCounted

# ---------------------------------------------------------
# Section 3A — Brands, the synergy layer.
#
# A club carries two classifications that do different jobs:
#   type  ("wood"/"iron"/"wedge"/"putter") — mechanical. Yardage band,
#         buffering, which Created card it makes. Lives on the club.
#   brand ("titanist"/"callowell"/...)     — social. Does nothing alone;
#         pays out once enough of them share your Bag.
#
# THE DESIGN RULE, and the reason this module holds no yardage numbers:
# a set bonus is a RULES effect, never a yardage effect. "Draw an extra
# Form card" or "ignore terrain penalties" mean the same thing on a
# 7,200-yard parkland and a 6,100-yard links. "+15 yards on Woods" does
# not, and would need rebalancing with every course that ships. Yardage
# stays on individual club cards (Main.build_club_pool); sets bend rules.
#
# Tiers are 2 / 4 / 7. Seven is half the 14-card Bag, so a 7-set is an
# identity rather than a bonus: it leaves only 7 slots to cover a whole
# course, which is not quite enough. That squeeze is the point.
# ---------------------------------------------------------

const TIERS := [2, 4, 7]

# Bogey-Mart is the starting set (Section 3A) and deliberately the worst
# gear in the game. It is NEVER in the draft pool — you start with it and
# you only ever lose it — so it has no entry here and no set bonus.
const STARTER := "bogeymart"

const NONE := ""  # brandless standard clubs: always in the pool, no set

const DISPLAY := {
	"titanist": "Titanist",
	"callowell": "Callowell",
	"pingwell": "Ping-Well",
	"macgregorian": "MacGregorian",
	"slazinger": "Slazinger",
	"nimbus": "Nimbus",
	"bogeymart": "Bogey-Mart",
}

# The axis each brand attacks. The per-run pool (Section 3B) uses these to
# guarantee a run always offers at least two genuinely different
# directions to build in, rather than four brands doing the same thing.
const AXIS := {
	"titanist": "draw",       # how many cards you see
	"slazinger": "draw",      # ...but charges severity for them
	"callowell": "severity",  # how badly a bad card hurts
	"pingwell": "tier",       # which tier you draw at
	"nimbus": "tier",         # ...by flexibility rather than fit
	"macgregorian": "lie",    # what your lie does to you
}

const DRAFTABLE := ["titanist", "callowell", "pingwell", "macgregorian", "slazinger", "nimbus"]

# Player-facing bonus text, indexed by brand then tier. Kept beside the
# mechanical flags below so the two can't drift apart silently.
const BONUS_TEXT := {
	"titanist": {
		2: "Your Form draw discards its worst card before you pick",
		4: "Draw +1 Form card at every tier",
		7: "Once per hole, re-draw your entire Form hand",
	},
	"callowell": {
		2: "Bad Form cards played from rough lose half their deviation",
		4: "Ignore all terrain penalties",
		7: "Bad cards can't downgrade your lie or taint a putt; Chunk and Top hit at half severity",
	},
	"pingwell": {
		2: "The Mid tier is widened — the middle third counts as the middle half",
		4: "Every club plays one tier better than its distance implies",
		7: "Extreme Finesse is abolished — you always draw normally",
	},
	"macgregorian": {
		2: "Landing in rough or a bunker no longer adds a bad card to your Form deck",
		4: "Play out of rough/bunker as though on the fairway",
		7: "Once per hole, improve your lie one step before playing",
	},
	"slazinger": {
		2: "Draw +1 Form card, but bad cards you play hit at +25% severity",
		4: "Draw +2 Form cards, same penalty",
		7: "Created cards no longer exhaust — they return at the end of each hole",
	},
	"nimbus": {
		2: "Any club may be played one tier better, once per hole",
		4: "Your clubs count as every category for set and ability purposes",
		7: "Once per hole, play any shot as though you held the ideal club",
	},
}


static func display_name(brand: String) -> String:
	return DISPLAY.get(brand, "")


# --- Counting -------------------------------------------------------

# How many of each brand the Bag holds. Brandless standards and the
# Bogey-Mart starter set are counted too (so the UI can show "3 unbranded"),
# but neither has a bonus table, so neither ever grants anything.
# Set-relevant brand counts. Bogey-Mart is excluded along with brandless
# clubs: it's the cheap starting set every run opens with, and it has no
# set bonus at any tier. Filtering it here rather than at each call site
# means no downstream effect — has(), active_bonuses(), or any mechanic
# built on them — can accidentally award the starter brand a bonus for the
# three clubs you were given for free.
static func counts(bag: Array) -> Dictionary:
	var out := {}
	for club in bag:
		var b: String = club.get("brand", NONE)
		if b == NONE or b == STARTER:
			continue
		out[b] = int(out.get(b, 0)) + 1
	return out


# The highest tier reached for one brand, or 0 for none. Tiers do NOT
# stack: reaching 4 replaces the 2-bonus rather than adding to it, which
# keeps a 7-set readable as a single identity instead of a pile of riders.
static func tier_reached(count: int) -> int:
	var best := 0
	for t in TIERS:
		if count >= t:
			best = t
	return best


# Every active bonus in the Bag, as [{brand, count, tier, text}, ...],
# strongest first. This is what the Bag UI's live counter renders.
static func active_bonuses(bag: Array) -> Array:
	var out: Array = []
	var c := counts(bag)
	for brand in c:
		var tier := tier_reached(int(c[brand]))
		if tier == 0:
			continue
		out.append({
			"brand": brand,
			"name": display_name(brand),
			"count": int(c[brand]),
			"tier": tier,
			"text": String(BONUS_TEXT.get(brand, {}).get(tier, "")),
		})
	out.sort_custom(func(a, b): return a.tier > b.tier)
	return out


# True when the Bag has reached at least `tier` of `brand`. The single
# predicate every mechanical effect below is written in terms of.
static func has(bag: Array, brand: String, tier: int) -> bool:
	var c := counts(bag)
	return int(c.get(brand, 0)) >= tier


# How far off the next tier this brand is, for the UI's "2/4" counter.
# Returns 0 once the top tier is reached.
static func next_tier(count: int) -> int:
	for t in TIERS:
		if count < t:
			return t
	return 0


# --- Mechanical effects ---------------------------------------------
#
# Each function below is the single place one rule bends. They take the
# whole Bag rather than a club because a set bonus is a property of what
# you're carrying, not of the club in your hands.

# Section 4 draw counts, after brand modifiers.
#   Titanist 4: +1 card at every tier.
#   Slazinger 2: +1 card, 4: +2 — paid for in severity (see severity_mult).
# Both are additive: a Bag running both brands draws both bonuses, which
# is the intended "see almost your whole deck" build.
static func bonus_draw_cards(bag: Array) -> int:
	var extra := 0
	if has(bag, "titanist", 4):
		extra += 1
	if has(bag, "slazinger", 4):
		extra += 2
	elif has(bag, "slazinger", 2):
		extra += 1
	return extra


# Titanist 2: the draw discards its worst card before you pick — you still
# choose from the same number, but never from the very worst option.
static func drops_worst_draw(bag: Array) -> bool:
	return has(bag, "titanist", 2)


# Slazinger's price: bad cards you play hit harder. Applies to deviation
# and to distance loss, so the extra cards are never free.
static func severity_mult(bag: Array) -> float:
	return 1.25 if has(bag, "slazinger", 2) else 1.0


# Callowell 2: bad cards from rough lose half their deviation.
# Callowell 7: Chunk and Top hit at half severity anywhere.
static func deviation_mult(bag: Array, lie: String, card: FormCard) -> float:
	var mult := 1.0
	if card != null and not card.good:
		if has(bag, "callowell", 2) and lie == "rough":
			mult *= 0.5
		if has(bag, "callowell", 7) and (card.name == "Chunk" or card.name == "Top"):
			mult *= 0.5
	return mult


# Callowell 4 / MacGregorian 4 / Nimbus: terrain stops taking its cut.
# Callowell ignores the penalty outright; MacGregorian restores the lie's
# *draw* quality, which is handled separately in plays_as_fairway().
static func ignores_terrain_penalty(bag: Array) -> bool:
	return has(bag, "callowell", 4)


# MacGregorian 4: you play OUT of rough/bunker as though on the fairway —
# normal draw counts, and no forced card in a bunker. Distinct from
# Callowell, which blunts the consequence rather than restoring the draw.
static func plays_as_fairway(bag: Array) -> bool:
	return has(bag, "macgregorian", 4)


# MacGregorian 2: hazards stop feeding bad cards into the Form deck, so a
# rough patch no longer compounds for the rest of the round.
static func blocks_form_decay(bag: Array) -> bool:
	return has(bag, "macgregorian", 2)


# Callowell 7: bad cards can no longer downgrade your lie or taint a putt.
static func blocks_lie_downgrade(bag: Array) -> bool:
	return has(bag, "callowell", 7)


static func blocks_yips(bag: Array) -> bool:
	return has(bag, "callowell", 7)


# Ping-Well 2: the Mid tier is widened from the middle third to the middle
# half. Returns the fraction of the band each side of centre that counts
# as Mid — 1/3 normally, 1/2 with the set.
static func mid_tier_span(bag: Array) -> float:
	return 0.5 if has(bag, "pingwell", 2) else (1.0 / 3.0)


# Ping-Well 4: every club plays one tier better than its distance implies.
# Ping-Well 7: Extreme Finesse is abolished for you entirely.
static func tier_upgrade_steps(bag: Array) -> int:
	return 1 if has(bag, "pingwell", 4) else 0


static func abolishes_extreme_finesse(bag: Array) -> bool:
	return has(bag, "pingwell", 7)


# Nimbus 4: your clubs count as every category for set and ability
# purposes — the reason Nimbus is the "safe" brand.
static func counts_as_all_categories(bag: Array) -> bool:
	return has(bag, "nimbus", 4)


# Slazinger 7: Created cards stop exhausting, returning at each hole's end.
static func created_cards_return(bag: Array) -> bool:
	return has(bag, "slazinger", 7)
