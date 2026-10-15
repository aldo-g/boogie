extends Control

# ---------------------------------------------------------
# BOGEY TITLE SCREEN + LOBBY
# Course map fills the entire background. Title wordmark sits on
# top of it in the open space.
#
# Three modes in one screen rather than separate scenes, since the whole
# UI is built in code and swapping a panel is cheaper than a scene change:
#   MENU     — solo, hot-seat counts, host, join
#   HOSTING  — the seat roster filling up, with Start
#   JOINING  — address entry, then the roster while we wait for the host
#
# Online rounds are ENet over LAN or a direct IP (see Net.gd). Playing
# across the internet needs port forwarding or a VPN.
# ---------------------------------------------------------

const COURSE_MAP := preload("res://assets/maps/llanfair-course.jpeg")
const TITLE_FONT := preload("res://assets/fonts/AlexBrush-Regular.ttf")
const Palette := preload("res://scripts/BogeyTheme.gd")
const MAIN_SCENE := "res://scenes/Main.tscn"

const MAX_PLAYERS := 4

const COLOR_DARK_GREEN := Palette.FAIRWAY_DEEP
const COLOR_FADED_WHITE := Palette.PARCHMENT

enum Mode { MENU, HOSTING, JOINING }

var mode: int = Mode.MENU
var panel: VBoxContainer          # the part that changes per mode
var status: Label
var address_field: LineEdit
var name_field: LineEdit
var start_button: Button


func _ready() -> void:
	# A previous round may have left a connection open.
	Net.reset()
	Net.lobby_changed.connect(_rebuild_panel)
	Net.connect_failed.connect(_on_connect_failed)
	Net.host_lost.connect(_on_host_lost)
	Net.round_starting.connect(_on_round_starting)
	build_ui()


func build_ui() -> void:
	# Course map, filling the entire window edge-to-edge.
	var bg := TextureRect.new()
	bg.texture = COURSE_MAP
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vbox.offset_left = 40
	vbox.offset_top = 24
	add_child(vbox)

	var title := Label.new()
	title.text = "Bogey!"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", COLOR_DARK_GREEN)
	title.add_theme_color_override("font_outline_color", COLOR_FADED_WHITE)
	title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title)

	status = _outlined_label("Choose how you want to play", 16)
	vbox.add_child(status)

	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	vbox.add_child(panel)

	_rebuild_panel()


func _outlined_label(text: String, size: int) -> Label:
	# The map behind is busy, so every label needs an outline to stay legible.
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", COLOR_DARK_GREEN)
	l.add_theme_color_override("font_outline_color", COLOR_FADED_WHITE)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _button(text: String, width: int = 150) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 40)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _clear(c: Node) -> void:
	for child in c.get_children():
		child.queue_free()
		c.remove_child(child)


# --- Panels ------------------------------------------------------------

func _rebuild_panel() -> void:
	if panel == null:
		return
	_clear(panel)
	match mode:
		Mode.MENU:
			_build_menu()
		Mode.HOSTING, Mode.JOINING:
			_build_lobby()


func _build_menu() -> void:
	panel.add_child(_outlined_label("One screen", 13))

	var local_row := HBoxContainer.new()
	local_row.add_theme_constant_override("separation", 8)
	panel.add_child(local_row)

	for n in range(1, MAX_PLAYERS + 1):
		var b := _button("1 Player" if n == 1 else "%d Players" % n, 118)
		b.pressed.connect(_on_local_pressed.bind(n))
		local_row.add_child(b)

	panel.add_child(_outlined_label(
		"Hot-seat — everyone plays on this screen, furthest from the pin first.", 12))

	panel.add_child(_outlined_label("Online", 13))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	panel.add_child(name_row)
	name_row.add_child(_outlined_label("Your name", 12))
	name_field = LineEdit.new()
	name_field.text = "Player"
	name_field.max_length = 16
	name_field.custom_minimum_size = Vector2(160, 36)
	name_row.add_child(name_field)

	var online_row := HBoxContainer.new()
	online_row.add_theme_constant_override("separation", 8)
	panel.add_child(online_row)

	var host_btn := _button("Host Game")
	host_btn.pressed.connect(_on_host_pressed)
	online_row.add_child(host_btn)

	address_field = LineEdit.new()
	address_field.text = "127.0.0.1"
	address_field.placeholder_text = "host address"
	address_field.custom_minimum_size = Vector2(160, 36)
	online_row.add_child(address_field)

	var join_btn := _button("Join Game")
	join_btn.pressed.connect(_on_join_pressed)
	online_row.add_child(join_btn)

	panel.add_child(_outlined_label(
		"Same network, or a direct IP. Up to 4 players.", 12))


