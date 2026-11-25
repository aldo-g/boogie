class_name GreedyBot
extends RefCounted

# ---------------------------------------------------------
# A bot that plays sensibly — greedy, one decision at a time, through the
# same Main.gd entry points the UI calls. Two jobs:
#   - the balance harness (BotSim.gd): a player whose scores mean
#     something, so the open questions in GAME_DESIGN.md Section 9 can be
#     answered with numbers instead of guesses;
#   - a solo opponent, eventually: act(main) plays whoever is active.
#
# How it decides:
#   Shot   — every playable club against a spread of aim points (the pin,
#            around it, and up the fairway), each scored as expected
#            strokes to hole out: the best of the Form cards it will
#            actually get to choose from (tier draw count, deck contents,
#            created cards), using the game's own outcome and settle maths.
#            A cheap straight-card pass short-lists, a full pass decides.
#   Form   — the card whose known outcome costs fewest strokes.
#   Draft  — the club that most improves the bag: yardage coverage (Mid
#            tier worth most), set progress, and abilities. A range session
#            when the Form deck has soured and the draft offers little.
#   Hunt   — the draft's other moves (DraftRules.gd): it calls birdie on a
#            hole it fancies, trades in a club the bag would not miss, and
#            digs when the rack offers next to nothing.
#   Putt   — the aim that would hole it (ShotResolver.solve_putt), misread
#            a little on line and weight, so putting is neither perfect
#            nor random.
#
# Abilities are spent greedily: when the saving on this shot clears a small
# threshold.
# ---------------------------------------------------------

const Tier := ShotResolver.Tier
const DraftRules := preload("res://scripts/DraftRules.gd")
const Route := preload("res://scripts/Route.gd")

# How far out its read of a putt is (see _misread): 0.10 is a steady
# amateur, the rivals run 0.15 to 0.225.
var putt_error: float = 0.10
# Range session once the Form deck holds this many bad cards (it starts
# with 12)...
var range_bad_at: int = 15
# How well it judges a line: the standard deviation, in yards per 100
# yards of shot, of the gap between the aim it wanted and the aim it
# commits. 0 is a perfect read of wind, slope and roll (an upper bound on
# skill); a human misjudges them. Card choice stays exact either way, as
# the Form-card previews show the true outcome.
var aim_error: float = 0.0
# ...or one fewer bad card than that when the draft offers this little.
var range_weak_gain: float = 1.0
var allow_range: bool = true
# Whether it uses the draft's other moves at all (off for controlled runs).
var allow_hunt: bool = true
# It calls birdie when it rates its chance at least this. At 0.22 the
# scratch rival called nearly every hole (17 a round), which is a tic, not
# a decision; at three in ten a call means it fancies the hole.
var call_at: float = 0.30
# It digs when the best club on the rack improves the bag by less than
# this, and trades in a club whose loss would cost the bag less than that.
var dig_below: float = 0.5
var trade_below: float = 0.4
# From this many clubs in the bag, a stop other than the pro shop is worth
# taking for its own sake (choose_stop).
var late_bag_at: int = 11
# BotSim's `allout`: chase one maker's top set with everything it has —
# every club of that maker it is offered, and a dig, then a trade-in,
# whenever the rack shows none. No rival plays like this. It is the measure
# of whether the top set can be reached by a player who goes all out for
# it, and of what that costs in strokes.
var all_out: bool = false
var _chase: String = ""      # the maker it is chasing, once it has one
# Points scored per yard band in draft valuation, see bag_score().
const COVER_MIN := 25
const COVER_MAX := 235
const COVER_STEP := 5

# Expected strokes to hole out from the fairway, by distance — a typical
# mid-handicap shape. Rough and sand add on top (see value_at()).
const OFF_GREEN := [
	[0.0, 2.1], [10.0, 2.25], [30.0, 2.45], [60.0, 2.65], [100.0, 2.85],
	[150.0, 3.05], [200.0, 3.3], [250.0, 3.65], [300.0, 3.9], [350.0, 4.05],
	[400.0, 4.3], [450.0, 4.6], [500.0, 4.85], [550.0, 5.1], [650.0, 5.6],
]
const ROUGH_COST := 0.28
const BUNKER_COST := 0.6
# A hazard landing may sour the Form deck; what that costs, roughly.
const DECAY_COST := 0.04
const YIPS_OFF_GREEN_COST := 0.35
const ZONE_BONUS := 0.04

const SHORTLIST := 6

var rng := RandomNumberGenerator.new()
var _putts: PackedFloat32Array = PackedFloat32Array()  # expected putts, index = half-yards
var _plan: Dictionary = {}
var _planned: bool = false   # _plan was made ahead by plan_shot() for the shot now due
var _call_hole: int = -1     # the hole it last weighed a call on
var _last_gain: float = 0.0  # what the best club in the last draft it read was worth

