extends SceneTree

# ---------------------------------------------------------
# NETWORKED ROUND HARNESS — two real ENet peers, one process.
#
# Dev tool, not shipped. A host and a client each get their own
# MultiplayerAPI bound to their own subtree, which is how one process can
# hold both ends of a real socket. Actions go over the wire as RPCs; the
# host resolves them and broadcasts; the client mirrors.
#
# After every action it asserts the two peers agree about the round —
# whose turn it is, where every ball is, every score, every bag. Desync
# is THE bug class for this feature, so the test is built around catching
# it rather than around finishing a round.
#
#   godot --headless --script res://scripts/NetTest.gd
#   NETTEST_HOLES=3 godot --headless --script res://scripts/NetTest.gd
#
# Note this shares a process, so it cannot catch genuine socket problems
# (MTU, real latency, packet loss). It covers the protocol and the
# mirroring, which is where the logic bugs live.
# ---------------------------------------------------------

const PORT := 46121
const SEATS := 2

var host_api: MultiplayerAPI
var cli_api: MultiplayerAPI
var host_game = null
var cli_game = null

var frames := 0
var actions := 0
var drifts: Array = []
var holes_to_play := 18
var phase := "connecting"
var settle := 0
var _pending_check := false
var _host_root: Node
var _cli_root: Node
var drop_at := 0        # NETTEST_DROP_AT=N closes the client at action N
var dropped := false
var _drop_reported := false


func _initialize() -> void:
	var raw := OS.get_environment("NETTEST_HOLES")
	if not raw.is_empty():
		holes_to_play = clampi(int(raw), 1, 18)
	var d := OS.get_environment("NETTEST_DROP_AT")
	if not d.is_empty():
		drop_at = maxi(int(d), 1)

	var host_root := Node.new()
	host_root.name = "HostRoot"
	var cli_root := Node.new()
	cli_root.name = "CliRoot"
	get_root().add_child(host_root)
	get_root().add_child(cli_root)

	var server := ENetMultiplayerPeer.new()
	var e1 := server.create_server(PORT, SEATS)
	host_api = MultiplayerAPI.create_default_interface()
	host_api.multiplayer_peer = server
	set_multiplayer(host_api, ^"/root/HostRoot")

	var client := ENetMultiplayerPeer.new()
	var e2 := client.create_client("127.0.0.1", PORT)
	cli_api = MultiplayerAPI.create_default_interface()
	cli_api.multiplayer_peer = client
	set_multiplayer(cli_api, ^"/root/CliRoot")

	if e1 != OK or e2 != OK:
		print("NETTEST: FAIL — could not open peers (server=%d client=%d)" % [e1, e2])
		quit(1)
		return

	_host_root = host_root
	_cli_root = cli_root


# Built once the peers are connected AND the roots are in the tree, so
# each game's `multiplayer` resolves to its own subtree API.
func _build_games() -> void:
	var payload := _roll_payload()
	host_game = _spawn_game(_host_root, payload, 0, true)
	cli_game = _spawn_game(_cli_root, payload, 1, false)
	print("host authority=%s / client authority=%s" % [
		host_game.is_authority(), cli_game.is_authority()])
	print("host api is harness api: %s" % str(host_game.multiplayer == host_api))
	print("host connected to drop signal: %s" % str(
		host_game.multiplayer.peer_disconnected.is_connected(host_game.on_peer_dropped)))


func _roll_payload() -> Dictionary:
	var scratch = load("res://scenes/Main.tscn").instantiate()
	scratch.player_count = SEATS
	scratch.init_game()
	var p: Dictionary = scratch.build_round_payload()
	scratch.free()
	return p


func _spawn_game(parent: Node, payload: Dictionary, seat: int, is_host: bool):
	var g = load("res://scenes/Main.tscn").instantiate()
	g.name = "Game"
	parent.add_child(g)
	# add_child() from _initialize() defers _ready(), so do its work here —
	# the same calls, with the online fields set as GameSetup would.
	g.player_count = SEATS
	g.online = true
	g.my_seat = seat
	g.build_ui()
	g.apply_round_payload(payload)
	g.start_hole()
	g.map_view.skip_animation = true
	g.connect_net_signals()
	g.set_meta("is_host", is_host)
	g._net_trace = OS.get_environment("NETTEST_TRACE") != ""
	return g


func _process(_delta: float) -> bool:
	frames += 1
	host_api.poll()
	cli_api.poll()

	if frames > 400000:
		print("NETTEST: FAIL — ran out of frames in phase '%s'" % phase)
		return _finish(false)

	match phase:
		"connecting":
			if cli_api.get_unique_id() != 0 and host_api.get_peers().size() > 0:
				print("peers connected (client id %d)" % cli_api.get_unique_id())
				_build_games()
				phase = "playing"
			return false
		"playing":
			return _play_step()
	return false


