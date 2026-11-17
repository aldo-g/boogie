extends SceneTree

# ---------------------------------------------------------
# RULES HARNESS — the club roster and the rules of a stroke, with no
# screen and no Main.gd. Dev tool, not shipped.
#
#   godot --headless --script res://scripts/RulesTest.gd
#
# Checks:
#   1. clubs.json loads, and every club in it is well-formed
#   2. the draft pool is built the way Section 3B/3C say it is
#   3. swing tiers, and the Ping-Well bonuses that move them
#   4. how many Form cards a shot earns, bunkers and brands included
#   5. where the ground leaves the ball: OB, water, bunker, Shank
#   6. putting leaves always walk toward the hole
#   7. club effects in clubs.json are ones the rules know
#   8. club modifiers and set bonuses change the shot as their text says
#   9. ability charges, created cards and purges
#  10. Staff clubs sleep out of their set and wake in it
#  11. the signature shots, and the Form deck taking and giving them up
#  12. the draft's rules: the call, the dig, the trade-in
# ---------------------------------------------------------

const Tier := ShotResolver.Tier
const DraftRules := preload("res://scripts/DraftRules.gd")

var failures: Array = []


func _initialize() -> void:
	_check_roster()
	_check_pool()
	_check_tiers()
	_check_form_counts()
	_check_families()
	_check_settle()
	_check_putting()
	_check_effect_data()
	_check_modifiers()
	_check_abilities()
	_check_draft_advice()
	_check_breakdown()
	_check_staff()
	_check_top_tier()
	_check_signatures()
	_check_draft_rules()
	if failures.is_empty():
		print("\nRULES: OK")
	else:
		for f in failures:
			print("  !! " + f)
		print("\nRULES: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


# A bag holding `n` clubs of one brand, for switching set bonuses on.
func _brand_bag(brand: String, n: int) -> Array:
	return ClubRoster.branded_clubs(brand).slice(0, n)


func _all_clubs() -> Array:
	var all: Array = ClubRoster.starter_bag() + ClubRoster.standard_clubs() + ClubRoster.limited_clubs()
	for b in Brands.DRAFTABLE:
		all.append_array(ClubRoster.branded_clubs(b))
	return all


func _check_roster() -> void:
	var starter := ClubRoster.starter_bag()
	_expect(starter.size() == 3, "starter bag is 3 clubs (got %d)" % starter.size())
	_expect(starter.size() == 3 and starter[2].type == "putter", "starter bag racks the putter last")
	for c in starter:
		_expect(c.brand == Brands.STARTER, "%s is Bogey-Mart" % c.name)

	var names := {}
	for c in _all_clubs():
		_expect(["wood", "iron", "wedge", "putter"].has(c.type), "%s has a real type (%s)" % [c.name, c.type])
		_expect(c.min_yard <= c.max_yard, "%s band is min <= max" % c.name)
		_expect(c.type == "putter" or c.min_yard > 0.0, "%s has a carry band" % c.name)
		_expect(c.brand == Brands.NONE or c.brand == Brands.STARTER or Brands.DRAFTABLE.has(c.brand),
			"%s has a known brand (%s)" % [c.name, c.brand])
		_expect(not names.has(c.name), "club name %s is unique" % c.name)
		names[c.name] = true

	var limited_by_brand := {}
	for b in Brands.DRAFTABLE:
		# Section 3C: ten a brand (the top set has to be reachable), two of
		# them Staff clubs.
		var clubs := ClubRoster.branded_clubs(b)
		_expect(clubs.size() == 10, "%s has 10 clubs (got %d)" % [b, clubs.size()])
		_expect(clubs.filter(func(c): return ClubAbilities.is_staff(c)).size() == 2,
			"%s has 2 Staff clubs" % b)
		_expect(clubs.any(func(c): return c.type == "putter"), "%s makes a putter" % b)
	for c in ClubRoster.limited_clubs():
		_expect(c.limited, "%s is marked limited" % c.name)
		_expect(c.ability != "", "%s has ability text" % c.name)
		_expect(c.ability.contains("With ") or c.ability.contains("With a"), "%s has a pair rider" % c.name)
		limited_by_brand[c.brand] = int(limited_by_brand.get(c.brand, 0)) + 1
	for b in Brands.DRAFTABLE:
		_expect(int(limited_by_brand.get(b, 0)) == 2, "%s has 2 limited editions" % b)


func _check_pool() -> void:
	var standards := ClubRoster.standard_clubs().size()
	var copies := int(ClubRoster.data().get("standard_copies", 3))
	_expect(ClubRoster.build_pool([]).size() == standards * copies,
		"an empty brand list leaves only the standards")

	var live := ["titanist", "callowell", "pingwell", "nimbus"]
	var pool := ClubRoster.build_pool(live)
	# 24 standards, 40 branded, 8 limited: more than the 54 offers a round
	# deals, so a given club is not certain to come past.
	_expect(pool.size() == standards * copies + 40 + 8, "a 4-brand pool is 72 clubs (got %d)" % pool.size())
	for c in pool:
		_expect(c.brand != Brands.STARTER, "Bogey-Mart never enters the pool (%s)" % c.name)
		_expect(c.brand == Brands.NONE or live.has(c.brand), "%s is from a live brand" % c.name)

	for attempt in range(50):
		var brands := ClubRoster.roll_live_brands()
		var axes := {}
		for b in brands:
			axes[Brands.AXIS[b]] = true
		_expect(brands.size() == 4 and axes.size() >= 2, "live brands are 4 spanning 2+ axes (%s)" % [brands])

	# The pool is copies, not shared references: drafting one Driver must
	# not edit the others.
	var p2 := ClubRoster.build_pool([])
	p2[0].name = "edited"
	_expect(p2[standards].name != "edited", "standard copies are independent")


func _check_tiers() -> void:
	var club := ClubRoster.make_club("Test Iron", 100, 160, "iron")
	var plain: Array = []
	_expect(ShotRules.swing_tier(plain, club, 130) == Tier.MID, "middle of the band is MID")
	_expect(ShotRules.swing_tier(plain, club, 155) == Tier.FULL, "top third is FULL")
	_expect(ShotRules.swing_tier(plain, club, 105) == Tier.FINESSE, "bottom third is FINESSE")
	_expect(ShotRules.swing_tier(plain, club, 90) == Tier.EXTREME_FINESSE, "below the band is EXTREME_FINESSE")

	var putter := ClubRoster.make_club("Test Putter", 0, 0, "putter")
	_expect(ShotRules.swing_tier(plain, putter, 20) == Tier.MID, "a 0-0 band is always MID")

	# Ping-Well 2 widens MID to the middle half: 0.3 of the band is FINESSE
	# without it and MID with it.
	_expect(ShotRules.swing_tier(_brand_bag("pingwell", 2), club, 118) == Tier.MID, "Ping-Well 2 widens MID")
	_expect(ShotRules.swing_tier(_brand_bag("pingwell", 4), club, 155) == Tier.MID, "Ping-Well 4 lifts FULL to MID")
	_expect(ShotRules.swing_tier(_brand_bag("pingwell", 4), club, 90) == Tier.FINESSE, "Ping-Well 4 lifts EXTREME to FINESSE")
	_expect(ShotRules.upgrade_tier(_brand_bag("pingwell", Brands.top_tier), Tier.EXTREME_FINESSE) != Tier.EXTREME_FINESSE,
		"Ping-Well 8 abolishes EXTREME_FINESSE")


func _check_form_counts() -> void:
	var plain: Array = []
	_expect(ShotRules.form_choice_count(plain, Tier.MID, "fairway") == 3, "MID draws 3")
	_expect(ShotRules.form_choice_count(plain, Tier.FULL, "rough") == 2, "FULL draws 2")
	_expect(ShotRules.form_choice_count(plain, Tier.EXTREME_FINESSE, "fairway") == 1, "EXTREME is one forced card")
	_expect(ShotRules.form_choice_count(plain, Tier.MID, "bunker") == 1, "a bunker forces one card")
	_expect(ShotRules.form_choice_count(_brand_bag("macgregorian", 4), Tier.MID, "bunker") == 3,
		"MacGregorian 4 plays a bunker as the fairway")
	_expect(ShotRules.form_choice_count(_brand_bag("titanist", 4), Tier.MID, "fairway") == 4, "Titanist 4 draws +1")
	_expect(ShotRules.form_choice_count(_brand_bag("titanist", 2), Tier.MID, "fairway") == 3,
		"Titanist 2 bins the extra card, leaving the normal count")

	# The real draw agrees with the preview.
	var club := ClubRoster.make_club("Test Iron", 100, 160, "iron")
	for bag in [[], _brand_bag("titanist", 4), _brand_bag("slazinger", 4), _brand_bag("titanist", 2)]:
		for lie in ["fairway", "bunker"]:
			var deck := FormDeck.new()
			var drawn := ShotRules.draw_form(deck, bag, club, 130, lie)
			_expect(drawn.cards.size() == ShotRules.form_choice_count(bag, drawn.tier, lie),
				"draw_form matches form_choice_count (%d-club bag, %s)" % [bag.size(), lie])
			_expect(drawn.forced == ShotRules.is_forced(bag, drawn.tier, lie), "draw_form forced flag matches")

	var wood := ClubRoster.make_club("Test Wood", 180, 230, "wood")
	_expect(not ShotRules.club_playable([], wood, "bunker"), "woods can't be played from sand")
	_expect(ShotRules.club_playable([], wood, "rough"), "woods can be played from rough")
	_expect(is_equal_approx(ShotRules.lie_distance_cap([], "rough"), 0.8), "rough caps distance to 80%")
	_expect(is_equal_approx(ShotRules.lie_distance_cap(_brand_bag("callowell", 4), "bunker"), 1.0),
		"Callowell 4 ignores terrain penalties")


# A point on `hole` whose terrain is `kind`, found by sampling a grid —
# Vector2.INF if the hole has none.
# Section 4 "Form by club family": a swing is dealt only from the family
# of the club in hand, and each family keeps its own form.
func _check_families() -> void:
	# Every card starts in exactly one family, about two good to one bad.
	var start := FormDeck.new()
	var form := start.family_form()
	for fam in FormCard.FAMILIES:
		var good: int = form[fam].good
		var bad: int = form[fam].bad
		_expect(good >= 2 * bad - 2 and bad >= 2, "%s starts about two good to one bad (%d / %d)" % [fam, good, bad])
	for c in start.deck:
		_expect(FormCard.FAMILIES.has(c.family), "%s starts in a family" % c.name)

	# Deal after deal — through several reshuffles — every card belongs to
	# the club's family, and no card is lost or made.
	for club in [ClubRoster.make_club("Test Wood", 180, 230, "wood"),
			ClubRoster.make_club("Test Iron", 100, 160, "iron"),
			ClubRoster.make_club("Test Wedge", 40, 90, "wedge"),
			ClubRoster.make_club("Test Putter", 0, 35, "putter")]:
		var fam := FormCard.family_of(club)
		var deck := FormDeck.new()
		var total := deck.deck.size()
		var mid := (float(club.min_yard) + float(club.max_yard)) / 2.0
		var strays := 0
		for i in range(40):
			var drawn := ShotRules.draw_form(deck, [], club, mid, "fairway")
			for c in drawn.cards:
				strays += 0 if c.family == fam else 1
			deck.return_unpicked(drawn.cards, -1)
		_expect(strays == 0, "a %s swing is only dealt %s cards (%d strays)" % [fam, fam, strays])
		_expect(deck.deck.size() + deck.discard.size() == total, "dealing %s loses no cards" % fam)

	# A family's discards come back when that family runs out; the others'
	# stay where they are.
	var rd := FormDeck.new()
	var iron_drawn := rd.draw_cards(3, "iron")
	rd.return_unpicked(iron_drawn, -1)
	var wood_total: int = form["wood"].good + form["wood"].bad
	rd.return_unpicked(rd.draw_cards(wood_total, "wood"), -1)
	var again := rd.draw_cards(1, "wood")
	_expect(again[0].family == "wood", "a spent family reshuffles its own cards")
	var iron_in_discard := 0
	for c in rd.discard:
		iron_in_discard += 1 if c.family == "iron" else 0
	_expect(iron_in_discard == 3, "...and leaves the other families' discards alone (%d)" % iron_in_discard)

	# A bigger hand than the family holds borrows rather than deals nothing.
	var small := FormDeck.new()
	var putter_total: int = form["putter"].good + form["putter"].bad
	_expect(small.draw_cards(putter_total + 2, "putter").size() == putter_total + 2,
		"a draw bigger than the family still fills the hand")

	# A hazard's card joins the family of the club that found it, and is one
	# of that family's own misses.
	for fam in FormCard.FAMILIES:
		var hd := FormDeck.new()
		var before := hd.family_form()
		var added := hd.add_bad_card_to_deck("", fam)
		var after := hd.family_form()
		_expect(added.family == fam and not added.good and FormCard.FAMILY_BAD[fam].has(added.name),
			"a hazard leaves a %s miss in the %s form (%s)" % [fam, fam, added.name])
		for other in FormCard.FAMILIES:
			_expect(int(after[other].bad) == int(before[other].bad) + (1 if other == fam else 0),
				"...and only there (%s after a %s hazard)" % [other, fam])
	_expect(FormDeck.new().add_bad_card_to_deck("Skied").family == "wood", "a miss with no family goes to its home")

	# A bunker's forced card is the club family's own kind of miss.
	var sand := ShotRules.draw_form(FormDeck.new(), [], ClubRoster.make_club("Test Wedge", 40, 90, "wedge"), 60, "bunker")
	_expect(sand.forced and sand.cards[0].created and FormCard.FAMILY_BAD["wedge"].has(sand.cards[0].name),
		"sand forces a wedge miss on a wedge (%s)" % sand.cards[0].name)

	# A played card comes back round; a created one does not.
	var cyc := FormDeck.new()
	var cyc_total := cyc.deck.size()
	for i in range(60):
		var hand_i := ShotRules.draw_form(cyc, [], ClubRoster.make_club("Test Wood", 180, 230, "wood"), 205, "fairway")
		cyc.return_unpicked(hand_i.cards, 0)
		cyc.discard_played(hand_i.cards[0])
	_expect(cyc.deck.size() + cyc.discard.size() == cyc_total, "sixty shots leave the deck the size it started")
	cyc.discard_played(FormCard.make("Pure Strike").as_created())
	_expect(cyc.deck.size() + cyc.discard.size() == cyc_total, "a created card exhausts when played")

	# A purge with a family clears that family first, then any.
	var pd := FormDeck.new()
	var iron_bad := pd.bad_count("iron")
	var all_bad := pd.bad_count()
	pd.purge_bad(1, "iron")
	_expect(pd.bad_count("iron") == iron_bad - 1 and pd.bad_count() == all_bad - 1, "a family purge takes that family's card")
	pd.purge_bad(iron_bad - 1, "iron")
	_expect(pd.bad_count("iron") == 0, "...down to none")
	pd.purge_bad(1, "iron")
	_expect(pd.bad_count() == all_bad - iron_bad - 1, "...and then takes one from elsewhere")


func _find(hole: HoleData, kind: String) -> Vector2:
	var r := hole.bounds.grow(30.0)
	for yi in range(0, 120):
		for xi in range(0, 60):
			var p := r.position + Vector2(r.size.x * xi / 59.0, r.size.y * yi / 119.0)
			if hole.terrain_at(p) == kind:
				return p
	return Vector2.INF


func _check_settle() -> void:
	Course.use_builtin()
	var seen := {}
	for n in range(1, Course.hole_count() + 1):
		var hole := HoleData.hole(n)
		var fairway := _find(hole, "fairway")
		if fairway == Vector2.INF:
			continue
		for kind in ["out", "water", "bunker", "rough", "green", "fairway"]:
			var at := _find(hole, kind)
			if at == Vector2.INF:
				continue
			seen[kind] = true
			var s := ShotRules.settle(hole, fairway, at, false, [])
			_expect(s.terrain == kind, "settle reports %s on hole %d" % [kind, n])
			match kind:
				"out", "water":
					_expect(s.penalty == 1 and s.ball_pos == fairway and s.hazard,
						"%s is a penalty stroke and a replay (hole %d)" % [kind, n])
					_expect(s.lie == "fairway", "%s replays from the fairway it was struck from" % kind)
				"bunker":
					_expect(s.penalty == 0 and s.lie == "bunker" and s.hazard, "a bunker is a hazard lie")
				_:
					_expect(s.penalty == 0 and s.lie == kind and not s.hazard, "%s is a plain lie" % kind)
			# What it can cost the Form deck: a hazard one time in three, the
			# rough one in five (it isn't a hazard, but it isn't free), and
			# short grass nothing.
			var risk: float = ShotRules.FORM_DECAY_CHANCE if kind in ["out", "water", "bunker"] \
				else (ShotRules.ROUGH_DECAY_CHANCE if kind == "rough" else 0.0)
			_expect(is_equal_approx(float(s.form_risk), risk),
				"%s risks a bad card %.2f of the time, not %.2f (hole %d)" % [kind, float(s.form_risk), risk, n])

		# A Shank downgrades the lie, unless Callowell 8 blocks it.
		var shank := ShotRules.settle(hole, fairway, fairway, true, [])
		_expect(shank.lie_downgraded and shank.lie == ShotResolver.lie_downgrade("fairway"), "Shank downgrades the lie")
		_expect(is_equal_approx(float(shank.form_risk), ShotRules.FORM_DECAY_CHANCE), "a Shanked lie risks a card like a hazard")
		var blocked := ShotRules.settle(hole, fairway, fairway, true, _brand_bag("callowell", Brands.top_tier))
		_expect(not blocked.lie_downgraded and blocked.lie == "fairway", "Callowell 8 blocks the Shank downgrade")
	for kind in ["out", "water", "bunker", "rough", "green", "fairway"]:
		_expect(seen.has(kind), "the built-in course has some %s to test against" % kind)

	var pin := Vector2(0, 300)
	for roll in range(1, ShotResolver.HOLE_OUT_DIE):
		var d: float = ShotRules.rim_out_position(pin, pin + Vector2(2, 2), roll).distance_to(pin)
		_expect(d >= 1.0 - 0.001 and d <= 3.0 + 0.001 and not ShotRules.is_gimme(d),
			"a rim-out on %d leaves a real putt (%.2f yds)" % [roll, d])


func _check_putting() -> void:
	for start in [1.0, 3.0, 8.0, 20.0, 40.0]:
		for result in ["close", "miss"]:
			for acc in [0.0, 0.5, 1.0]:
				var leave := ShotRules.putt_leave(result, acc, start)
				_expect(leave <= start + 0.001, "a %s putt from %.0f never finishes further out (%.2f)" % [result, start, leave])
				# A close one may finish inside the gimme (and is conceded); a
				# miss always leaves something to play.
				_expect(result == "close" or leave >= ShotRules.GIMME_YARDS - 0.001,
					"a miss leaves at least a gimme (%.2f)" % leave)
				_expect(leave > 0.0, "a %s putt stays out of the hole" % result)
		_expect(ShotRules.yips_putt_leave(start) >= 1.0, "the Yips always leaves a putt")
	_expect(ShotRules.is_gimme(0.5) and not ShotRules.is_gimme(1.0), "the gimme is about 2 feet")
	_expect(ShotRules.yips_effect([], FormCard.make("Yips")) == ShotRules.Yips.TAINTS_PUTT, "the Yips taints a putt")
	_expect(ShotRules.yips_effect(_brand_bag("callowell", Brands.top_tier), FormCard.make("Yips")) == ShotRules.Yips.BLOCKED,
		"Callowell 8 shrugs off the Yips")
	_expect(ShotRules.yips_effect([], FormCard.make("Pure Strike")) == ShotRules.Yips.NONE, "other cards don't trigger it")


# --- Club abilities --------------------------------------------------

const KNOWN_EFFECTS := ["buffer", "rough_cap", "bunker_cap", "bunker_playable", "soft_mishits",
	"no_lie_downgrade", "mid_span", "bump_run_share", "categories", "blocks_form_decay",
	"fringe_putt", "big_strike_bonus", "putt_long_band", "putt_short_band", "steady_mult", "power",
	"draw_bonus", "trouble_draw", "severity", "bad_fate", "no_mid", "all_mid"]
const KNOWN_POWERS := ["gold_cleek", "bulger", "old_tom", "rutter", "old_reliable",
	"persimmon_spoon", "equaliser", "putt_retry", "lob_flop", "utility_any_lie",
	"surgeon", "gambler", "old_faithful", "metronome", "chameleon"]


func _club(name: String) -> Dictionary:
	for c in _all_clubs():
		if c.name == name:
			return c
	failures.append("no club named %s in clubs.json" % name)
	return ClubRoster.make_club(name, 100, 150, "iron")


func _check_effect_data() -> void:
	for c in _all_clubs():
		for key in c.effects:
			_expect(KNOWN_EFFECTS.has(key), "%s: unknown effect '%s'" % [c.name, key])
		for key in c.staff:
			_expect(KNOWN_EFFECTS.has(key) and key != "power", "%s: unknown staff effect '%s'" % [c.name, key])
		_expect(not ClubAbilities.is_staff(c) or c.ability.begins_with("Staff club"),
			"%s says it is a Staff club" % c.name)
		var pw := ClubAbilities.power(c)
		_expect(pw == "" or KNOWN_POWERS.has(pw), "%s: unknown power '%s'" % [c.name, pw])
	for pw in KNOWN_POWERS:
		var found := false
		for c in _all_clubs():
			found = found or ClubAbilities.power(c) == pw
		_expect(found, "some club carries the %s power" % pw)

	# Pure Strike, Big Strike and Steady Hands are created, never drawn.
	var deck := FormDeck.build_starting_deck()
	var good := 0
	for c in deck:
		_expect(not ["Pure Strike", "Big Strike", "Steady Hands"].has(c.name), "%s is not in the Form deck" % c.name)
		good += 1 if c.good else 0
	_expect(good == 35 and deck.size() == 53, "the Form deck is 35 good / 18 bad (%d / %d)" % [good, deck.size() - good])
	# Every card in the game can be made by name (decks travel online as
	# names), is on the list for its side, and has a caddy line.
	for n in FormCard.BAD_NAMES + FormCard.GOOD_NAMES:
		var c := FormCard.make(n)
		_expect(c.name == n and c.good == FormCard.GOOD_NAMES.has(n), "%s is made as itself" % n)
		_expect(preload("res://scripts/Caddy.gd").CARD_KEYS.has(n) or ["Steady Hands", "Yips"].has(n), "the caddy knows %s" % n)
	for fam in FormCard.FAMILIES:
		for n in FormCard.FAMILY_MIX[fam]:
			_expect(FormCard.BAD_NAMES.has(n) or FormCard.GOOD_NAMES.has(n), "%s in the %s mix is a real card" % [n, fam])
		for n in FormCard.FAMILY_BAD[fam]:
			_expect(FormCard.BAD_NAMES.has(n), "%s, a %s miss, is a bad card" % [n, fam])


func _degrees(bag: Array, club: Dictionary, card_name: String, lie: String = "fairway", armed: Dictionary = {}) -> float:
	return float(ShotRules.resolve(bag, club, 130, lie, FormCard.make(card_name), armed).degree)


func _distance(bag: Array, club: Dictionary, card_name: String, lie: String = "fairway", aim: float = 130) -> float:
	return float(ShotRules.resolve(bag, club, aim, lie, FormCard.make(card_name)).distance)


# The cards added for variety each do the one thing that makes them worth
# picking over their neighbours.
func _check_new_cards(plain: Dictionary) -> void:
	var stinger := _distance([], plain, "Stinger")
	_expect(_distance([], plain, "Flushed") > _distance([], plain, "Spinner"), "Flushed flies further than straight")
	_expect(_distance([], plain, "Power Draw") > _distance([], plain, "Controlled Draw"), "Power Draw flies further than Controlled Draw")
	_expect(_distance([], plain, "Soft Fade") < _distance([], plain, "Controlled Fade"), "Soft Fade gives up a little distance")
	_expect(_distance([], plain, "Punch Out", "rough") > _distance([], plain, "Stinger", "rough"), "Punch Out escapes the rough")
	_expect(stinger > 0.0, "Stinger still flies")
	_expect(_distance([], plain, "Overswing") > _distance([], plain, "Hook"), "Overswing goes long")
	_expect(_degrees([], plain, "Duck Hook") > _degrees([], plain, "Hook"), "a Duck Hook is worse than a Hook")
	_expect(_degrees([], plain, "Pull") < _degrees([], plain, "Hook"), "a Pull is milder than a Hook")
	var spin := ShotRules.resolve([], plain, 130, "fairway", FormCard.make("Spinner"))
	_expect(float(spin.roll_mult) < 0.5, "Spinner checks up")
	var skied := ShotRules.resolve([], plain, 130, "fairway", FormCard.make("Skied"))
	_expect(float(skied.flight) > 1.2, "Skied balloons in the wind")


func _check_modifiers() -> void:
	var plain := ClubRoster.make_club("Plain Iron", 120, 150, "iron")
	var titanist := _club("Titanist 6-Iron")
	var slazinger := _club("Slazinger Deep Iron")
	_expect(_degrees([], titanist, "Hook") < _degrees([], plain, "Hook"), "Titanist irons buffer better")
	_expect(_degrees([], slazinger, "Hook") > _degrees([], plain, "Hook"), "Slazinger irons buffer worse")
	_expect(_degrees([], plain, "Hook", "fairway", {"ideal_club": true}) < _degrees([], plain, "Hook"),
		"Nimbus 8's ideal club buffers like a wedge")

	var spoon := _club("MacGregorian Spoon")
	_expect(is_equal_approx(_distance([], spoon, "Stinger", "rough", 150), _distance([], spoon, "Stinger", "fairway", 150)),
		"MacGregorian Spoon takes no rough penalty")
	_expect(_distance([], _club("Titanist Pro Driver"), "Stinger", "rough", 200) < _distance([], _club("Driver"), "Stinger", "rough", 200),
		"Titanist Pro Driver suffers more in rough")
	_expect(_distance([], _club("Slazinger Blast Wedge"), "Stinger", "bunker", 60) > _distance([], _club("Sand Wedge"), "Stinger", "bunker", 60),
		"Slazinger Blast Wedge flies further from sand")

	var driver := _club("Driver")
	_expect(ShotRules.club_playable([], _club("MacGregorian Persimmon Driver"), "bunker"), "Persimmon Driver plays from sand")
	_expect(not ShotRules.club_playable([], driver, "bunker"), "a plain Driver doesn't")
	var persimmon_spoon := _club("Persimmon Spoon")
	_expect(not ShotRules.club_playable([persimmon_spoon], persimmon_spoon, "bunker"), "Persimmon Spoon alone can't play from sand")
	var mac_pair := [persimmon_spoon, _club("MacGregorian Mashie")]
	_expect(ShotRules.club_playable(mac_pair, persimmon_spoon, "bunker"), "Persimmon Spoon with a 2nd MacGregorian plays from sand")
	_expect(ClubAbilities.plays_clean(mac_pair, persimmon_spoon, "bunker", {}, 1) == "persimmon_spoon",
		"...and plays it as the fairway")

	# Big Strike flies the club's whole carry.
	var big := FormCard.make("Big Strike")
	_expect(is_equal_approx(ShotRules.resolve([], driver, 150, "rough", big).distance, driver.max_yard),
		"Big Strike flies max carry, ignoring the rough")
	var launch := _club("Slazinger Launch Wood")
	_expect(is_equal_approx(ShotRules.resolve([], launch, 150, "fairway", big).distance, launch.max_yard + 10),
		"Slazinger Launch Wood's Big Strike flies +10")

	_expect(_distance(_brand_bag("callowell", Brands.top_tier), plain, "Thin") > _distance([], plain, "Thin"), "Callowell 8 softens a Thin")
	_expect(is_equal_approx(_distance(_brand_bag("callowell", Brands.top_tier), plain, "Pull"), _distance([], plain, "Pull")),
		"Callowell 8 leaves a Pull's distance alone")
	_check_new_cards(plain)
	# Chunk and Top: half severity means half the distance loss.
	var chunk_plain := _distance([], plain, "Chunk")
	_expect(_distance(_brand_bag("callowell", Brands.top_tier), plain, "Chunk") > chunk_plain, "Callowell 8 softens a Chunk")
	_expect(_distance([], _club("Callowell Big Deal Driver"), "Chunk", "fairway", 200) > _distance([], driver, "Chunk", "fairway", 200),
		"Callowell Big Deal Driver softens a Chunk")

	# 143 yds is 0.3 of the way up a 130-175 band: Finesse in the middle
	# third, Mid in the middle half.
	_expect(ShotRules.swing_tier([], _club("Ping-Well i-Series 5"), 143) == Tier.MID,
		"a Ping-Well club's own rider widens its Mid tier")
	_expect(ShotRules.swing_tier([], ClubRoster.make_club("Plain 5", 130, 175, "iron"), 143) == Tier.FINESSE,
		"...where a plain club of the same band is Finesse")
	_expect(ShotRules.swing_tier([], plain, 155, {"boost_tier": true}) == Tier.MID, "Nimbus 2 lifts FULL to MID")
	_expect(ShotRules.swing_tier([], plain, 100, {"ideal_club": true}) == Tier.MID, "the ideal club is always MID")

	var brassie := _club("MacGregorian Brassie")
	_expect(is_equal_approx(ShotRules.resolve([], brassie, 160, "fairway", FormCard.make("Bump and Run")).run_share, 0.67),
		"the Brassie's Bump and Run runs two thirds")

	# The Equaliser: 3+ brands and it counts as every brand.
	var eq := _club("The Equaliser")
	var scattered := [eq, _club("Titanist 6-Iron"), _club("Callowell Rescue")]
	_expect(int(Brands.counts(scattered).get("pingwell", 0)) == 1, "the Equaliser counts as Ping-Well with 3 brands")
	_expect(int(Brands.counts(scattered).get("titanist", 0)) == 2, "...and as a second Titanist")
	_expect(int(Brands.counts([eq, _club("Titanist 6-Iron")]).get("pingwell", 0)) == 0, "but not with only 2 brands")

	# Nimbus 4: every club counts as every type for riders.
	var wedge := _club("Sand Wedge")
	_expect(not ClubAbilities.is_type([], wedge, "wood"), "a wedge is not a wood")
	_expect(ClubAbilities.is_type(_brand_bag("nimbus", 4), wedge, "wood"), "under Nimbus 4 it is")
	_expect(ClubAbilities.is_type([], _club("Nimbus Hybrid 5"), "wood"), "a Nimbus hybrid counts as a wood")

	_expect(not ShotRules.hazard_can_decay_form([_club("MacGregorian Niblick")]), "the MacGregorian Niblick blocks Form decay")
	_expect(ShotRules.putt_band_mult([_club("Callowell Mallet Putter")], 12.0) > 1.0, "the Callowell Mallet widens long putts")
	_expect(ShotRules.putt_band_mult([_club("Slazinger Heavy Putter")], 2.0) < 1.0, "the Slazinger Heavy Putter narrows short ones")
	var steady := ShotRules.putt_band_mult([], 8.0, {"old_reliable": true})
	_expect(steady > 1.0, "Steady Hands widens the band")
	_expect(ShotRules.putt_band_mult([_club("Ping-Well Mallet Putter")], 8.0, {"old_reliable": true}) > steady,
		"the Ping-Well Mallet makes Steady Hands wider still")


func _check_abilities() -> void:
	var cleek := _club("Gold Cleek")
	var bag := [cleek]
	var charges := {}
	var ctx := {"lie": "fairway", "club": cleek, "options": [], "charges": charges, "hole": 3}
	_expect(_ids(bag, "form", ctx).has("gold_cleek"), "Gold Cleek offers a Pure Strike")
	ClubAbilities.record(charges, "gold_cleek", 3)
	_expect(not _ids(bag, "form", ctx).has("gold_cleek"), "...once per hole")
	ctx.hole = 4
	_expect(_ids(bag, "form", ctx).has("gold_cleek"), "...and again next hole")
	var with_wood := [cleek, _club("Titanist Pro Driver")]
	ClubAbilities.record(charges, "gold_cleek", 4)
	_expect(_ids(with_wood, "form", ctx).has("gold_cleek"), "with a Titanist Wood, twice per hole")

	var reliable := _club("Old Reliable Putter")
	var rcharges := {}
	ClubAbilities.record(rcharges, "old_reliable", 2)
	var putt_ctx := {"charges": rcharges, "hole": 9}
	_expect(not _ids([reliable], "putting", putt_ctx).has("old_reliable"), "Old Reliable is once per round")
	_expect(_ids([reliable, _club("Ping-Well i-Series 5")], "putting", putt_ctx).has("old_reliable"),
		"...once every six holes with another Ping-Well")
	_expect(_ids([reliable] + _brand_bag("slazinger", Brands.top_tier), "putting", putt_ctx).has("old_reliable"),
		"...every hole under Slazinger 8")

	var bulger := _club("The Bulger")
	var bctx := {"lie": "fairway", "club": bulger, "options": [], "charges": {}, "hole": 1}
	_expect(not _ids([bulger], "form", bctx).has("bulger"), "The Bulger needs a bad lie...")
	bctx.lie = "rough"
	_expect(_ids([bulger], "form", bctx).has("bulger"), "...and offers a Big Strike from rough")
	bctx.lie = "fairway"
	_expect(_ids([bulger, _club("Sand Wedge")], "form", bctx).has("bulger"), "...or anywhere with a wedge in the bag")

	var titan7 := _brand_bag("titanist", Brands.top_tier)
	var hand := [FormCard.make("Hook")]
	_expect(_ids(titan7, "form", {"options": hand, "charges": {}, "hole": 1}).has("redraw"), "Titanist 8 can re-draw")
	_expect(not _ids(titan7, "form", {"options": [FormCard.make("Hook").as_created()], "forced": false,
		"charges": {}, "hole": 1}).has("redraw"), "...but not a hand of only created cards")
	_expect(_ids(_brand_bag("macgregorian", Brands.top_tier), "club_select", {"lie": "bunker", "charges": {}, "hole": 1}).has("improve_lie"),
		"MacGregorian 8 improves a bunker lie")
	_expect(ClubAbilities.lie_improved("bunker") == "rough" and ClubAbilities.lie_improved("rough") == "fairway",
		"a lie improves one step")

	# A created card turns a forced draw into a choice, and exhausts.
	var deck := FormDeck.new()
	var club := ClubRoster.make_club("Test Iron", 100, 160, "iron")
	var drawn := ShotRules.draw_form(deck, [], club, 130, "bunker", {}, ["Flop Shot"])
	_expect(drawn.cards.size() == 2 and not drawn.forced and drawn.had_forced_card,
		"a created Flop Shot beside a forced card is a choice")
	var before := deck.discard.size()
	deck.return_unpicked(drawn.cards, 1)
	_expect(deck.discard.size() == before, "neither the forced card nor the created one reaches the discard pile")
	_expect(ClubAbilities.draw_extras(_club("Ping-Well Lob Wedge"), "rough") == ["Flop Shot"],
		"the Lob Wedge brings a Flop Shot from rough")

	# Purges take the worst bad cards first.
	var pdeck := FormDeck.new()
	var bad_before := pdeck.bad_count()
	var purged := pdeck.purge_bad(2)
	_expect(purged.size() == 2 and pdeck.bad_count() == bad_before - 2, "purge_bad removes two bad cards")
	_expect(purged.has("Shank"), "the Shank goes first (%s)" % [purged])
	_expect(FormCard.make("In the Zone").purges_bad == 1, "In the Zone purges a bad card")

	# Landing passives.
	var tom := _club("Old Tom's Niblick")
	var land := ClubAbilities.on_landing([tom], "bunker", true, {}, 1)
	_expect(land.create == ["Flop Shot"], "Old Tom's Niblick: sand brings a Flop Shot")
	_expect(ClubAbilities.on_landing([tom], "fairway", false, {}, 1).create.is_empty(), "...the fairway nothing alone")
	_expect(ClubAbilities.on_landing([tom, _club("MacGregorian Brassie")], "fairway", false, {}, 1).create == ["Bump and Run"],
		"...a Bump and Run with a MacGregorian Wood")
	var rutter := _club("The Rutter")
	_expect(ClubAbilities.on_landing([rutter], "water", true, {}, 1).purge == 1, "The Rutter purges one per hazard")
	_expect(ClubAbilities.on_landing([rutter, _club("Callowell Rescue")], "water", true, {}, 1).purge == 2,
		"...two with a Callowell Iron")

	var utility := _club("Nimbus Utility Wedge")
	var ucharges := {}
	_expect(ClubAbilities.plays_clean([utility], utility, "rough", ucharges, 1) == "utility_any_lie", "the Utility Wedge plays rough clean")
	ClubAbilities.record(ucharges, "utility_any_lie", 1)
	_expect(ClubAbilities.plays_clean([utility], utility, "rough", ucharges, 1) == "", "...once per hole")


func _ids(bag: Array, phase: String, ctx: Dictionary) -> Array:
	return ClubAbilities.actives(bag, phase, ctx).map(func(e): return e.id)


# --- Draft advice and the shot breakdown --------------------------------

func _texts(lines: Array) -> String:
	return " | ".join(PackedStringArray(lines.map(func(l): return str(l.text))))


func _check_draft_advice() -> void:
	var three: Array = _brand_bag("titanist", 3)
	var fourth: Dictionary = ClubRoster.branded_clubs("titanist")[3]
	var g := _texts(DraftAdvisor.gains(three, fourth))
	_expect(g.contains("Completes your Titanist 4-set"), "a 4th Titanist completes the set (%s)" % g)
	_expect(DraftAdvisor.gains(three, fourth)[0].strong, "...and says so first")
	var two := _texts(DraftAdvisor.gains(_brand_bag("titanist", 1), ClubRoster.branded_clubs("titanist")[2]))
	_expect(two.contains("Completes your Titanist 2-set"), "a 2nd Titanist completes the 2-set (%s)" % two)
	var progress := _texts(DraftAdvisor.gains(_brand_bag("titanist", 2), ClubRoster.branded_clubs("titanist")[2]))
	_expect(progress.contains("3/4"), "a 3rd Titanist shows progress (%s)" % progress)

	var rider := _texts(DraftAdvisor.gains([_club("Gold Cleek")], _club("Titanist Pro Driver")))
	_expect(rider.contains("Switches on: Gold Cleek"), "a Titanist Wood switches on the Gold Cleek (%s)" % rider)

	var bag := [_club("Driver"), _club("7-Iron")]
	var gap := _texts(DraftAdvisor.gains(bag, _club("5-Iron")))
	_expect(gap.contains("145–170"), "a 5-Iron fills 145-170 above a 7-Iron (%s)" % gap)
	_expect(not _texts(DraftAdvisor.gains(bag + [_club("5-Iron")], _club("Titanist 6-Iron"))).contains("Fills"),
		"no gap claimed when the band is already covered")
	_expect(_texts(DraftAdvisor.gains(bag, _club("Sand Wedge"), 2)).contains("Bag is full"), "a full bag says so")

	var four: Array = _brand_bag("titanist", 4)
	var loss := _texts(DraftAdvisor.losses(four, four[0]))
	_expect(loss.contains("Breaks your Titanist 4-set"), "cutting from a 4-set breaks it (%s)" % loss)
	var putters := [_club("Driver"), _club("Putter")]
	_expect(_texts(DraftAdvisor.losses(putters, putters[1])).contains("only putter"), "cutting the only putter is flagged")
	_expect(_texts(DraftAdvisor.losses(bag, bag[1])).contains("Leaves a gap"), "cutting the 7-Iron leaves a gap")


func _check_breakdown() -> void:
	Course.use_builtin()
	var hole := HoleData.hole(1)
	var club := _club("7-Iron")
	var from := hole.tee_pos
	var aim := (hole.pin_pos - from).normalized()
	var result := ShotRules.resolve([], club, 130, "fairway", FormCard.make("Stinger"))

	hole.wind = Vector2.ZERO
	var calm_out := ShotResolver.shot_outcome(hole, from, aim, result, club)
	var calm := ShotRules.shot_breakdown(hole, from, aim, result, club, calm_out)
	_expect(absf(calm.wind_along) < 0.01 and absf(calm.wind_across) < 0.01, "no wind, no wind effect")
	_expect(is_equal_approx(calm.carry, calm_out.carry), "the breakdown's carry is the shot's carry")

	# Wind blowing back down the hole, into the player: a shorter carry.
	hole.wind = -aim * 20.0
	var into_out := ShotResolver.shot_outcome(hole, from, aim, result, club)
	var into := ShotRules.shot_breakdown(hole, from, aim, result, club, into_out)
	_expect(into.wind_along < -1.0, "a headwind costs carry (%.1f)" % into.wind_along)
	# Wind from the left, blowing right.
	hole.wind = Vector2(aim.y, -aim.x) * 20.0
	var cross := ShotRules.shot_breakdown(hole, from, aim, result, club,
		ShotResolver.shot_outcome(hole, from, aim, result, club))
	_expect(cross.wind_across > 1.0, "a left-to-right wind pushes it right (%.1f)" % cross.wind_across)
	var text := ShotRules.breakdown_text(cross)
	_expect(text.begins_with("Carried") and text.contains("right"), "the breakdown reads (%s)" % text)


# --- Staff clubs (Section 3C) --------------------------------------------

# `club` in a bag with three more of its maker's clubs: awake.
func _staff_bag(club: Dictionary) -> Array:
	var bag: Array = [club]
	for c in ClubRoster.branded_clubs(club.brand):
		if bag.size() < 4 and not ClubAbilities.is_staff(c):
			bag.append(c)
	return bag


func _check_staff() -> void:
	for b in Brands.DRAFTABLE:
		for c in ClubRoster.branded_clubs(b):
			if not ClubAbilities.is_staff(c):
				continue
			_expect(not ClubAbilities.is_awake([c], c), "%s is asleep on its own" % c.name)
			_expect(not ClubAbilities.is_awake(_staff_bag(c).slice(0, 3), c), "%s is asleep with 3 of its maker" % c.name)
			_expect(ClubAbilities.is_awake(_staff_bag(c), c), "%s wakes with 4 of its maker" % c.name)
	_expect(not ClubAbilities.is_staff(_club("Driver")) and not ClubAbilities.is_awake(_brand_bag("titanist", 4), _club("Titanist 4-Iron")),
		"an ordinary club is never a Staff club")

	# Titanist: one Form card fewer asleep, one more awake (on top of the
	# 4-set's own extra card).
	var t := _club("Titanist Staff 7-Iron")
	_expect(ShotRules.form_choice_count([t], Tier.MID, "fairway", 0, t) == 2, "a Titanist Staff club asleep draws one fewer")
	_expect(ShotRules.form_choice_count([t], Tier.FULL, "fairway", 0, t) == 1, "...and never fewer than one")
	_expect(ShotRules.form_choice_count(_staff_bag(t), Tier.MID, "fairway", 0, t) == 5, "awake it draws one more")
	_expect(ShotRules.form_choice_count(_staff_bag(t), Tier.MID, "fairway", 0, _club("Titanist 4-Iron")) == 4,
		"...and only with the Staff club itself")
	for bag in [[t], _staff_bag(t)]:
		var drawn := ShotRules.draw_form(FormDeck.new(), bag, t, 122, "fairway")
		_expect(drawn.cards.size() == ShotRules.form_choice_count(bag, drawn.tier, "fairway", 0, t),
			"a Staff club's real draw matches its preview (%d-club bag)" % bag.size())

	# Slazinger: bad cards hit 50% harder asleep; awake, no harder than
	# they would with no Slazinger in the bag at all.
	var s := _club("Slazinger Staff Iron")
	var plain_hook := _degrees([], _club("5-Iron"), "Hook")
	_expect(_degrees([s], s, "Hook") > plain_hook * 1.4, "a Slazinger Staff club asleep hits bad cards harder")
	_expect(is_equal_approx(_degrees(_staff_bag(s), s, "Hook"), plain_hook), "awake it cancels the Slazinger penalty")
	_expect(is_equal_approx(_degrees([s], s, "Controlled Draw"), _degrees([], _club("5-Iron"), "Controlled Draw")),
		"...and never touches a good card")

	# Ping-Well: no Mid tier asleep; awake, Mid everywhere — below its range too.
	var p := _club("Ping-Well Staff 7-Iron")
	_expect(ShotRules.swing_tier([p], p, 122) != Tier.MID and ShotRules.swing_tier([p], p, 124) != Tier.MID,
		"a Ping-Well Staff club asleep has no Mid tier")
	_expect(ShotRules.swing_tier([p], p, 60) == Tier.EXTREME_FINESSE, "...and still has a bottom to its range")
	for d in [60.0, 101.0, 122.0, 144.0]:
		_expect(ShotRules.swing_tier(_staff_bag(p), p, d) == Tier.MID, "awake it is Mid at %d yds" % int(d))
	_expect(ShotRules.swing_tier([], _club("The Metronome"), 40) == Tier.MID, "The Metronome is always Mid")

	# MacGregorian: poor from trouble asleep; awake, an extra card from it.
	var m := _club("MacGregorian Staff Cleek")
	_expect(is_equal_approx(ShotRules.lie_distance_cap([m], "rough", m), 0.5), "a MacGregorian Staff club asleep flies half from rough")
	_expect(is_equal_approx(ShotRules.lie_distance_cap(_staff_bag(m), "rough", m), 1.0), "awake the rough costs it nothing")
	_expect(ShotRules.form_choice_count(_staff_bag(m), Tier.MID, "rough", 0, m) == 4, "...and it draws one more from rough")
	_expect(ShotRules.form_choice_count(_staff_bag(m), Tier.MID, "fairway", 0, m) == 3, "...but not from the fairway")
	var baffy := _club("MacGregorian Staff Baffy")
	_expect(not ShotRules.club_playable([baffy], baffy, "bunker") and ShotRules.club_playable(_staff_bag(baffy), baffy, "bunker"),
		"the Staff Baffy plays from sand only once awake")

	# Callowell: what becomes of a bad card played with it.
	var c := _club("Callowell Staff Wedge")
	_expect(ClubAbilities.bad_fate([c], c) == "top" and ClubAbilities.bad_fate(_staff_bag(c), c) == "gone",
		"a Callowell Staff club sends a bad card back asleep and away awake")
	_expect(ClubAbilities.bad_fate(_staff_bag(c), _club("Callowell 6-Iron")) == "", "...and only the Staff club does")
	var top := FormDeck.new()
	var shank := FormCard.make("Shank").of_family("wedge")
	top.return_to_top(shank)
	_expect(top.draw_cards(1, "wedge")[0] == shank, "a card sent back on top is the next its family is dealt")

	# Nimbus: more deviation than a driver asleep, less than a wedge awake.
	var n := _club("Nimbus Staff Hybrid")
	_expect(ClubAbilities.buffer(n, [n]) > 1.0, "a Nimbus Staff club asleep lets through more than a driver")
	_expect(ClubAbilities.buffer(n, _staff_bag(n)) < 0.5, "awake, less than a wedge")
	_expect(is_equal_approx(ClubAbilities.buffer(n), ClubAbilities.buffer(n, [n])), "with no bag it reads as asleep")

	# The advice says so at the draft and at the cut.
	var three: Array = _brand_bag("titanist", 3)
	var taking := _texts(DraftAdvisor.gains(three, t))
	_expect(taking.contains("Completes your Titanist 4-set") and taking.contains("awake in this bag"),
		"a Staff club that completes the set is awake on arrival (%s)" % taking)
	_expect(_texts(DraftAdvisor.gains(_brand_bag("titanist", 1), t)).contains("asleep until you carry 4 Titanist (2/4)"),
		"a Staff club offered early says it is asleep")
	var waking := _texts(DraftAdvisor.gains(_brand_bag("titanist", 2) + [t], ClubRoster.branded_clubs("titanist")[2]))
	_expect(waking.contains("Wakes your Titanist Staff 7-Iron"), "the club that makes the set wakes the Staff club (%s)" % waking)
	var four := _staff_bag(t)
	_expect(_texts(DraftAdvisor.losses(four, four[1])).contains("Puts your Titanist Staff 7-Iron to sleep"),
		"cutting from the set puts it back to sleep")

	# The Chameleon counts as the brand the rest of the bag holds most of.
	var cham := _club("The Chameleon")
	var counted := Brands.counts(three + [cham])
	_expect(int(counted.get("titanist", 0)) == 4 and not counted.has("nimbus"), "the Chameleon makes a 4th Titanist (%s)" % [counted])
	counted = Brands.counts(three + [cham, _club("Nimbus Driver")])
	_expect(int(counted.get("titanist", 0)) == 4 and int(counted.get("nimbus", 0)) == 2,
		"with a Nimbus Wood it counts as both (%s)" % [counted])
	_expect(int(Brands.counts([cham]).get("nimbus", 0)) == 1, "alone it is a Nimbus club")


# --- Signature shots (Section 4 "Clubs bring their shots") ---------------

func _check_signatures() -> void:
	for b in Brands.DRAFTABLE:
		var shot: String = Brands.SIGNATURE.get(b, "")
		_expect(FormCard.SIGNATURE_NAMES.has(shot), "%s has a signature shot (%s)" % [b, shot])
		for c in ClubRoster.branded_clubs(b):
			_expect(Brands.signature(c) == ("" if c.type == "putter" else shot), "%s brings %s" % [c.name, shot])
	for c in ClubRoster.standard_clubs() + ClubRoster.starter_bag():
		_expect(Brands.signature(c) == "", "%s brings nothing" % c.name)
	for n in FormCard.SIGNATURE_NAMES:
		_expect(FormCard.make(n).good, "%s is a good card" % n)
		_expect(FormDeck.new().count_of(n) == 0, "%s is not in the deck a round starts with" % n)
	_expect(Brands.signature_family(_club("Titanist 4-Iron")) == "iron" and Brands.signature_family(_club("Nimbus Driver")) == "",
		"a signature shot joins its club's family; a Nimbus one joins none")
	_expect(Brands.baggage(_club("Slazinger Cannon Driver")) == "Duck Hook" and Brands.baggage(_club("Slazinger Power Iron")) == "Hook"
		and Brands.baggage(_club("Slazinger Heavy Putter")) == "" and Brands.baggage(_club("Titanist Pro Driver")) == "",
		"only Slazinger clubs bring a bad card, one of their family's")

	# The deck takes a card and gives it up again.
	var deck := FormDeck.new()
	var total := deck.deck.size()
	var iron_good: int = deck.family_form()["iron"].good
	deck.add_card("Knockdown", "iron")
	_expect(deck.deck.size() == total + 1 and int(deck.family_form()["iron"].good) == iron_good + 1
		and deck.count_of("Knockdown") == 1, "a club's shot joins its family")
	_expect(not deck.remove_card("Knockdown", "wood"), "...and is not taken from another family")
	_expect(deck.remove_card("Knockdown", "iron") and deck.deck.size() == total and not deck.remove_card("Knockdown", "iron"),
		"...and leaves when the club does")

	# A card of no family is part of every family's form and dealt to any.
	var wild := FormDeck.new()
	var before := wild.family_form()
	wild.add_card("Utility Swing", "")
	var after := wild.family_form()
	for fam in FormCard.FAMILIES:
		_expect(int(after[fam].good) == int(before[fam].good) + 1, "a Utility Swing counts in the %s form" % fam)
	var only := FormDeck.new()
	only.deck = []
	only.add_card("Utility Swing", "")
	_expect(only.draw_cards(1, "wedge")[0].name == "Utility Swing", "...and any swing can be dealt it")

	# What each of them does.
	var iron := _club("7-Iron")
	_expect(_distance([], iron, "Bomb") > _distance([], iron, "Flushed"), "a Bomb outflies a Flushed")
	_expect(_distance([], iron, "Knockdown") < _distance([], iron, "Spinner") and FormCard.make("Knockdown").flight < 0.8,
		"a Knockdown is short and low")
	_expect(is_equal_approx(_distance([], iron, "Safe Swing", "rough"), 130.0 * 0.9), "a Safe Swing takes no cut from rough")
	_expect(is_equal_approx(_distance([], iron, "Scotch Runner", "rough"), 130.0) and FormCard.make("Scotch Runner").roll_mult >= 2.0,
		"a Scotch Runner takes no cut and runs")
	# Stock Shot: pure from the Mid tier, a push from anywhere else. A 7-Iron
	# is 95-145: 120 is Mid, 140 Full.
	var stock := FormCard.make("Stock Shot")
	_expect(int(ShotRules.resolve([], iron, 120, "fairway", stock).degree) == 0, "a Stock Shot is straight from the Mid tier")
	var pushed := ShotRules.resolve([], iron, 140, "fairway", stock)
	_expect(int(pushed.degree) > 0 and pushed.side == ShotResolver.Side.FADE, "...and pushed from a full swing")
	_expect(ShotRules.card_for_shot([], iron, 140, stock).off_tier and not ShotRules.card_for_shot([], iron, 120, stock).off_tier,
		"the hand shows it as it will play")
	_expect(not stock.off_tier, "...without changing the card in the deck")
	var fitted := [_club("The Metronome"), _club("Ping-Well Driver")]
	_expect(int(ShotRules.resolve(fitted, iron, 140, "fairway", stock).degree) == 0,
		"The Metronome with a Ping-Well Wood strikes it pure from anywhere")
	_expect(int(ShotRules.resolve([_club("The Metronome")], iron, 140, "fairway", stock).degree) > 0, "...but not on its own")

	var bringing := _texts(DraftAdvisor.gains([], _club("Titanist 4-Iron")))
	_expect(bringing.contains("Brings a Knockdown to your iron form"), "the draft says what a club brings (%s)" % bringing)
	_expect(_texts(DraftAdvisor.gains([], _club("Slazinger Cannon Driver"))).contains("and a Duck Hook with it"),
		"...and what comes with it")
	_expect(_texts(DraftAdvisor.gains([], _club("Nimbus Driver"))).contains("every club's form"), "...and that a Nimbus shot is anyone's")


# --- The draft's rules (DraftRules.gd) ------------------------------------

# The top set: eight of a maker, where it was seven (Section 3A).
func _check_top_tier() -> void:
	_expect(Brands.top_tier == Brands.DEFAULT_TOP and Brands.tiers() == [2, 4, 8], "the tiers are 2 / 4 / 8")
	_expect(Brands.tier_reached(7) == 4 and Brands.tier_reached(8) == 8 and Brands.tier_reached(12) == 8,
		"seven of a maker is still the 4-set; eight is the top set")
	_expect(Brands.next_tier(7) == 8 and Brands.next_tier(8) == 0, "the next tier after 4 is 8")
	for b in Brands.DRAFTABLE:
		for t in Brands.tiers():
			_expect(Brands.bonus_text(b, t) != "" and Brands.stamp_text(b, t) != "", "%s has a bonus and a stamp at %d" % [b, t])
		_expect(not Brands.has_top(_brand_bag(b, 7), b) and Brands.has_top(_brand_bag(b, 8), b), "%s's top set needs eight" % b)
	var seven: Array = _brand_bag("titanist", 7)
	_expect(not Brands.can_redraw(seven) and Brands.can_redraw(_brand_bag("titanist", 8)), "Titanist's re-draw comes with the eighth club")
	var eighth := _texts(DraftAdvisor.gains(seven, ClubRoster.branded_clubs("titanist")[7]))
	_expect(eighth.contains("Completes your Titanist 8-set"), "the eighth Titanist completes the top set (%s)" % eighth)
	_expect(_ids(_brand_bag("titanist", 8), "form", {"options": [FormCard.make("Hook")], "charges": {}, "hole": 1}).has("redraw"),
		"...and its power is listed")


func _check_draft_rules() -> void:
	_expect(DraftRules.call_result(false, 3, 4) == "", "no call, no result")
	_expect(DraftRules.call_result(true, 3, 4) == DraftRules.MADE and DraftRules.call_result(true, 2, 4) == DraftRules.MADE,
		"a birdie or better makes the call")
	_expect(DraftRules.call_result(true, 4, 4) == DraftRules.MISSED, "a par misses it")

	var plain: Array = [_club("Driver"), _club("7-Iron"), _club("Putter")]
	_expect(DraftRules.offer_count(plain, "") == 3 and DraftRules.keep_count(plain, "") == 1, "a draft is three, keep one")
	_expect(DraftRules.offer_count(plain, DraftRules.MADE) == 5 and DraftRules.keep_count(plain, DraftRules.MADE) == 2,
		"a call made is five, keep two")
	_expect(DraftRules.offer_count(plain, DraftRules.MISSED) == 2 and DraftRules.keep_count(plain, DraftRules.MISSED) == 1,
		"a call missed is two, keep one")
	_expect(DraftRules.offer_count(plain, DraftRules.MADE) <= DraftRules.MAX_OFFERS, "the rack never shows more than its limit")

	var gambler: Array = plain + [_club("The Gambler")]
	_expect(DraftRules.keep_count(gambler, DraftRules.MADE) == 3 and DraftRules.offer_count(gambler, DraftRules.MISSED) == 2,
		"The Gambler keeps a third club from a call made")
	_expect(DraftRules.offer_count(gambler + [_club("Slazinger Launch Wood")], DraftRules.MISSED) == 3,
		"...and with a Slazinger Wood softens a call missed")

	_expect(DraftRules.can_dig(plain, 0, 0, 3) and DraftRules.dig_costs_card(plain), "one dig a draft, at the cost of a card")
	_expect(not DraftRules.can_dig(plain, 0, 1, 3) and not DraftRules.can_dig(plain, 1, 0, 3) and not DraftRules.can_dig(plain, 0, 0, 0),
		"no second dig, none after a pick, none of an empty rack")
	var faithful: Array = plain + [_club("Old Faithful")]
	_expect(not DraftRules.dig_costs_card(faithful) and DraftRules.dig_limit(faithful) == 1, "Old Faithful digs for nothing")
	_expect(DraftRules.dig_limit(faithful + [_club("Callowell Gap Wedge")]) == 2 and DraftRules.can_dig(faithful + [_club("Callowell Gap Wedge")], 0, 1, 3),
		"...and twice with a Callowell Wedge")

	_expect(DraftRules.can_trade(plain, 0, false, 3), "a club can be traded in for a fourth offer")
	_expect(not DraftRules.can_trade(plain, 0, true, 4) and not DraftRules.can_trade(plain, 1, false, 3),
		"one trade a draft, and not after a pick")
	_expect(not DraftRules.can_trade(plain, 0, false, DraftRules.MAX_OFFERS), "no trade into a full rack")
	_expect(not DraftRules.can_trade([_club("Putter")], 0, false, 3), "the last club can't be traded")

	# The new riders switch on at the draft like the old ones.
	_expect(_texts(DraftAdvisor.gains([_club("The Surgeon")], _club("Titanist 4-Iron"))).contains("Switches on: The Surgeon"),
		"a Titanist Iron switches on The Surgeon")
	_expect(_texts(DraftAdvisor.gains([_club("Old Faithful")], _club("Callowell Gap Wedge"))).contains("Switches on: Old Faithful"),
		"a Callowell Wedge switches on Old Faithful")
	var surgeon_ctx := {"options": [FormCard.make("Hook")], "charges": {}, "hole": 3}
	_expect(_ids([_club("The Surgeon")], "form", surgeon_ctx).has("surgeon"), "The Surgeon offers a re-draw")
	_expect(int(ClubAbilities.allowance([_club("The Surgeon")], "surgeon")[0]) == ClubAbilities.Period.ROUND
		and int(ClubAbilities.allowance([_club("The Surgeon"), _club("Titanist 4-Iron")], "surgeon")[0]) == ClubAbilities.Period.SIX_HOLES,
		"...once a round, or every six holes with a Titanist Iron")
