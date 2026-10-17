class_name ClubAbilities
extends RefCounted

# ---------------------------------------------------------
# CLUB ABILITIES (Sections 3C and 4 "Created cards")
#
# What the text on a club card actually does. Three kinds:
#
#   Modifiers — how one club plays: better or worse buffering, no rough
#     penalty, a wider Mid tier. Read from the club's `effects` in
#     assets/data/clubs.json, applied by ShotRules when that club is used.
#
#   Passives — fire on their own: a wedge that adds a Flop Shot to the
#     draw from sand, a niblick that blocks Form decay, a wedge that purges
#     a bad card when you find a hazard.
#
#   Actives — the player spends a charge, in the moment: "create a Pure
#     Strike in this hand", "re-draw", "Steady Hands on this putt". Each has
#     a limit per hole, per round, or per six holes. A created card joins
#     the current Form hand and exhausts whether played or not — so the
#     decision is which shot to spend it on, not whether to hoard it.
#
# Set bonuses that are activated (Titanist 7, MacGregorian 7, Nimbus 2/7)
# are listed and charged here too, so the player sees one list of things
# they can do.
#
# Charges live on the Player as `ability_log`: ability id -> the hole
# numbers it was used on. Everything here is a pure function of the bag
# and that log; Main.gd records uses and does the logging.
# ---------------------------------------------------------

enum Period { HOLE, ROUND, SIX_HOLES }

const HAZARD_LIES := ["rough", "bunker"]

# Steady Hands: how much wider the putt meter's bands get.
const STEADY_HANDS_WIDEN := 0.6


# --- Reading a club's effects ------------------------------------------

static func effect(club: Dictionary, key: String, default: Variant = null) -> Variant:
	return (club.get("effects", {}) as Dictionary).get(key, default)


static func power(club: Dictionary) -> String:
	return str(effect(club, "power", ""))


static func club_with_power(bag: Array, id: String) -> Dictionary:
	for club in bag:
		if power(club) == id:
			return club
	return {}


static func has_power(bag: Array, id: String) -> bool:
	return not club_with_power(bag, id).is_empty()


# Whether `club` counts as type `t` for club riders: its own type, any
# extra types it lists (Nimbus hybrids), or any type at all under the
# Nimbus 4-set. A putter is only ever a putter.
static func is_type(bag: Array, club: Dictionary, t: String) -> bool:
	var own: String = club.get("type", "")
	if own == t:
		return true
	if own == "putter" or t == "putter":
		return false
	if Brands.counts_as_all_categories(bag):
		return true
	return (effect(club, "categories", []) as Array).has(t)


# Is there a club in the bag of this brand ("" for any) and type, other
# than the one named `except`?
static func bag_has(bag: Array, brand: String, t: String, except: String = "") -> bool:
	for club in bag:
		if club.get("name", "") == except:
			continue
		if brand != "" and club.get("brand", "") != brand:
			continue
		if is_type(bag, club, t):
			return true
	return false


# --- Club modifiers (applied by ShotRules) -------------------------------

# Share of a Form card's deviation this club lets through, before brands.
static func buffer(club: Dictionary) -> float:
	return ShotResolver.buffer_for_club(club) * float(effect(club, "buffer", 1.0))


# The share of the aim this club flies from `lie`, or -1 for "use the
# terrain table".
static func lie_cap(club: Dictionary, lie: String) -> float:
	match lie:
		"rough":
			return float(effect(club, "rough_cap", -1.0))
		"bunker":
			return float(effect(club, "bunker_cap", -1.0))
	return -1.0


static func mid_span(bag: Array, club: Dictionary) -> float:
	return maxf(Brands.mid_tier_span(bag), float(effect(club, "mid_span", 0.0)))


# Woods are barred from sand, except the Persimmon Driver, and the
# Persimmon Spoon once a second MacGregorian club is in the bag.
static func bunker_playable(bag: Array, club: Dictionary) -> bool:
	if bool(effect(club, "bunker_playable", false)):
		return true
	return power(club) == "persimmon_spoon" and _persimmon_rider(bag)


static func _persimmon_rider(bag: Array) -> bool:
	return int(Brands.counts(bag).get("macgregorian", 0)) >= 2


# "Half severity" for Chunk and Top: they lose half as much distance.
static func softens_mishit(club: Dictionary, card: FormCard) -> bool:
	return (card.name == "Chunk" or card.name == "Top") and bool(effect(club, "soft_mishits", false))


static func blocks_lie_downgrade(club: Dictionary) -> bool:
	return bool(effect(club, "no_lie_downgrade", false))


static func big_strike_bonus(club: Dictionary) -> float:
	return float(effect(club, "big_strike_bonus", 0.0))


