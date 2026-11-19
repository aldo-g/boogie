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
# stays on individual club cards (assets/data/clubs.json); sets bend rules.
#
# Tiers are 2 / 4 / 8. Eight is more than half the 14-card Bag, so the top
# set is an identity rather than a bonus: it leaves six slots to cover a
# whole course, which is not enough. That squeeze is the point.
#
# The top tier was 7 until 2026-11-17. With ten clubs a maker (there were
# seven) a bag reached seven in more than a quarter of rounds without
# trying; at eight it is rare unless you go all out for it, and reachable
# if you do (GAME_DESIGN.md Section 3A, "The top set").
# ---------------------------------------------------------

const TIER_PAIR := 2
const TIER_SET := 4
const DEFAULT_TOP := 8
# The top tier. A variable, not a constant, only so the balance harness can
# measure another size from the same tree (BotSim's `top=<n>`); the game
# never changes it.
static var top_tier: int = DEFAULT_TOP

# The key the top tier's bonus is filed under in the tables below, whatever
# size the tier is.
const TOP := 0


static func tiers() -> Array:
	return [TIER_PAIR, TIER_SET, top_tier]


static func is_top(tier: int) -> bool:
	return tier >= top_tier


# What a brand's set gives at `tier` (2, 4, or the top tier), in the card's
# words, and cut to a line for the stamp.
static func bonus_text(brand: String, tier: int) -> String:
	return String((BONUS_TEXT.get(brand, {}) as Dictionary).get(TOP if is_top(tier) else tier, ""))


static func stamp_text(brand: String, tier: int) -> String:
	return String((BONUS_STAMP.get(brand, {}) as Dictionary).get(TOP if is_top(tier) else tier, ""))

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

