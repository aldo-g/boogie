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
# Set bonuses that are activated (Titanist 8, MacGregorian 8, Nimbus 2/8)
# are listed and charged here too, so the player sees one list of things
# they can do.
#
# Charges live on the Player as `ability_log`: ability id -> the hole
# numbers it was used on. Everything here is a pure function of the bag
# and that log; Main.gd records uses and does the logging.
# ---------------------------------------------------------

enum Period { HOLE, ROUND, SIX_HOLES }

const HAZARD_LIES := ["rough", "bunker"]

# Steady Hands: how much bigger the cup plays.
const STEADY_HANDS_WIDEN := 0.6


# --- Reading a club's effects ------------------------------------------

# One of a club's effects. With a `bag`, a Staff club that is awake in it
# answers from its `staff` effects first — so every rule that hands over
# the bag sees the club as it plays there, and nothing has to be rewritten
# on the club when the bag changes.
static func effect(club: Dictionary, key: String, default: Variant = null, bag: Array = []) -> Variant:
	if not bag.is_empty() and is_awake(bag, club):
		var woken: Dictionary = club.get("staff", {})
		if woken.has(key):
			return woken[key]
	return (club.get("effects", {}) as Dictionary).get(key, default)


# --- Staff clubs (Section 3C) -------------------------------------------
# Built for a maker's staff players. Poor in a mixed bag; once the bag
# holds four of the maker's clubs (this one included) its `staff` effects
# take over from its own.

static func is_staff(club: Dictionary) -> bool:
	return not (club.get("staff", {}) as Dictionary).is_empty()


static func is_awake(bag: Array, club: Dictionary) -> bool:
	return is_staff(club) and Brands.has(bag, club.get("brand", Brands.NONE), Brands.STAFF_TIER)


# The Staff clubs in `bag` that are awake there, by name.
static func awake_names(bag: Array) -> Array:
	var out: Array = []
	for club in bag:
		if is_awake(bag, club):
			out.append(str(club.get("name", "")))
	return out


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
static func buffer(club: Dictionary, bag: Array = []) -> float:
	return ShotResolver.buffer_for_club(club) * float(effect(club, "buffer", 1.0, bag))


# The share of the aim this club flies from `lie`, or -1 for "use the
# terrain table".
static func lie_cap(club: Dictionary, lie: String, bag: Array = []) -> float:
	match lie:
		"rough":
			# A MacGregorian club worn in on hickory takes no cut from rough.
			if has_boost(club, "hickory"):
				return 1.0
			return float(effect(club, "rough_cap", -1.0, bag))
		"bunker":
			return float(effect(club, "bunker_cap", -1.0, bag))
	return -1.0


static func mid_span(bag: Array, club: Dictionary) -> float:
	return maxf(Brands.mid_tier_span(bag), float(effect(club, "mid_span", 0.0, bag))) \
		+ (FIT_SPAN if has_boost(club, "custom_fit") else 0.0)


# A club with no Mid tier at all: every swing in its band is Full or
# Finesse (a Ping-Well Staff club out of its set).
static func no_mid(bag: Array, club: Dictionary) -> bool:
	return bool(effect(club, "no_mid", false, bag))


# A club every swing of which is Mid, even below its range (a Ping-Well
# Staff club in its set, The Metronome always).
static func all_mid(bag: Array, club: Dictionary) -> bool:
	return bool(effect(club, "all_mid", false, bag))


# Form cards this club adds to (or takes from) its own draw: its own
# figure, and `trouble_draw` when it is played from rough or sand.
static func draw_bonus(bag: Array, club: Dictionary, lie: String = "") -> int:
	var n := int(effect(club, "draw_bonus", 0, bag))
	if HAZARD_LIES.has(lie):
		n += int(effect(club, "trouble_draw", 0, bag))
	if curse(club) == "bent_shaft":
		n -= 1
	if has_boost(club, "tour_grind"):
		n += 1
	return n


# How much harder (or softer) a bad card hits when played with this club,
# on top of the bag's own (Brands.severity_mult).
static func severity(bag: Array, club: Dictionary) -> float:
	return float(effect(club, "severity", 1.0, bag)) \
		* (REGRIP_SEVERITY if has_boost(club, "regrip") else 1.0) \
		* (LOOSE_GRIP_SEVERITY if curse(club) == "loose_grip" else 1.0)


# --- Growth: wear, boosts and curses (Section 3E) -----------------------
# A club is built as well as drafted. All of it is kept on the club's own
# Dictionary (`marks`, `level`, `boosts`, `curse`, and the `shots` it
# brings), so it travels with the bag online and leaves with the club.
# Putters take no part: they bring no shots and are aimed on the green.

static func grows(club: Dictionary) -> bool:
	return not (club.get("shots", []) as Array).is_empty()


# Wear. A shot that finds the fairway or the green leaves a mark on the
# club that hit it; every WEAR_MARKS marks is a level, MAX_LEVEL at most,
# and each level is a choice taken at the next draft (wear_choices).
const WEAR_MARKS := 3
const MAX_LEVEL := 2


