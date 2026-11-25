extends SceneTree

# ---------------------------------------------------------
# SAVE HARNESS — leaving a round and coming back (RoundSave.gd). Dev tool,
# not shipped. Works on a scratch file, never the player's own save.
#
#   godot --headless --script res://scripts/SaveTest.gd
#
# Checks:
#   1. nothing is saved unless the round was started by a player
#   2. a round is saved before the first tee and at the stop after each
#      hole, and what is read back is what was written
#   3. a second game built from the save stands where the first did: the
#      same bag, decks, scores and stop, and it plays on to the last hole
#   4. finishing the round removes the save
#   5. a tour course keeps its save when it finishes, with the tour so
#      far in it, and RoundSave.restore_setup() puts the tour back
#   6. a round with a computer golfer comes back with one
# ---------------------------------------------------------

const RoundSave := preload("res://scripts/RoundSave.gd")
const TestBags := preload("res://scripts/TestBags.gd")
# Held so their statics (the scratch paths) survive between calls.
const _KEEP := [preload("res://scripts/Records.gd"), preload("res://scripts/GameSetup.gd")]

const SAVE_FILE := "user://round_test.save"
const RECORDS_FILE := "user://records_savetest.json"
const MAX_ACTIONS := 20000

var failures: Array = []


func _initialize() -> void:
	RoundSave.path = SAVE_FILE
	Records.path = RECORDS_FILE
	RoundSave.clear()

	_check_gate()
	Records.enabled = true
	_check_round_trip()
	_check_tour()
	_check_rival()

	RoundSave.clear()
	if FileAccess.file_exists(RECORDS_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS_FILE))
	if failures.is_empty():
		print("\nSAVE: OK")
	else:
		for f in failures:
			print("  !! " + f)
		print("\nSAVE: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


# A game scene set up the way Main._ready() does it (add_child() from
# _initialize() defers _ready(), so its calls are made here).
func _new_main(fresh: bool = true):
	var main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(main)
	main.player_count = GameSetup.player_count
	main.cpu_seats = GameSetup.cpu_seats.duplicate()
	main.build_ui()
	main.map_view.skip_animation = true
	if fresh:
		main.init_game()
		main._apply_tour_carry()
		main.begin_round()
	return main


# Plays with the balance bot until `until` says stop. False if it stuck.
func _play(main, until: Callable) -> bool:
	var bot := GreedyBot.new(7)
	var actions := 0
	while not until.call() and actions < MAX_ACTIONS:
		actions += 1
		if main.is_cpu_turn():
			main.cpu_act()
		elif not bot.act(main):
			return false
	return until.call()


func _bag(p) -> Array:
	return p.hand.map(func(c): return c.name)


func _check_gate() -> void:
	GameSetup.reset_to_local(1)
	var main = _new_main()
	_expect(not RoundSave.exists(), "a round nobody started from the title was saved")
	main.free()


func _check_round_trip() -> void:
	GameSetup.reset_to_local(1)
	var a = _new_main()
	var first := RoundSave.read()
	_expect(not first.is_empty() and int(first.get("hole", -1)) == 0, "no save before the first tee")
	_expect(RoundSave.summary(first).contains("before the first tee"), "the title's line for a new round reads '%s'" % RoundSave.summary(first))

	# Play to the fourth tee: the save on disk is the stop after the third.
	_expect(_play(a, func(): return a.current_hole_index == 4 and a.state == a.State.CLUB_SELECT),
		"the first game never reached the fourth tee")
	var saved := RoundSave.read()
	_expect(int(saved.get("hole", -1)) == 3, "at the fourth tee the save should stand after hole 3 (it says %s)" % str(saved.get("hole")))
	_expect((saved.players[0].round_scores as Array).size() == 3, "the save holds %d scores, not 3" % (saved.players[0].round_scores as Array).size())
	_expect(RoundSave.summary(saved).contains("3 holes played"), "the title's line reads '%s'" % RoundSave.summary(saved))
	a.free()

	# A second game, built from the file alone.
	GameSetup.reset_to_local(4)   # whatever the title last said, the save decides
	RoundSave.restore_setup(saved)
	_expect(GameSetup.player_count == 1 and not GameSetup.resume.is_empty(), "restore_setup did not hand the round to the game scene")
	GameSetup.resume = {}
	var b = _new_main(false)
	b.apply_save(saved)
	_expect(var_to_str(b.save_data(3)) == var_to_str(saved), "a game rebuilt from a save does not save back the same")
	b.resume_round(saved)
	_expect(b.current_hole_index == 3 and b.state == b.State.DRAFT, "it came back on hole %d in state %d, not at the stop after the 3rd" % [b.current_hole_index, b.state])
	_expect(b.me.round_scores.size() == 3 and b.me.total_strokes() == _strokes(saved), "the scores did not come back")
	_expect(_play(b, func(): return b.state == b.State.DONE), "the game that came back never finished its round")
	# Played for strokes in hand, the bot may run out before the 18th.
	_expect(b.me.round_scores.size() == Course.hole_count() or b._run_over, "it finished after %d holes" % b.me.round_scores.size())
	_expect(not RoundSave.exists(), "a finished round left its save behind")
	b.free()


func _strokes(saved: Dictionary) -> int:
	var total := 0
	for entry in saved.players[0].round_scores:
		total += int(entry.strokes)
	return total


func _check_tour() -> void:
	# The second course of a tour, with five clubs carried and one result in.
	GameSetup.start_tour()
	GameSetup.tour_leg = 1
	var kept: Array = TestBags.loadout(0).slice(0, 5)
	kept[0]["level"] = 1
	GameSetup.tour_bag = kept
	GameSetup.tour_brands = ["titanist", "callowell", "pingwell", "nimbus"]
	GameSetup.tour_results = [{"course": "Bogey Links", "strokes": 75, "par": 71}]
	Course.use_shipped("windlestraw-links")
	var a = _new_main()
	a.for_keeps = true
	var saved := RoundSave.read()
	var tour: Dictionary = saved.get("tour", {})
	_expect(bool(tour.get("on", false)) and int(tour.get("leg", 0)) == 1, "the save does not say which course of the tour it is")
	_expect((saved.players[0].hand as Array).size() == kept.size(), "the carried bag is not in the save (%d clubs)" % (saved.players[0].hand as Array).size())
	_expect(int(saved.players[0].hand.filter(func(c): return c.name == kept[0].name)[0].get("level", 0)) == 1, "a carried club lost its level in the save")

	# The course finished with another to come: the save stays, marked done.
	a.current_hole_index = Course.hole_count()
	for n in range(1, Course.hole_count() + 1):
		a.me.round_scores.append({"hole": n, "par": 4, "strokes": 4})
	a.finish_round()
	saved = RoundSave.read()
	_expect(bool(saved.get("done", false)), "a finished tour course with one to come should keep its save, marked done")
	a.free()

	GameSetup.reset_to_local(1)
	Course.use_builtin()
	RoundSave.restore_setup(saved)
	_expect(GameSetup.tour and GameSetup.tour_leg == 1 and GameSetup.tour_results.size() == 1, "restore_setup did not put the tour back")
	_expect(Course.active_id == "windlestraw-links", "restore_setup put back %s, not the course being played" % Course.active_id)
	GameSetup.resume = {}
	var b = _new_main(false)
	b.apply_save(saved)
	b.resume_round(saved)
	_expect(b.state == b.State.DONE and b.tour_continues(), "a finished tour course should come back on its card, ready to pack")
	_expect(_bag(b.me) == _bag_names(saved), "the bag to pack did not come back")
	b.free()
	RoundSave.clear()
	GameSetup.reset_to_local(1)
	Course.use_builtin()


func _bag_names(saved: Dictionary) -> Array:
	return (saved.players[0].hand as Array).map(func(c): return c.name)


func _check_rival() -> void:
	GameSetup.reset_to_local(2)
	GameSetup.cpu_seats = {1: "medium"}
	var a = _new_main()
	var saved := RoundSave.read()
	a.free()
	_expect(str(saved.players[1].get("cpu_skill", "")) == "medium", "the computer golfer's seat is not in the save")
	GameSetup.reset_to_local(1)
	RoundSave.restore_setup(saved)
	_expect(GameSetup.player_count == 2 and str(GameSetup.cpu_seats.get(1, "")) == "medium", "restore_setup did not seat the computer golfer")
	GameSetup.resume = {}
	var b = _new_main(false)
	b.apply_save(saved)
	_expect(b.is_cpu_seat(1) and not b.is_cpu_seat(0), "the game came back without its computer golfer")
	b.free()
	RoundSave.clear()
	GameSetup.reset_to_local(1)
