extends "res://scripts/MPTest.gd"

# ---------------------------------------------------------
# Headless harness for rounds against computer golfers — a dev tool, not
# shipped behaviour. Unlike MPTest it lets the scene tree run frames, so
# the computer seats are played by the same per-frame driver the real game
# uses (Main._process), and the human seats by MPTest's random player.
#
# Asserts that:
#   - the round finishes, every seat scores every hole, bags stay capped
#   - the turn order is still "furthest from the pin plays first"
#   - nothing a person presses does anything while a computer golfer is up
#   - a computer golfer's round is never recorded, and plays like golf
#     rather than at random
#   - the stamp titles, the under-par streak and the match margin are right
#
#   godot --headless --script res://scripts/CpuTest.gd
#   CPUTEST_CASES=0 godot --headless --script res://scripts/CpuTest.gd
# ---------------------------------------------------------

const HoleBanner := preload("res://scripts/HoleBanner.gd")
const Rivals := preload("res://scripts/Rivals.gd")

# `pace` is Main.cpu_pace. At 0 a computer golfer acts every frame with no
# thread; above 0 it plays the way the real game does — a pause before each
# action, the shot planned on a worker thread, the picked card shown first —
# just with the pauses cut to almost nothing.
const CASES := [
	{"name": "you vs Dory", "count": 2, "cpu": {1: "easy"}, "pace": 0.0},
	{"name": "you vs Ace and Coley", "count": 3, "cpu": {1: "hard", 2: "medium"}, "pace": 0.0},
	{"name": "computer vs computer, paced", "count": 2, "cpu": {0: "medium", 1: "easy"}, "pace": 0.01},
]
# Frames with nothing changing before the round is called stuck. Generous:
# headless frames are near-instant, and a paced computer golfer spends a
# few hundred of them waiting on its own plan.
const STALL_FRAMES := 200000
# A computer golfer who shoots outside this is not playing golf.
const CPU_TOTAL_MIN := 48
const CPU_TOTAL_MAX := 125

var _queue: Array = []
var _case: Dictionary = {}
var _main = null
var _started := false
var _all_ok := true
var _fails: Array = []
var _frames := 0
var _stall := 0
var _last_mark := ""
var _order_violations := 0
var _blocked_checks := 0


func _initialize() -> void:
	_unit_checks()
	var only := OS.get_environment("CPUTEST_CASES")
	for i in range(CASES.size()):
		if only.is_empty() or str(i) in only.split(","):
			_queue.append(CASES[i])
	_next_case()


func _process(_delta: float) -> bool:
	if _main == null:
		return false
	if _main.players.is_empty():
		return false  # the scene's _ready() hasn't run yet
	if not _started:
		_started = true
		_main.map_view.skip_animation = true
		_main.cpu_pace = float(_case.get("pace", 0.0))
		_check_setup()

	_frames += 1
	if _main.state == _main.State.DONE:
		_finish_case()
		return false

	var mark := "%d|%d|%d|%d|%d" % [_main.current_hole_index, _main.state, _main.active_index,
		_main.strokes, _main.hand.size()]
	_stall = _stall + 1 if mark == _last_mark else 0
	_last_mark = mark
	if _stall > STALL_FRAMES:
		_fail("stuck in state %d on hole %d (seat %d)" % [
			_main.state, _main.current_hole_index, _main.active_index])
		_finish_case()
		return false

	if not _turn_order_holds(_main):
		_order_violations += 1
	if _main.is_cpu_turn():
		_check_input_is_ignored()
	elif not _step(_main):
		_fail("the human seat has no move in state %d on hole %d" % [
			_main.state, _main.current_hole_index])
		_finish_case()
	return false


