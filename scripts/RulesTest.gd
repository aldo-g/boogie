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
# ---------------------------------------------------------

const Tier := ShotResolver.Tier

var failures: Array = []


func _initialize() -> void:
	_check_roster()
	_check_pool()
	_check_tiers()
	_check_form_counts()
	_check_settle()
	_check_putting()
	_check_effect_data()
	_check_modifiers()
	_check_abilities()
	_check_draft_advice()
	_check_breakdown()
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

	for b in Brands.DRAFTABLE:
		# Section 3A: every brand must be able to reach a 7-set.
		_expect(ClubRoster.branded_clubs(b).size() >= 7, "%s has 7+ clubs" % b)
	for c in ClubRoster.limited_clubs():
		_expect(c.limited, "%s is marked limited" % c.name)
		_expect(c.ability != "", "%s has ability text" % c.name)


func _check_pool() -> void:
	var standards := ClubRoster.standard_clubs().size()
	var copies := int(ClubRoster.data().get("standard_copies", 3))
	_expect(ClubRoster.build_pool([]).size() == standards * copies,
		"an empty brand list leaves only the standards")

	var live := ["titanist", "callowell", "pingwell", "nimbus"]
	var pool := ClubRoster.build_pool(live)
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
	_expect(ShotRules.upgrade_tier(_brand_bag("pingwell", 7), Tier.EXTREME_FINESSE) != Tier.EXTREME_FINESSE,
		"Ping-Well 7 abolishes EXTREME_FINESSE")


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

		# A Shank downgrades the lie, unless Callowell 7 blocks it.
		var shank := ShotRules.settle(hole, fairway, fairway, true, [])
		_expect(shank.lie_downgraded and shank.lie == ShotResolver.lie_downgrade("fairway"), "Shank downgrades the lie")
		var blocked := ShotRules.settle(hole, fairway, fairway, true, _brand_bag("callowell", 7))
		_expect(not blocked.lie_downgraded and blocked.lie == "fairway", "Callowell 7 blocks the Shank downgrade")
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
	_expect(ShotRules.yips_effect(_brand_bag("callowell", 7), FormCard.make("Yips")) == ShotRules.Yips.BLOCKED,
		"Callowell 7 shrugs off the Yips")
	_expect(ShotRules.yips_effect([], FormCard.make("Pure Strike")) == ShotRules.Yips.NONE, "other cards don't trigger it")


# --- Club abilities --------------------------------------------------

const KNOWN_EFFECTS := ["buffer", "rough_cap", "bunker_cap", "bunker_playable", "soft_mishits",
	"no_lie_downgrade", "mid_span", "bump_run_share", "categories", "blocks_form_decay",
	"fringe_putt", "big_strike_bonus", "putt_long_band", "putt_short_band", "steady_mult", "power"]
const KNOWN_POWERS := ["gold_cleek", "bulger", "old_tom", "rutter", "old_reliable",
	"persimmon_spoon", "equaliser", "putt_retry", "lob_flop", "utility_any_lie"]


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
	_expect(good == 28 and deck.size() == 42, "the Form deck is 28 good / 14 bad (%d / %d)" % [good, deck.size() - good])
	# Every card in the game can be made by name (decks travel online as
	# names), is on the list for its side, and has a caddy line.
	for n in FormCard.BAD_NAMES + FormCard.GOOD_NAMES:
		var c := FormCard.make(n)
		_expect(c.name == n and c.good == FormCard.GOOD_NAMES.has(n), "%s is made as itself" % n)
		_expect(preload("res://scripts/Caddy.gd").CARD_KEYS.has(n) or ["Steady Hands", "Yips"].has(n), "the caddy knows %s" % n)
	for n in FormCard.DECK_MIX:
		_expect(FormCard.BAD_NAMES.has(n) or FormCard.GOOD_NAMES.has(n), "%s in the deck mix is a real card" % n)


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
		"Nimbus 7's ideal club buffers like a wedge")

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

	_expect(_distance(_brand_bag("callowell", 7), plain, "Thin") > _distance([], plain, "Thin"), "Callowell 7 softens a Thin")
	_expect(is_equal_approx(_distance(_brand_bag("callowell", 7), plain, "Pull"), _distance([], plain, "Pull")),
		"Callowell 7 leaves a Pull's distance alone")
	_check_new_cards(plain)
	# Chunk and Top: half severity means half the distance loss.
	var chunk_plain := _distance([], plain, "Chunk")
	_expect(_distance(_brand_bag("callowell", 7), plain, "Chunk") > chunk_plain, "Callowell 7 softens a Chunk")
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
	_expect(_ids([reliable] + _brand_bag("slazinger", 7), "putting", putt_ctx).has("old_reliable"),
		"...every hole under Slazinger 7")

	var bulger := _club("The Bulger")
	var bctx := {"lie": "fairway", "club": bulger, "options": [], "charges": {}, "hole": 1}
	_expect(not _ids([bulger], "form", bctx).has("bulger"), "The Bulger needs a bad lie...")
	bctx.lie = "rough"
	_expect(_ids([bulger], "form", bctx).has("bulger"), "...and offers a Big Strike from rough")
	bctx.lie = "fairway"
	_expect(_ids([bulger, _club("Sand Wedge")], "form", bctx).has("bulger"), "...or anywhere with a wedge in the bag")

	var titan7 := _brand_bag("titanist", 7)
	var hand := [FormCard.make("Hook")]
	_expect(_ids(titan7, "form", {"options": hand, "charges": {}, "hole": 1}).has("redraw"), "Titanist 7 can re-draw")
	_expect(not _ids(titan7, "form", {"options": [FormCard.make("Hook").as_created()], "forced": false,
		"charges": {}, "hole": 1}).has("redraw"), "...but not a hand of only created cards")
	_expect(_ids(_brand_bag("macgregorian", 7), "club_select", {"lie": "bunker", "charges": {}, "hole": 1}).has("improve_lie"),
		"MacGregorian 7 improves a bunker lie")
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
