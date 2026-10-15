extends Node

# ---------------------------------------------------------
# NET — the multiplayer connection, and nothing else.
#
# Autoload ("Net" in project.godot), because the peer has to outlive the
# title -> lobby -> game scene changes and has signals to hold. GameSetup's
# static-var trick can't do that.
#
# What lives here: the ENet peer, the seat table (which player index each
# connected machine controls), and the connection lifecycle. What does NOT
# live here: any game state. The round lives in Main.gd exactly as it does
# in a solo or hot-seat game.
#
# Authority model (host-authoritative): the host is also a player and owns
# every decision. Clients send what they want to do; the host decides what
# happened and tells everyone. Clients never roll dice.
#
# Transport is ENet over LAN or a direct IP. There is no relay, so playing
# over the internet needs port forwarding or a VPN (Tailscale/ZeroTier) —
# a deliberate trade for having no backend to run.
# ---------------------------------------------------------

signal lobby_changed()                  # seats joined/left — refresh the lobby list
signal connect_failed(reason: String)   # join attempt didn't land
signal host_lost()                      # the host went away mid-session
signal round_starting(payload: Dictionary)  # host said go; payload is the round setup

const DEFAULT_PORT := 45888
const MAX_PLAYERS := 4
const HOST_PEER_ID := 1

enum Role { LOCAL, HOST, CLIENT }

var role: int = Role.LOCAL

# seat index (0..3) -> peer id. The host is always seat 0, which lines up
# with start_hole()'s "first shot of a hole goes in seating order".
var seat_to_peer: Dictionary = {}
var seat_names: Dictionary = {}   # seat index -> display name

var my_seat: int = 0
var _local_name: String = "Player"


func is_online() -> bool:
	return role != Role.LOCAL


func is_host() -> bool:
	return role == Role.HOST


# The seat a given peer controls, or -1 if that peer isn't seated. Used by
# the host to decide whether an incoming action is allowed.
func seat_of_peer(peer_id: int) -> int:
	for seat in seat_to_peer:
		if int(seat_to_peer[seat]) == peer_id:
			return int(seat)
	return -1


func peer_of_seat(seat: int) -> int:
	return int(seat_to_peer.get(seat, -1))


func seated_count() -> int:
	return seat_to_peer.size()


# Seats in order, for building the lobby list and the round payload.
func seats_in_order() -> Array:
	var seats: Array = seat_to_peer.keys()
	seats.sort()
	return seats


func name_for_seat(seat: int) -> String:
	return str(seat_names.get(seat, "Player %d" % (seat + 1)))


# --- Hosting -----------------------------------------------------------

func host_game(player_name: String, port: int = DEFAULT_PORT) -> String:
	reset()
	var peer := ENetMultiplayerPeer.new()
	# max_clients excludes the host itself, so a 4-player game allows 3.
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return "Couldn't open port %d (error %d). Another host may already be running." % [port, err]

	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	_local_name = player_name
	my_seat = 0
	seat_to_peer[0] = HOST_PEER_ID
	seat_names[0] = player_name
	_connect_signals()
	lobby_changed.emit()
	return ""


# --- Joining -----------------------------------------------------------

func join_game(address: String, player_name: String, port: int = DEFAULT_PORT) -> String:
	reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return "Couldn't reach %s:%d (error %d)." % [address, port, err]

	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	_local_name = player_name
	my_seat = -1   # assigned by the host once connected
	_connect_signals()
	return ""


func local_name() -> String:
	return _local_name


# The address a player on the same network should type to reach this host.
#
# Picking this well matters more than it looks: a machine typically has
# several addresses — loopback, VPN tunnels, virtual-machine bridges — and
# handing out the wrong one fails with no useful error. So prefer the
# ordinary home-network ranges, and skip the 192.168.64+ block that
# virtualisation tools (Docker, UTM, Parallels) commonly claim.
func lan_address() -> String:
	var fallbacks: Array = []
	for addr in IP.get_local_addresses():
		if not addr.contains("."):
			continue  # IPv6
		if addr.begins_with("127.") or addr.begins_with("169.254."):
			continue  # loopback, link-local
		if addr.begins_with("192.168."):
			# 192.168.64-127 is the usual virtual-adapter range; keep it
			# only as a last resort.
			var third := int(addr.split(".")[2])
			if third >= 64 and third <= 127:
				fallbacks.append(addr)
				continue
			return addr
		if addr.begins_with("10.") or addr.begins_with("172."):
			fallbacks.append(addr)
	if not fallbacks.is_empty():
		return str(fallbacks[0])
	return ""


