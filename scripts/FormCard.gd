class_name FormCard
extends RefCounted

# ---------------------------------------------------------
# Section 4 — Form Card System
# A single, fully-known Form card: its identity (good/bad) and its
# deterministic effect on the shot it's played into. No hidden state —
# everything here is exactly what the player sees before they aim.
#
# side: -1 = pulls left (Hook/Draw-shape), +1 = pulls right (Slice/Fade-shape), 0 = straight
# degrees: known deviation magnitude, in degrees, before club buffering
# distance_mult: known distance multiplier, before terrain/tier caps
# ---------------------------------------------------------

var name: String
var good: bool
var side: int
var degrees: float
var distance_mult: float
var ignores_hazard_penalty: bool  # Flop Shot: ignores rough/bunker distance cap
var extra_roll: float             # Bump and Run: added roll distance
var roll_mult: float = 1.0        # how much the ball runs after landing (Stinger low, Flop dead)
var flight: float = 1.0           # how high it flies, so how much the wind gets hold of it
var run_share: float = 0.0        # share of the shot played along the ground (Bump and Run)
var downgrades_lie: bool          # Shank: worsens the resulting lie by one step
var is_yips: bool                 # Only meaningful on the green — see Section 4 cross-trigger
var to_max_band: bool = false     # Big Strike: flies the club's full carry, whatever the aim
var purges_bad: int = 0           # In the Zone: bad cards it removes from your Form deck
# A bad strike off the face (Top, Thin, Chunk, Skied) rather than a bad
# line — what Callowell 7 and the Big Deal Driver soften.
var mishit: bool = false
# Created by a club ability rather than drawn (Section 4 "Created cards").
# A created card exhausts: played or not, it never goes back into the
# Form deck.
var created: bool = false
# The club family this card belongs to (Section 4 "Form by club family"):
# one of FAMILIES. A swing is only dealt cards of the family of the club
# in hand, so the same Hook is a different card in the Wood pile and the
# Iron pile. "" for a card that belongs to no family — the cards a club
# creates for itself.
var family: String = ""


func _init(p_name: String, p_good: bool, p_side: int = 0, p_degrees: float = 0.0,
		p_distance_mult: float = 1.0, p_ignores_hazard_penalty: bool = false,
		p_extra_roll: float = 0.0, p_downgrades_lie: bool = false, p_is_yips: bool = false) -> void:
	name = p_name
	good = p_good
	side = p_side
	degrees = p_degrees
	distance_mult = p_distance_mult
	ignores_hazard_penalty = p_ignores_hazard_penalty
	extra_roll = p_extra_roll
	downgrades_lie = p_downgrades_lie
	is_yips = p_is_yips


func side_label() -> String:
	if side < 0:
		return "Left"
	elif side > 0:
		return "Right"
	return "Straight"


# One-line, fully-known effect text — exactly what Section 4 says the
# player should be able to read before aiming. No hidden numbers.
func effect_text() -> String:
	var bits: Array = []
	if degrees > 0.0:
		bits.append("Pulls %s %d°" % [side_label().to_lower(), int(degrees)])
	if distance_mult < 0.999:
		bits.append("%d%% distance" % int(round(distance_mult * 100.0)))
	elif distance_mult > 1.001:
		bits.append("+%d%% distance" % int(round((distance_mult - 1.0) * 100.0)))
	if to_max_band:
		bits.append("flies the club's full carry, whatever you aimed")
	bits.append_array(_other_bits())
	if bits.is_empty():
		bits.append("No deviation, standard distance")
	return "; ".join(bits)


# --- The card face (see CardFace.gd) -------------------------------------
# The same effect, split the way a card is set: two figures — how far,
# then how straight — as [datum, label] pairs, and the rest in words.
# A club's face carries the same two figures, so the pair reads across.

func distance_figure() -> Array:
	if to_max_band:
		return ["Max", "carry"]
	if distance_mult < 0.999:
		return ["%d%%" % int(round(distance_mult * 100.0)), "distance"]
	if distance_mult > 1.001:
		return ["+%d%%" % int(round((distance_mult - 1.0) * 100.0)), "distance"]
	return ["Full", "distance"]


func line_figure() -> Array:
	if degrees > 0.0:
		return ["%d°" % int(degrees), side_label().to_lower()]
	return ["Straight", ""]


# Everything effect_text() says beyond the two figures, as one sentence.
# Empty for a card that only bends the line or changes the distance.
func detail_text() -> String:
	var bits := _other_bits()
	if to_max_band:
		bits.push_front("the club's full carry, whatever you aimed")
	if bits.is_empty():
		return ""
	var text := "; ".join(bits)
	return text[0].to_upper() + text.substr(1)


