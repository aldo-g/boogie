extends SceneTree

const TestBags := preload("res://scripts/TestBags.gd")

# ---------------------------------------------------------
# Headless flow harness for hot-seat rounds — a dev tool, not shipped
# behaviour. Drives full 18-hole rounds for 1..4 players through the REAL
# Main.gd entry points the UI calls, and asserts that:
#   - every player finishes all 18 holes
#   - the turn order is always "furthest from the pin plays first"
#   - bags stay within [3, HAND_CAP]
#   - nobody is offered a draft after the last hole
#   - the round actually terminates
#
#   godot --headless --script res://scripts/MPTest.gd
#   MPTEST_COUNTS=3,4 godot --headless --script res://scripts/MPTest.gd
#
# It plays randomly rather than well, so stroke totals are meaningless —
# this checks the flow, not the balance. CourseMapView.skip_animation is
# set so shots resolve with no tween, which is what makes a 4-player round
# finish in seconds instead of ~15 minutes of real-time ball flight.
# ---------------------------------------------------------

const MAX_ACTIONS := 300000


func _initialize() -> void:
	var all_ok := true
	for count in _counts_from_env():
		if not _run_round(count):
			all_ok = false
		# Alone, the round is for keeps: random play must run out of strokes
		# in hand and be stopped before the last hole.
		if count == 1 and not _run_round(1, true):
			all_ok = false
	if not _check_tour():
		all_ok = false
	print("\nALL ROUNDS: %s" % ("OK" if all_ok else "FAIL"))
	quit(0 if all_ok else 1)


# The tour: a second course starts with the bag carried from the first,
# a Form deck built from it, and a tighter allowance.
func _check_tour() -> bool:
	GameSetup.start_tour()
	GameSetup.tour_leg = 1
	var kept: Array = TestBags.loadout(0).slice(0, 5)
	kept[0]["level"] = 1
	GameSetup.tour_bag = kept
	GameSetup.tour_brands = ["titanist", "callowell", "pingwell", "nimbus"]
	var main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(main)
	if main.players.is_empty():
		main.player_count = 1
		Course.use_shipped(main.TOUR[1])
		main.build_ui()
		main.init_game()
		main._apply_tour_carry()
		main.begin_round()
	var problems: Array = []
	if main.hand.size() != kept.size() or int(main.hand.filter(func(c): return c.name == kept[0].name)[0].get("level", 0)) != 1:
		problems.append("the bag did not travel (%d clubs)" % main.hand.size())
	if main.strokes_allowance() != main.STROKES_IN_HAND - main.TOUR_TIGHTEN:
		problems.append("the second course allows %d strokes in hand" % main.strokes_allowance())
	var owned := 0
	for c in main.form_deck.deck:
		owned += 1 if c.owner != "" else 0
	if owned == 0:
		problems.append("the Form deck was not built from the bag")
	if main.club_deck.any(func(c): return main.hand.any(func(h): return h.name == c.name)):
		problems.append("the draft pool offers a club already in the bag")
	if Course.active_name == Course.BUILTIN_NAME:
		problems.append("the second course is still %s" % Course.active_name)
	print("tour carry -> %s" % ("OK" if problems.is_empty() else "FAIL: " + "; ".join(problems)))
	main.free()
	GameSetup.reset_to_local(1)
	Course.use_builtin()
	return problems.is_empty()


func _counts_from_env() -> Array:
	var raw := OS.get_environment("MPTEST_COUNTS")
	if raw.is_empty():
		return [1, 2, 3, 4]
	var out: Array = []
	for part in raw.split(","):
		var n := int(part.strip_edges())
		if n >= 1 and n <= 4:
			out.append(n)
	return out if not out.is_empty() else [1, 2, 3, 4]


