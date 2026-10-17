class_name ClubRoster
extends RefCounted

# ---------------------------------------------------------
# THE CLUB ROSTER (Section 3C)
#
# Every club in the game, as data. The numbers live in
# assets/data/clubs.json so balancing a band or adding an expansion club
# is an edit to one file rather than to the game loop.
#
# A club is a plain Dictionary — name, min_yard, max_yard, type, brand,
# limited, ability (the card text) and effects (what the rules read; see
# ClubAbilities.gd) — which is what the views render and what
# the online round payload sends, so nothing downstream needs to know the
# roster came from a file.
#
# Yardage lives here, on individual cards, where it's a local stat the
# player reads. Set bonuses never touch yardage — see Brands.gd.
# ---------------------------------------------------------

const DATA_PATH := "res://assets/data/clubs.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("ClubRoster: could not parse %s" % DATA_PATH)
			_data = {"starter": [], "standards": [], "brands": {}, "limited": []}
	return _data


static func make_club(cname: String, min_y: float, max_y: float, ctype: String,
		brand: String = Brands.NONE, limited: bool = false, ability: String = "",
		effects: Dictionary = {}) -> Dictionary:
	return {
		"name": cname,
		"min_yard": min_y,
		"max_yard": max_y,
		"type": ctype,          # "wood" / "iron" / "wedge" / "putter"
		"brand": brand,         # Brands.NONE for standards — see Brands.gd
		"limited": limited,
		"ability": ability,
		"effects": effects,
	}


# One JSON entry -> a club. `brand` fills in when the entry doesn't name
# its own (the starter set and the per-brand lists take it from context).
static func _from_entry(entry: Dictionary, brand: String = Brands.NONE) -> Dictionary:
	return make_club(str(entry.get("name", "?")),
		float(entry.get("min_yard", 0)), float(entry.get("max_yard", 0)),
		str(entry.get("type", "iron")), str(entry.get("brand", brand)),
		bool(entry.get("limited", false)), str(entry.get("ability", "")),
		(entry.get("effects", {}) as Dictionary).duplicate(true))


static func _clubs(entries: Array, brand: String = Brands.NONE) -> Array:
	var out: Array = []
	for e in entries:
		if e is Dictionary:
			out.append(_from_entry(e, brand))
	return out


# The Bogey-Mart starting set (Section 3A): a cheap supermarket three-piece,
# deliberately the worst gear in the game. Shorter bands, and — the sharper
# penalty — NARROWER ones, which drops you into the 2-card Form draw far
# more often than a real club would. Escaping this set is the run's first
# goal. Returned sorted.
static func starter_bag() -> Array:
	var bag := _clubs(data().get("starter", []), Brands.STARTER)
	sort_bag(bag)
	return bag


static func standard_clubs() -> Array:
	return _clubs(data().get("standards", []))


# Every club belonging to one brand. Each brand spans enough categories
# and enough cards to actually reach a 7-set, and each carries riders that
# express its axis locally — the set bonus expresses the same idea as a
# rule (Brands.gd).
static func branded_clubs(brand: String) -> Array:
	return _clubs(data().get("brands", {}).get(brand, []), brand)


# Limited editions: one copy each, a Created-card ability, and a pair
# rider that keys off a specific partner in the Bag rather than a count.
# These are the draft's "I need one more thing" hooks.
static func limited_clubs() -> Array:
	return _clubs(data().get("limited", []))


# The shared club deck (Section 3C), unshuffled. Standards are brandless
# and always present, so the deck always covers every yardage gap and is
# never unplayable. Branded clubs sit on top of that base and are the
# draft's real content — but only the run's live brands (Section 3B).
static func build_pool(brands: Array) -> Array:
	var pool: Array = []
	var standards := standard_clubs()
	for i in range(int(data().get("standard_copies", 3))):
		for club in standards:
			pool.append(club.duplicate(true))
	for brand in brands:
		pool.append_array(branded_clubs(brand))
	for card in limited_clubs():
		if card.brand == Brands.NONE or brands.has(card.brand):
			pool.append(card)
	return pool


# Section 3B — picks this run's 4 live brands, under the pairing rule:
# at least two distinct axes must be represented. Four brands all
# attacking the same axis would collapse the run into a single strategy,
# so the constraint guarantees every run offers two real directions to
# commit to. Retries rather than repairs — the pool is tiny and a valid
# draw is overwhelmingly likely, so a simple reroll is clearer than
# patching a bad set.
static func roll_live_brands() -> Array:
	var all: Array = Brands.DRAFTABLE.duplicate()
	for attempt in range(32):
		all.shuffle()
		var pick: Array = all.slice(0, 4)
		var axes := {}
		for b in pick:
			axes[Brands.AXIS.get(b, "")] = true
		if axes.size() >= 2:
			return pick
	# Unreachable in practice (any 4 of these 6 already span 2+ axes), but
	# return something valid rather than an empty pool if it ever is.
	return all.slice(0, 4)


# Keeps a bag in the order a real golfer racks it: longest club first,
# putter always last. Every view renders the bag by index and every pick
# callback captures that same index, so sorting the array itself — rather
# than sorting a copy at draw time — keeps the bag row, the discard row,
# and the click handlers in agreement for free.
static func sort_bag(bag: Array) -> void:
	bag.sort_custom(func(a, b):
		# The putter has a 0-0 band and would otherwise sort to the front.
		var a_putter: bool = a.type == "putter"
		var b_putter: bool = b.type == "putter"
		if a_putter != b_putter:
			return b_putter
		if a.max_yard != b.max_yard:
			return a.max_yard > b.max_yard
		# Same reach: the club that also carries further at the bottom of
		# its band is the longer stick, and name is a stable last resort so
		# two identical bands never swap places between redraws.
		if a.min_yard != b.min_yard:
			return a.min_yard > b.min_yard
		return a.name < b.name)