# What happened, for the harness. Reset with reset_log().
var notes: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value
	_build_putt_table()
	reset_log()


func reset_log() -> void:
	notes = {"shots": [], "created_seen": 0, "created_played": 0, "abilities": [],
		"range": false, "draft": "", "cut": "", "called": false, "digs": 0, "trades": 0,
		"wears": 0, "boosts": 0, "stop": ""}


# Works out the next shot without playing it; act() then plays that plan
# instead of working it out again. This is the slow part of a turn (a few
# hundred milliseconds), so the game runs it on a worker thread while the
# bot "thinks". Safe there because it only reads the game and writes only
# to this bot — as long as nothing changes the game until it's done.
func plan_shot(main) -> void:
	_plan = choose_shot(main)
	_planned = true


# True when act() would spend a lie-improving ability before choosing a
# club, in which case the plan has to wait for the new lie.
func will_improve_lie(main) -> bool:
	return _can(main, "improve_lie")


# Where it means to aim the shot it has just chosen a club for, so a
# watcher can be shown the line before it commits.
func planned_aim(fallback: Vector2) -> Vector2:
	return _plan.get("aim", fallback)


# Plays one action for whoever is active. False when there is nothing to do.
func act(main) -> bool:
	match main.state:
		main.State.CLUB_SELECT:
			# On the tee, once a hole: is this one worth calling?
			if allow_hunt and _call_hole != main.current_hole_index and main.can_call_hole():
				_call_hole = main.current_hole_index
				if not main.me.called and birdie_chance(main) >= call_at:
					notes.called = true
					main.on_call_hole()
					return true
			if _can(main, "improve_lie"):
				_planned = false
				_use(main, "improve_lie")
				return true
			if not _planned:
				plan_shot(main)
			_planned = false
			main.on_club_select(_plan.index)
		main.State.AIM:
			for id in _plan.get("arm", []):
				if _can(main, id) and not main.me.armed.has(id):
					_use(main, id)
			main._on_aim_picked(_misjudge(main, _plan.get("aim", main.hole.pin_pos)))
		main.State.FORM_DRAW:
			var pick := form_step(main)
			if pick >= 0:
				main.on_form_pick(pick)
		main.State.DRAFT:
			# A club that is worn in: lose its miss if it has one to lose,
			# otherwise groove its first shot.
			var worn: int = main.wear_due()
			if worn >= 0:
				var choices := ClubAbilities.wear_choices(main.hand[worn])
				var gain := 0
				for i in range(choices.size()):
					if choices[i].kind == "drop":
						gain = i
				notes.wears += 1
				main.on_wear_in(worn, gain)
				return true
			# The fork after the hole (Route.gd), then what is done there.
			match str(main.me.draft_stop):
				"":
					var stop := choose_stop(main)
					notes.stop = str(Route.stops(main.wind_seed, main.current_hole_index)[stop])
					notes.range = notes.stop == Route.RANGE
					main.on_stop(stop)
					return true
				Route.FIT:
					var fit := _boost_move(main)
					if fit.is_empty():
						main.on_leave_stop()
					else:
						notes.boosts += 1
						main.on_boost(str(fit.boost), int(fit.index), 0)
					return true
				Route.HUT:
					if _wants_event(main):
						main.on_event()
					else:
						main.on_leave_stop()
					return true
			var move := choose_draft_move(main)
			match str(move.kind):
				"dig":
					notes.digs += 1
					main.on_dig()
				"trade":
					notes.trades += 1
					main.on_trade_in(int(move.index))
				"done":
					main.on_draft_done()
				_:
					var taken := str(main.current_draft_options[int(move.index)].name)
					notes.draft = taken if notes.draft == "" else "%s + %s" % [notes.draft, taken]
					main.on_draft_pick(int(move.index))
		main.State.DISCARD_FOR_DRAFT, main.State.DISCARD_FOR_HAZARD:
			# Going all out, never a club of the maker it is chasing.
			var cut := _cut_outside(main.hand, _chase, main.pending_new_card) if all_out and _chase != "" else -1
			if cut < 0:
				cut = choose_discard(main.hand, main.pending_new_card)
			notes.cut = str(main.hand[cut].name)
			main.on_discard_pick(cut)
		main.State.PUTTING:
			_arm_putt_abilities(main)
			main.on_putt(putt(main))
		_:
			return false
	return true


# The Form phase, without playing the card: uses an ability if one is
# worth it (returns -1 — the hand has changed, so ask again), otherwise
# returns the index of the card to play. Split from act() so a watcher can
# be shown the card before it's played.
func form_step(main) -> int:
	if _maybe_form_ability(main):
		return -1
	return choose_form(main)