# What the card does besides bend the line and change the distance.
func _other_bits() -> Array:
	var bits: Array = []
	if ignores_hazard_penalty:
		bits.append("ignores rough/bunker penalty")
	if run_share > 0.0:
		bits.append("lands %d%% of the way and runs the rest to your target" % int(round((1.0 - run_share) * 100.0)))
	if extra_roll > 0.0:
		bits.append("+%d yds roll" % int(extra_roll))
	if flight < 0.8:
		bits.append("flies low under the wind")
	elif flight > 1.2:
		bits.append("flies high into the wind")
	if roll_mult > 1.001:
		bits.append("runs out %sx" % _mult_text(roll_mult))
	elif roll_mult < 0.999:
		bits.append("stops %s" % ("dead" if roll_mult <= 0.2 else "quickly"))
	if downgrades_lie:
		bits.append("downgrades your lie")
	if is_yips:
		bits.append("taints your next putt if played")
	if purges_bad > 0:
		bits.append("removes a bad card from your Form deck")
	return bits


func _mult_text(m: float) -> String:
	return str(snappedf(m, 0.1)).trim_suffix(".0")


func with_roll(m: float) -> FormCard:
	roll_mult = m
	return self


func with_flight(f: float) -> FormCard:
	flight = f
	return self


func with_run(share: float) -> FormCard:
	run_share = share
	return self


func as_mishit() -> FormCard:
	mishit = true
	return self


func as_created() -> FormCard:
	created = true
	return self


func of_family(f: String) -> FormCard:
	family = f
	return self


# --- Card definitions (Section 4) ---
static func make(card_name: String) -> FormCard:
	match card_name:
		# --- Bad ---
		"Hook":
			return FormCard.new("Hook", false, -1, 15.0, 0.9)
		"Slice":
			return FormCard.new("Slice", false, 1, 15.0, 0.9)
		"Pull":
			# The mild misses: on line for distance, just off it.
			return FormCard.new("Pull", false, -1, 8.0, 1.0)
		"Push":
			return FormCard.new("Push", false, 1, 8.0, 1.0)
		"Duck Hook":
			# The left-hand disaster, as Shank is the right-hand one: it
			# dives in low and keeps running.
			return FormCard.new("Duck Hook", false, -1, 28.0, 0.7).with_roll(1.6)
		"Overswing":
			# The bad card with an upside: it goes further than you asked,
			# and left. Right on a par 5, wrong with water behind the green.
			return FormCard.new("Overswing", false, -1, 12.0, 1.1)
		"Top":
			return FormCard.new("Top", false, 0, 0.0, 0.45).with_roll(2.0).with_flight(0.3).as_mishit()
		"Thin":
			return FormCard.new("Thin", false, 0, 0.0, 0.8).with_roll(1.5).with_flight(0.6).as_mishit()
		"Chunk":
			return FormCard.new("Chunk", false, 0, 0.0, 0.3).with_roll(0.5).with_flight(0.7).as_mishit()
		"Skied":
			# Up under it: short, and the wind's plaything.
			return FormCard.new("Skied", false, 0, 0.0, 0.7).with_roll(0.4).with_flight(1.8).as_mishit()
		"Shank":
			return FormCard.new("Shank", false, 1, 35.0, 0.6, false, 0.0, true)
		"Yips":
			return FormCard.new("Yips", false, 0, 0.0, 1.0, false, 0.0, false, true)
		# --- Good ---
		"Pure Strike":
			return FormCard.new("Pure Strike", true, 0, 0.0, 1.0)
		"Stinger":
			return FormCard.new("Stinger", true, 0, 0.0, 0.92).with_roll(1.8).with_flight(0.4)
		"Controlled Draw":
			return FormCard.new("Controlled Draw", true, -1, 10.0, 1.0)
		"Controlled Fade":
			return FormCard.new("Controlled Fade", true, 1, 10.0, 1.0)
		"Power Draw":
			# A draw that runs: longer, and chases on after landing.
			return FormCard.new("Power Draw", true, -1, 6.0, 1.08).with_roll(1.4)
		"Soft Fade":
			# A fade that sits down: a touch short, but it holds a green.
			return FormCard.new("Soft Fade", true, 1, 6.0, 0.95).with_roll(0.5)
		"Flushed":
			return FormCard.new("Flushed", true, 0, 0.0, 1.08)
		"Spinner":
			# Full distance, straight, and it checks — the green-holder.
			return FormCard.new("Spinner", true).with_roll(0.25)
		"Punch Out":
			# The rough escape that stays low, where Flop Shot goes high.
			return FormCard.new("Punch Out", true, 0, 0.0, 0.9, true).with_roll(1.4).with_flight(0.6)
		"Flop Shot":
			return FormCard.new("Flop Shot", true, 0, 0.0, 0.85, true).with_roll(0.15).with_flight(1.6)
		"Bump and Run":
			return FormCard.new("Bump and Run", true).with_flight(0.5).with_run(0.5)
		"Steady Hands":
			# Created only, and on the green only (Old Reliable Putter): it
			# widens the putt meter's sunk band rather than shaping a shot.
			return FormCard.new("Steady Hands", true)
		"In the Zone":
			var zone := FormCard.new("In the Zone", true)
			zone.purges_bad = 1
			return zone
		"Big Strike":
			# Created only (The Bulger). Dead straight, the club's full
			# carry, and the lie takes no cut.
			var big := FormCard.new("Big Strike", true, 0, 0.0, 1.0, true)
			big.to_max_band = true
			return big
	push_error("FormCard.make(): unknown card '%s'" % card_name)
	return FormCard.new(card_name, true)


