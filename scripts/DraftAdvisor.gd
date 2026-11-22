class_name DraftAdvisor
extends RefCounted

# ---------------------------------------------------------
# What a club would change about your bag — said on the card, at the
# moment you choose. The end-of-hole draft is where the deckbuilding
# happens, and its payoffs (a set completed, a rider switched on, a
# yardage gap filled) shouldn't be left for the player to work out.
#
# gains(bag, club, cap) — taking it: [{text, strong}], most important first
# losses(bag, club) — cutting it from a full bag: the same shape
#
# "strong" lines are the ones worth shouting about: a set tier reached
# or broken, a rider switched on or off, a real gap filled or opened.
# ---------------------------------------------------------

# A carry range only counts as a gap once it's this wide (yards).
const GAP_YARDS := 10.0


static func gains(bag: Array, club: Dictionary, bag_cap: int = 14) -> Array:
	var after := bag + [club]
	var out: Array = []
	out.append_array(_set_changes(bag, after, true))
	out.append_array(_rider_changes(bag, after, true))
	out.append_array(_staff_changes(bag, after, club, true))
	var gaps := uncovered(club, bag)
	if not gaps.is_empty():
		out.append({"text": _gain_text(gaps, bag), "strong": true})
	# Brand progress short of a tier — worth a quieter line.
	var brand: String = club.get("brand", Brands.NONE)
	if Brands.DRAFTABLE.has(brand) and not _reaches_tier(bag, after, brand):
		var n := int(Brands.counts(after).get(brand, 0))
		var next := Brands.next_tier(n)
		if next > 0:
			out.append({"text": "%s %d/%d toward the next set" % [Brands.display_name(brand), n, next], "strong": false})
	# The shot it brings to the Form deck — and anything bad that comes too.
	# A second-hand club: what is already in it, and what is wrong with it.
	var cursed := ClubAbilities.curse(club)
	if cursed != "":
		# Short enough for two lines of a draft card.
		out.append({"text": "Second-hand: worn in, with a %s" % str(ClubAbilities.curse_info(cursed).name).to_lower(),
			"strong": true})
	if ClubAbilities.grows(club):
		var bad := Brands.baggage(club)
		out.append({"text": "Brings %s to %s%s" % [Brands.shots_text(club), _form_place(club),
			"" if bad == "" else " — and a %s with it" % bad], "strong": false})
	if bag.size() >= bag_cap:
		out.append({"text": "Bag is full — taking it means cutting a club", "strong": false})
	# Strong lines first, keeping each group in the order it was built.
	return out.filter(func(e): return e.strong) + out.filter(func(e): return not e.strong)


static func losses(bag: Array, club: Dictionary) -> Array:
	var after: Array = []
	var removed := false
	for c in bag:
		# Remove this one copy, by identity, not every club of that name.
		if not removed and c == club:
			removed = true
			continue
		after.append(c)
	var out: Array = []
	out.append_array(_set_changes(bag, after, false))
	out.append_array(_rider_changes(bag, after, false))
	out.append_array(_staff_changes(bag, after, club, false))
	var gaps := uncovered(club, after)
	if not gaps.is_empty() and club.get("type", "") != "putter":
		out.append({"text": "Leaves a gap: %s yds" % _ranges_text(gaps), "strong": true})
	if club.get("type", "") == "putter" and not after.any(func(c): return c.get("type", "") == "putter"):
		out.append({"text": "Your only putter", "strong": true})
	# What has been put into it goes too.
	var grown := ClubAbilities.growth_text(club)
	if grown != "":
		out.append({"text": "Gives up: %s" % grown, "strong": true})
	if ClubAbilities.grows(club):
		out.append({"text": "Its shots leave %s: %s" % [_form_place(club), Brands.shots_text(club)], "strong": false})
	return out


# Where a club's signature shot lives in the Form deck, in words.
static func _form_place(club: Dictionary) -> String:
	var fam := FormCard.family_of(club)
	return "your %s form" % str(FormCard.FAMILY_LABEL.get(fam, "")).to_lower()


