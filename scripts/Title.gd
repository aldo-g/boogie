extends Control

# ---------------------------------------------------------
# PARS AND CHARS TITLE SCREEN + LOBBY
# Course map fills the entire background, washed to parchment on the
# left where the menu card sits.
#
# Three modes in one screen rather than separate scenes, since the whole
# UI is built in code and swapping a panel is cheaper than a scene change:
#   MENU     — solo, hot-seat counts, a computer opponent, host, join
#   HOSTING  — the seat roster filling up, with Start
#   JOINING  — address entry, then the roster while we wait for the host
#
# Online rounds are ENet over LAN or a direct IP (see Net.gd). Playing
# across the internet needs port forwarding or a VPN.
# ---------------------------------------------------------

const COURSE_MAP := preload("res://assets/maps/llanfair-course.jpeg")
const TITLE_FONT := preload("res://assets/fonts/AlexBrush-Regular.ttf")
const Palette := preload("res://scripts/BogeyTheme.gd")
const Rivals := preload("res://scripts/Rivals.gd")
const MAIN_SCENE := "res://scenes/Main.tscn"
const EDITOR_SCENE := "res://scenes/CourseEditor.tscn"

const MAX_PLAYERS := 4
const CARD_WIDTH := 560

const COLOR_DARK_GREEN := Palette.FAIRWAY_DEEP
const COLOR_FADED_WHITE := Palette.PARCHMENT

enum Mode { MENU, HOSTING, JOINING, CREDITS, SETTINGS, RECORDS }

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
	theme = BogeyUI.theme()

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
	var card_style := BogeyUI.panel(BogeyTheme.CARD_BG, 44, BogeyUI.RADIUS + 1)
	card_style.content_margin_top = 30
	card_style.content_margin_bottom = 30
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
	title.text = "Pars and Chars"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 84)
	# The wordmark is ink, like a signature — not a colour.
	title.add_theme_color_override("font_color", BogeyTheme.INK)
	vbox.add_child(title)

	vbox.add_child(_kicker("A golf card game"))
	vbox.add_child(_gap(18))

	# One line under the wordmark that says where you are: an invitation
	# on the menu, the state of the lobby once you're in one.
	status = BogeyUI.body("Choose how you want to play", 22, BogeyTheme.INK)
	status.add_theme_font_override("font", BogeyUI.serif_italic(500))
	vbox.add_child(status)
	vbox.add_child(_gap(18))

	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	vbox.add_child(panel)

	_rebuild_panel()

	# Ease the card in rather than popping it on.
	card.modulate.a = 0.0
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.45)


func _kicker(text: String) -> Label:
	return BogeyUI.kicker(text, BogeyTheme.INK, 11)


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _caption(text: String) -> Label:
	return BogeyUI.kicker(text, BogeyTheme.NEUTRAL_600, 9)


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
		Mode.SETTINGS:
			_build_settings()
		Mode.RECORDS:
			_build_records()


func _build_menu() -> void:
	_build_course_picker()
	panel.add_child(_gap(2))
	panel.add_child(BogeyUI.hairline(0.12))
	panel.add_child(_gap(2))

	# Each group is a label and its controls. What a group is for is said
	# once, quietly, beside its label — and again on the hover.
	panel.add_child(_group_head("On this screen", "Hot-seat: one screen, furthest from the pin plays first"))

	var local_row := HBoxContainer.new()
	local_row.add_theme_constant_override("separation", 8)
	panel.add_child(local_row)

	for n in range(1, MAX_PLAYERS + 1):
		var b := _button("Solo" if n == 1 else "%d Players" % n, n == 1)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_local_pressed.bind(n))
		local_row.add_child(b)

	# A round against one computer golfer: the same rules, their own bag
	# and draft. Three of them, by how well they play.
	panel.add_child(_gap(6))
	panel.add_child(_group_head("Against the computer", "Shot for shot; they draft their own bag"))
	var rival_row := HBoxContainer.new()
	rival_row.add_theme_constant_override("separation", 8)
	panel.add_child(rival_row)
	for skill in Rivals.ORDER:
		var b := _button("%s\n%s" % [Rivals.name_of(skill), Rivals.blurb_of(skill)])
		b.custom_minimum_size = Vector2(0, 58)
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "%s — %s on %s (par 71)." % [
			Rivals.name_of(skill), Rivals.typical_text(skill), Course.BUILTIN_NAME]
		b.pressed.connect(_on_rival_pressed.bind(skill))
		rival_row.add_child(b)

	panel.add_child(_gap(6))
	panel.add_child(BogeyUI.hairline(0.12))
	panel.add_child(_gap(6))

	panel.add_child(_group_head("Online", "Same network or a direct IP, up to 4 players"))

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

	panel.add_child(_gap(6))
	panel.add_child(BogeyUI.hairline(0.12))

	var footer := HBoxContainer.new()
	# Link buttons carry no box, so without a gap the three run together
	# into one phrase.
	footer.add_theme_constant_override("separation", 18)
	panel.add_child(footer)
	for link in [["Records", _on_records_pressed], ["Settings", _on_settings_pressed],
			["Credits", _on_credits_pressed]]:
		var b := Button.new()
		b.text = link[0]
		BogeyUI.style_link_button(b)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(link[1])
		footer.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var hint := BogeyUI.body("or click the course to tee off solo", 13, BogeyTheme.NEUTRAL_500)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(hint)