func _next_case() -> void:
	if _queue.is_empty():
		print("\nCPU ROUNDS: %s" % ("OK" if _all_ok else "FAIL"))
		quit(0 if _all_ok else 1)
		return
	_case = _queue.pop_front()
	_fails = []
	_frames = 0
	_stall = 0
	_last_mark = ""
	_order_violations = 0
	_blocked_checks = 0
	_started = false
	# Set up the way the title screen does, and let the scene's own
	# _ready() build the round from it.
	GameSetup.reset_to_local(int(_case.count))
	GameSetup.cpu_seats = (_case.cpu as Dictionary).duplicate()
	_main = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(_main)


func _check_setup() -> void:
	if _main.players.size() != int(_case.count):
		_fail("built %d players, expected %d" % [_main.players.size(), int(_case.count)])
	var humans := 0
	for i in range(_main.players.size()):
		var skill := str(_case.cpu.get(i, ""))
		var p: Player = _main.players[i]
		if skill == "":
			humans += 1
			if _main.is_cpu_seat(i):
				_fail("seat %d should be a person" % i)
			continue
		if not _main.is_cpu_seat(i):
			_fail("seat %d should be played by the computer" % i)
		if p.name != Rivals.name_of(skill):
			_fail("seat %d is named '%s', expected '%s'" % [i, p.name, Rivals.name_of(skill)])
		if _main.records_this_seat(i):
			_fail("seat %d (computer) would be recorded" % i)
	if humans == 1 and _main.lone_human() == null:
		_fail("lone_human() didn't find the one person")
	if humans == 1 and _main.lone_human().name != "You":
		_fail("the one person should be 'You', is '%s'" % _main.lone_human().name)
	if _main.round_mode() != "vs computer":
		_fail("round mode is '%s'" % _main.round_mode())


# Everything a person can press goes through submit(); while a computer
# golfer is up, none of it may change the game.
func _check_input_is_ignored() -> void:
	var before := _snapshot()
	match _main.state:
		_main.State.CLUB_SELECT:
			_main.submit("call", {})
			_main.submit("club", {"index": 0})
		_main.State.AIM:
			_main.submit("aim", {"target": _main.hole.pin_pos})
			_main._on_aim_changed(_main.hole.tee_pos)
		_main.State.FORM_DRAW:
			_main.submit("form", {"index": 0})
		_main.State.DRAFT:
			_main.submit("draft", {"index": 0})
			_main.submit("stop", {"index": 1})
			_main.submit("leave", {})
			_main.submit("event", {})
			_main.submit("dig", {})
			_main.submit("trade", {"index": 0})
			_main.submit("done", {})
		_main.State.DISCARD_FOR_DRAFT, _main.State.DISCARD_FOR_HAZARD:
			_main.submit("discard", {"index": 0})
		_main.State.PUTTING:
			_main.submit("putt", {"result": "sunk", "accuracy": 1.0})
			_main._on_strike_pressed()
		_:
			return
	_blocked_checks += 1
	if _snapshot() != before:
		_fail("input changed the game during a computer golfer's turn (state %d, hole %d)" % [
			_main.state, _main.current_hole_index])


func _snapshot() -> String:
	return "%d|%d|%d|%d|%s|%s|%d|%d|%s|%d|%d" % [_main.state, _main.active_index, _main.strokes,
		_main.hand.size(), str(_main.ball_pos), str(_main.aim_target),
		_main.current_form_options.size(), _main.me.round_scores.size(),
		str(_main.me.called), _main.current_draft_options.size(), _main.form_deck.bad_count()]


