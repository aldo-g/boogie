extends SceneTree

# Loaded at run time, not preloaded: Main.gd names the Net autoload, which
# is only registered once the tree is up.
var BotSimMain: GDScript

# ---------------------------------------------------------
# Balance harness — a dev tool, not shipped. Plays solo 18-hole rounds
# with GreedyBot through the real rules and writes one JSON line per
# round: the total, and per hole the strokes, wind, hazards, Form decay,
# bag, set tiers, every shot (club, distance, tier, card) and the draft.
#
#   BOTSIM_ROUNDS=200 BOTSIM_SEED=1 BOTSIM_OUT=/tmp/base.jsonl \
#     godot --headless --script res://scripts/BotSim.gd
#
# BOTSIM_VARIANT is a comma-separated list of changes for controlled
# experiments (default: none — the game as shipped):
#   decay=<p>            Form decay chance after a hazard (game: 0.333)
#   wind=off | wind=<n>  no wind, or cap it at n mph
#   norange              the bot never takes a range session
#   gift=<A>+<B>         start with these clubs added to the bag
#   blank=power|brand    ...stripped of their ability, or of their brand
#   starter=std          standard Driver / 7-Iron / Putter instead of Bogey-Mart
#   fixed=<k>            no draft: a fixed bag of k brandless clubs chosen
#                        for yardage coverage, plus a putter
#   putt=<ms>            the bot's putting timing error (default 100)
#   aim=<sd>             the bot's aim error, yards per 100 yds (default 0)
#
# Records are not written (the round runs as an editor test round), so
# the player's course records are untouched.
# ---------------------------------------------------------

const MAX_ACTIONS := 20000


func _initialize() -> void:
	var rounds := int(_env("BOTSIM_ROUNDS", "10"))
	var seed0 := int(_env("BOTSIM_SEED", "1"))
	var variant := _parse(_env("BOTSIM_VARIANT", ""))
	var out_path := _env("BOTSIM_OUT", "user://botsim.jsonl")
	BotSimMain = load("res://scripts/BotSimMain.gd")
	GameSetup.reset_to_local(1)
	GameSetup.return_to_editor = true

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("BotSim: cannot write %s" % out_path)
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var failures := 0
	for r in range(rounds):
		var rec := _play(seed0 + r, variant)
		if rec.is_empty():
			failures += 1
			continue
		rec["variant"] = _env("BOTSIM_VARIANT", "")
		f.store_line(JSON.stringify(rec))
		if (r + 1) % 10 == 0 or r == rounds - 1:
			print("%d/%d rounds  last=%d  (%.1fs/round)" % [r + 1, rounds, int(rec.total),
				(Time.get_ticks_msec() - t0) / 1000.0 / (r + 1)])
	f.close()
	quit(0 if failures == 0 else 1)


func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return fallback if v.is_empty() else v


func _parse(spec: String) -> Dictionary:
	var out := {}
	for part in spec.split(",", false):
		var kv := part.strip_edges().split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func _play(round_seed: int, v: Dictionary) -> Dictionary:
	seed(round_seed)
	var main = BotSimMain.new()
	main.player_count = 1
	if v.has("decay"):
		main.decay_chance = float(v.decay)
	if v.has("wind"):
		main.wind_cap = 0.0 if v.wind == "off" else float(v.wind)
	main.no_draft = v.has("fixed")
	get_root().add_child(main)
	main.build_ui()
	main.init_game()
	_shape_bag(main.players[0], v)
	main.start_hole()
	main.map_view.skip_animation = true

	var bot := GreedyBot.new(round_seed)
	bot.allow_range = not v.has("norange")
	if v.has("putt"):
		bot.putt_timing_sd = float(v.putt) / 1000.0
	if v.has("aim"):
		bot.aim_error = float(v.aim)
	var seen_holes := 1
	var hole_notes: Array = []
	var actions := 0
	while main.state != main.State.DONE and actions < MAX_ACTIONS:
		actions += 1
		if main.hole_log.size() != seen_holes:
			hole_notes.append(bot.notes)
			bot.reset_log()
			seen_holes = main.hole_log.size()
		if not bot.act(main):
			printerr("seed %d: stuck in state %d on hole %d" % [round_seed, main.state, main.current_hole_index])
			main.free()
			return {}
	hole_notes.append(bot.notes)
	if actions >= MAX_ACTIONS:
		printerr("seed %d: no finish after %d actions" % [round_seed, actions])
		main.free()
		return {}

	var p: Player = main.players[0]
	var holes: Array = []
	for i in range(p.round_scores.size()):
		var h: Dictionary = main.hole_log[i].duplicate()
		h.merge(p.round_scores[i], true)
		if i < hole_notes.size():
			h.merge(hole_notes[i], true)
		holes.append(h)
	var rec := {"seed": round_seed, "total": p.total_strokes(), "par": p.total_par(),
		"live": p.live_brands, "holes": holes,
		"final_bag": p.hand.map(func(c): return c.name)}
	main.free()
	return rec


# Applies the bag-shaping parts of the variant to the player's opening bag.
func _shape_bag(p: Player, v: Dictionary) -> void:
	if v.get("starter", "") == "std":
		p.hand = _named(["Driver", "7-Iron", "Putter"])
	if v.has("fixed"):
		p.hand = coverage_bag(int(v.fixed))
	if v.has("gift"):
		var gifts := _named(Array(str(v.gift).split("+")))
		for c in gifts:
			match v.get("blank", ""):
				"power":
					c.effects = {}
					c.ability = ""
					c.limited = false
				"brand":
					c.brand = Brands.NONE
			p.hand.append(c)
	ClubRoster.sort_bag(p.hand)


static func _roster() -> Array:
	var all: Array = ClubRoster.standard_clubs() + ClubRoster.limited_clubs()
	for b in Brands.DRAFTABLE:
		all.append_array(ClubRoster.branded_clubs(b))
	return all


static func _named(names: Array) -> Array:
	var out: Array = []
	var all := _roster()
	for n in names:
		for c in all:
			if c.name == n:
				out.append(c.duplicate(true))
				break
	return out


# k brandless, ability-free clubs picked greedily for yardage coverage
# (GreedyBot.bag_score with no sets in play is pure coverage), plus a
# putter. Bands come from the whole roster, so coverage is the best the
# game's clubs allow, not just the standards'.
static func coverage_bag(k: int) -> Array:
	var pool: Array = []
	var bands := {}
	for c in _roster():
		if c.type == "putter":
			continue
		var key := "%d-%d-%s" % [int(c.min_yard), int(c.max_yard), c.type]
		if bands.has(key):
			continue
		bands[key] = true
		var g: Dictionary = c.duplicate(true)
		g.brand = Brands.NONE
		g.effects = {}
		g.ability = ""
		g.limited = false
		pool.append(g)
	var bag: Array = _named(["Putter"])
	for i in range(k):
		var best := -1
		var best_score := -INF
		for j in range(pool.size()):
			var s := GreedyBot.bag_score(bag + [pool[j]])
			if s > best_score:
				best_score = s
				best = j
		bag.append(pool[best])
		pool.remove_at(best)
	return bag