# The committed aim: the one it wanted, misjudged by aim_error.
func _misjudge(main, aim: Vector2) -> Vector2:
	if aim_error <= 0.0:
		return aim
	var sd: float = aim_error * main.ball_pos.distance_to(aim) / 100.0
	return aim + Vector2(rng.randfn(0.0, sd), rng.randfn(0.0, sd))


# --- Valuing a position ---------------------------------------------------

# Expected strokes to hole out from `pos` on `lie`.
func value_at(main, pos: Vector2, lie: String) -> float:
	var d: float = pos.distance_to(main.hole.pin_pos)
	if lie == "green":
		return putts_from(d)
	var v := _lerp_table(OFF_GREEN, d)
	var bag: Array = main.hand
	if lie == "rough":
		v += ROUGH_COST * (0.3 if ShotRules.lie_distance_cap(bag, "rough") >= 1.0 else 1.0)
	elif lie == "bunker":
		v += BUNKER_COST * (0.3 if Brands.plays_as_fairway(bag) else 1.0)
	return v


func putts_from(d: float) -> float:
	var i := clampi(int(round(d * 2.0)), 0, _putts.size() - 1)
	return _putts[i]


static func _lerp_table(table: Array, x: float) -> float:
	if x <= table[0][0]:
		return table[0][1]
	for i in range(1, table.size()):
		if x <= table[i][0]:
			var a: Array = table[i - 1]
			var b: Array = table[i]
			return lerpf(a[1], b[1], (x - a[0]) / (b[0] - a[0]))
	var last: Array = table[table.size() - 1]
	return last[1] + (x - last[0]) * 0.005


# --- Valuing a shot -------------------------------------------------------

# Strokes this shot costs, the stroke itself included: 1 + penalties + the
# expected strokes from wherever it settles.
func shot_cost(main, club: Dictionary, aim: Vector2, card: FormCard, lie: String,
		armed: Dictionary) -> float:
	var bag: Array = main.hand
	var from: Vector2 = main.ball_pos
	var hole: HoleData = main.hole
	var result := ShotRules.resolve(bag, club, from.distance_to(aim), lie, card, armed)
	var dir := ShotRules.aim_direction(from, aim, hole.pin_pos)
	var out := ShotResolver.shot_outcome(hole, from, dir, result, club)
	var cost := 1.0
	if out.cup:
		# A natural 20 drops; otherwise a short rim-out putt.
		return cost + 0.95 * putts_from(2.0)
	var s := ShotRules.settle(hole, from, out.rest, result.downgrades_lie, bag, club)
	cost += float(s.penalty) + value_at(main, s.ball_pos, s.lie)
	# DECAY_COST is for a hazard's one-in-three; the rough's chance is lower.
	if float(s.form_risk) > 0.0 and ShotRules.hazard_can_decay_form(bag):
		cost += DECAY_COST * float(s.form_risk) / ShotRules.FORM_DECAY_CHANCE
	if ShotRules.yips_effect(bag, card) == ShotRules.Yips.TAINTS_PUTT:
		if s.lie == "green":
			var d: float = s.ball_pos.distance_to(hole.pin_pos)
			cost += 1.0 + putts_from(ShotRules.yips_putt_leave(d)) - putts_from(d)
		else:
			cost += YIPS_OFF_GREEN_COST
	if card.purges_bad > 0:
		cost -= ZONE_BONUS
	return cost


# The lie a club would play this shot from (some clubs play rough or sand
# clean — see Main.play_lie()).
func _lie_for(main, club: Dictionary, armed: Dictionary) -> String:
	if armed.has("clean_lie"):
		return "fairway"
	if ClubAbilities.plays_clean(main.hand, club, main.current_lie,
			main.me.ability_log, main.current_hole_index) != "":
		return "fairway"
	return main.current_lie


# The Form deck as the next draw of `family` sees it: [{card, p}], one
# entry per name. Only that family's cards are in it — a swing is dealt
# from no other (Section 4 "Form by club family").
func deck_mix(fd: FormDeck, family: String = "") -> Array:
	# A card with no family can be dealt to any (see FormDeck._in_family()).
	var of_family := func(c): return family == "" or c.family == family or c.family == ""
	var pool: Array = fd.deck.filter(of_family)
	if pool.size() < 4:
		pool = (fd.deck + fd.discard).filter(of_family)
	if pool.is_empty():
		pool = fd.deck + fd.discard
	var counts := {}
	for c in pool:
		counts[c.name] = int(counts.get(c.name, 0)) + 1
	var out: Array = []
	for n in counts:
		out.append({"card": FormCard.make(n), "p": float(counts[n]) / float(pool.size())})
	return out