# --- Staff clubs -----------------------------------------------------

# Staff clubs that wake or go back to sleep between the two bags, and —
# when the club on offer is one — whether it would be awake in yours.
static func _staff_changes(before: Array, after: Array, club: Dictionary, gaining: bool) -> Array:
	var out: Array = []
	var was := ClubAbilities.awake_names(before)
	var now := ClubAbilities.awake_names(after)
	var own := str(club.get("name", ""))
	if gaining:
		var woken: Array = now.filter(func(n): return not was.has(n) and n != own)
		if not woken.is_empty():
			out.append({"text": "Wakes your %s" % _name_list(woken), "strong": true})
		if ClubAbilities.is_staff(club):
			if now.has(own):
				out.append({"text": "A Staff club, and awake in this bag", "strong": true})
			else:
				var brand: String = club.get("brand", Brands.NONE)
				out.append({"text": "A Staff club: asleep until you carry %d %s (%d/%d)" % [
					Brands.STAFF_TIER, Brands.display_name(brand),
					int(Brands.counts(after).get(brand, 0)), Brands.STAFF_TIER], "strong": true})
	else:
		var slept: Array = was.filter(func(n): return not now.has(n) and n != own)
		if not slept.is_empty():
			out.append({"text": "Puts your %s to sleep" % _name_list(slept), "strong": true})
	return out


static func _name_list(names: Array) -> String:
	return " and ".join(PackedStringArray(names))


# --- Sets ------------------------------------------------------------

static func _reaches_tier(before: Array, after: Array, brand: String) -> bool:
	return Brands.tier_reached(int(Brands.counts(after).get(brand, 0))) \
		!= Brands.tier_reached(int(Brands.counts(before).get(brand, 0)))


# Every brand whose tier changes between the two bags. Covers the
# Equaliser, which can move every brand at once.
static func _set_changes(before: Array, after: Array, gaining: bool) -> Array:
	var out: Array = []
	var c0 := Brands.counts(before)
	var c1 := Brands.counts(after)
	for brand in Brands.DRAFTABLE:
		var t0 := Brands.tier_reached(int(c0.get(brand, 0)))
		var t1 := Brands.tier_reached(int(c1.get(brand, 0)))
		if t0 == t1:
			continue
		var name := Brands.display_name(brand)
		if gaining and t1 > t0:
			out.append({"text": "Completes your %s %d-set: %s" % [name, t1,
				Brands.bonus_text(brand, t1)], "strong": true})
		elif not gaining and t1 < t0:
			out.append({"text": "Breaks your %s %d-set: %s" % [name, t0,
				Brands.bonus_text(brand, t0)], "strong": true})
	return out


# --- Club riders -----------------------------------------------------

# The pair riders, and what turning each on means, in the card's words.
const RIDERS := {
	"gold_cleek": "Gold Cleek creates a Pure Strike twice per hole",
	"bulger": "The Bulger's Big Strike works from any lie",
	"old_tom": "Old Tom's Niblick also creates a Bump and Run on the fairway",
	"rutter": "The Rutter purges two bad cards per hazard",
	"old_reliable": "Old Reliable's Steady Hands every six holes, not once a round",
	"persimmon_spoon": "The Persimmon Spoon plays from any lie, sand included",
	"surgeon": "The Surgeon re-draws every six holes, not once a round",
	"gambler": "The Gambler: a called hole missed still shows 3",
	"old_faithful": "Old Faithful digs twice a draft",
	"metronome": "The Metronome strikes your Stock Shots pure from any tier",
	"chameleon": "The Chameleon counts as Nimbus too",
}