# Levels earned and not yet chosen.
static func wear_pending(club: Dictionary) -> int:
	if not grows(club):
		return 0
	return mini(MAX_LEVEL, int(club.get("marks", 0)) / WEAR_MARKS) - int(club.get("level", 0))


# What a maker's club can also wear into, once: its maker's own gain. Some
# are the fitting bay's boosts given for nothing; three are the maker's
# alone (MAKER_GAINS).
const MAKER_WEAR := {
	"titanist": "tour_grind", "slazinger": "new_shaft", "callowell": "regrip",
	"pingwell": "custom_fit", "macgregorian": "hickory", "nimbus": "utility",
}
const MAKER_GAINS := {
	"tour_grind": {"name": "Tour grind", "does": "Dealt one more Form card"},
	"hickory": {"name": "Hickory shaft", "does": "Takes no cut from the rough"},
	"utility": {"name": "Utility weighting", "does": "Adds a Utility Swing any club can be dealt"},
}


# A boost's or a maker's gain's {name, does}.
static func gain_info(id: String) -> Dictionary:
	return BOOSTS.get(id, MAKER_GAINS.get(id, {"name": id, "does": ""}))


# What a level can be spent on: groove one of the club's good shots, lose
# one of its misses, or take its maker's gain.
# [{kind: "groove" | "drop" | "maker", shot, text}, ...] — for "maker",
# `shot` is the gain's id.
static func wear_choices(club: Dictionary) -> Array:
	var out: Array = []
	for s in club.get("shots", []):
		var shot := str(s)
		if shot.ends_with(FormCard.GROOVE_MARK):
			continue
		if FormCard.make(shot).good:
			out.append({"kind": "groove", "shot": shot, "text": "Groove its %s" % shot})
		else:
			out.append({"kind": "drop", "shot": shot, "text": "Lose its %s" % shot})
	var gain := str(MAKER_WEAR.get(club.get("brand", Brands.NONE), ""))
	if gain != "" and not has_boost(club, gain) and (gain != "custom_fit" or _has_middle(club)):
		out.append({"kind": "maker", "shot": gain, "text": str(gain_info(gain).name)})
	return out


# Boosts. Each draft offers one, in place of a club, for a club already in
# the bag; a club takes each kind once.
const BOOSTS := {
	"regrip": {"name": "Regrip", "does": "Its misses hit softer"},
	"custom_fit": {"name": "Custom fit", "does": "A wider comfortable middle: more three-card draws"},
	"new_shaft": {"name": "New shaft", "does": "Ten yards longer at the top of its range"},
	"grooves": {"name": "Fresh grooves", "does": "Its shots stop quicker"},
	"lead_tape": {"name": "Lead tape", "does": "Adds a shot to the club"},
}
const REGRIP_SEVERITY := 0.7
const FIT_SPAN := 1.0 / 6.0     # of the club's band, added to its Mid tier
const SHAFT_YARDS := 10.0
const GROOVES_ROLL := 0.6
# The shots lead tape can add; a draft that offers it shows three of them.
const TAPE_SHOTS := ["Stinger", "Controlled Draw", "Controlled Fade", "Spinner", "Soft Fade",
	"Punch Out", "Flushed", "In the Zone"]
const TAPE_CHOICES := 3


static func has_boost(club: Dictionary, id: String) -> bool:
	return (club.get("boosts", []) as Array).has(id)


# Whether `boost` can go on `club`. On a cursed club only the boost that
# mends its curse can (MENDS), and it is spent on the mending.
static func can_boost(club: Dictionary, boost: String) -> bool:
	if not BOOSTS.has(boost):
		return false
	if curse(club) != "":
		return MENDS[curse(club)] == boost
	# A putter takes a boost only to be mended.
	if not grows(club) or has_boost(club, boost):
		return false
	return boost != "custom_fit" or _has_middle(club)


# A club with no Mid tier, or nothing but one, has no middle to widen.
static func _has_middle(club: Dictionary) -> bool:
	for fx in [club.get("effects", {}), club.get("staff", {})]:
		if (fx as Dictionary).has("no_mid") or (fx as Dictionary).has("all_mid"):
			return false
	return true


# Curses. A ball in the water or out of bounds can leave one on the club
# that put it there, and a second-hand club arrives with one; a club
# carries one at most. The matching boost at a fitting bay lifts it
# (MENDS), and it goes with the club when the club leaves the bag.
const CURSES := {
	"bent_shaft": {"name": "Bent shaft", "does": "Dealt one fewer Form card"},
	"loose_grip": {"name": "Loose grip", "does": "Its misses hit harder"},
	"hosel_rocket": {"name": "Hosel rocket", "does": "A Shank joins its shots"},
}
const CURSE_CHANCE := 0.5
const LOOSE_GRIP_SEVERITY := 1.5
# The one boost that mends each curse.
const MENDS := {"bent_shaft": "new_shaft", "loose_grip": "regrip", "hosel_rocket": "custom_fit",
	"twitchy": "regrip"}
# A club on the rack is second-hand this often: already worn in (a level
# waits), and carrying a curse.
const SECOND_HAND_CHANCE := 0.125


