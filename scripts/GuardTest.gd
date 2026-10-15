extends SceneTree
# Stage 1 check: the action entry points must REFUSE malformed or
# out-of-turn input instead of crashing. Everything here is what a
# buggy or malicious peer could send once actions arrive over the wire.
var passed := 0
var failed := 0

func _check(label: String, cond: bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: %s" % label)

func _initialize() -> void:
	GameSetup.player_count = 2
	var m = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(m)
	m.player_count = 2
	m.build_ui(); m.init_game(); m.start_hole()
	m.map_view.skip_animation = true

	# Baseline: a fresh hole is CLUB_SELECT with a 3-club bag.
	_check("starts in CLUB_SELECT", m.state == m.State.CLUB_SELECT)
	var bag_before: int = m.hand.size()

	# --- Out-of-range indices on every index-taking entry point ---
	for bad in [-1, 99, 2147483647]:
		m.on_club_select(bad)
		_check("club_select(%d) did not change state" % bad, m.state == m.State.CLUB_SELECT)
		m.on_form_pick(bad)
		_check("form_pick(%d) refused in wrong state" % bad, m.state == m.State.CLUB_SELECT)
		m.on_draft_pick(bad)
		_check("draft_pick(%d) refused in wrong state" % bad, m.state == m.State.CLUB_SELECT)
		m.on_discard_pick(bad)
		_check("discard_pick(%d) left bag intact" % bad, m.hand.size() == bag_before)

	# --- Actions sent in the wrong phase ---
	m.on_putt_stopped("sunk", 1.0)
	_check("putt in CLUB_SELECT refused", m.state == m.State.CLUB_SELECT and m.strokes == 0)

	# --- A garbage putt result, in the right phase ---
	m.on_club_select(0)
	_check("legit club_select advanced to AIM", m.state == m.State.AIM)
	m._on_aim_picked(m.map_view.aim_target)
	_check("legit aim advanced to FORM_DRAW", m.state == m.State.FORM_DRAW)
	# Wrong-phase putt again, now from FORM_DRAW.
	m.on_putt_stopped("sunk", 1.0)
	_check("putt in FORM_DRAW refused", m.state == m.State.FORM_DRAW)
	# A legit form pick must be ACCEPTED (not refused). Check the shooter's
	# own stroke count, not m.strokes — the turn passes after the shot, so
	# m.strokes would report whoever is up next. play_shot() increments
	# before any animation, so this holds regardless of tween timing.
	var shooter = m.me
	var before_strokes: int = shooter.strokes
	m.on_form_pick(0)
	_check("legit form_pick was accepted (stroke counted)",
		shooter.strokes == before_strokes + 1)

	print("\nGUARDS: %d passed, %d failed" % [passed, failed])
	print("RESULT: %s" % ("OK" if failed == 0 else "FAIL"))
	m.free()
	quit(0 if failed == 0 else 1)