static func _rider_on(bag: Array, power: String) -> bool:
	var owner := ClubAbilities.club_with_power(bag, power)
	if owner.is_empty():
		return false
	match power:
		"gold_cleek":
			return ClubAbilities.bag_has(bag, "titanist", "wood")
		"bulger":
			return ClubAbilities.bag_has(bag, "", "wedge")
		"old_tom":
			return ClubAbilities.bag_has(bag, "macgregorian", "wood", owner.name)
		"rutter":
			return ClubAbilities.bag_has(bag, "callowell", "iron", owner.name)
		"old_reliable":
			return int(Brands.counts(bag).get("pingwell", 0)) >= 2
		"persimmon_spoon":
			return int(Brands.counts(bag).get("macgregorian", 0)) >= 2
		"surgeon":
			return ClubAbilities.bag_has(bag, "titanist", "iron")
		"gambler":
			return ClubAbilities.bag_has(bag, "slazinger", "wood", owner.name)
		"old_faithful":
			return ClubAbilities.bag_has(bag, "callowell", "wedge", owner.name)
		"metronome":
			return ClubAbilities.bag_has(bag, "pingwell", "wood", owner.name)
		"chameleon":
			return Brands._has_nimbus_wood(bag, owner)
	return false


static func _rider_changes(before: Array, after: Array, gaining: bool) -> Array:
	var out: Array = []
	for power in RIDERS:
		var on0 := _rider_on(before, power)
		var on1 := _rider_on(after, power)
		if gaining and on1 and not on0:
			out.append({"text": "Switches on: %s" % RIDERS[power], "strong": true})
		elif not gaining and on0 and not on1:
			out.append({"text": "Switches off: %s" % RIDERS[power], "strong": true})
	return out


# --- Yardage coverage ------------------------------------------------

# The parts of `club`'s carry band that no club in `bag` covers, as
# [Vector2(from, to)] — only stretches of GAP_YARDS or more. Putters
# aren't about carry and never count.
static func uncovered(club: Dictionary, bag: Array) -> Array:
	if club.get("type", "") == "putter":
		return []
	var lo := float(club.get("min_yard", 0.0))
	var hi := float(club.get("max_yard", 0.0))
	var bands: Array = []
	for c in bag:
		if c.get("type", "") != "putter":
			bands.append(Vector2(float(c.min_yard), float(c.max_yard)))
	bands.sort_custom(func(a, b): return a.x < b.x)
	var out: Array = []
	var cursor := lo
	for b in bands:
		if b.y <= cursor:
			continue
		if b.x >= hi:
			break
		if b.x > cursor and b.x - cursor >= GAP_YARDS:
			out.append(Vector2(cursor, minf(b.x, hi)))
		cursor = maxf(cursor, b.y)
		if cursor >= hi:
			break
	if hi - cursor >= GAP_YARDS:
		out.append(Vector2(cursor, hi))
	return out


# What the new yards are, in words: more reach off the top of the bag, a
# hole in the middle filled, or a shorter shot than anything carried.
static func _gain_text(gaps: Array, bag: Array) -> String:
	var lo := INF
	var hi := -INF
	for c in bag:
		if c.get("type", "") != "putter" and float(c.get("max_yard", 0.0)) > 0.0:
			lo = minf(lo, float(c.min_yard))
			hi = maxf(hi, float(c.max_yard))
	if lo == INF:
		return "Your first full-swing club: %s yds" % _ranges_text(gaps)
	var bits: Array = []
	for g in gaps:
		if g.x >= hi - 0.5:
			bits.append("adds reach past %d, out to %d yds" % [int(hi), int(g.y)])
		elif g.y <= lo + 0.5:
			bits.append("adds a shorter shot, %d–%d yds" % [int(g.x), int(g.y)])
		else:
			bits.append("fills your %d–%d yd gap" % [int(g.x), int(g.y)])
	var text := "; ".join(PackedStringArray(bits))
	return text.substr(0, 1).to_upper() + text.substr(1)


static func _ranges_text(ranges: Array) -> String:
	var bits: Array = []
	for r in ranges:
		bits.append("%d–%d" % [int(r.x), int(r.y)])
	return ", ".join(PackedStringArray(bits))