# Each brand's livery: the badge on its clubs and its chip in the brand
# rack, so a half-built set reads at a glance across the Bag. Muted to sit
# on parchment, and kept clear of the club-type colours (olive / slate /
# rust / grey) and the Limited gold, which own the card frame. Bogey-Mart
# gets a deliberately drab khaki.
const COLOR := {
	"titanist": Color("7A2E3A"),      # oxblood
	"callowell": Color("2E6B66"),     # teal
	"pingwell": Color("6A4C7A"),      # plum
	"macgregorian": Color("2E4566"),  # navy
	"slazinger": Color("B5574A"),     # terracotta
	"nimbus": Color("4F87A3"),        # sky
	"bogeymart": Color("776E5D"),     # khaki
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

# --- Signature shots (Section 4 "Clubs bring their shots") ---------------
# Every maker has a shot. Drafting one of its clubs puts that Form card
# into your Form deck, in the family of the club that brought it; cutting
# the club takes the card out again. So the draft builds the deck you draw
# from as well as the bag — a Titanist bag swings Knockdowns.
#
# Putters bring nothing: they are played on the meter, and their little
# pile of chips is too small to take a card without changing its nature.
const SIGNATURE := {
	"titanist": "Knockdown",
	"slazinger": "Bomb",
	"callowell": "Safe Swing",
	"macgregorian": "Scotch Runner",
	"pingwell": "Stock Shot",
	"nimbus": "Utility Swing",
}

# The makers whose shot belongs to no family: any club can be dealt it.
const SIGNATURE_ANY_FAMILY := ["nimbus"]

# What else comes with the club, by the club's family: a bad Form card that
# joins the deck when the club does and stays when the club goes. Slazinger
# only — the Bomb is the longest shot in the game and this is its price.
const BAGGAGE := {
	"slazinger": {"wood": "Duck Hook", "iron": "Hook", "wedge": "Chunk"},
}

# Staff clubs (Section 3C) play as their maker meant once the bag holds
# this many of the maker's clubs.
const STAFF_TIER := 4


# The Form card `club` brings to the deck, or "" for none.
static func signature(club: Dictionary) -> String:
	if club.get("type", "") == "putter":
		return ""
	return String(SIGNATURE.get(club.get("brand", NONE), ""))


# The family that card joins: the club's own, or "" (any) for Nimbus.
static func signature_family(club: Dictionary) -> String:
	if SIGNATURE_ANY_FAMILY.has(club.get("brand", NONE)):
		return ""
	return FormCard.family_of(club)


# The family one of `club`'s shots (its `shots`, ClubRoster.shots_for)
# joins: the club's own, except a Nimbus club's Utility Swing.
static func shot_family(club: Dictionary, shot: String) -> String:
	if shot.trim_suffix(FormCard.GROOVE_MARK) == signature(club):
		return signature_family(club)
	return FormCard.family_of(club)


# A club's shots in words: "Knockdown, Flushed, Hook".
static func shots_text(club: Dictionary) -> String:
	var out := PackedStringArray()
	for s in club.get("shots", []):
		out.append(str(s) + (" (any club)" if shot_family(club, str(s)) == "" else ""))
	return ", ".join(out)


# The bad card that comes with `club`, or "" for none. It joins the club's
# own family.
static func baggage(club: Dictionary) -> String:
	if club.get("type", "") == "putter":
		return ""
	return String((BAGGAGE.get(club.get("brand", NONE), {}) as Dictionary).get(FormCard.family_of(club), ""))

# Player-facing bonus text, indexed by brand then tier. Kept beside the
# mechanical flags below so the two can't drift apart silently.
const BONUS_TEXT := {
	"titanist": {
		2: "Your Form draw discards its worst card before you pick",
		4: "Draw +1 Form card at every tier",
		TOP: "Once per hole, re-draw your entire Form hand",
	},
	"callowell": {
		2: "Bad Form cards played from rough lose half their deviation",
		4: "Ignore all terrain penalties",
		TOP: "Bad cards can't downgrade your lie or taint a putt; mishits (Top, Thin, Chunk, Skied) hit at half severity",
	},
	"pingwell": {
		2: "The Mid tier is widened — the middle third counts as the middle half",
		4: "Every club plays one tier better than its distance implies",
		TOP: "Extreme Finesse is abolished — you always draw normally",
	},
	"macgregorian": {
		2: "Landing in rough or a bunker no longer adds a bad card to your Form deck",
		4: "Play out of rough/bunker as though on the fairway",
		TOP: "Once per hole, improve your lie one step before playing",
	},
	"slazinger": {
		2: "Draw +1 Form card, but bad cards you play hit at +25% severity",
		4: "Draw +2 Form cards, same penalty",
		TOP: "Your once-per-round club abilities recharge every hole",
	},
	"nimbus": {
		2: "Once per hole, play a shot one swing tier better",
		4: "Every club counts as every type (wood, iron, wedge) for club riders",
		TOP: "Once per hole, play a shot as though with the ideal club: Mid tier, a wedge's buffering",
	},
}

# The same bonuses cut to a line, for the stamp that lands when a set is
# completed (Main._celebrate_bag_change).
const BONUS_STAMP := {
	"titanist": {
		2: "The worst card of every draw is binned",
		4: "One more Form card on every swing",
		TOP: "Re-draw a Form hand, once a hole",
	},
	"callowell": {
		2: "Bad cards from the rough bend half as far",
		4: "No lie costs you distance",
		TOP: "Mishits at half strength, and no Yips",
	},
	"pingwell": {
		2: "A wider Mid tier on every club",
		4: "Every club plays a tier better",
		TOP: "No more Extreme Finesse",
	},
	"macgregorian": {
		2: "Rough and sand leave no bad cards",
		4: "Rough and sand play as fairway",
		TOP: "Improve your lie, once a hole",
	},
	"slazinger": {
		2: "One more Form card, and the bad ones bite",
		4: "Two more Form cards, and the bad ones bite",
		TOP: "Round abilities recharge every hole",
	},
	"nimbus": {
		2: "One swing a hole, a tier better",
		4: "Every club counts as every type",
		TOP: "The ideal club, once a hole",
	},
}


static func display_name(brand: String) -> String:
	return DISPLAY.get(brand, "")


static func color(brand: String) -> Color:
	return COLOR.get(brand, BogeyTheme.NEUTRAL_600)


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
#
# The Equaliser (limited edition): while the Bag holds 3+ distinct brands,
# it counts as every brand — a scattered draft's rescue.
#
# The Chameleon (limited edition) counts as whichever brand the rest of the
# bag holds most of, not as Nimbus — the wild card that makes the set. With
# another Nimbus Wood beside it, it counts as both.
static func counts(bag: Array) -> Dictionary:
	var out := {}
	var equaliser := false
	var chameleon: Dictionary = {}
	for club in bag:
		var b: String = club.get("brand", NONE)
		if b == NONE or b == STARTER:
			continue
		var power: String = (club.get("effects", {}) as Dictionary).get("power", "")
		if power == "chameleon" and chameleon.is_empty():
			chameleon = club
			continue
		out[b] = int(out.get(b, 0)) + 1
		if power == "equaliser":
			equaliser = true
	if not chameleon.is_empty():
		# The most-carried brand; a tie goes to the first in DRAFTABLE, so
		# every machine agrees.
		var top := "nimbus"
		var top_n := 0
		for b in DRAFTABLE:
			if int(out.get(b, 0)) > top_n:
				top_n = int(out[b])
				top = b
		out[top] = int(out.get(top, 0)) + 1
		if top != "nimbus" and _has_nimbus_wood(bag, chameleon):
			out["nimbus"] = int(out.get("nimbus", 0)) + 1
	if equaliser and out.size() >= 3:
		for b in DRAFTABLE:
			if b != "nimbus":  # the Equaliser is already counted as Nimbus
				out[b] = int(out.get(b, 0)) + 1
	return out


# The Chameleon's rider: a Nimbus club that is, or counts as, a Wood — other
# than the Chameleon itself. Read straight off the clubs rather than through
# ClubAbilities.bag_has(), which asks this class for its counts.
static func _has_nimbus_wood(bag: Array, except: Dictionary) -> bool:
	for club in bag:
		if is_same(club, except) or club.get("brand", NONE) != "nimbus":
			continue
		if club.get("type", "") == "wood":
			return true
		if ((club.get("effects", {}) as Dictionary).get("categories", []) as Array).has("wood"):
			return true
	return false


# The highest tier reached for one brand, or 0 for none. Tiers do NOT
# stack: reaching 4 replaces the 2-bonus rather than adding to it, which
# keeps the top set readable as a single identity instead of a pile of riders.
static func tier_reached(count: int) -> int:
	var best := 0
	for t in tiers():
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
			"text": bonus_text(brand, tier),
		})
	out.sort_custom(func(a, b): return a.tier > b.tier)
	return out