func _play_step() -> bool:
	# Let in-flight RPCs land before reading state or acting again.
	if settle > 0:
		settle -= 1
		return false
	if _pending_check:
		_pending_check = false
		if not dropped:
			_check_agreement()

	# Simulated disconnect: pull the client's socket and let the host carry
	# the round on its own.
	if drop_at > 0 and not dropped and actions >= drop_at:
		dropped = true
		print("dropping the client at action %d" % actions)
		cli_api.multiplayer_peer.close()
		settle = 60
		return false

	if dropped and not _drop_reported:
		_drop_reported = true
		var l = host_game.players[1]
		print("  after drop: abandoned=%s host_peers=%s active=%d state=%d" % [
			l.abandoned, str(host_api.get_peers()), host_game.active_index, host_game.state])

	if host_game.state == host_game.State.DONE:
		print("round finished on the host")
		if dropped:
			var left = host_game.players[1]
			print("departed seat: abandoned=%s holes_scored=%d" % [
				left.abandoned, left.round_scores.size()])
			var survivor = host_game.players[0]
			print("survivor holes_scored=%d" % survivor.round_scores.size())
			var ok: bool = left.abandoned and survivor.round_scores.size() == 18
			if not ok:
				print("  FAIL: round did not complete cleanly after the drop")
			return _finish(ok)
		return _finish(drifts.is_empty())
	if host_game.current_hole_index > holes_to_play:
		print("reached hole %d, stopping as asked" % host_game.current_hole_index)
		return _finish(drifts.is_empty())

	# Whoever is up acts, through the same submit() path the UI uses.
	var seat: int = host_game.active_index
	var actor = host_game if (seat == 0 or dropped) else cli_game
	var kind_payload := _pick_action(actor)
	if kind_payload.is_empty():
		print("NETTEST: FAIL — no legal action in state %d (hole %d)%s" % [
			host_game.state, host_game.current_hole_index,
			" (after a drop)" if dropped else ""])
		return _finish(false)

	actions += 1
	# After a drop the host plays on alone, so point its my_seat at
	# whichever seat is up — submit() checks that before sending. A real
	# host only ever plays its own seat; this is the harness standing in
	# for the remaining humans.
	if dropped:
		actor.my_seat = seat
	actor.submit(kind_payload.kind, kind_payload.payload)
	# Assert on the NEXT visit, once the round trip (client -> host ->
	# broadcast back) has had frames to land. Checking in this same frame
	# would compare the host's new state against a client that has not
	# been told yet.
	settle = 30
	_pending_check = true
	return false


# Chooses a legal action for the state the given peer believes it is in.
func _pick_action(g) -> Dictionary:
	match g.state:
		g.State.CLUB_SELECT:
			if g.hand.is_empty():
				return {}
			return {"kind": "club", "payload": {"index": randi() % g.hand.size()}}
		g.State.AIM:
			return {"kind": "aim", "payload": {"target": g.map_view.aim_target}}
		g.State.FORM_DRAW:
			if g.current_form_options.is_empty():
				return {}
			return {"kind": "form", "payload": {"index": randi() % g.current_form_options.size()}}
		g.State.DRAFT:
			if g.current_draft_options.is_empty():
				return {}
			return {"kind": "draft", "payload": {"index": randi() % g.current_draft_options.size()}}
		g.State.DISCARD_FOR_DRAFT, g.State.DISCARD_FOR_HAZARD:
			if g.hand.is_empty():
				return {}
			return {"kind": "discard", "payload": {"index": randi() % g.hand.size()}}
		g.State.PUTTING:
			return {"kind": "putt", "payload": {
				"result": ["sunk", "close", "miss"][randi() % 3],
				"accuracy": randf()}}
	return {}


# The host is authoritative, so any difference is the client having
# drifted. Reported with the action count so a failure is locatable.
func _check_agreement() -> void:
	var ctx := "action %d (hole %d)" % [actions, host_game.current_hole_index]
	_cmp(ctx, "hole", host_game.current_hole_index, cli_game.current_hole_index)
	_cmp(ctx, "state", host_game.state, cli_game.state)
	_cmp(ctx, "active_index", host_game.active_index, cli_game.active_index)
	for i in range(host_game.players.size()):
		var a = host_game.players[i]
		var b = cli_game.players[i]
		var who := "p%d" % i
		_cmp(ctx, who + ".ball", a.ball_pos.snapped(Vector2(0.001, 0.001)),
			b.ball_pos.snapped(Vector2(0.001, 0.001)))
		_cmp(ctx, who + ".strokes", a.strokes, b.strokes)
		_cmp(ctx, who + ".lie", a.current_lie, b.current_lie)
		_cmp(ctx, who + ".holed_out", a.holed_out, b.holed_out)
		_cmp(ctx, who + ".bag", str(_names(a.hand)), str(_names(b.hand)))
		_cmp(ctx, who + ".scores", str(a.round_scores), str(b.round_scores))
		_cmp(ctx, who + ".form_deck_size", a.form_deck.deck.size(), b.form_deck.deck.size())


func _names(bag: Array) -> Array:
	var out: Array = []
	for c in bag:
		out.append(c.name)
	return out


func _cmp(ctx: String, field: String, va, vb) -> void:
	if va != vb and drifts.size() < 40:
		drifts.append("[%s] %s: host=%s client=%s" % [ctx, field, str(va), str(vb)])


func _finish(ok: bool) -> bool:
	print("")
	if ok and drifts.is_empty():
		print("NETTEST: OK — %d actions over a real socket, host and client agreed throughout" % actions)
	else:
		print("NETTEST: FAIL — %d drift(s) across %d actions" % [drifts.size(), actions])
		var shown := 0
		for d in drifts:
			print("  %s" % d)
			shown += 1
			if shown >= 20:
				break
	if host_game != null:
		host_game.free()
	if cli_game != null:
		cli_game.free()
	quit(0 if (ok and drifts.is_empty()) else 1)
	return true