# Every candidate address, so the lobby can offer the rest if the first
# one turns out to be the wrong guess.
func all_lan_addresses() -> Array:
	var out: Array = []
	for addr in IP.get_local_addresses():
		if not addr.contains("."):
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		out.append(addr)
	return out


# --- Lifecycle ---------------------------------------------------------

func _connect_signals() -> void:
	# Reconnecting in one session is possible (host, quit, host again), so
	# every connect is guarded against doubling up.
	_connect_once(multiplayer.peer_connected, _on_peer_connected)
	_connect_once(multiplayer.peer_disconnected, _on_peer_disconnected)
	_connect_once(multiplayer.connected_to_server, _on_connected_to_server)
	_connect_once(multiplayer.connection_failed, _on_connection_failed)
	_connect_once(multiplayer.server_disconnected, _on_server_disconnected)


func _connect_once(sig: Signal, target: Callable) -> void:
	if not sig.is_connected(target):
		sig.connect(target)


# Drops the connection and forgets the session. Safe to call when there
# isn't one.
func reset() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	role = Role.LOCAL
	seat_to_peer.clear()
	seat_names.clear()
	my_seat = 0


# --- Host side ---------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if not is_host():
		return
	var seat := _first_free_seat()
	if seat < 0:
		# Lobby is full. Close this one rather than seating a fifth player.
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	seat_to_peer[seat] = peer_id
	seat_names[seat] = "Player %d" % (seat + 1)
	# Tell the newcomer which seat it has, and tell everyone the new roster.
	rpc_id(peer_id, "net_assign_seat", seat)
	_broadcast_roster()
	lobby_changed.emit()


func _on_peer_disconnected(peer_id: int) -> void:
	var seat := seat_of_peer(peer_id)
	if seat >= 0:
		seat_to_peer.erase(seat)
		seat_names.erase(seat)
	if is_host():
		_broadcast_roster()
	lobby_changed.emit()


func _first_free_seat() -> int:
	for seat in range(MAX_PLAYERS):
		if not seat_to_peer.has(seat):
			return seat
	return -1


func _broadcast_roster() -> void:
	var roster: Dictionary = {}
	for seat in seat_to_peer:
		roster[seat] = seat_names.get(seat, "Player %d" % (int(seat) + 1))
	rpc("net_roster", roster)


# --- Client side -------------------------------------------------------

func _on_connected_to_server() -> void:
	# Seat number arrives separately via net_assign_seat; announce our name
	# so the host can label the lobby.
	rpc_id(HOST_PEER_ID, "net_claim_name", _local_name)


func _on_connection_failed() -> void:
	reset()
	connect_failed.emit("Couldn't connect — check the address and that the host is waiting.")


func _on_server_disconnected() -> void:
	reset()
	host_lost.emit()


# --- RPCs --------------------------------------------------------------

@rpc("authority", "reliable")
func net_assign_seat(seat: int) -> void:
	my_seat = seat
	lobby_changed.emit()


@rpc("authority", "reliable")
func net_roster(roster: Dictionary) -> void:
	# The host's roster is the truth; replace rather than merge so a
	# departed player actually disappears.
	seat_to_peer.clear()
	seat_names.clear()
	for seat in roster:
		var s := int(seat)
		seat_names[s] = str(roster[seat])
		# Clients don't need real peer ids, only that the seat is taken.
		seat_to_peer[s] = 0
	lobby_changed.emit()


@rpc("any_peer", "reliable")
func net_claim_name(player_name: String) -> void:
	if not is_host():
		return
	var seat := seat_of_peer(multiplayer.get_remote_sender_id())
	if seat < 0:
		return
	# Trim and bound it — this string goes straight into other players' UI.
	var clean := player_name.strip_edges().substr(0, 16)
	seat_names[seat] = clean if clean != "" else "Player %d" % (seat + 1)
	_broadcast_roster()
	lobby_changed.emit()


# Host only: hand everyone the round setup and send them into the game.
# call_local so the host runs the identical path it just told clients to
# run, rather than a separate setup that could drift from it.
@rpc("authority", "call_local", "reliable")
func net_start_round(payload: Dictionary) -> void:
	round_starting.emit(payload)