# A Bump and Run with this club runs this share of the shot, or -1.
static func bump_run_share(club: Dictionary) -> float:
	return float(effect(club, "bump_run_share", -1.0))


# --- Bag-wide passives ----------------------------------------------

# MacGregorian 2, or a MacGregorian Niblick anywhere in the bag.
static func blocks_form_decay(bag: Array) -> bool:
	if Brands.blocks_form_decay(bag):
		return true
	for club in bag:
		if bool(effect(club, "blocks_form_decay", false)):
			return true
	return false


# The MacGregorian Jigger: a ball on the fringe is putted.
static func fringe_putts(bag: Array) -> bool:
	for club in bag:
		if bool(effect(club, "fringe_putt", false)):
			return true
	return false


# Every putter rider in the bag, multiplied: Callowell and Slazinger widen
# long putts, Slazinger narrows short ones. `steady` adds Steady Hands.
static func putt_band_mult(bag: Array, putt_yards: float, steady: bool) -> float:
	var mult := 1.0
	var steady_scale := 1.0
	for club in bag:
		if putt_yards >= 10.0:
			mult *= float(effect(club, "putt_long_band", 1.0))
		elif putt_yards < 4.0:
			mult *= float(effect(club, "putt_short_band", 1.0))
		steady_scale = maxf(steady_scale, float(effect(club, "steady_mult", 1.0)))
	if steady:
		mult *= 1.0 + STEADY_HANDS_WIDEN * steady_scale
	return mult


# --- Charges ------------------------------------------------------------

static func uses(charges: Dictionary, id: String, hole_n: int, period: int) -> int:
	var n := 0
	for h in charges.get(id, []):
		match period:
			Period.HOLE:
				if int(h) == hole_n:
					n += 1
			Period.ROUND:
				n += 1
			Period.SIX_HOLES:
				if int(h) > hole_n - 6:
					n += 1
	return n


static func record(charges: Dictionary, id: String, hole_n: int) -> void:
	var hist: Array = charges.get(id, [])
	hist.append(hole_n)
	charges[id] = hist


# How often an ability may be used: [period, limit]. Slazinger 7 turns
# once-per-round and once-per-six-holes into once per hole.
static func allowance(bag: Array, id: String) -> Array:
	var out := [Period.HOLE, 1]
	match id:
		"gold_cleek":
			# Twice per hole with a Titanist Wood alongside.
			out = [Period.HOLE, 2 if bag_has(bag, "titanist", "wood") else 1]
		"old_reliable":
			var pingwell := int(Brands.counts(bag).get("pingwell", 0))
			out = [Period.SIX_HOLES if pingwell >= 2 else Period.ROUND, 1]
		"putt_retry":
			out = [Period.ROUND, 1]
	if out[0] != Period.HOLE and Brands.round_abilities_per_hole(bag):
		out[0] = Period.HOLE
	return out


static func uses_left(bag: Array, charges: Dictionary, id: String, hole_n: int) -> int:
	var a := allowance(bag, id)
	return maxi(0, int(a[1]) - uses(charges, id, hole_n, int(a[0])))


static func period_text(period: int) -> String:
	match period:
		Period.ROUND:
			return "per round"
		Period.SIX_HOLES:
			return "per six holes"
	return "per hole"


# --- Actives ----------------------------------------------------------

