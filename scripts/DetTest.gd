extends SceneTree

const TestBags := preload("res://scripts/TestBags.gd")

# ---------------------------------------------------------
# DETERMINISM HARNESS — the test online multiplayer rests on.
#
# Dev tool, not shipped. Runs TWO independent game instances in one
# process and checks they stay identical when fed the same actions and
# the same random results.
#
# Why this exists: in an online round the host decides every random
# outcome and the other machines reproduce the result. That only works if
# "same starting state + same action + same rolls" really does give the
# same end state. This proves it, offline, before any networking exists —
# and when it fails it names the exact field that drifted, which is far
# cheaper than finding the same bug over a socket.
#
#   godot --headless --script res://scripts/DetTest.gd
#   DETTEST_HOLES=3 godot --headless --script res://scripts/DetTest.gd
#
# A is the "host": it plays normally and records what it rolled.
# B is the "client": it is given A's starting state, then replays each of
# A's actions with A's rolls injected, and must land in the same place.
# ---------------------------------------------------------

const MAX_ACTIONS := 300000

var a = null          # the deciding instance
var b = null          # the reproducing instance
var drifts: Array = []
var actions := 0
var holes_to_play := 18


func _initialize() -> void:
	var raw := OS.get_environment("DETTEST_HOLES")
	if not raw.is_empty():
		holes_to_play = clampi(int(raw), 1, 18)

	GameSetup.player_count = 2
	a = _make_instance()
	b = _make_instance()
	# Ability loadouts, so club abilities are replayed too.
	for i in range(a.players.size()):
		a.players[i].hand = TestBags.loadout(i)

	# B starts from A's exact state, the way a joining peer would be sent
	# the host's state rather than rolling its own.
	_copy_state(a, b)
	_assert_match("after initial sync")

	while a.state != a.State.DONE and actions < MAX_ACTIONS:
		if a.current_hole_index > holes_to_play:
			break
		actions += 1
		if not _step_both():
			break

	print("")
	# Proof the loadouts did their job: charges spent, by ability.
	var spent := {}
	for p in a.players:
		for id in p.ability_log:
			spent[id] = int(spent.get(id, 0)) + (p.ability_log[id] as Array).size()
	print("abilities used: %s" % str(spent))
	if drifts.is_empty():
		print("DETERMINISM: OK — %d actions, %d hole(s), two instances stayed identical" % [
			actions, mini(a.current_hole_index, holes_to_play)])
	else:
		print("DETERMINISM: FAIL — %d drift(s) across %d actions" % [drifts.size(), actions])
		var shown := 0
		for d in drifts:
			print("  %s" % d)
			shown += 1
			if shown >= 25:
				print("  ... and %d more" % (drifts.size() - shown))
				break
	# Free both trees before quitting: two full UI trees left queued
	# flush deferred Control callbacks during teardown, which muddies the
	# process exit code.
	if a != null:
		a.free()
	if b != null:
		b.free()
	quit(0 if drifts.is_empty() else 1)


func _make_instance():
	var m = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(m)
	# add_child() from _initialize() defers _ready(), so run the same calls
	# _ready() makes. Mirrors what MPTest.gd does.
	if m.players.is_empty():
		m.player_count = 2
		m.build_ui()
		m.init_game()
		m.start_hole()
	m.map_view.skip_animation = true
	return m


# --- State transfer ----------------------------------------------------
# Deliberately goes through plain-data shapes only — the same shapes a
# network sync would use. If something can't be expressed here, it can't
# be sent over a wire either, so this doubles as a serialization check.

func _serialize_player(p) -> Dictionary:
	return {
		"name": p.name,
		"hand": p.hand.duplicate(true),
		"club_deck": p.club_deck.duplicate(true),
		"club_discard": p.club_discard.duplicate(true),
		"live_brands": p.live_brands.duplicate(),
		# FormCards are rebuilt from their names — every card in the game
		# comes from FormCard.make(), so a name is the whole card.
		"form_deck": _card_names(p.form_deck.deck),
		"form_discard": _card_names(p.form_deck.discard),
		"ball_pos": p.ball_pos,
		"shot_path": p.shot_path.duplicate(),
		"strokes": p.strokes,
		"current_lie": p.current_lie,
		"aim_target": p.aim_target,
		"holed_out": p.holed_out,
		"putt_dist": p.putt_dist,
		"putt_dir": p.putt_dir,
		"yips_pending": p.yips_pending,
		"round_scores": p.round_scores.duplicate(true),
	}


