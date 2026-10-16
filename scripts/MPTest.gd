extends SceneTree

# ---------------------------------------------------------
# Headless flow harness for hot-seat rounds — a dev tool, not shipped
# behaviour. Drives full 18-hole rounds for 1..4 players through the REAL
# Main.gd entry points the UI calls, and asserts that:
#   - every player finishes all 18 holes
#   - the turn order is always "furthest from the pin plays first"
#   - bags stay within [3, HAND_CAP]
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
	print("\nALL ROUNDS: %s" % ("OK" if all_ok else "FAIL"))
	quit(0 if all_ok else 1)


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


func _run_round(count: int) -> bool:
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
		main.start_hole()

	if main.players.size() != count:
		print("players=%d -> FAIL (built %d players)" % [count, main.players.size()])
		main.free()
		return false

	main.map_view.skip_animation = true

	var ok := true
	var order_violations := 0
	var actions := 0

	while main.state != main.State.DONE and actions < MAX_ACTIONS:
		actions += 1
		if not _turn_order_holds(main):
			order_violations += 1
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
			if p.round_scores.size() != Course.hole_count():
				print("  !! %s scored %d holes, expected %d" % [p.name, p.round_scores.size(), Course.hole_count()])
				ok = false
			if p.hand.size() < 3 or p.hand.size() > main.HAND_CAP:
				print("  !! %s bag is %d clubs (cap %d)" % [p.name, p.hand.size(), main.HAND_CAP])
				ok = false
		if order_violations > 0:
			print("  !! %d turn-order violations (someone was up who wasn't furthest out)" % order_violations)
			ok = false

	var totals: Array = []
	for p in main.players:
		totals.append("%s=%d" % [p.name, p.total_strokes()])
	print("players=%d -> %s  (%d actions)  %s" % [
		count, "OK" if ok else "FAIL", actions, ", ".join(totals)])

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
	match main.state:
		main.State.CLUB_SELECT:
			if main.hand.is_empty():
				return false
			main.on_club_select(randi() % main.hand.size())
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
			# Resolve the putt directly rather than driving the meter, which
			# is a real-time sweep.
			main.on_putt_stopped("sunk" if randf() < 0.45 else "miss", randf())
		_:
			return false
	return true