func _finish_case() -> void:
	var holes := Course.hole_count()
	if _main.state == _main.State.DONE:
		for i in range(_main.players.size()):
			var p: Player = _main.players[i]
			if p.round_scores.size() != holes:
				_fail("%s scored %d holes, expected %d" % [p.name, p.round_scores.size(), holes])
			if p.hand.size() < 3 or p.hand.size() > _main.HAND_CAP:
				_fail("%s bag is %d clubs (cap %d)" % [p.name, p.hand.size(), _main.HAND_CAP])
			if _main.is_cpu_seat(i) and (p.total_strokes() < CPU_TOTAL_MIN or p.total_strokes() > CPU_TOTAL_MAX):
				_fail("%s shot %d — not a round of golf" % [p.name, p.total_strokes()])
		if _order_violations > 0:
			_fail("%d turn-order violations" % _order_violations)
		if _blocked_checks == 0:
			_fail("never got to check that input is ignored on a computer turn")
		# The margin and the lead line must agree with the card.
		var a: Player = _main.players[0]
		var b: Player = _main.players[1]
		if _main.players.size() == 2:
			if _main.match_margin(a) != b.total_strokes() - a.total_strokes():
				_fail("match_margin disagrees with the totals")
			var lead: String = _main.lead_text()
			if a.total_strokes() == b.total_strokes():
				if lead != "All square.":
					_fail("level round reported as '%s'" % lead)
			else:
				var leader: Player = a if a.total_strokes() < b.total_strokes() else b
				if not lead.begins_with(leader.name):
					_fail("lead line '%s' doesn't name the leader %s" % [lead, leader.name])

	var totals: Array = []
	for p in _main.players:
		totals.append("%s=%d" % [p.name, p.total_strokes()])
	print("%s -> %s  (%d frames, %d blocked-input checks)  %s" % [
		_case.name, "OK" if _fails.is_empty() else "FAIL", _frames, _blocked_checks, ", ".join(totals)])
	for f in _fails:
		print("  !! " + f)
	if not _fails.is_empty():
		_all_ok = false
	_main.queue_free()
	_main = null
	_next_case()


func _fail(what: String) -> void:
	if not what in _fails:
		_fails.append(what)


# Cutting Bogey-Mart clubs from a full bag: the stamp lands when the last
# one goes, and not before.
func _starter_retired_checks() -> Array:
	var bad: Array = []
	var m = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(m)
	m.player_count = 1
	m.build_ui()
	m.init_game()
	m.start_hole()

	var extras: Array = ClubRoster.standard_clubs() + ClubRoster.branded_clubs("titanist")
	var bag: Array = ClubRoster.starter_bag()
	var incoming: Array = []
	for c in extras:
		if bag.size() < m.HAND_CAP:
			bag.append(c)
		else:
			incoming.append(c)
	if bag.size() != m.HAND_CAP or incoming.size() < 3:
		bad.append("couldn't build a full bag to cut from (%d clubs, %d spare)" % [bag.size(), incoming.size()])
		m.free()
		return bad
	m.me.hand = bag

	var title := "BOGEY-MART RETIRED"
	for cut in range(3):
		var index := -1
		for i in range(m.hand.size()):
			if m.hand[i].get("brand", "") == Brands.STARTER:
				index = i
				break
		if index < 0:
			bad.append("ran out of Bogey-Mart clubs after %d cuts" % cut)
			break
		m.pending_new_card = incoming[cut]
		m.state = m.State.DISCARD_FOR_DRAFT
		m.on_discard_pick(index)
		var stamped: bool = m.hole_banner.is_showing() and m.hole_banner._title.text == title
		if cut < 2 and stamped:
			bad.append("retirement stamped with Bogey-Mart clubs still in the bag (cut %d)" % (cut + 1))
		if cut == 2 and not stamped:
			bad.append("cutting the last Bogey-Mart club didn't stamp the retirement")
	if m.hand.size() != m.HAND_CAP:
		bad.append("bag is %d clubs after the cuts" % m.hand.size())
	m.free()
	return bad


func _named_club(club_name: String) -> Dictionary:
	var all: Array = ClubRoster.standard_clubs() + ClubRoster.limited_clubs()
	for b in Brands.DRAFTABLE:
		all.append_array(ClubRoster.branded_clubs(b))
	for c in all:
		if c.name == club_name:
			return c.duplicate(true)
	return {}


func _offer_names(m) -> Array:
	return m.current_draft_options.map(func(c): return str(c.name))