# Expected cost of the best of `n` draws, given each card's cost. Treats
# the draws as independent (the deck is big enough for that to be close).
# `cap` is the cost of a created card already in hand: no draw can make
# the shot worse than playing that.
static func expected_best(costs: Array, probs: Array, n: int, cap: float = INF) -> float:
	if n <= 0:
		return cap
	var idx: Array = range(costs.size())
	idx.sort_custom(func(a, b): return costs[a] < costs[b])
	var e := 0.0
	var tail := 1.0  # P(every draw is at least this bad)
	for i in idx:
		var next_tail := maxf(tail - float(probs[i]), 0.0)
		var p_min_here := pow(tail, n) - pow(next_tail, n)
		e += p_min_here * minf(float(costs[i]), cap)
		tail = next_tail
	return e


# Expected cost of a declared shot, over the Form hand it will draw.
func expected_shot(main, club: Dictionary, aim: Vector2, armed: Dictionary, mix: Array) -> float:
	var bag: Array = main.hand
	var lie := _lie_for(main, club, armed)
	var dist: float = main.ball_pos.distance_to(aim)
	var tier := ShotRules.swing_tier(bag, club, dist, armed)
	var created: Array = main.me.created_next + ClubAbilities.draw_extras(club, main.current_lie)
	var cap := INF
	for cname in created:
		cap = minf(cap, shot_cost(main, club, aim, FormCard.make(cname), lie, armed))
	if ShotRules.is_forced(bag, tier, lie):
		# The forced card is one of the club family's own misses.
		var misses: Array = FormCard.bad_names_for(FormCard.family_of(club))
		var total := 0.0
		for bad in misses:
			total += minf(shot_cost(main, club, aim, FormCard.make(bad), lie, armed), cap)
		return total / misses.size()
	var n := ShotRules.form_choice_count(bag, tier, lie, 0, club)
	if Brands.drops_worst_draw(bag):
		n += 1
	var costs: Array = []
	var probs: Array = []
	for m in mix:
		costs.append(shot_cost(main, club, aim, m.card, lie, armed))
		probs.append(m.p)
	return expected_best(costs, probs, n, cap)


# Where it might aim: at and around the pin, and up the fairway.
func aim_points(main) -> Array:
	var hole: HoleData = main.hole
	var from: Vector2 = main.ball_pos
	var pin: Vector2 = hole.pin_pos
	var to_pin := (pin - from).normalized()
	if to_pin == Vector2.ZERO:
		to_pin = Vector2(0, 1)
	var side := Vector2(to_pin.y, -to_pin.x)
	var pts: Array = [pin]
	for along in [-8.0, 8.0, 16.0]:
		pts.append(pin + to_pin * along)
	for across in [-10.0, -5.0, 5.0, 10.0]:
		pts.append(pin + side * across)
	var y := from.y + 15.0
	while y < pin.y - 10.0:
		var cx := hole.centre_x_at(y)
		for dx in [-13.0, 0.0, 13.0]:
			pts.append(Vector2(cx + dx, y))
		y += 10.0
	return pts


# The shot to play: {index, aim, arm, cost}.
func choose_shot(main) -> Dictionary:
	var bag: Array = main.hand
	var from: Vector2 = main.ball_pos
	var hole: HoleData = main.hole
	var straight := FormCard.make("Pure Strike")
	var points := aim_points(main)
	var short: Array = []
	var cache := {}
	for i in main.playable_club_indices():
		var club: Dictionary = bag[i]
		var lo: float = float(club.min_yard)
		var seen := {}
		for p in points:
			var aim := ShotResolver.clamp_aim(p, from, float(club.max_yard), hole.bounds)
			var d := from.distance_to(aim)
			if d < 1.0 or d < lo * 0.6:
				continue
			var key := Vector2i(int(aim.x), int(aim.y))
			if seen.has(key):
				continue
			seen[key] = true
			short.append({"index": i, "aim": aim, "rough": _rough(main, club, aim, straight, cache)})
	short.sort_custom(func(a, b): return a.rough < b.rough)
	# The grid is coarse; look around the best few before short-listing.
	for s in short.slice(0, 4):
		var club: Dictionary = bag[s.index]
		var along: Vector2 = (s.aim - from).normalized()
		var across := Vector2(along.y, -along.x)
		for off in [across * 6.0, across * -6.0, along * 6.0, along * -6.0]:
			var aim := ShotResolver.clamp_aim(s.aim + off, from, float(club.max_yard), hole.bounds)
			short.append({"index": s.index, "aim": aim, "rough": _rough(main, club, aim, straight, cache)})
	short.sort_custom(func(a, b): return a.rough < b.rough)
	short = short.slice(0, SHORTLIST)

	var mixes := {}  # club family -> the deck as a swing of it sees it
	var toggles: Array = []
	for id in ["ideal_club", "boost_tier"]:
		if _can_aim_toggle(main, id):
			toggles.append(id)
	var best := {}
	for s in short:
		var club: Dictionary = bag[s.index]
		var options: Array = [[]] + toggles.map(func(t): return [t])
		for arm in options:
			var armed := {}
			for id in arm:
				armed[id] = true
			var fam := FormCard.family_of(club)
			if not mixes.has(fam):
				mixes[fam] = deck_mix(main.form_deck, fam)
			var e := expected_shot(main, club, s.aim, armed, mixes[fam])
			# A toggle has to earn its charge.
			if not arm.is_empty():
				e += 0.05
			if best.is_empty() or e < best.cost:
				best = {"index": s.index, "aim": s.aim, "arm": arm, "cost": e}
	if best.is_empty():
		# Nothing scored (shouldn't happen): play the first club at the pin.
		var idx: int = main.playable_club_indices()[0]
		best = {"index": idx, "aim": hole.pin_pos, "arm": [], "cost": 0.0}
	var c: Dictionary = bag[best.index]
	var aimed := from.distance_to(best.aim)
	var armed_now := {}
	for id in best.arm:
		armed_now[id] = true
	notes.shots.append({"club": c.name, "d": int(round(aimed)), "lie": main.current_lie,
		"tier": ShotRules.swing_tier(bag, c, aimed, armed_now)})
	return best