# A group's label, with a few quiet words on what the group is for set at
# the far end of the same line.
func _group_head(text: String, note: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_kicker(text))
	var l := BogeyUI.label(note, 12, BogeyTheme.NEUTRAL_500)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)
	return row


# Which course this round is played on: one of the game's own (see
# CourseLibrary) or anything saved from the editor. Applies to solo,
# hot-seat and hosted rounds alike — a hosted round sends the course to
# everyone who joins.
func _build_course_picker() -> void:
	panel.add_child(_kicker("Course"))
	var courses := _course_choices()
	var index := 0
	for i in courses.size():
		# A saved course is known by its file, one of the game's by its id.
		var c: Dictionary = courses[i]
		if (Course.active_path != "" and str(c.path) == Course.active_path) \
				or (Course.active_path == "" and str(c.id) != "" and str(c.id) == Course.active_id):
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

	var s := BogeyUI.panel(BogeyTheme.CARD_BG, 0, BogeyUI.RADIUS)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 6
	s.content_margin_bottom = 8
	s.border_color = BogeyTheme.NEUTRAL_400
	s.set_border_width_all(1)
	var box := BogeyUI.make_panel(s)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(col)
	var name_l := BogeyUI.heading(Course.active_name, 24)
	name_l.clip_text = true
	col.add_child(name_l)
	col.add_child(BogeyUI.body("%s · %s" % [Course.summary(Course.active()),
		CourseTheme.label(Course.active_theme)], 13, BogeyTheme.NEUTRAL_600))
	col.add_child(BogeyUI.body(Records.summary_line(), 13, BogeyTheme.NEUTRAL_600))
	box.tooltip_text = CourseLibrary.blurb(Course.active_id)

	var next := _button("›")
	next.custom_minimum_size = Vector2(46, 46)
	next.disabled = courses.size() < 2
	next.pressed.connect(_on_course_step.bind(courses, index, 1))
	row.add_child(next)

	var edit := _button("Course editor")
	edit.pressed.connect(_on_editor_pressed)
	row.add_child(edit)

	# What the terrain does to a shot, so the choice is an informed one.
	var terrain := BogeyUI.body("%s — %s." % [CourseTheme.label(Course.active_theme),
		CourseTheme.play_summary(Course.active_theme)], 13)
	terrain.tooltip_text = CourseTheme.blurb(Course.active_theme)
	terrain.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(terrain)


# Every course there is to pick, as [{ name, path, id }]: the game's own
# first (id set, no path), then the saved ones (path set, no id).
func _course_choices() -> Array:
	var out: Array = []
	for c in CourseLibrary.all():
		out.append({"name": c.name, "path": "", "id": c.id})
	for c in Course.list_saved():
		out.append({"name": c.name, "path": c.path, "id": ""})
	return out


func _on_course_step(courses: Array, index: int, step: int) -> void:
	Sound.play("ui_click")
	var pick: Dictionary = courses[posmod(index + step, courses.size())]
	var ok: bool = Course.use_shipped(str(pick.id)) if str(pick.id) != "" else Course.use_file(str(pick.path))
	if not ok:
		Course.use_builtin()
	_rebuild_panel()