# The draft's other moves (DraftRules.gd), driven straight through Main:
# the call, a draft that keeps two, a dig, a trade-in, the shot a club
# brings to the Form deck, and the stamp for the club that makes a set.
func _draft_checks() -> Array:
	var bad: Array = []
	var m = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(m)
	m.player_count = 1
	m.build_ui()
	m.init_game()
	m.start_hole()
	var p: Player = m.me

	# The call is made on the tee and can be taken back.
	if not m.can_call_hole():
		bad.append("the hole can't be called on the first tee")
	m.on_call_hole()
	if not p.called:
		bad.append("calling the hole didn't take")
	m.on_call_hole()
	if p.called:
		bad.append("the call couldn't be taken back")

	# A call made: five on the rack, two to keep, and the draft stays open
	# after the first.
	p.call_result = "made"
	m.begin_draft_phase()
	m.on_stop(0)   # the pro shop
	if m.current_draft_options.size() != 5 or p.draft_keeps != 2:
		bad.append("a call made dealt %d and keeps %d (expected 5 and 2)" % [m.current_draft_options.size(), p.draft_keeps])
	var clubs_before: int = m.hand.size()
	m.on_draft_pick(0)
	if m.state != m.State.DRAFT or m.current_draft_options.size() != 4 or m.hand.size() != clubs_before + 1:
		bad.append("the first of two picks should leave the draft open on four (state %d, %d left, %d clubs)" % [
			m.state, m.current_draft_options.size(), m.hand.size()])
	m.on_draft_done()
	if m.state != m.State.CLUB_SELECT or m.current_hole_index != 2:
		bad.append("\"that'll do\" should end the draft and start the next hole (state %d, hole %d)" % [m.state, m.current_hole_index])
	if p.called or p.call_result != "":
		bad.append("a new hole should start with no call standing")

	# A call missed: two. Then a dig replaces both, at the cost of a card.
	p.call_result = "missed"
	m.begin_draft_phase()
	m.on_stop(0)   # the pro shop
	if m.current_draft_options.size() != 2:
		bad.append("a call missed dealt %d (expected 2)" % m.current_draft_options.size())
	var before_names := _offer_names(m)
	var bad_before: int = m.form_deck.bad_count()
	m.on_dig()
	var after_names := _offer_names(m)
	if after_names.size() != 2 or after_names.any(func(n): return before_names.has(n)):
		bad.append("a dig should deal as many fresh clubs (%s -> %s)" % [before_names, after_names])
	if m.form_deck.bad_count() != bad_before + 1:
		bad.append("a dig should leave one bad card in the Form deck")
	m.on_dig()
	if _offer_names(m) != after_names or m.form_deck.bad_count() != bad_before + 1:
		bad.append("a second dig in one draft should be refused")

	# A trade-in: a club out of the bag, one more on the rack, once.
	var clubs_now: int = m.hand.size()
	m.on_trade_in(0)
	if m.hand.size() != clubs_now - 1 or m.current_draft_options.size() != 3 or not p.draft_traded:
		bad.append("a trade-in should cost a club and add an offer (%d clubs, %d offers)" % [m.hand.size(), m.current_draft_options.size()])
	m.on_trade_in(0)
	if m.hand.size() != clubs_now - 1:
		bad.append("a second trade-in in one draft should be refused")

	# A maker's club brings its shot to the Form deck, and the club that
	# makes the set is stamped. Three Titanist in the bag, a fourth offered.
	# A fresh Form deck: the picks above were whatever the pool dealt, and
	# one of them may have brought a Knockdown of its own.
	p.form_deck = FormDeck.new()
	p.hand = [_named_club("Titanist 4-Iron"), _named_club("Titanist 8-Iron"),
		_named_club("Titanist Staff 7-Iron"), _named_club("Putter")]
	p.current_draft_options = [_named_club("Titanist Tour Wedge")]
	p.draft_keeps = 1
	p.draft_taken = 0
	m.state = m.State.DRAFT
	var hole_before: int = m.current_hole_index
	m.on_draft_pick(0)
	if m.form_deck.count_of("Knockdown") != 1:
		bad.append("a Titanist club should bring a Knockdown (deck holds %d)" % m.form_deck.count_of("Knockdown"))
	if not (m.hole_banner.is_showing() and m.hole_banner._title.text == "TITANIST 4-SET"):
		bad.append("the club that made the 4-set wasn't stamped (stamp says '%s')" % m.hole_banner._title.text)
	if not m.hole_banner._sub.text.contains("Staff 7-Iron"):
		bad.append("the stamp should say the Staff club woke (says '%s')" % m.hole_banner._sub.text)
	if m.current_hole_index != hole_before + 1:
		bad.append("a draft that keeps one should end with the pick")

	# ...and takes it away again when it is traded in.
	p.call_result = ""
	m.begin_draft_phase()
	m.on_stop(0)   # the pro shop
	var wedge := -1
	for i in range(m.hand.size()):
		if m.hand[i].name == "Titanist Tour Wedge":
			wedge = i
	m.on_trade_in(wedge)
	if m.form_deck.count_of("Knockdown") != 0:
		bad.append("trading in the club should take its Knockdown out of the Form deck")
	m.free()
	return bad