func _apply_player(p, d: Dictionary) -> void:
	p.name = d.name
	p.hand = d.hand.duplicate(true)
	p.club_deck = d.club_deck.duplicate(true)
	p.club_discard = d.club_discard.duplicate(true)
	p.live_brands = d.live_brands.duplicate()
	p.form_deck.deck = _cards_from_names(d.form_deck)
	p.form_deck.discard = _cards_from_names(d.form_discard)
	p.ball_pos = d.ball_pos
	p.shot_path = d.shot_path.duplicate()
	p.strokes = d.strokes
	p.current_lie = d.current_lie
	p.aim_target = d.aim_target
	p.holed_out = d.holed_out
	p.putt_dist = d.putt_dist
	p.putt_dir = d.putt_dir
	p.yips_pending = d.yips_pending
	p.round_scores = d.round_scores.duplicate(true)


# The game's own wire format, so created cards keep their mark.
func _card_names(cards: Array) -> Array:
	return a.form_card_names(cards)


func _cards_from_names(names: Array) -> Array:
	return a.form_cards_from_names(names)


func _copy_state(src, dst) -> void:
	dst.current_hole_index = src.current_hole_index
	dst.hole = HoleData.hole(src.current_hole_index)  # derived, never sent
	dst.wind_seed = src.wind_seed                      # sent in the round payload
	dst.hole.wind = src.hole.wind
	dst.hole_yardage = dst.hole.yardage
	dst.hole_par = dst.hole.par
	dst.active_index = src.active_index
	dst.state = src.state
	dst._draft_queue = src._draft_queue.duplicate()
	for i in range(src.players.size()):
		_apply_player(dst.players[i], _serialize_player(src.players[i]))


# --- Comparison --------------------------------------------------------

func _assert_match(context: String) -> void:
	_cmp(context, "current_hole_index", a.current_hole_index, b.current_hole_index)
	_cmp(context, "state", a.state, b.state)
	_cmp(context, "active_index", a.active_index, b.active_index)
	_cmp(context, "wind", a.hole.wind, b.hole.wind)
	_cmp(context, "draft_queue", str(a._draft_queue), str(b._draft_queue))
	for i in range(a.players.size()):
		var pa = a.players[i]
		var pb = b.players[i]
		var who := "p%d" % i
		_cmp(context, who + ".ball_pos", pa.ball_pos, pb.ball_pos)
		_cmp(context, who + ".strokes", pa.strokes, pb.strokes)
		_cmp(context, who + ".current_lie", pa.current_lie, pb.current_lie)
		_cmp(context, who + ".holed_out", pa.holed_out, pb.holed_out)
		_cmp(context, who + ".putt_dist", snappedf(pa.putt_dist, 0.0001), snappedf(pb.putt_dist, 0.0001))
		_cmp(context, who + ".yips_pending", pa.yips_pending, pb.yips_pending)
		_cmp(context, who + ".bag", str(_club_names(pa.hand)), str(_club_names(pb.hand)))
		_cmp(context, who + ".form_deck", str(_card_names(pa.form_deck.deck)), str(_card_names(pb.form_deck.deck)))
		_cmp(context, who + ".scores", str(pa.round_scores), str(pb.round_scores))
		_cmp(context, who + ".ability_log", str(pa.ability_log), str(pb.ability_log))
		_cmp(context, who + ".created_next", str(pa.created_next), str(pb.created_next))


func _club_names(bag: Array) -> Array:
	var out: Array = []
	for c in bag:
		out.append(c.name)
	return out


func _cmp(context: String, field: String, va, vb) -> void:
	if va != vb:
		drifts.append("[%s] %s: A=%s  B=%s" % [context, field, str(va), str(vb)])


# --- Driving both instances -------------------------------------------
# A decides (and records its rolls); B is handed those rolls and replays
# the identical action. Returns false if the flow has nothing to do.