# The short-list score: a straight card's cost plus a flat charge for a
# swing tier that draws fewer cards. A straight card lands the same for
# every club of a type at the same lie cut, so `cache` shares the work.
func _rough(main, club: Dictionary, aim: Vector2, straight: FormCard, cache: Dictionary) -> float:
	var bag: Array = main.hand
	var lie := _lie_for(main, club, {})
	var cap := ShotRules.lie_distance_cap(bag, lie, club)
	var tier := ShotRules.swing_tier(bag, club, main.ball_pos.distance_to(aim))
	var pen := 0.0
	if ShotRules.is_forced(bag, tier, lie):
		pen = 0.6
	elif tier != Tier.MID:
		pen = 0.08
	var ck := "%s|%d|%d|%.2f|%s" % [club.type, int(aim.x * 2.0), int(aim.y * 2.0), cap, lie]
	if not cache.has(ck):
		cache[ck] = shot_cost(main, club, aim, straight, lie, {})
	return float(cache[ck]) + pen

func choose_form(main) -> int:
	var options: Array = main.current_form_options
	var lie: String = main.play_lie()
	var best := 0
	var best_cost := INF
	for i in range(options.size()):
		var cost := shot_cost(main, main.pending_club, main.aim_target, options[i], lie, main.me.armed)
		if cost < best_cost:
			best_cost = cost
			best = i
	var card: FormCard = options[best]
	if card.created:
		notes.created_played += 1
	if not notes.shots.is_empty():
		notes.shots[-1]["card"] = card.name
		notes.shots[-1]["n"] = options.size()
	return best


# --- Abilities -------------------------------------------------------------

func _can(main, id: String) -> bool:
	for e in main.available_abilities():
		if e.id == id and e.left > 0:
			return true
	return false


func _use(main, id: String) -> void:
	notes.abilities.append(id)
	main.on_ability(id)


# Aim-phase toggles are only listed once a club is in hand, so read the
# bag directly to decide whether to consider them while choosing.
func _can_aim_toggle(main, id: String) -> bool:
	var ok := false
	match id:
		"boost_tier":
			ok = Brands.can_boost_tier(main.hand)
		"ideal_club":
			ok = Brands.can_play_ideal(main.hand)
	return ok and ClubAbilities.uses_left(main.hand, main.me.ability_log, id, main.current_hole_index) > 0


# Spends a created-card ability or a re-draw when it's worth it. True if
# it acted (the Form hand changed, so choose again).
func _maybe_form_ability(main) -> bool:
	var options: Array = main.current_form_options
	if options.any(func(c): return c.created) and not _plan.get("seen_created", false):
		notes.created_seen += 1
		_plan["seen_created"] = true
	var lie: String = main.play_lie()
	var club: Dictionary = main.pending_club
	var aim: Vector2 = main.aim_target
	var armed: Dictionary = main.me.armed
	var best_now := INF
	for c in options:
		best_now = minf(best_now, shot_cost(main, club, aim, c, lie, armed))
	for id in ["gold_cleek", "bulger"]:
		if _can(main, id):
			var made := shot_cost(main, club, aim, FormCard.make(ClubAbilities.creates(id)), lie, armed)
			if best_now - made > 0.05:
				_use(main, id)
				if not _plan.get("seen_created", false):
					notes.created_seen += 1
					_plan["seen_created"] = true
				return true
	# A re-draw: the Titanist 7-set's, or The Surgeon's.
	var redraw_id := ""
	for id in ["redraw", "surgeon"]:
		if redraw_id == "" and _can(main, id):
			redraw_id = id
	if redraw_id != "":
		var drawn := options.filter(func(c): return not c.created)
		var costs: Array = []
		var probs: Array = []
		for m in deck_mix(main.form_deck, FormCard.family_of(club)):
			costs.append(shot_cost(main, club, aim, m.card, lie, armed))
			probs.append(m.p)
		if best_now - expected_best(costs, probs, drawn.size()) > 0.08:
			_use(main, redraw_id)
			return true
	return false


