extends RefCounted

# ---------------------------------------------------------
# THE RULES OF THE DRAFT (Section 3D — hunting for a club)
#
# The end-of-hole draft is where the bag and the Form deck are built. Left
# alone it deals three clubs and you keep one. Three things bend that,
# each at a price, so that the club you want can be hunted for rather than
# waited for:
#
#   Call the hole — on the tee, call birdie. Make it and the draft shows
#       five and you keep two; miss and it shows two. The one place the
#       way you play a hole changes what you draft.
#   Dig          — send the whole offer back and see as many fresh ones.
#       A bad card joins your Form deck.
#   Trade in     — give up a club from the bag for one more offer.
#
# Pure functions of the bag and the draft so far, like ShotRules: Main.gd
# owns the decks, the rolls and the screen. Loaded by preload:
#   const DraftRules := preload("res://scripts/DraftRules.gd")
# ---------------------------------------------------------

# How many clubs a draft shows, and how many of them you keep.
const OFFERS := 3
const KEEPS := 1
# A called hole, made and missed.
const OFFERS_MADE := 5
const KEEPS_MADE := 2
const OFFERS_MISSED := 2
# The most the draft ever shows at once: a trade-in can't add to a full rack.
const MAX_OFFERS := 5

# What is called: this many under par, or better.
const CALL_UNDER := 1
const CALL_NAME := "birdie"

const MADE := "made"
const MISSED := "missed"
# The stop before the first tee (Main.begin_round): the round opens at the
# pro shop, with the rack a made call pays.
const OPENING := "opening"

# A dig unsettles the swing with one of these families' own misses. Not the
# putter's: its pile is too small to take one.
const DIG_FAMILIES := ["wood", "iron", "wedge"]


# How a called hole came out: MADE, MISSED, or "" when it wasn't called.
static func call_result(called: bool, strokes: int, par: int) -> String:
	if not called:
		return ""
	return MADE if strokes <= par - CALL_UNDER else MISSED


# --- The Gambler (limited edition putter) -------------------------------
# A called hole you make keeps one more; with a Slazinger Wood beside it, a
# called hole you miss still shows the usual three.

static func _gambler(bag: Array) -> Dictionary:
	return ClubAbilities.club_with_power(bag, "gambler")


static func gambler_softens_miss(bag: Array) -> bool:
	var g := _gambler(bag)
	return not g.is_empty() and ClubAbilities.bag_has(bag, "slazinger", "wood", g.name)


# How many clubs the draft deals.
static func offer_count(bag: Array, result: String) -> int:
	match result:
		MADE, OPENING:
			return OFFERS_MADE
		MISSED:
			return OFFERS if gambler_softens_miss(bag) else OFFERS_MISSED
	return OFFERS


# How many of them may be kept.
static func keep_count(bag: Array, result: String) -> int:
	if result == MADE:
		return KEEPS_MADE + (0 if _gambler(bag).is_empty() else 1)
	if result == OPENING:
		return KEEPS_MADE
	return KEEPS


# --- Digging ------------------------------------------------------------
# Old Faithful (limited edition) digs for nothing; with a Callowell Wedge
# beside it, twice a draft.

static func dig_limit(bag: Array) -> int:
	var faithful := ClubAbilities.club_with_power(bag, "old_faithful")
	if not faithful.is_empty() and ClubAbilities.bag_has(bag, "callowell", "wedge", faithful.name):
		return 2
	return 1


static func dig_costs_card(bag: Array) -> bool:
	return not ClubAbilities.has_power(bag, "old_faithful")


# A dig comes before anything is kept: `taken` is the picks (and range
# sessions) made in this draft, `digs` the digs, `offers` what is showing.
static func can_dig(bag: Array, taken: int, digs: int, offers: int) -> bool:
	return taken == 0 and offers > 0 and digs < dig_limit(bag)


# --- The putter stays ---------------------------------------------------
# A bag always holds a putter (Alastair, 2026-11-25). The only one can't be
# traded in, cut for a new club or left behind on a tour; it can go when
# the club coming in for it (`incoming`) is a putter.
static func can_leave(bag: Array, index: int, incoming = null) -> bool:
	if index < 0 or index >= bag.size() or not ClubAbilities.is_putter(bag[index]):
		return true
	if incoming is Dictionary and ClubAbilities.is_putter(incoming):
		return true
	return bag.filter(func(c): return ClubAbilities.is_putter(c)).size() > 1


# --- Trading in ---------------------------------------------------------

# One trade a draft, before anything is kept, while the rack has room —
# and never the last club: a bag has to be able to play the next hole.
static func can_trade(bag: Array, taken: int, traded: bool, offers: int) -> bool:
	return taken == 0 and not traded and offers > 0 and offers < MAX_OFFERS and bag.size() >= 2
