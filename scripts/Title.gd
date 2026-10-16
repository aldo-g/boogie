extends Control

# ---------------------------------------------------------
# BOGEY TITLE SCREEN + LOBBY
# Course map fills the entire background, washed to parchment on the
# left where the menu card sits.
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
const EDITOR_SCENE := "res://scenes/CourseEditor.tscn"

const MAX_PLAYERS := 4
const CARD_WIDTH := 560

const COLOR_DARK_GREEN := Palette.FAIRWAY_DEEP
const COLOR_FADED_WHITE := Palette.PARCHMENT

enum Mode { MENU, HOSTING, JOINING, CREDITS }

var mode: int = Mode.MENU
var panel: VBoxContainer          # the part that changes per mode
var status: Label
var address_field: LineEdit
var name_field: LineEdit
var start_button: Button
var card: PanelContainer


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
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# A parchment wash fading in from the left, so the menu sits on calm
	# paper and the course stays the hero on the right.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.62])
	grad.colors = PackedColorArray([
		Color(COLOR_FADED_WHITE, 0.9), Color(COLOR_FADED_WHITE, 0.7), Color(COLOR_FADED_WHITE, 0.0)])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(1, 0)
	var wash := TextureRect.new()
	wash.texture = grad_tex
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 88)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	# The menu card. It stops mouse input, so only clicks on the open
	# course fall through to the tee-off-solo shortcut.
	var card_style := BogeyUI.panel(BogeyTheme.CARD_BG, 40, 18)
	card_style.content_margin_top = 28
	card_style.content_margin_bottom = 28
	card_style.border_color = BogeyTheme.RULE
	card_style.set_border_width_all(1)
	card_style.shadow_color = BogeyTheme.SHADOW_LG
	card_style.shadow_size = 28
	card_style.shadow_offset = Vector2(0, 10)
	card = BogeyUI.make_panel(card_style)
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "Bogey!"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 104)
	title.add_theme_color_override("font_color", COLOR_DARK_GREEN)
	vbox.add_child(title)

	vbox.add_child(_kicker("A golf card game"))
	vbox.add_child(_gap(14))

	status = BogeyUI.body("Choose how you want to play", 16, BogeyTheme.INK_SOFT)
	vbox.add_child(status)
	vbox.add_child(_gap(20))

	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	vbox.add_child(panel)

	_rebuild_panel()

	# Ease the card in rather than popping it on.
	card.modulate.a = 0.0
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.45)


func _kicker(text: String) -> Label:
	var l := BogeyUI.kicker(text)
	l.add_theme_font_size_override("font_size", 12)
	return l


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", BogeyTheme.NEUTRAL_600)
	return l


func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_NONE
	return BogeyUI.style_button(b, primary)


func _field(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 42)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return BogeyUI.style_line_edit(e)


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
		Mode.CREDITS:
			_build_credits()