func _arm_putt_abilities(main) -> void:
	var d: float = main.putt_dist
	if main.yips_pending:
		# A tainted putt misses whatever happens; the retry is the only help.
		if _can(main, "putt_retry") and not main.me.armed.has("putt_retry"):
			_use(main, "putt_retry")
		return
	if d >= 2.0 and _can(main, "putt_retry") and not main.me.armed.has("putt_retry"):
		_use(main, "putt_retry")
	if d >= 3.0 and d <= 15.0 and _can(main, "old_reliable") and not main.me.armed.has("old_reliable"):
		_use(main, "old_reliable")


# --- Putting ----------------------------------------------------------------

# Where it aims the putt in hand: the aim that would hole it, as well as
# it can read it.
func putt(main) -> Vector2:
	var ball: Vector2 = main.ball_pos
	return _misread(ball, main.hole.pin_pos, ShotResolver.solve_putt(main.hole, ball))


# A read is out three ways, each scaled by putt_error: a wobble on any
# putt, a line that drifts with the length of it, and a misjudged share of
# the break; and the weight is out by a share of the length.
const READ_WOBBLE := 0.37   # yards
const READ_LINE := 0.011    # yards per yard of putt
const READ_BREAK := 0.44    # share of the break allowed for
const READ_WEIGHT := 0.26   # yards per yard of putt
# The break a putt has on a typical green, per yard: what the putt table
# below assumes, having no green to read.
const TYPICAL_BREAK := 0.04

func _misread(ball: Vector2, pin: Vector2, ideal: Vector2, typical: bool = false) -> Vector2:
	var d: float = ball.distance_to(pin)
	var line: Vector2 = (ideal - ball).normalized()
	var across := Vector2(line.y, -line.x)
	var to_pin: Vector2 = (pin - ball).normalized()
	var allowed: float = TYPICAL_BREAK * d if typical \
		else absf((ideal - pin).dot(Vector2(to_pin.y, -to_pin.x)))
	return ideal \
		+ across * rng.randfn(0.0, putt_error * (READ_WOBBLE + READ_LINE * d + READ_BREAK * allowed)) \
		+ line * rng.randfn(0.0, putt_error * READ_WEIGHT * d)


# Expected putts from each distance under the same misread, built bottom
# up on a flat green: there the ball goes straight to the aim and stops,
# so no roll has to be run.
func _build_putt_table() -> void:
	var n := 81  # 0 .. 40 yards in half yards
	_putts.resize(n)
	var samples := 300
	var pin := Vector2.ZERO
	for i in range(n):
		var d := i * 0.5
		if ShotRules.is_gimme(d):
			_putts[i] = 1.0
			continue
		var ball := Vector2(0, -d)
		var ideal := Vector2(0, ShotResolver.PUTT_IDEAL_PAST)
		var total := 0.0
		for s in samples:
			var aim := _misread(ball, pin, ideal, true)
			total += 1.0
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(pin, ball, aim)
			if ShotResolver.cup_takes(near.length(), near.distance_to(aim), 1.0):
				continue
			var leave: float = aim.length()
			if ShotRules.is_gimme(leave):
				total += 1.0
			else:
				total += _putts[clampi(int(round(leave * 2.0)), 0, i - 1)]
		_putts[i] = total / samples


# --- Drafting ---------------------------------------------------------------

