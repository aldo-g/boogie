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
#   Putt   — the meter's real bands (PuttMeter.bands) against a human-ish
#            timing error, so putting is neither perfect nor random.
#
# Abilities are spent greedily: when the saving on this shot clears a small
# threshold.
# ---------------------------------------------------------

const Tier := ShotResolver.Tier

# A human stopping the putt marker: timing error, standard deviation in
# seconds. 100 ms averages ~1.2 putts from 10 yds and ~1.6 from 30 — a
# steady amateur, inside the 1.1-2.0 Section 6 expects of a competent player.
var putt_timing_sd: float = 0.10
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

# What happened, for the harness. Reset with reset_log().
var notes: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value
	_build_putt_table()
	reset_log()


func reset_log() -> void:
	notes = {"shots": [], "created_seen": 0, "created_played": 0, "abilities": [],
		"range": false, "draft": "", "cut": ""}


# Plays one action for whoever is active. False when there is nothing to do.
func act(main) -> bool:
	match main.state:
		main.State.CLUB_SELECT:
			if _can(main, "improve_lie"):
				_use(main, "improve_lie")
				return true
			_plan = choose_shot(main)
			main.on_club_select(_plan.index)
		main.State.AIM:
			for id in _plan.get("arm", []):
				if _can(main, id) and not main.me.armed.has(id):
					_use(main, id)
			main._on_aim_picked(_misjudge(main, _plan.get("aim", main.hole.pin_pos)))
		main.State.FORM_DRAW:
			if _maybe_form_ability(main):
				return true
			main.on_form_pick(choose_form(main))
		main.State.DRAFT:
			var pick := choose_draft(main)
			if pick < 0:
				notes.range = true
				main.on_range_session()
			else:
				notes.draft = str(main.current_draft_options[pick].name)
				main.on_draft_pick(pick)
		main.State.DISCARD_FOR_DRAFT, main.State.DISCARD_FOR_HAZARD:
			var cut := choose_discard(main.hand, main.pending_new_card)
			notes.cut = str(main.hand[cut].name)
			main.on_discard_pick(cut)
		main.State.PUTTING:
			_arm_putt_abilities(main)
			var r := putt(main)
			main.on_putt_stopped(r[0], r[1])
		_:
			return false
	return true


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
	if s.hazard and ShotRules.hazard_can_decay_form(bag):
		cost += DECAY_COST
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


# The Form deck as the next draw sees it: [{card, p}], one entry per name.
func deck_mix(fd: FormDeck) -> Array:
	var pool: Array = fd.deck if fd.deck.size() >= 4 else fd.deck + fd.discard
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
		var total := 0.0
		for bad in FormCard.BAD_NAMES:
			total += minf(shot_cost(main, club, aim, FormCard.make(bad), lie, armed), cap)
		return total / FormCard.BAD_NAMES.size()
	var n := ShotRules.form_choice_count(bag, tier, lie)
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

	var mix := deck_mix(main.form_deck)
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
			var e := expected_shot(main, club, s.aim, armed, mix)
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
	if _can(main, "redraw"):
		var drawn := options.filter(func(c): return not c.created)
		var costs: Array = []
		var probs: Array = []
		for m in deck_mix(main.form_deck):
			costs.append(shot_cost(main, club, aim, m.card, lie, armed))
			probs.append(m.p)
		if best_now - expected_best(costs, probs, drawn.size()) > 0.08:
			_use(main, "redraw")
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

# [result, accuracy] for the putt in hand, as a human with a steady but
# imperfect stroke would stop the meter.
func putt(main) -> Array:
	var read := ShotResolver.putt_read(main.hole, main.ball_pos)
	var mult: float = read.band_mult * ShotRules.putt_band_mult(main.hand, main.putt_dist, main.me.armed)
	return _stroke(main.putt_dist, mult)


func _stroke(dist: float, band_mult: float) -> Array:
	var b := PuttMeter.bands(dist, band_mult)
	var offset: float = absf(rng.randfn(0.0, putt_timing_sd) * float(b.speed))
	offset = minf(offset, 0.5)
	var accuracy := clampf(1.0 - offset / 0.5, 0.0, 1.0)
	if offset <= b.sunk_half:
		return ["sunk", accuracy]
	if offset <= b.close_half:
		return ["close", accuracy]
	return ["miss", accuracy]


# Expected putts from each distance on flat ground under the same stroke
# model, built bottom up: every leave is shorter than the putt it came from.
func _build_putt_table() -> void:
	var n := 81  # 0 .. 40 yards in half yards
	_putts.resize(n)
	var samples := 300
	for i in range(n):
		var d := i * 0.5
		if ShotRules.is_gimme(d):
			_putts[i] = 1.0
			continue
		var total := 0.0
		for s in samples:
			var r := _stroke(d, 1.0)
			total += 1.0
			if r[0] == "sunk":
				continue
			var leave := ShotRules.putt_leave(r[0], r[1], d)
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
		match Brands.tier_reached(n):
			2:
				score += 2.5
			4:
				score += 6.0
			7:
				score += 10.0
	# Progress toward a set, for the brand the bag leans on most.
	score += 0.6 * top
	for c in bag:
		if ClubAbilities.power(c) != "":
			score += 2.5
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
	if allow_range and main.form_deck.bad_count() > 0:
		var bad: int = main.form_deck.bad_count()
		if bad >= range_bad_at or (bad >= range_bad_at - 1 and best_gain < range_weak_gain) \
				or best_gain <= 0.0:
			return -1
	return best


# Which club to cut so `incoming` fits: the one whose loss hurts least.
# Never the last putter.
static func choose_discard(bag: Array, incoming) -> int:
	var best := 0
	var best_score := -INF
	for i in range(bag.size()):
		var after: Array = bag.duplicate()
		after.remove_at(i)
		if incoming != null:
			after.append(incoming)
		var s := bag_score(after)
		if s > best_score:
			best_score = s
			best = i
	return best