static func curse(club: Dictionary) -> String:
	return str(club.get("curse", ""))


# A curse's {name, does}, a putter's included.
static func curse_info(id: String) -> Dictionary:
	return CURSES.get(id, PUTTER_CURSES.get(id, {"name": id, "does": ""}))


# --- The putter (Section 3E "The putter") -------------------------------
# It brings no shots, so it wears its own way: a putt holed in one from
# PUTT_MARK_YARDS or more leaves a mark, a level comes with no choice to
# make (the cup plays bigger), and three putts on a green can
# leave it twitchy. Regrip mends that.

static func is_putter(club: Dictionary) -> bool:
	return club.get("type", "") == "putter"


# (3 yards and 12% at first: the bot's putter was at its second level by
# the turn and the round was most of a stroke easier for it.)
const PUTT_MARK_YARDS := 5.0
const PUTTER_WEAR_BAND := 0.08   # wider bands, a level
const PUTTER_CURSES := {
	"twitchy": {"name": "Twitchy", "does": "The cup plays a fifth smaller"},
}
const TWITCHY_BAND := 0.8
const TWITCHY_PUTTS := 3         # putts on one green that can leave it


# What has been done to a club, in a line: "Worn in 1 · Regrip". "" for a
# club as it came off the rack. The curse is not in it — see curse().
static func growth_text(club: Dictionary) -> String:
	var bits := PackedStringArray()
	if int(club.get("level", 0)) > 0:
		bits.append("Worn in %d" % int(club.level))
	for id in club.get("boosts", []):
		bits.append(str(gain_info(str(id)).name))
	return " · ".join(bits)


# What becomes of a bad card played with this club: "" (the discard pile,
# like any other), "top" (straight back on top of the Form deck) or "gone"
# (out of the Form deck for good). The Callowell Staff clubs.
static func bad_fate(bag: Array, club: Dictionary) -> String:
	return str(effect(club, "bad_fate", "", bag))


# The Metronome with a Ping-Well Wood beside it: Stock Shots are struck
# pure from any tier, with any club.
static func stock_always(bag: Array) -> bool:
	var metronome := club_with_power(bag, "metronome")
	return not metronome.is_empty() and bag_has(bag, "pingwell", "wood", metronome.name)


# Woods are barred from sand, except the Persimmon Driver, and the
# Persimmon Spoon once a second MacGregorian club is in the bag.
static func bunker_playable(bag: Array, club: Dictionary) -> bool:
	if bool(effect(club, "bunker_playable", false, bag)):
		return true
	return power(club) == "persimmon_spoon" and _persimmon_rider(bag)


static func _persimmon_rider(bag: Array) -> bool:
	return int(Brands.counts(bag).get("macgregorian", 0)) >= 2


# "Half severity" for mishits (Top, Thin, Chunk, Skied): they lose half as
# much distance.
static func softens_mishit(club: Dictionary, card: FormCard) -> bool:
	return card.mishit and bool(effect(club, "soft_mishits", false))


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
		# A putter that is worn in holes more; a twitchy one, fewer.
		if is_putter(club):
			mult *= 1.0 + PUTTER_WEAR_BAND * float(club.get("level", 0))
			if curse(club) == "twitchy":
				mult *= TWITCHY_BAND
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


# How often an ability may be used: [period, limit]. Slazinger 8 turns
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
		"surgeon":
			# Once every six holes with a Titanist Iron alongside.
			out = [Period.SIX_HOLES if bag_has(bag, "titanist", "iron") else Period.ROUND, 1]
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
					"MacGregorian %d-set" % Brands.top_tier, false))
		"aim":
			if Brands.can_boost_tier(bag):
				out.append(_entry(bag, ctx, "boost_tier", "Play this shot one swing tier better",
					"Nimbus 2-set", true))
			if Brands.can_play_ideal(bag):
				out.append(_entry(bag, ctx, "ideal_club", "Play this as the ideal club",
					"Nimbus %d-set" % Brands.top_tier, true))
		"form":
			if has_power(bag, "gold_cleek") and not _holds_created(options, "Pure Strike"):
				out.append(_entry(bag, ctx, "gold_cleek", "Create a Pure Strike", "Gold Cleek", false))
			if has_power(bag, "bulger") and not _holds_created(options, "Big Strike") \
					and not club.is_empty() and is_type(bag, club, "wood") \
					and (HAZARD_LIES.has(lie) or bag_has(bag, "", "wedge")):
				out.append(_entry(bag, ctx, "bulger", "Create a Big Strike", "The Bulger", false))
			# Re-drawing only touches drawn cards, so it needs one in hand.
			if not bool(ctx.get("forced", false)) and options.any(func(c): return not c.created):
				if Brands.can_redraw(bag):
					out.append(_entry(bag, ctx, "redraw", "Re-draw your Form hand", "Titanist %d-set" % Brands.top_tier, false))
				if has_power(bag, "surgeon"):
					out.append(_entry(bag, ctx, "surgeon", "Re-draw your Form hand", "The Surgeon", false))
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