# How good a bag is, in rough "yard bands covered" units: every 5 yards
# from 25 to 235 scores the best tier any club gives it (Mid 1, Full or
# Finesse ~0.6), plus set tiers and progress, plus abilities.
static func bag_score(bag: Array) -> float:
	var score := 0.0
	var has_putter := false
	for c in bag:
		if c.type == "putter":
			has_putter = true
	if not has_putter:
		score -= 100.0
	var slots := (COVER_MAX - COVER_MIN) / COVER_STEP + 1
	var best: Array = []
	best.resize(slots)
	best.fill(0.0)
	for c in bag:
		if c.type == "putter":
			continue
		# Irons and wedges forgive; a wood at the same tier slightly less.
		var forgive := 1.0 - 0.1 * (ShotResolver.buffer_for_club(c) - 0.5)
		# Only yardages inside the club's own band can score: below it is
		# Extreme Finesse, above it out of reach.
		var first := maxi(0, ceili((float(c.min_yard) - COVER_MIN) / COVER_STEP))
		var last := mini(slots - 1, floori((float(c.max_yard) - COVER_MIN) / COVER_STEP))
		for s in range(first, last + 1):
			var q := 0.0
			match ShotRules.swing_tier(bag, c, float(COVER_MIN + s * COVER_STEP)):
				Tier.MID:
					q = 1.0
				Tier.FULL:
					q = 0.62
				Tier.FINESSE:
					q = 0.58
			best[s] = maxf(best[s], q * forgive)
	for q in best:
		score += q
	var counts := Brands.counts(bag)
	var top := 0
	for b in counts:
		var n := int(counts[b])
		top = maxi(top, n)
		var tier := Brands.tier_reached(n)
		if Brands.is_top(tier):
			score += 10.0
		elif tier >= Brands.TIER_SET:
			score += 6.0
		elif tier >= Brands.TIER_PAIR:
			score += 2.5
	# Progress toward a set, for the brand the bag leans on most.
	score += 0.6 * top
	for c in bag:
		if ClubAbilities.power(c) != "":
			score += 2.5
		# A Staff club is a liability asleep and a prize awake.
		if ClubAbilities.is_staff(c):
			score += 2.0 if ClubAbilities.is_awake(bag, c) else -1.5
		# The shot a maker's club brings to the Form deck, and what comes with it.
		if Brands.signature(c) != "":
			score += 0.3
		if Brands.baggage(c) != "":
			score -= 0.4
		# What has been put into a club, and what is wrong with it.
		score += 0.5 * float(c.get("level", 0)) + 0.4 * float((c.get("boosts", []) as Array).size())
		if ClubAbilities.curse(c) != "":
			score -= 1.5
	return score


# Index into current_draft_options, or -1 for a range session.
func choose_draft(main) -> int:
	var bag: Array = main.hand
	var base := bag_score(bag)
	var best := -1
	var best_gain := -INF
	for i in range(main.current_draft_options.size()):
		var club: Dictionary = main.current_draft_options[i]
		var after: Array = bag + [club]
		if bag.size() >= main.HAND_CAP:
			after.remove_at(choose_discard(bag, club))
		var gain := bag_score(after) - base
		if gain > best_gain:
			best_gain = gain
			best = i
	_last_gain = best_gain
	return best


# The pro shop's next move: {kind, index} — "pick" a club, or one of the
# hunting moves (DraftRules.gd): "dig", "trade", "done".
func choose_draft_move(main) -> Dictionary:
	var p = main.me
	if all_out:
		var chasing := _all_out_move(main)
		if not chasing.is_empty():
			return chasing
	var pick := choose_draft(main)
	var gain := _last_gain
	if p.draft_taken > 0:
		# A called hole made keeps two: the second only if it earns its place.
		return {"kind": "pick", "index": pick} if gain > 0.0 and pick >= 0 else {"kind": "done"}
	if allow_hunt:
		var shown: int = main.current_draft_options.size()
		# A club the bag would not miss buys one more offer.
		if DraftRules.can_trade(main.hand, p.draft_taken, p.draft_traded, shown):
			var dead := _dead_club(main.hand)
			if dead >= 0:
				return {"kind": "trade", "index": dead}
		# A rack with next to nothing on it is worth a bad card to replace —
		# while the Form deck can still take one.
		if pick >= 0 and gain < dig_below \
				and DraftRules.can_dig(main.hand, p.draft_taken, p.draft_digs, shown) \
				and (not DraftRules.dig_costs_card(main.hand)
					or main.form_deck.bad_count() <= range_bad_at - 2):
			return {"kind": "dig"}
	return {"kind": "pick", "index": maxi(pick, 0)}


# Which of the two stops to take after this hole (an index into
# Route.stops): the pro shop unless the other is worth more than a club.
#   Fitting bay — to mend a curse, or once the bag is nearly full
#   Range       — once a quarter of the Form deck is bad cards
#   The hut     — once the bag is nearly full, for what it thinks a bargain
func choose_stop(main) -> int:
	var bag: Array = main.hand
	match str(Route.stops(main.wind_seed, main.current_hole_index)[1]):
		Route.FIT:
			var fit := _boost_move(main)
			if not fit.is_empty() and (bool(fit.mends) or bag.size() >= late_bag_at):
				return 1
		Route.RANGE:
			var deck: int = main.form_deck.deck.size() + main.form_deck.discard.size()
			if allow_range and bag.size() >= 6 and main.form_deck.bad_count() * 4 >= deck:
				return 1
		Route.HUT:
			if bag.size() >= late_bag_at and _wants_event(main):
				return 1
	return 0


# What it would do at the fitting bay: {boost, index, mends}, or {} for
# nothing. A curse the bench can mend comes first, then the club it has hit
# the most good shots with.
func _boost_move(main) -> Dictionary:
	var best := {}
	var most := -1
	for boost in main.me.draft_boosts:
		for i in range(main.hand.size()):
			var c: Dictionary = main.hand[i]
			if not ClubAbilities.can_boost(c, boost):
				continue
			var mends: bool = ClubAbilities.curse(c) != ""
			var worth := int(c.get("marks", 0)) + (100 if mends else 0)
			if worth > most:
				most = worth
				best = {"boost": boost, "index": i, "mends": mends}
	return best