# The activated abilities available right now. `phase` is "club_select",
# "aim", "form" or "putting". `ctx` carries:
#   lie, club (the club in hand, if any), forced (the Form hand is a
#   forced card), options (the current Form hand), armed (abilities toggled
#   on for this shot), charges (the ability log), hole.
# Returns [{id, label, source, left, period, toggle, armed}, ...]. Toggles
# arm an effect for the shot or putt and are only charged once it's used;
# the rest act the moment they're pressed.
static func actives(bag: Array, phase: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var lie: String = ctx.get("lie", "")
	var club: Dictionary = ctx.get("club", {})
	var armed: Dictionary = ctx.get("armed", {})
	var options: Array = ctx.get("options", [])
	match phase:
		"club_select":
			if Brands.can_improve_lie(bag) and HAZARD_LIES.has(lie):
				out.append(_entry(bag, ctx, "improve_lie", "Improve your lie to %s" % lie_improved(lie),
					"MacGregorian 7-set", false))
		"aim":
			if Brands.can_boost_tier(bag):
				out.append(_entry(bag, ctx, "boost_tier", "Play this shot one swing tier better",
					"Nimbus 2-set", true))
			if Brands.can_play_ideal(bag):
				out.append(_entry(bag, ctx, "ideal_club", "Play this as the ideal club",
					"Nimbus 7-set", true))
		"form":
			if has_power(bag, "gold_cleek") and not _holds_created(options, "Pure Strike"):
				out.append(_entry(bag, ctx, "gold_cleek", "Create a Pure Strike", "Gold Cleek", false))
			if has_power(bag, "bulger") and not _holds_created(options, "Big Strike") \
					and not club.is_empty() and is_type(bag, club, "wood") \
					and (HAZARD_LIES.has(lie) or bag_has(bag, "", "wedge")):
				out.append(_entry(bag, ctx, "bulger", "Create a Big Strike", "The Bulger", false))
			# Re-drawing only touches drawn cards, so it needs one in hand.
			if Brands.can_redraw(bag) and not bool(ctx.get("forced", false)) \
					and options.any(func(c): return not c.created):
				out.append(_entry(bag, ctx, "redraw", "Re-draw your Form hand", "Titanist 7-set", false))
		"putting":
			if has_power(bag, "old_reliable"):
				out.append(_entry(bag, ctx, "old_reliable", "Steady Hands on this putt",
					"Old Reliable Putter", true))
			if has_power(bag, "putt_retry"):
				out.append(_entry(bag, ctx, "putt_retry", "If this putt misses, take it again",
					"Titanist Blade Putter", true))
	# An armed toggle stays listed (so it can be switched off) even once
	# its charge would read 0; anything else needs a charge left.
	return out.filter(func(e): return e.left > 0 or e.armed)


static func _entry(bag: Array, ctx: Dictionary, id: String, label: String, source: String,
		toggle: bool) -> Dictionary:
	var a := allowance(bag, id)
	return {
		"id": id, "label": label, "source": source, "toggle": toggle,
		"armed": (ctx.get("armed", {}) as Dictionary).has(id),
		"left": uses_left(bag, ctx.get("charges", {}), id, int(ctx.get("hole", 0))),
		"period": int(a[0]),
	}


static func _holds_created(options: Array, card_name: String) -> bool:
	for c in options:
		if c.created and c.name == card_name:
			return true
	return false


static func lie_improved(lie: String) -> String:
	match lie:
		"bunker":
			return "rough"
		"rough":
			return "fairway"
	return lie


# The card an active ability creates into the Form hand, or "".
static func creates(id: String) -> String:
	match id:
		"gold_cleek":
			return "Pure Strike"
		"bulger":
			return "Big Strike"
	return ""


# --- Passives ---------------------------------------------------------

# Which ability lets `club` play from `lie` as though from the fairway —
# no distance cut, no forced card — or "" for none. The Nimbus Utility
# Wedge does it once per hole; the Persimmon Spoon always, with a second
# MacGregorian club.
static func plays_clean(bag: Array, club: Dictionary, lie: String, charges: Dictionary, hole_n: int) -> String:
	if not HAZARD_LIES.has(lie) or club.is_empty():
		return ""
	if power(club) == "utility_any_lie" and uses_left(bag, charges, "utility_any_lie", hole_n) > 0:
		return "utility_any_lie"
	if power(club) == "persimmon_spoon" and _persimmon_rider(bag):
		return "persimmon_spoon"
	return ""


# Created cards a club adds to its own draw: the Ping-Well Lob Wedge
# played from rough or sand brings a Flop Shot.
static func draw_extras(club: Dictionary, lie: String) -> Array:
	if power(club) == "lob_flop" and HAZARD_LIES.has(lie):
		return ["Flop Shot"]
	return []


# What the bag does once a shot has settled on `terrain`. Returns:
#   create — card names to add to the next Form draw
#   purge  — bad cards to remove from the Form deck
#   used   — once-per-hole passives that fired, to record
#   by     — the club names responsible, for the log
static func on_landing(bag: Array, terrain: String, hazard: bool, charges: Dictionary,
		hole_n: int) -> Dictionary:
	var out := {"create": [], "purge": 0, "used": [], "by": []}
	var tom := club_with_power(bag, "old_tom")
	if not tom.is_empty():
		if terrain == "bunker":
			out.create.append("Flop Shot")
			out.by.append(tom.name)
		elif terrain == "fairway" and bag_has(bag, "macgregorian", "wood", tom.name) \
				and uses_left(bag, charges, "old_tom_fairway", hole_n) > 0:
			out.create.append("Bump and Run")
			out.used.append("old_tom_fairway")
			out.by.append(tom.name)
	var rutter := club_with_power(bag, "rutter")
	if hazard and not rutter.is_empty():
		out.purge = 2 if bag_has(bag, "callowell", "iron", rutter.name) else 1
		out.by.append(rutter.name)
	return out