func _step_both() -> bool:
	var choice := _choose_action()
	if choice.is_empty():
		return false
	var kind: String = choice[0]
	var arg = choice[1]

	# A acts, recording every random result it consumes.
	a.begin_roll_capture()
	_apply_action(a, kind, arg)
	var rolls: Array = a.take_captured_rolls()

	# B replays the same action with A's results injected.
	b.inject_rolls(rolls)
	_apply_action(b, kind, arg)

	# Deck draws are randomness that lives inside the deck's own shuffle
	# rather than a _roll() call, so B cannot reproduce them — the drawn
	# cards/clubs and the resulting deck order are STATE, and the host has
	# to ship them. This mirrors what the real broadcast must carry.
	#
	# Committing an aim is what triggers the Form draw (begin_form_draw is
	# called from _on_aim_picked), and entering the draft is what draws the
	# three club options — so those are the two actions after which the
	# decks must be re-synced.
	if kind == "aim" or kind == "draft" or kind == "discard" or kind == "putt" or kind == "form" \
			or kind == "ability" or kind == "range":
		_sync_decks()

	_assert_match("%s #%d (hole %d)" % [kind, actions, a.current_hole_index])
	return true


# What A does next, as [kind, arg] — or [] if the flow has nothing to do.
# Now and then that's an ability or a range session rather than the
# phase's ordinary action.
func _choose_action() -> Array:
	var ability := TestBags.pick_ability(a, 0.3)
	if ability != "":
		return ["ability", ability]
	if TestBags.wants_range(a, 0.15):
		return ["range", null]
	match a.state:
		a.State.CLUB_SELECT:
			if a.hand.is_empty():
				return []
			var playable: Array = a.playable_club_indices()
			return ["club", playable[randi() % playable.size()]]
		a.State.AIM:
			return ["aim", a.map_view.aim_target]
		a.State.FORM_DRAW:
			if a.current_form_options.is_empty():
				return []
			return ["form", randi() % a.current_form_options.size()]
		a.State.DRAFT:
			if a.current_draft_options.is_empty():
				return []
			return ["draft", randi() % a.current_draft_options.size()]
		a.State.DISCARD_FOR_DRAFT, a.State.DISCARD_FOR_HAZARD:
			if a.hand.is_empty():
				return []
			return ["discard", randi() % a.hand.size()]
		a.State.PUTTING:
			# The accuracy travels WITH the action (it's the player's
			# timing, not a roll), so both instances get the same pair.
			return ["putt", {
				"result": ["sunk", "close", "miss"][randi() % 3],
				"accuracy": randf(),
			}]
	return []


# Copies every deck-derived value from A to B. Everything here is a
# shuffle result: reproducible only by being sent, not by being re-rolled.
func _sync_decks() -> void:
	for i in range(a.players.size()):
		var pa = a.players[i]
		var pb = b.players[i]
		pb.form_deck.deck = _cards_from_names(_card_names(pa.form_deck.deck))
		pb.form_deck.discard = _cards_from_names(_card_names(pa.form_deck.discard))
		pb.club_deck = pa.club_deck.duplicate(true)
		pb.club_discard = pa.club_discard.duplicate(true)
		pb.current_draft_options = pa.current_draft_options.duplicate(true)
		pb.current_form_options = _cards_from_names(_card_names(pa.current_form_options))
		pb.current_form_forced = pa.current_form_forced
		pb.pending_club = pa.pending_club.duplicate(true)
		pb.pending_new_card = pa.pending_new_card
		pb.ability_log = pa.ability_log.duplicate(true)
		pb.armed = pa.armed.duplicate()
		pb.created_next = pa.created_next.duplicate()


func _apply_action(m, kind: String, arg) -> void:
	match kind:
		"club": m.on_club_select(arg)
		"aim": m._on_aim_picked(arg)
		"form": m.on_form_pick(arg)
		"draft": m.on_draft_pick(arg)
		"discard": m.on_discard_pick(arg)
		"putt": m.on_putt_stopped(arg.result, arg.accuracy)
		"ability": m.on_ability(arg)
		"range": m.on_range_session()