# Whether it takes what the hut offers: a grooved shot or strokes in hand
# always, a cursed club while the bag has room, a coin toss never.
func _wants_event(main) -> bool:
	match Route.event(main.wind_seed, main.current_hole_index, main.plays_for_keeps()):
		"gorse":
			return main.hand.size() < main.HAND_CAP
		"hustler":
			return false
	return true


# Going all out for one maker's top set: the move that serves the chase, or
# {} to draft as usual (nothing to chase with on this rack, or the set is in).
func _all_out_move(main) -> Dictionary:
	var bag: Array = main.hand
	var options: Array = main.current_draft_options
	var counts := Brands.counts(bag)
	# It chases the live maker it holds most of — the first one it is
	# offered, to begin with.
	if _chase == "":
		var most := 0
		for b in main.live_brands:
			if int(counts.get(b, 0)) > most:
				most = int(counts[b])
				_chase = b
	if _chase == "":
		for i in range(options.size()):
			if main.live_brands.has(options[i].get("brand", "")):
				_chase = options[i].brand
				return {"kind": "pick", "index": i}
		return {}
	var held := int(counts.get(_chase, 0))
	if held >= Brands.top_tier:
		return {}
	# Any club that adds to the count is taken (a wild card counts).
	for i in range(options.size()):
		if int(Brands.counts(bag + [options[i]]).get(_chase, 0)) > held:
			return {"kind": "pick", "index": i}
	var p = main.me
	if p.draft_taken > 0:
		return {}
	# Nothing for the chase on the rack: dig for it, then trade in for one
	# more look — while the Form deck can still take the card a dig costs.
	var shown: int = options.size()
	if DraftRules.can_dig(bag, p.draft_taken, p.draft_digs, shown) \
			and (not DraftRules.dig_costs_card(bag) or main.form_deck.bad_count() <= range_bad_at - 2):
		return {"kind": "dig"}
	if bag.size() >= 5 and DraftRules.can_trade(bag, p.draft_taken, p.draft_traded, shown):
		var cut := _cut_outside(bag, _chase)
		if cut >= 0:
			return {"kind": "trade", "index": cut}
	return {}


# The club to give up that is not one of `maker`'s (nor a wild card counting
# as one): the one whose loss hurts the bag least, or -1.
func _cut_outside(bag: Array, maker: String, incoming = null) -> int:
	var held := int(Brands.counts(bag).get(maker, 0))
	var best := -1
	var best_score := -INF
	for i in range(bag.size()):
		var after: Array = bag.duplicate()
		after.remove_at(i)
		if int(Brands.counts(after).get(maker, 0)) < held or not DraftRules.can_leave(bag, i, incoming):
			continue
		if incoming != null:
			after.append(incoming)
		var s := bag_score(after)
		if s > best_score:
			best_score = s
			best = i
	return best


# A club whose loss would cost the bag less than trade_below, or -1.
func _dead_club(bag: Array) -> int:
	if bag.size() < 4:
		return -1
	var base := bag_score(bag)
	var best := -1
	var least := trade_below
	for i in range(bag.size()):
		if not DraftRules.can_leave(bag, i):
			continue
		var after: Array = bag.duplicate()
		after.remove_at(i)
		var loss := base - bag_score(after)
		if loss < least:
			least = loss
			best = i
	return best


# Its chance of a birdie or better on the hole in front of it, roughly:
# how good a player it is, how gettable the hole is for its length and
# par, and how much of a bag it has to play it with. A rule of thumb, set
# against what BotSim's medium rival actually makes on Bogey Links (about
# one hole in five on the front nine, one in three on the back, and one in
# two on a par 5 with a full bag).
func birdie_chance(main) -> float:
	var expected := _lerp_table(OFF_GREEN, main.hole.tee_pos.distance_to(main.hole.pin_pos))
	var skill := 0.50 - 0.016 * aim_error - 1.1 * (putt_error - 0.10)
	var bag := 0.012 * float(maxi(main.hand.size() - 3, 0))
	return clampf(skill + bag + 0.3 * (float(main.hole_par) - expected), 0.0, 0.9)


# Which club to cut so `incoming` fits: the one whose loss hurts least.
# Never the last putter.
static func choose_discard(bag: Array, incoming) -> int:
	var best := -1
	var best_score := -INF
	for i in range(bag.size()):
		# A bag keeps its only putter (DraftRules.can_leave).
		if not DraftRules.can_leave(bag, i, incoming):
			continue
		var after: Array = bag.duplicate()
		after.remove_at(i)
		if incoming != null:
			after.append(incoming)
		var s := bag_score(after)
		if s > best_score:
			best_score = s
			best = i
	return maxi(best, 0)