func _run_round(count: int, keeps: bool = false) -> bool:
	GameSetup.player_count = count
	var main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(main)
	# add_child() from _initialize() queues _ready() for the next frame,
	# and this harness never yields one — so run the game's own setup
	# directly. These are exactly the calls Main._ready() makes.
	if main.players.is_empty():
		main.player_count = count
		main.build_ui()
		main.init_game()
		main.begin_round()

	if main.players.size() != count:
		print("players=%d -> FAIL (built %d players)" % [count, main.players.size()])
		main.free()
		return false

	main.map_view.skip_animation = true
	main.for_keeps = keeps
	# Seat 0 keeps the drafted starter bag; the rest carry ability
	# loadouts, so a group round exercises every club ability too.
	for i in range(1, main.players.size()):
		main.players[i].hand = TestBags.loadout(i - 1)

	var ok := true
	var order_violations := 0
	var late_drafts := 0
	var actions := 0

	while main.state != main.State.DONE and actions < MAX_ACTIONS:
		actions += 1
		if not _turn_order_holds(main):
			order_violations += 1
		if main.current_hole_index >= Course.hole_count() \
				and (main.state == main.State.DRAFT or main.state == main.State.DISCARD_FOR_DRAFT):
			late_drafts += 1
		if not _step(main):
			print("players=%d -> FAIL (stuck in state %d on hole %d)" % [
				count, main.state, main.current_hole_index])
			ok = false
			break

	if actions >= MAX_ACTIONS:
		print("players=%d -> FAIL (no termination after %d actions, hole %d state %d)" % [
			count, MAX_ACTIONS, main.current_hole_index, main.state])
		ok = false

	if ok:
		for p in main.players:
			if keeps:
				if not main._run_over or p.round_scores.size() >= Course.hole_count():
					print("  !! for keeps, %s played %d holes and was not stopped" % [p.name, p.round_scores.size()])
					ok = false
			elif p.round_scores.size() != Course.hole_count():
				print("  !! %s scored %d holes, expected %d" % [p.name, p.round_scores.size(), Course.hole_count()])
				ok = false
			if p.hand.size() < 3 or p.hand.size() > main.HAND_CAP:
				print("  !! %s bag is %d clubs (cap %d)" % [p.name, p.hand.size(), main.HAND_CAP])
				ok = false
		if order_violations > 0:
			print("  !! %d turn-order violations (someone was up who wasn't furthest out)" % order_violations)
			ok = false
		if late_drafts > 0:
			print("  !! a draft was offered after the last hole (%d actions), with no shot left to play the club" % late_drafts)
			ok = false

	var totals: Array = []
	for p in main.players:
		totals.append("%s=%d" % [p.name, p.total_strokes()])
	print("players=%d%s -> %s  (%d actions)  %s" % [
		count, " for keeps" if keeps else "", "OK" if ok else "FAIL", actions, ", ".join(totals)])

	main.free()
	return ok


# While anyone is still playing the hole, the active player must be the one
# furthest from the pin (Section 7). Drafts are exempt — they run in
# seating order once everybody is in.
func _turn_order_holds(main) -> bool:
	if main.player_count <= 1:
		return true
	if main.state == main.State.DRAFT or main.state == main.State.DISCARD_FOR_DRAFT:
		return true
	if main.me.holed_out:
		return true
	var mine: float = main.me.distance_to(main.hole.pin_pos)
	for p in main.players:
		if p.holed_out:
			continue
		if p.distance_to(main.hole.pin_pos) > mine + 0.01:
			return false
	return true


# Performs one action for the current state. Returns false if the state
# offers nothing to do, which means the flow is stuck.
func _step(main) -> bool:
	var ability := TestBags.pick_ability(main, 0.3)
	if ability != "":
		main.on_ability(ability)
		return true
	var stop := TestBags.stop_move(main)
	if not stop.is_empty():
		main._apply_action(stop.kind, stop.payload)
		return true
	var hunt := TestBags.pick_hunt(main, 0.25)
	if not hunt.is_empty():
		main._apply_action(hunt.kind, hunt.payload)
		return true
	match main.state:
		main.State.CLUB_SELECT:
			if main.hand.is_empty():
				return false
			main.on_club_select(main.playable_club_indices().pick_random())
		main.State.AIM:
			main._on_aim_picked(main.map_view.aim_target)
		main.State.FORM_DRAW:
			if main.current_form_options.is_empty():
				return false
			main.on_form_pick(randi() % main.current_form_options.size())
		main.State.DRAFT:
			if main.current_draft_options.is_empty():
				return false
			main.on_draft_pick(randi() % main.current_draft_options.size())
		main.State.DISCARD_FOR_DRAFT, main.State.DISCARD_FOR_HAZARD:
			if main.hand.is_empty():
				return false
			main.on_discard_pick(randi() % main.hand.size())
		main.State.PUTTING:
			# A perfect read a little under half the time, a wild one otherwise.
			main.on_putt(ShotResolver.solve_putt(main.hole, main.ball_pos) \
				+ (Vector2.ZERO if randf() < 0.45 else Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))))
		_:
			return false
	return true