# True when the Bag holds a brand's top set.
static func has_top(bag: Array, brand: String) -> bool:
	return has(bag, brand, top_tier)


# True when the Bag has reached at least `tier` of `brand`. The single
# predicate every mechanical effect below is written in terms of.
static func has(bag: Array, brand: String, tier: int) -> bool:
	var c := counts(bag)
	return int(c.get(brand, 0)) >= tier


# How far off the next tier this brand is, for the UI's "2/4" counter.
# Returns 0 once the top tier is reached.
static func next_tier(count: int) -> int:
	for t in tiers():
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
static func deviation_mult(bag: Array, lie: String, card: FormCard) -> float:
	if card != null and not card.good and has(bag, "callowell", 2) and lie == "rough":
		return 0.5
	return 1.0


# Callowell 8: mishits hit at half severity anywhere. They have no
# deviation, so their severity is their distance loss — see
# ShotRules.resolve().
static func softens_mishits(bag: Array) -> bool:
	return has_top(bag, "callowell")


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


# Callowell 8: bad cards can no longer downgrade your lie or taint a putt.
static func blocks_lie_downgrade(bag: Array) -> bool:
	return has_top(bag, "callowell")


static func blocks_yips(bag: Array) -> bool:
	return has_top(bag, "callowell")


# Ping-Well 2: the Mid tier is widened from the middle third to the middle
# half. Returns the fraction of the band each side of centre that counts
# as Mid — 1/3 normally, 1/2 with the set.
static func mid_tier_span(bag: Array) -> float:
	return 0.5 if has(bag, "pingwell", 2) else (1.0 / 3.0)


# Ping-Well 4: every club plays one tier better than its distance implies.
# Ping-Well 8: Extreme Finesse is abolished for you entirely.
static func tier_upgrade_steps(bag: Array) -> int:
	return 1 if has(bag, "pingwell", 4) else 0


static func abolishes_extreme_finesse(bag: Array) -> bool:
	return has_top(bag, "pingwell")


# Nimbus 4: every club counts as every type for club riders ("while a
# Titanist Wood is in your bag") — the reason Nimbus is the "safe" brand.
static func counts_as_all_categories(bag: Array) -> bool:
	return has(bag, "nimbus", 4)


# Slazinger 8: once-per-round club abilities recharge every hole.
static func round_abilities_per_hole(bag: Array) -> bool:
	return has_top(bag, "slazinger")


# --- Once-per-hole set abilities ----------------------------------------
# Activated by the player; ClubAbilities.gd lists and charges them.

# Titanist 8: re-draw the whole Form hand.
static func can_redraw(bag: Array) -> bool:
	return has_top(bag, "titanist")


# MacGregorian 8: improve the lie one step before playing.
static func can_improve_lie(bag: Array) -> bool:
	return has_top(bag, "macgregorian")


# Nimbus 2: play one shot a swing tier better.
static func can_boost_tier(bag: Array) -> bool:
	return has(bag, "nimbus", 2)


# Nimbus 8: play one shot as though with the ideal club.
static func can_play_ideal(bag: Array) -> bool:
	return has_top(bag, "nimbus")