func _on_editor_pressed() -> void:
	Sound.play("ui_confirm")
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _seat_row(seat: int) -> PanelContainer:
	var s := BogeyUI.panel(BogeyTheme.CARD_BG, 12, BogeyUI.RADIUS)
	s.border_color = BogeyTheme.NEUTRAL_300
	s.set_border_width_all(1)
	var p := BogeyUI.make_panel(s)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)

	var dot_style := BogeyUI.panel(BogeyTheme.INK, 0, 99)
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

	var name_label := BogeyUI.heading(Net.name_for_seat(seat), 21)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	if seat == 0:
		var t := BogeyUI.tag("Host", BogeyTheme.OLIVE_200, BogeyTheme.OLIVE_800)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
	if seat == Net.my_seat:
		var t := BogeyUI.tag("You", BogeyTheme.NEUTRAL_200, BogeyTheme.NEUTRAL_800)
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
		col.add_child(BogeyUI.heading(str(section.heading), 22))
		if str(section.note) != "":
			col.add_child(_caption(str(section.note)))
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


# The settings page — the same controls as the in-game popup.
func _build_settings() -> void:
	var settings := SettingsPanel.new()
	settings.closed.connect(_on_credits_back_pressed)
	panel.add_child(settings)


func _on_settings_pressed() -> void:
	Sound.play("ui_click")
	mode = Mode.SETTINGS
	status.text = "Settings"
	_rebuild_panel()


# The selected course's records: the best round, how you've been playing
# it lately, and your best on each hole.
func _build_records() -> void:
	panel.add_child(_kicker(Course.active_name))
	var best := Records.best_round()
	if best.is_empty():
		panel.add_child(BogeyUI.body("No rounds finished on this course yet. Your first one sets the record.", 14))
	else:
		var stats := HBoxContainer.new()
		stats.add_theme_constant_override("separation", 8)
		panel.add_child(stats)
		stats.add_child(BogeyUI.stat_block("Best", "%d (%s)" % [int(best.strokes), Records.diff_text(int(best.diff))]))
		stats.add_child(BogeyUI.stat_block("Rounds", str(Records.rounds_played())))
		stats.add_child(BogeyUI.stat_block("Average", "%.1f" % Records.average()))
		panel.add_child(BogeyUI.body("Best set by %s on %s (%s)." % [
			str(best.player), str(best.date), str(best.mode)], 12, BogeyTheme.NEUTRAL_600))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	# Hole by hole: the best you've managed on each, against par.
	col.add_child(BogeyUI.heading("Best on each hole", 22))
	var any_hole := false
	for n in range(1, Course.hole_count() + 1):
		var b := Records.hole_best(n)
		if b == 0:
			continue
		any_hole = true
		var par := int(HoleData.hole(n).par)
		var l := BogeyUI.body("Hole %d — par %d — best %d (%s)" % [n, par, b, Records.diff_text(b - par)], 13)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(l)
	if not any_hole:
		col.add_child(BogeyUI.body("No holes finished yet.", 13, BogeyTheme.NEUTRAL_600))

	var history := Records.history()
	if not history.is_empty():
		col.add_child(_gap(10))
		col.add_child(BogeyUI.heading("Recent rounds", 22))
		for e in history:
			var l := BogeyUI.body("%s — %s — %d (%s)%s" % [
				str(e.date), str(e.player), int(e.strokes), Records.diff_text(int(e.diff)),
				"" if str(e.mode) == "solo" else "  · %s" % str(e.mode)], 13)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			col.add_child(l)

	panel.add_child(_gap(4))
	var back := _button("Back")
	back.custom_minimum_size.x = 140
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_on_credits_back_pressed)
	panel.add_child(back)


func _on_records_pressed() -> void:
	Sound.play("ui_click")
	mode = Mode.RECORDS
	status.text = "Records"
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


# You in seat 0, the chosen computer golfer in seat 1.
func _on_rival_pressed(skill: String) -> void:
	Sound.play("ui_confirm")
	GameSetup.reset_to_local(2)
	GameSetup.cpu_seats = {1: skill}
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