func _build_lobby() -> void:
	panel.add_child(_outlined_label("Players", 13))

	var seats := Net.seats_in_order()
	if seats.is_empty():
		panel.add_child(_outlined_label("  (waiting…)", 13))
	for seat in seats:
		var label := "  Seat %d — %s" % [int(seat) + 1, Net.name_for_seat(int(seat))]
		if int(seat) == Net.my_seat:
			label += "   (you)"
		if int(seat) == 0:
			label += "   host"
		panel.add_child(_outlined_label(label, 14))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	if mode == Mode.HOSTING:
		start_button = _button("Start Round")
		# One player is a legitimate online round (handy for testing), so
		# this is never disabled on headcount.
		start_button.pressed.connect(_on_start_pressed)
		row.add_child(start_button)

	var cancel := _button("Back")
	cancel.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel)

	if mode == Mode.HOSTING:
		# Show the address rather than telling the host to go and find it.
		# This is the whole setup step for two people in one house.
		var addr := Net.lan_address()
		if addr != "":
			panel.add_child(_outlined_label(
				"On the same network, they join with:   %s" % addr, 15))
			if Net.DEFAULT_PORT != 45888:
				panel.add_child(_outlined_label("Port %d" % Net.DEFAULT_PORT, 12))
			# A machine can have several addresses and the guess above can
			# be wrong (VPNs, virtual adapters), so list the others.
			var others: Array = Net.all_lan_addresses().filter(
				func(a): return a != addr)
			if not others.is_empty():
				panel.add_child(_outlined_label(
					"If that doesn't work, try: %s" % ", ".join(others), 11))
		else:
			panel.add_child(_outlined_label(
				"Couldn't detect this machine's network address — check your "
				+ "Wi-Fi settings for it. Port %d." % Net.DEFAULT_PORT, 12))
	else:
		panel.add_child(_outlined_label("Waiting for the host to start…", 12))


# --- Menu actions ------------------------------------------------------

func _on_local_pressed(count: int) -> void:
	Sound.play("ui_confirm")
	GameSetup.reset_to_local(count)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_host_pressed() -> void:
	Sound.play("ui_confirm")
	var err := Net.host_game(_entered_name())
	if err != "":
		status.text = err
		return
	mode = Mode.HOSTING
	status.text = "Hosting — waiting for players"
	_rebuild_panel()


func _on_join_pressed() -> void:
	Sound.play("ui_confirm")
	var address := address_field.text.strip_edges() if address_field else ""
	if address == "":
		status.text = "Enter the host's address first."
		return
	var err := Net.join_game(address, _entered_name())
	if err != "":
		status.text = err
		return
	mode = Mode.JOINING
	status.text = "Connecting to %s…" % address
	_rebuild_panel()


func _entered_name() -> String:
	if name_field == null:
		return "Player"
	var n := name_field.text.strip_edges()
	return n if n != "" else "Player"


func _on_cancel_pressed() -> void:
	Sound.play("ui_back")
	Net.reset()
	mode = Mode.MENU
	status.text = "Choose how you want to play"
	_rebuild_panel()


func _on_start_pressed() -> void:
	if not Net.is_host():
		return
	Sound.play("ui_confirm")
	# The host builds every player's decks here and ships them, so no two
	# machines start the round from a different shuffle. Main.gd owns that
	# setup, so borrow an instance purely to roll it.
	var seats := Net.seats_in_order()
	var names: Dictionary = {}
	for seat in seats:
		names[int(seat)] = Net.name_for_seat(int(seat))

	var payload := _roll_round(seats.size(), names)
	Net.net_start_round.rpc(payload)


# Rolls a fresh round's decks without building any UI: Main.init_game()
# only touches game state, so a bare instance is enough to produce the
# starting bags, pools and Form decks.
func _roll_round(count: int, names: Dictionary) -> Dictionary:
	var scratch = load(MAIN_SCENE).instantiate()
	scratch.player_count = clampi(count, 1, MAX_PLAYERS)
	scratch.init_game()
	scratch.apply_seat_names(names)
	var payload: Dictionary = scratch.build_round_payload()
	scratch.free()
	payload["seat_names"] = names
	payload["player_count"] = clampi(count, 1, MAX_PLAYERS)
	return payload


# --- Net events --------------------------------------------------------

func _on_connect_failed(reason: String) -> void:
	mode = Mode.MENU
	status.text = reason
	_rebuild_panel()


func _on_host_lost() -> void:
	mode = Mode.MENU
	status.text = "The host closed the lobby."
	_rebuild_panel()


func _on_round_starting(payload: Dictionary) -> void:
	GameSetup.online = true
	GameSetup.player_count = clampi(int(payload.get("player_count", 1)), 1, MAX_PLAYERS)
	GameSetup.my_seat = maxi(Net.my_seat, 0)
	GameSetup.seat_names = payload.get("seat_names", {})
	GameSetup.round_payload = payload
	get_tree().change_scene_to_file(MAIN_SCENE)


# Clicking the background still tees off solo, but ONLY from the menu —
# in a lobby that shortcut would fire on every stray click and drop the
# player into a solo round instead of the game they were waiting for.
func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.MENU:
		return
	if (event is InputEventMouseButton or event is InputEventKey) and event.pressed:
		_on_local_pressed(1)
