extends SceneTree

# ---------------------------------------------------------
# PAYOFF HARNESS — the marks the screen makes when something goes well.
# Dev tool, not shipped. They are cosmetic and no rule waits on them, so
# nothing else notices if one stops firing; and with no window open nobody
# sees them either. This plays a short round with the animations ON (so it
# takes real time: about a minute) and watches the real nodes.
#
#   godot --headless --script res://scripts/PayoffTest.gd
#
# Checks, on a three-hole course with a best to beat on every hole and a
# course record to beat:
#   1. a long shot that finds the green or the fairway is noted on the map
#   2. a club's mark lands on its bag tile
#   3. a hole best beaten is said on the hole's stamp
#   4. strokes in hand show what the hole paid or cost
#   5. the pro shop's rack is dealt, not just there
#   6. the card is tallied: every line arrives, the score is told, and a
#      new course record is announced
# Uses scratch files — never the player's records, save or settings.
# ---------------------------------------------------------

const RoundSave := preload("res://scripts/RoundSave.gd")
const _KEEP := [preload("res://scripts/Records.gd"), preload("res://scripts/Settings.gd"),
	preload("res://scripts/GameSetup.gd")]

const RECORDS_FILE := "user://records_payoff.json"
const SAVE_FILE := "user://round_payoff.save"
const SETTINGS_FILE := "user://settings_payoff.cfg"
const LIMIT_MSEC := 240000
const TALLY_WAIT_MSEC := 5000

var m
var bot: GreedyBot
var fails: Array = []
var started := 0
var done_at := 0
var seen := {"note": false, "fairway_mark": false, "flash": false, "best": false,
	"count": false, "deal": false}


func _initialize() -> void:
	Records.enabled = true
	Records.path = RECORDS_FILE
	RoundSave.path = SAVE_FILE
	Settings.path = SETTINGS_FILE
	_wipe()
	seed(11)
	Course.use(Course.from_wire(Course.to_wire({"name": "Payoff Three",
		"holes": [Course.blank_hole(4), Course.blank_hole(3), Course.blank_hole(4)]})))
	# A best to beat on every hole (a hole is capped below it), and a round.
	for n in range(1, 4):
		Records.record_hole(n, 12)
	Records.record_round("You", 60, 11, "solo")
	GameSetup.reset_to_local(1)
	m = load("res://scenes/Main.tscn").instantiate()
	get_root().add_child(m)
	bot = GreedyBot.new(4)
	bot.allow_hunt = false
	started = Time.get_ticks_msec()


func _wipe() -> void:
	for f in [RECORDS_FILE, SAVE_FILE, SETTINGS_FILE]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _labels(n: Node, out: Array) -> Array:
	for c in n.get_children():
		if c is Label and c.is_visible_in_tree():
			out.append(c)
		_labels(c, out)
	return out


func _cards(n: Node, out: Array) -> Array:
	for c in n.get_children():
		if c is CardView:
			out.append(c)
		_cards(c, out)
	return out


func _process(_delta: float) -> bool:
	if m.players.is_empty():
		return false   # the scene's _ready() hasn't run yet
	if Time.get_ticks_msec() - started > LIMIT_MSEC:
		fails.append("ran out of time in state %d on hole %d" % [m.state, m.current_hole_index])
		return _finish()
	_watch()
	if m.state == m.State.DONE:
		# Give the tally its time, then read the card.
		if done_at == 0:
			done_at = Time.get_ticks_msec()
		if Time.get_ticks_msec() - done_at < TALLY_WAIT_MSEC:
			return false
		_check_card()
		return _finish()
	# One action at a time, once the last has finished on screen.
	if m._animating or m._putt_rolling():
		return false
	if not bot.act(m):
		fails.append("no move in state %d on hole %d" % [m.state, m.current_hole_index])
		return _finish()
	return false


# What is on screen this frame.
func _watch() -> void:
	var banner = m.hole_banner
	if banner.is_showing():
		var title: String = banner._title.text
		if title.ends_with(" FT") or title == "FAIRWAY":
			seen.note = true
			if banner._sub.text.contains("mark") and title == "FAIRWAY":
				seen.fairway_mark = true
		if banner._sub.text.contains("your best here"):
			seen.best = true
	if m.state == m.State.CLUB_SELECT:
		# By its tint, not its swell: the bag row is a container, and a
		# container puts a child's scale back to one when it next sorts.
		for cv in _cards(m.options_container, []):
			if cv._panel != null and cv._panel.modulate.r < 0.99:
				seen.flash = true
	if m.interlude.visible:
		for cv in _cards(m.interlude, []):
			if cv.modulate.a < 0.99:
				seen.deal = true
		for l in _labels(m.interlude, []):
			var t: String = l.text
			if t.to_upper().begins_with("STROKES IN HAND") and (t.contains("+") or t.contains("−")):
				seen.count = true


func _check_card() -> void:
	var p = m.players[0]
	_expect(seen.note, "no long shot was noted on the map in %d holes" % p.round_scores.size())
	_expect(seen.best, "a hole best was beaten and the stamp did not say so")
	_expect(p.bests == p.round_scores.size(), "%d bests counted over %d holes, every one of them a best" % [p.bests, p.round_scores.size()])
	_expect(seen.deal, "the rack was never dealt")
	# A drive that marked its club is followed by the bag row, where the mark lands.
	if seen.fairway_mark:
		_expect(seen.flash, "a club's mark never landed on its tile")
	# Strokes in hand move after any hole but the last that was not a par.
	var moved := false
	for i in range(p.round_scores.size() - 1):
		moved = moved or int(p.round_scores[i].strokes) != int(p.round_scores[i].par)
	if moved and not m._run_over:
		_expect(seen.count, "strokes in hand never showed what a hole paid or cost")

	if m._run_over:
		return   # out of strokes: no record, and the headline is not a score
	var texts: Array = _labels(m.interlude, []).map(func(l): return l.text)
	_expect(texts.any(func(t): return t.begins_with("A new course record: %d beats 60" % p.total_strokes())),
		"the card did not announce the course record (it says %s)" % str(texts.slice(0, 6)))
	_expect(texts.any(func(t): return t.begins_with("%d — " % p.total_strokes())),
		"the headline did not finish on the score (it says %s)" % str(texts.slice(0, 3)))
	_expect(texts.any(func(t): return t.begins_with("Your best beaten on %d hole" % p.bests)),
		"the card did not count the bests beaten")
	# Every line of the card has arrived.
	var faint := 0
	for l in _labels(m.interlude, []):
		var n: Node = l
		while n != null and n != m.interlude:
			if n is CanvasItem and (n as CanvasItem).modulate.a < 0.99:
				faint += 1
				break
			n = n.get_parent()
	_expect(faint == 0, "%d lines of the card had not arrived after the tally" % faint)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _finish() -> bool:
	print("seen: %s" % str(seen))
	if fails.is_empty():
		print("\nPAYOFFS: OK")
	else:
		for f in fails:
			print("  !! " + f)
		print("\nPAYOFFS: FAIL (%d)" % fails.size())
	if m != null:
		m.free()
	_wipe()
	Course.use_builtin()
	quit(0 if fails.is_empty() else 1)
	return true