# --- The parts that need no round ---------------------------------------

func _unit_checks() -> void:
	var bad: Array = []
	var titles := {
		[-3, 2]: "ALBATROSS", [-2, 3]: "EAGLE", [-1, 3]: "BIRDIE", [0, 4]: "PAR",
		[1, 5]: "BOGEY", [2, 6]: "DOUBLE BOGEY", [3, 7]: "TRIPLE BOGEY", [5, 9]: "5 OVER",
		[-2, 1]: "HOLE IN ONE", [-4, 1]: "HOLE IN ONE",
	}
	for k in titles:
		var got := HoleBanner.result_title(k[0], k[1])
		if got != titles[k]:
			bad.append("result_title(%d, %d) = '%s', expected '%s'" % [k[0], k[1], got, titles[k]])
	if HoleBanner.result_tone(-2) != HoleBanner.Tone.GREAT or HoleBanner.result_tone(-1) != HoleBanner.Tone.GOOD \
			or HoleBanner.result_tone(0) != HoleBanner.Tone.PLAIN or HoleBanner.result_tone(2) != HoleBanner.Tone.BAD:
		bad.append("result_tone() maps a score to the wrong tone")

	# The streak counts back from the last hole and stops at the first
	# hole that wasn't under par.
	var main = load("res://scripts/Main.gd").new()
	var p := Player.new("Test")
	for pair in [[4, 3], [4, 4], [3, 2], [5, 4], [4, 3]]:
		p.round_scores.append({"hole": p.round_scores.size() + 1, "par": pair[0], "strokes": pair[1]})
	if main.under_par_streak(p) != 3:
		bad.append("under_par_streak = %d, expected 3" % main.under_par_streak(p))
	p.round_scores.append({"hole": 6, "par": 4, "strokes": 4})
	if main.under_par_streak(p) != 0:
		bad.append("a par should end the streak")
	main.free()

	bad.append_array(_starter_retired_checks())
	bad.append_array(_draft_checks())

	for skill in Rivals.ORDER:
		if not Rivals.has(skill) or Rivals.name_of(skill) == "" or Rivals.blurb_of(skill) == "":
			bad.append("rival '%s' is missing a name or a blurb" % skill)
	var easy: Dictionary = Rivals.SKILLS["easy"]
	var hard: Dictionary = Rivals.SKILLS["hard"]
	if float(easy.aim) <= float(hard.aim) or float(easy.putt) <= float(hard.putt) \
			or int(easy.typical) <= int(hard.typical):
		bad.append("the easy rival should be worse than the hard one on every count")

	print("stamp, streak, draft and rival checks -> %s" % ("OK" if bad.is_empty() else "FAIL"))
	for b in bad:
		print("  !! " + b)
	if not bad.is_empty():
		_all_ok = false