func _build_menu() -> void:
	_build_course_picker()
	panel.add_child(_gap(2))
	panel.add_child(BogeyUI.hairline(0.12))
	panel.add_child(_gap(2))

	panel.add_child(_kicker("On this screen"))

	var local_row := HBoxContainer.new()
	local_row.add_theme_constant_override("separation", 8)
	panel.add_child(local_row)

	for n in range(1, MAX_PLAYERS + 1):
		var b := _button("Solo" if n == 1 else "%d Players" % n, n == 1)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_local_pressed.bind(n))
		local_row.add_child(b)

	panel.add_child(BogeyUI.body(
		"Hot-seat — everyone shares this screen, furthest from the pin plays first.", 13))

	panel.add_child(_gap(6))
	panel.add_child(BogeyUI.hairline(0.12))
	panel.add_child(_gap(6))

	panel.add_child(_kicker("Online"))

	# Two columns: your name pairs with hosting, the address with joining.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	panel.add_child(cols)

	var host_col := VBoxContainer.new()
	host_col.add_theme_constant_override("separation", 6)
	host_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(host_col)
	host_col.add_child(_caption("Your name"))
	name_field = _field("Player", "your name")
	name_field.max_length = 16
	host_col.add_child(name_field)
	var host_btn := _button("Host Game")
	host_btn.pressed.connect(_on_host_pressed)
	host_col.add_child(host_btn)

	var join_col := VBoxContainer.new()
	join_col.add_theme_constant_override("separation", 6)
	join_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(join_col)
	join_col.add_child(_caption("Host address"))
	address_field = _field("127.0.0.1", "host address")
	join_col.add_child(address_field)
	var join_btn := _button("Join Game")
	join_btn.pressed.connect(_on_join_pressed)
	join_col.add_child(join_btn)

	panel.add_child(BogeyUI.body("Same network, or a direct IP. Up to 4 players.", 13))

	panel.add_child(_gap(4))
	panel.add_child(BogeyUI.hairline(0.12))

	var footer := HBoxContainer.new()
	panel.add_child(footer)
	var credits_btn := BogeyUI.style_link_button(Button.new())
	credits_btn.text = "Credits"
	credits_btn.focus_mode = Control.FOCUS_NONE
	credits_btn.pressed.connect(_on_credits_pressed)
	footer.add_child(credits_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var hint := BogeyUI.body("or click the course to tee off solo", 12, BogeyTheme.NEUTRAL_500)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(hint)


# Which course this round is played on: the built-in one or anything
# saved from the editor. Applies to solo, hot-seat and hosted rounds alike —
# a hosted round sends the course to everyone who joins.
func _build_course_picker() -> void:
	panel.add_child(_kicker("Course"))
	var courses := _course_choices()
	var index := 0
	for i in courses.size():
		if str(courses[i].path) == Course.active_path and (courses[i].path != "" or Course.is_builtin()):
			index = i
			break

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var prev := _button("‹")
	prev.custom_minimum_size = Vector2(46, 46)
	prev.disabled = courses.size() < 2
	prev.pressed.connect(_on_course_step.bind(courses, index, -1))
	row.add_child(prev)

	var s := BogeyUI.panel(BogeyTheme.NEUTRAL_100, 0, 10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.border_color = BogeyTheme.NEUTRAL_400
	s.set_border_width_all(1)
	var box := BogeyUI.make_panel(s)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(col)
	var name_l := BogeyUI.body(Course.active_name, 15, BogeyTheme.INK)
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.clip_text = true
	col.add_child(name_l)
	col.add_child(BogeyUI.body(Course.summary(Course.active()), 12, BogeyTheme.NEUTRAL_600))

	var next := _button("›")
	next.custom_minimum_size = Vector2(46, 46)
	next.disabled = courses.size() < 2
	next.pressed.connect(_on_course_step.bind(courses, index, 1))
	row.add_child(next)

	var edit := _button("Course editor")
	edit.pressed.connect(_on_editor_pressed)
	row.add_child(edit)


func _course_choices() -> Array:
	var out: Array = [{"name": Course.BUILTIN_NAME, "path": ""}]
	out.append_array(Course.list_saved())
	return out


func _on_course_step(courses: Array, index: int, step: int) -> void:
	Sound.play("ui_click")
	var pick: Dictionary = courses[posmod(index + step, courses.size())]
	if str(pick.path) == "" or not Course.use_file(str(pick.path)):
		Course.use_builtin()
	_rebuild_panel()


func _on_editor_pressed() -> void:
	Sound.play("ui_confirm")
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _seat_row(seat: int) -> PanelContainer:
	var s := BogeyUI.panel(BogeyTheme.NEUTRAL_100, 12, 10)
	s.border_color = BogeyTheme.RULE
	s.set_border_width_all(1)
	var p := BogeyUI.make_panel(s)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)

	var dot_style := BogeyUI.panel(BogeyTheme.FAIRWAY_DEEP, 0, 99)
	dot_style.content_margin_left = 10
	dot_style.content_margin_right = 10
	dot_style.content_margin_top = 3
	dot_style.content_margin_bottom = 3
	var dot := BogeyUI.make_panel(dot_style)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var num := Label.new()
	num.text = str(seat + 1)
	num.add_theme_font_size_override("font_size", 13)
	num.add_theme_color_override("font_color", BogeyTheme.NEUTRAL_100)
	dot.add_child(num)
	row.add_child(dot)

	var name_label := BogeyUI.body(Net.name_for_seat(seat), 16, BogeyTheme.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	if seat == 0:
		var t := BogeyUI.tag("Host", BogeyTheme.OLIVE_200, BogeyTheme.OLIVE_800)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
	if seat == Net.my_seat:
		var t := BogeyUI.tag("You", BogeyTheme.ACCENT_200, BogeyTheme.ACCENT_800)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
	return p


func _build_lobby() -> void:
	if mode == Mode.HOSTING:
		# Only the host knows the course until the round starts; it's sent
		# with the opening decks.
		panel.add_child(BogeyUI.body("Course: %s · %s" % [
			Course.active_name, Course.summary(Course.active())], 13, BogeyTheme.NEUTRAL_700))
	panel.add_child(_kicker("Players"))

	var seats := Net.seats_in_order()
	if seats.is_empty():
		panel.add_child(BogeyUI.body("Waiting…", 14))
	for seat in seats:
		panel.add_child(_seat_row(int(seat)))

	if mode == Mode.HOSTING:
		# Show the address rather than telling the host to go and find it.
		# This is the whole setup step for two people in one house.
		var addr := Net.lan_address()
		if addr != "":
			var text := "On the same network, they join with:   %s" % addr
			if Net.DEFAULT_PORT != 45888:
				text += "   (port %d)" % Net.DEFAULT_PORT
			panel.add_child(_gap(4))
			panel.add_child(BogeyUI.note_box(text,
				BogeyTheme.ACCENT_100, BogeyTheme.ACCENT_300, BogeyTheme.ACCENT_800))
			# A machine can have several addresses and the guess above can
			# be wrong (VPNs, virtual adapters), so list the others.
			var others: Array = Net.all_lan_addresses().filter(
				func(a): return a != addr)
			if not others.is_empty():
				panel.add_child(BogeyUI.body(
					"If that doesn't work, try: %s" % ", ".join(others), 12))
		else:
			panel.add_child(BogeyUI.note_box(
				"Couldn't detect this machine's network address — check your "
				+ "Wi-Fi settings for it. Port %d." % Net.DEFAULT_PORT,
				BogeyTheme.ACCENT_100, BogeyTheme.ACCENT_300, BogeyTheme.ACCENT_800))
	else:
		panel.add_child(BogeyUI.body("Waiting for the host to start…", 13))

	panel.add_child(_gap(6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var cancel := _button("Back")
	cancel.custom_minimum_size.x = 140
	cancel.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel)

	if mode == Mode.HOSTING:
		start_button = _button("Start Round", true)
		start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# One player is a legitimate online round (handy for testing), so
		# this is never disabled on headcount.
		start_button.pressed.connect(_on_start_pressed)
		row.add_child(start_button)


# The credits screen. This is a licence obligation rather than a nicety:
# the Form card icons are CC BY 3.0, which requires the authors to be
# credited where the work is used, so the names have to be reachable from
# inside the game and not only from a file in the repo.
#
# Scrolls, because the list is longer than the panel on a small window and
# a credit the player cannot scroll to is not a credit.
func _build_credits() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	for section in Credits.SECTIONS:
		col.add_child(BogeyUI.heading(str(section.heading), 16))
		if str(section.note) != "":
			var note := _caption(str(section.note))
			note.add_theme_color_override("font_color", BogeyTheme.SAND_DEEP)
			col.add_child(note)
		for line in section.lines:
			var l := BogeyUI.body(str(line), 13)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			col.add_child(l)
		col.add_child(_gap(12))

	col.add_child(BogeyUI.body(Credits.LICENCE_NOTE, 12, BogeyTheme.NEUTRAL_600))

	panel.add_child(_gap(4))
	var back := _button("Back")
	back.custom_minimum_size.x = 140
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_on_credits_back_pressed)
	panel.add_child(back)


func _on_credits_pressed() -> void:
	Sound.play("ui_click")
	mode = Mode.CREDITS
	status.text = "Credits"
	_rebuild_panel()


func _on_credits_back_pressed() -> void:
	Sound.play("ui_back")
	mode = Mode.MENU
	status.text = "Choose how you want to play"
	_rebuild_panel()


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
	# Adopt the host's course before the game scene builds its scorecard
	# and header from it.
	# The host already has it — and keeps it as-is, so it still knows which
	# saved file the course came from.
	if not Net.is_host():
		var course := Course.from_wire(payload.get("course", {}))
		if course.is_empty():
			Course.use_builtin()
		else:
			Course.use(course)
	get_tree().change_scene_to_file(MAIN_SCENE)


# Clicking the background still tees off solo, but ONLY from the menu — in
# a lobby or the credits that shortcut would fire on every stray click and
# drop the player into a solo round instead of the screen they opened.
func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.MENU:
		return
	if (event is InputEventMouseButton or event is InputEventKey) and event.pressed:
		_on_local_pressed(1)