const BAD_NAMES := ["Hook", "Slice", "Pull", "Push", "Duck Hook", "Overswing",
	"Top", "Thin", "Chunk", "Skied", "Shank", "Yips"]
const GOOD_NAMES := ["Pure Strike", "Stinger", "Controlled Draw", "Controlled Fade",
	"Power Draw", "Soft Fade", "Flushed", "Spinner", "Punch Out",
	"Flop Shot", "Bump and Run", "Steady Hands", "In the Zone", "Big Strike"]

# --- Form by club family (Section 4) -------------------------------------
# Your form is not one thing: it is how you are striking each kind of
# club. Every card in the Form deck belongs to one family, and a swing is
# dealt only from the family of the club in hand — a driver is never
# handed a Flop Shot, and a bad day with the driver leaves the wedges
# alone.
const FAMILIES := ["wood", "iron", "wedge", "putter"]
const FAMILY_LABEL := {"wood": "Wood", "iron": "Iron", "wedge": "Wedge", "putter": "Putter"}

# What the Form deck starts with, family by family: about two good cards
# to every bad one in each. Each family has its own shots and its own way
# of missing:
#   wood   — length and shape; the misses are big and off line
#   iron   — precision; the misses are small
#   wedge  — height and spin; the misses are the strike itself
#   putter — played from off the green: it rolls true or it doesn't
# Pure Strike, Big Strike and Steady Hands are deliberately absent: they
# only ever come from a club's ability (Section 4 "Created cards"), so
# they're a resource you spend rather than a lucky draw.
const FAMILY_MIX := {
	"wood": {
		"Power Draw": 2, "Flushed": 2, "Stinger": 2, "Controlled Fade": 2,
		"Controlled Draw": 1, "In the Zone": 1,
		"Hook": 1, "Slice": 1, "Duck Hook": 1, "Overswing": 1, "Skied": 1, "Top": 1,
	},
	"iron": {
		"Controlled Draw": 2, "Controlled Fade": 2, "Punch Out": 2, "Stinger": 1,
		"Spinner": 1, "Soft Fade": 1, "In the Zone": 1,
		"Pull": 1, "Push": 1, "Hook": 1, "Slice": 1, "Thin": 1,
	},
	"wedge": {
		"Flop Shot": 3, "Bump and Run": 3, "Spinner": 2, "Soft Fade": 1, "In the Zone": 1,
		"Chunk": 1, "Thin": 1, "Shank": 1, "Yips": 1, "Pull": 1,
	},
	# No In the Zone here: in a pile this small it would turn up on most
	# chips, and clear the whole deck of bad cards.
	"putter": {
		"Bump and Run": 3, "Stinger": 1, "Punch Out": 1,
		"Thin": 1, "Top": 1,
	},
}

# The bad cards a family can be handed — left by a hazard, or created on
# the spot by a bunker or a swing below the club's range. Wider than what
# the family starts with: an iron begins without a Chunk or a Shank in it,
# and a rough round can put them there.
const FAMILY_BAD := {
	"wood": ["Hook", "Slice", "Duck Hook", "Overswing", "Skied", "Top"],
	"iron": ["Pull", "Push", "Hook", "Slice", "Thin", "Chunk", "Shank"],
	"wedge": ["Chunk", "Thin", "Shank", "Yips", "Pull", "Push"],
	"putter": ["Thin", "Top", "Yips"],
}


# The family a club's swing is dealt from: its type.
static func family_of(club: Dictionary) -> String:
	var t: String = club.get("type", "iron")
	return t if FAMILIES.has(t) else "iron"


# The bad cards `family` can be handed; every bad card for no family.
static func bad_names_for(fam: String) -> Array:
	return FAMILY_BAD.get(fam, BAD_NAMES)


# A family for a bad card that arrives without one: the first whose misses
# include it.
static func home_family(card_name: String) -> String:
	for fam in FAMILIES:
		if (FAMILY_BAD[fam] as Array).has(card_name) or (FAMILY_MIX[fam] as Dictionary).has(card_name):
			return fam
	return "iron"
