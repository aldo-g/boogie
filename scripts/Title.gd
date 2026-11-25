extends Control

# ---------------------------------------------------------
# PARS AND CHARS TITLE SCREEN + LOBBY
# The yardage book's front page (v2 mock): on the left, the wordmark and a
# column of ways to play — choosing one selects it, and the one TEE OFF
# button under the course starts it. On the right, the course the round
# will be played on, drawn whole, with the arrows that change it.
#
# Modes in one screen rather than separate scenes, since the whole UI is
# built in code and swapping a panel is cheaper than a scene change:
#   MENU     — the ways to play, and the course
#   HOSTING  — the seat roster filling up, with Start
#   JOINING  — connecting, then waiting for the host
#   CREDITS / SETTINGS / RECORDS — full pages with a Back
#
# Online rounds are ENet over LAN or a direct IP (see Net.gd). Playing
# across the internet needs port forwarding or a VPN.
# ---------------------------------------------------------

const TITLE_FONT := preload("res://assets/fonts/AlexBrush-Regular.ttf")
const Palette := preload("res://scripts/BogeyTheme.gd")
const Rivals := preload("res://scripts/Rivals.gd")
const CoursePlan := preload("res://scripts/CoursePlan.gd")
const RoundSave := preload("res://scripts/RoundSave.gd")
const MAIN_SCENE := "res://scenes/Main.tscn"
const EDITOR_SCENE := "res://scenes/CourseEditor.tscn"

const MAX_PLAYERS := 4
const LEFT_WIDTH := 560

enum Mode { MENU, HOSTING, JOINING, CREDITS, SETTINGS, RECORDS }

var mode: int = Mode.MENU
# Which way to play is selected on the menu: "play", "hot", "tour",
# "cpu" or "online". TEE OFF starts whichever it is.
var pick := "play"
var seats := 2
var rival := ""

var cols: HBoxContainer          # the two-column front page
var page_root: VBoxContainer     # a full page: records, settings, credits
var kicker_label: Label          # "A golf card game" / "Online"
var panel: VBoxContainer         # the part of the left column that changes per mode
var footer: HBoxContainer
var status: Label
var address_field: LineEdit
var name_field: LineEdit
var start_button: Button
var course_col: VBoxContainer    # the course on the right; rebuilt when it changes
var course_controls: Array = []  # its arrows, editor and tee-off: menu only
var _name_text := "Player"
var _addr_text := "127.0.0.1"


func _ready() -> void:
	# Rounds started from here are the ones that count toward records.
	Records.title_shown(self)
	# A previous round may have left a connection open.
	Net.reset()
	Net.lobby_changed.connect(_rebuild_panel)
	Net.connect_failed.connect(_on_connect_failed)
	Net.host_lost.connect(_on_host_lost)
	Net.round_starting.connect(_on_round_starting)
	rival = Rivals.ORDER[mini(1, Rivals.ORDER.size() - 1)]
	build_ui()


func build_ui() -> void:
	theme = BogeyUI.theme()

	# Plain paper. The picture on this screen is the course itself.
	var bg := ColorRect.new()
	bg.color = BogeyTheme.PARCHMENT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 88)
	margin.add_theme_constant_override("margin_right", 88)
	margin.add_theme_constant_override("margin_top", 72)
	margin.add_theme_constant_override("margin_bottom", 56)
	add_child(margin)

	cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 88)
	margin.add_child(cols)

	page_root = VBoxContainer.new()
	page_root.add_theme_constant_override("separation", 0)
	page_root.visible = false
	margin.add_child(page_root)

	# The left column: wordmark, status, the ways to play, the footer.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	left.add_theme_constant_override("separation", 0)
	cols.add_child(left)

	var title := Label.new()
	title.text = "Pars and Chars"
	# The wordmark is ink, like a signature — not a colour.
	BogeyUI.set_font(title, TITLE_FONT, 96, BogeyTheme.INK)
	left.add_child(title)

	kicker_label = BogeyUI.kicker("A golf card game", BogeyTheme.INK, 11)
	left.add_child(kicker_label)
	left.add_child(_gap(18))

	# One line under the wordmark that says where you are: an invitation
	# on the menu, the state of the lobby once you're in one, and in claret
	# when something went wrong.
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BogeyUI.set_font(status, BogeyUI.serif_italic(500), 24, BogeyTheme.INK)
	left.add_child(status)
	left.add_child(_gap(24))

	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 22)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(panel)

	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 28)
	left.add_child(footer)
	for link in [["Records", _on_records_pressed], ["Settings", _on_settings_pressed],
			["Credits", _on_credits_pressed]]:
		var b := Button.new()
		b.text = link[0]
		BogeyUI.style_link_button(b, 10)
		b.add_theme_color_override("font_color", BogeyTheme.INK)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(link[1])
		footer.add_child(b)

	course_col = VBoxContainer.new()
	course_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	course_col.add_theme_constant_override("separation", 14)
	cols.add_child(course_col)

	_set_status("Choose how you want to play")
	_rebuild_course()
	_rebuild_panel()

	# Ease the page in rather than popping it on.
	cols.modulate.a = 0.0
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cols, "modulate:a", 1.0, 0.45)


# --- Small pieces ------------------------------------------------------

func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_NONE
	return BogeyUI.style_button(b, primary)


# A wide-set capitals button — the mock's TEE OFF, HOST, BACK.
func _caps_button(text: String, primary: bool, height: int = 56, size: int = 12) -> Button:
	var b := _button(text.to_upper(), primary)
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_override("font", BogeyUI.sans(600, 4))
	b.add_theme_font_size_override("font_size", size)
	return b


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


func _set_status(text: String, bad: bool = false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", BogeyTheme.FLAG if bad else BogeyTheme.INK)


# A group's head: its name in capitals over an ink rule, with a few quiet
# words on what the group is for at the far end. `on_press` makes the
# whole head a button (Online opens its fields this way).
func _group_head(text: String, note: String, on_press: Callable = Callable()) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	row.add_child(BogeyUI.kicker(text, BogeyTheme.INK, 10))
	var l := BogeyUI.label(note, 12, BogeyTheme.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)
	col.add_child(BogeyUI.hairline(1.0))
	if not on_press.is_valid():
		return col
	# The whole head as one button, with the head drawn inside it.
	var b := Button.new()
	b.flat = true
	for key in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 24)
	for c in [col, row] + row.get_children() + col.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(col)
	b.pressed.connect(on_press)
	return b


# A selectable tile: white with a hairline edge, or solid ink once chosen.
# `title` is set in the display face; `sub`, if any, small beneath it or
# at the right end of the line.
func _tile(title: String, sub: String, selected: bool, on_press: Callable,
		sub_right: bool = false, title_size: int = 22) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ink: Color = BogeyTheme.NEUTRAL_100 if selected else BogeyTheme.INK
	var normal := BogeyUI._box(BogeyTheme.INK if selected else BogeyTheme.CARD_BG,
		BogeyTheme.INK if selected else BogeyTheme.NEUTRAL_300, 1)
	var hover := BogeyUI._box(BogeyTheme.INK if selected else BogeyTheme.CARD_BG, BogeyTheme.INK, 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var box: BoxContainer = HBoxContainer.new() if sub_right else VBoxContainer.new()
	box.add_theme_constant_override("separation", 0 if not sub_right else 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Label.new()
	t.text = title
	BogeyUI.set_font(t, BogeyUI.serif(600), title_size, ink)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL if sub_right else Control.SIZE_FILL
	box.add_child(t)
	if sub != "":
		var s := BogeyUI.label(sub, 11 if not sub_right else 12, Color(ink, 0.75))
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(s)
	var pad := BogeyUI.margin(box, 16, 9 if sub != "" and not sub_right else 11, 16, 9 if sub != "" and not sub_right else 11)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(pad)
	b.custom_minimum_size = Vector2(0, (58 if sub != "" and not sub_right else 50))
	b.pressed.connect(on_press)
	return b


# --- Panels ------------------------------------------------------------

func _rebuild_panel() -> void:
	if panel == null:
		return
	_clear(panel)
	var paged := mode == Mode.CREDITS or mode == Mode.SETTINGS or mode == Mode.RECORDS
	cols.visible = not paged
	page_root.visible = paged
	footer.visible = mode == Mode.MENU
	kicker_label.text = "A GOLF CARD GAME" if mode == Mode.MENU else "ONLINE"
	match mode:
		Mode.MENU:
			_build_menu()
		Mode.HOSTING, Mode.JOINING:
			_build_lobby()
		Mode.CREDITS:
			_build_page("Credits", _build_credits)
		Mode.SETTINGS:
			_build_page("Settings", _build_settings)
		Mode.RECORDS:
			_build_page("Records", _build_records)
	_sync_course_controls()


func _choose(what: String) -> void:
	Sound.play("ui_click")
	pick = what
	_tee_armed = false
	_set_status("Choose how you want to play")
	_rebuild_panel()
	_refresh_tee_off()


func _build_menu() -> void:
	# A round left unfinished (RoundSave.gd): one press picks it up.
	var saved := RoundSave.read()
	if not saved.is_empty():
		var again := _tile("Continue", RoundSave.summary(saved), false, _on_resume_pressed.bind(saved), true)
		again.tooltip_text = "Pick up the round you left, at the stop after the last hole you finished.\nStarting another round replaces it."
		panel.add_child(again)

	# On this screen: a round alone, hot-seat (2–4), the tour.
	var here := VBoxContainer.new()
	here.add_theme_constant_override("separation", 8)
	panel.add_child(here)
	here.add_child(_group_head("On this screen", "Hot-seat: furthest from the pin plays first"))
	here.add_child(_gap(2))
	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 8)
	here.add_child(two)
	var solo := _tile("Play a round", "", pick == "play", _choose.bind("play"))
	solo.tooltip_text = "A round alone on %s." % Course.active_name
	solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(solo)
	var hot := _tile("Hot-seat", "", pick == "hot", _choose.bind("hot"))
	hot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(hot)
	if pick == "hot":
		var seat_row := HBoxContainer.new()
		seat_row.add_theme_constant_override("separation", 6)
		here.add_child(seat_row)
		for n in range(2, MAX_PLAYERS + 1):
			var b := _tile("%d players" % n, "", seats == n, func():
				seats = n
				_choose("hot"), false, 15)
			b.custom_minimum_size.y = 38
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			seat_row.add_child(b)
	var tour := _tile("The Tour", "All four courses, one bag" if CourseLibrary.first_lock().is_empty() \
		else "Opens with the last course", pick == "tour", _choose.bind("tour"), true)
	tour.tooltip_text = "Alone, for strokes in hand. Six clubs travel from each course to the next,\nwith everything they have gained, and each course allows two fewer strokes."
	here.add_child(tour)

	# A round against one computer golfer: the same rules, their own bag
	# and draft. Three of them, by how well they play.
	var cpu := VBoxContainer.new()
	cpu.add_theme_constant_override("separation", 8)
	panel.add_child(cpu)
	cpu.add_child(_group_head("Against the computer", "Shot for shot; they draft their own bag"))
	cpu.add_child(_gap(2))
	var rival_row := HBoxContainer.new()
	rival_row.add_theme_constant_override("separation", 8)
	cpu.add_child(rival_row)
	for skill in Rivals.ORDER:
		var b := _tile(Rivals.name_of(skill), Rivals.blurb_of(skill),
			pick == "cpu" and rival == skill, func():
				rival = skill
				_choose("cpu"), false, 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "%s — %s on %s (par 71)." % [
			Rivals.name_of(skill), Rivals.typical_text(skill), Course.BUILTIN_NAME]
		rival_row.add_child(b)

	# Online: the head opens the fields.
	var online := VBoxContainer.new()
	online.add_theme_constant_override("separation", 8)
	panel.add_child(online)
	online.add_child(_group_head("Online", "Same network or a direct IP, up to 4 players",
		_choose.bind("online")))
	if pick == "online":
		online.add_child(_gap(2))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		online.add_child(grid)
		var name_col := VBoxContainer.new()
		name_col.add_theme_constant_override("separation", 4)
		name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_col.add_child(BogeyUI.kicker("Your name", BogeyTheme.INK_SOFT, 9))
		name_field = _field(_name_text, "your name")
		name_field.max_length = 16
		name_field.text_changed.connect(func(t): _name_text = t)
		name_col.add_child(name_field)
		grid.add_child(name_col)
		var addr_col := VBoxContainer.new()
		addr_col.add_theme_constant_override("separation", 4)
		addr_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		addr_col.add_child(BogeyUI.kicker("Host address", BogeyTheme.INK_SOFT, 9))
		address_field = _field(_addr_text, "192.168.1.24")
		address_field.text_changed.connect(func(t): _addr_text = t)
		addr_col.add_child(address_field)
		grid.add_child(addr_col)
		var host_btn := _caps_button("Host", true, 44, 11)
		host_btn.pressed.connect(_on_host_pressed)
		grid.add_child(host_btn)
		var join_btn := _caps_button("Join", false, 44, 11)
		join_btn.pressed.connect(_on_join_pressed)
		grid.add_child(join_btn)
	else:
		name_field = null
		address_field = null


# The course this round is played on — one of the game's own (see
# CourseLibrary) or anything saved from the editor — drawn whole (CoursePlan),
# with the arrows that change it, the editor, and the button that starts
# whatever is chosen on the left. The same course is what hot-seat and
# hosted rounds play; a hosted round sends it to everyone who joins.
var _tee_off: Button

func _rebuild_course() -> void:
	_clear(course_col)
	course_controls = []
	var courses := _course_choices()
	var index := 0
	for i in courses.size():
		# A saved course is known by its file, one of the game's by its id.
		var c: Dictionary = courses[i]
		if (Course.active_path != "" and str(c.path) == Course.active_path) \
				or (Course.active_path == "" and str(c.id) != "" and str(c.id) == Course.active_id):
			index = i
			break

	# The name, and the arrows at the far end of the same line.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	course_col.add_child(head)
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 4)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_col)
	var kick := "Course · %d of %d" % [index + 1, courses.size()] if mode == Mode.MENU else "Course"
	name_col.add_child(BogeyUI.kicker(kick, BogeyTheme.INK, 10))
	var name_l := BogeyUI.heading(Course.active_name, 56)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_col.add_child(name_l)
	var arrows: Array = []
	for step in [-1, 1]:
		var b := _button("‹" if step < 0 else "›")
		b.custom_minimum_size = Vector2(46, 46)
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_vertical = Control.SIZE_SHRINK_END
		b.disabled = courses.size() < 2
		b.pressed.connect(_on_course_step.bind(courses, index, step))
		head.add_child(b)
		arrows.append(b)

	# What the course is, then its numbers, its ground and its record on
	# one ruled line — so the choice is an informed one.
	var about := CourseLibrary.blurb(Course.active_id)
	if about == "":
		about = CourseTheme.blurb(Course.active_theme)
	var blurb := BogeyUI.body(about, 15, BogeyTheme.NEUTRAL_800)
	blurb.custom_minimum_size = Vector2(0, 0)
	course_col.add_child(blurb)

	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", 0)
	course_col.add_child(facts)
	facts.add_child(BogeyUI.hairline(0.12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	facts.add_child(BogeyUI.margin(row, 0, 9, 0, 9))
	var par := 0
	var yds := 0.0
	for h in Course.active().get("holes", []):
		par += int(h.get("par", 0))
		yds += float(h.get("yardage", 0.0))
	row.add_child(BogeyUI.label("Par %d · %s yds" % [par, _thousands(int(round(yds)))], 13))
	var terrain := BogeyUI.label("%s: %s" % [CourseTheme.label(Course.active_theme),
		CourseTheme.play_summary(Course.active_theme)], 13)
	terrain.tooltip_text = CourseTheme.blurb(Course.active_theme)
	terrain.mouse_filter = Control.MOUSE_FILTER_STOP
	terrain.mouse_default_cursor_shape = Control.CURSOR_HELP
	row.add_child(terrain)
	var record := BogeyUI.label(Records.summary_line(), 13, BogeyTheme.INK_SOFT)
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record.clip_text = true
	record.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(record)
	facts.add_child(BogeyUI.hairline(0.12))

	# The ladder (CourseLibrary): what this course is locked behind, or
	# what a round on it would open.
	var lock := _lock()
	var next: Dictionary = CourseLibrary.next_after(Course.active_id) if Course.active_path == "" else {}
	var rung := ""
	if not lock.is_empty():
		rung = "Locked. Score %s on %s to open it" % [CourseLibrary.target_text(int(lock.target)), lock.name]
		if not (lock.best as Dictionary).is_empty():
			rung += " (your best there: %s)" % Records.diff_text(int(lock.best.diff))
	elif not next.is_empty() and not CourseLibrary.lock_on(str(next.id)).is_empty():
		rung = "Score %s here to open %s" % [CourseLibrary.target_text(CourseLibrary.target_on(Course.active_id)), next.name]
	if rung != "":
		facts.add_child(BogeyUI.margin(BogeyUI.label(rung + ".", 13,
			BogeyTheme.FLAG if not lock.is_empty() else BogeyTheme.FAIRWAY_DEEP), 0, 9, 0, 9))
		facts.add_child(BogeyUI.hairline(0.12))

	# The course itself, every hole on one routed sheet. Faint while locked.
	var plan := CoursePlan.new()
	plan.size_flags_vertical = Control.SIZE_EXPAND_FILL
	plan.modulate.a = 1.0 if lock.is_empty() else 0.4
	course_col.add_child(plan)
	plan.show_course()

	# The editor, and the one button that starts the round.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	course_col.add_child(actions)
	var edit := _caps_button("Course editor", false, 60, 11)
	edit.custom_minimum_size.x = 200
	edit.pressed.connect(_on_editor_pressed)
	actions.add_child(edit)
	_tee_off = _caps_button("Tee off", true, 60, 13)
	_tee_off.add_theme_font_override("font", BogeyUI.sans(600, 5))
	_tee_off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tee_off.pressed.connect(_on_tee_off_pressed)
	actions.add_child(_tee_off)
	course_controls = arrows + [edit, _tee_off]
	_refresh_tee_off()
	_sync_course_controls()


func _thousands(n: int) -> String:
	var s := str(n)
	return s if s.length() <= 3 else "%s,%s" % [s.substr(0, s.length() - 3), s.substr(s.length() - 3)]


# TEE OFF says what it will start.
func _refresh_tee_off() -> void:
	if _tee_off == null:
		return
	_tee_off.disabled = pick == "online"
	# A locked course can't be played, nor the tour until every course is open.
	var lock := CourseLibrary.first_lock() if pick == "tour" else _lock()
	if pick != "online" and not lock.is_empty():
		_tee_off.disabled = true
		_tee_off.text = "LOCKED"
		_tee_off.tooltip_text = "Score %s on %s to open %s." % [CourseLibrary.target_text(int(lock.target)),
			lock.name, "the tour" if pick == "tour" else Course.active_name]
		return
	match pick:
		"online":
			_tee_off.text = "HOST OR JOIN ABOVE"
		"tour":
			_tee_off.text = "START THE TOUR"
		"cpu":
			_tee_off.text = "PLAY %s" % Rivals.name_of(rival).get_slice(" ", 0).to_upper()
		"hot":
			_tee_off.text = "TEE OFF · %d PLAYERS" % seats
		_:
			_tee_off.text = "TEE OFF"
	_tee_off.tooltip_text = "A round alone on %s." % Course.active_name if pick == "play" else ""
	if _tee_armed:
		_tee_off.text = "REPLACE THE ROUND YOU LEFT?"
		_tee_off.tooltip_text = "A round is saved. Press again to start this one in its place, or Continue to go back to it."


# What the course in the picker is locked behind ({} if it is open; a
# saved course always is).
func _lock() -> Dictionary:
	return CourseLibrary.lock_on(Course.active_id) if Course.active_path == "" else {}


# Set once TEE OFF has been pressed with a round saved: the next press
# starts the new round, which replaces the saved one.
var _tee_armed := false


func _on_tee_off_pressed() -> void:
	if not _tee_armed and not RoundSave.read().is_empty():
		_tee_armed = true
		Sound.play("ui_click")
		_refresh_tee_off()
		return
	_tee_armed = false
	match pick:
		"play":
			_on_local_pressed(1)
		"hot":
			_on_local_pressed(seats)
		"tour":
			_on_tour_pressed()
		"cpu":
			_on_rival_pressed(rival)


# Changing the course and starting a round are for the menu. In a lobby
# the course is settled, and a joiner isn't told the host's until the
# round starts — the one here would be the wrong one, so it isn't shown.
func _sync_course_controls() -> void:
	if course_col == null:
		return
	course_col.visible = mode != Mode.JOINING
	for c in course_controls:
		if is_instance_valid(c):
			c.visible = mode == Mode.MENU


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
	_tee_armed = false
	var choice: Dictionary = courses[posmod(index + step, courses.size())]
	var ok: bool = Course.use_shipped(str(choice.id)) if str(choice.id) != "" else Course.use_file(str(choice.path))
	if not ok:
		Course.use_builtin()
	_rebuild_course()


func _on_editor_pressed() -> void:
	Sound.play("ui_confirm")
	get_tree().change_scene_to_file(EDITOR_SCENE)


# --- The lobby ---------------------------------------------------------

func _build_lobby() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(col)

	if mode == Mode.HOSTING:
		# A line a player, the host and you tagged at the far end.
		col.add_child(BogeyUI.hairline(1.0))
		var seat_list := Net.seats_in_order()
		if seat_list.is_empty():
			col.add_child(BogeyUI.margin(BogeyUI.body("Waiting…", 14), 0, 14, 0, 14))
		for seat in seat_list:
			var row := HBoxContainer.new()
			row.add_child(BogeyUI.heading(Net.name_for_seat(int(seat)), 24))
			var tags := PackedStringArray()
			if int(seat) == 0:
				tags.append("HOST")
			if int(seat) == Net.my_seat:
				tags.append("YOU")
			var t := BogeyUI.kicker(" · ".join(tags), BogeyTheme.INK_SOFT, 10)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(t)
			col.add_child(BogeyUI.margin(row, 0, 10, 0, 10))
			col.add_child(BogeyUI.hairline(0.12))
		col.add_child(_gap(22))

		# Show the address rather than telling the host to go and find it.
		# This is the whole setup step for two people in one house.
		var addr := Net.lan_address()
		if addr != "":
			var line := RichTextLabel.new()
			line.bbcode_enabled = true
			line.fit_content = true
			line.scroll_active = false
			line.add_theme_font_override("normal_font", BogeyUI.sans())
			line.add_theme_font_override("bold_font", BogeyUI.sans(600))
			line.add_theme_font_size_override("normal_font_size", 14)
			line.add_theme_font_size_override("bold_font_size", 14)
			line.add_theme_color_override("default_color", BogeyTheme.INK)
			line.text = "On the same network, they join with: [b]%s[/b]" % addr
			col.add_child(line)
			# A machine can have several addresses and the guess above can
			# be wrong (VPNs, virtual adapters), so list the others.
			var others: Array = Net.all_lan_addresses().filter(func(a): return a != addr)
			var more := "" if others.is_empty() else "If that doesn't work, try: %s" % ", ".join(others)
			if Net.DEFAULT_PORT != 45888:
				more += ("" if more == "" else " · ") + "port %d" % Net.DEFAULT_PORT
			if more != "":
				col.add_child(BogeyUI.body(more, 12, BogeyTheme.INK_SOFT))
		else:
			col.add_child(BogeyUI.body(
				"Couldn't detect this machine's network address — check your "
				+ "Wi-Fi settings for it. Port %d." % Net.DEFAULT_PORT, 14, BogeyTheme.FLAG))
	else:
		col.add_child(BogeyUI.hairline(1.0))
		col.add_child(_gap(18))
		var waiting := "Connected. Waiting for the host to start…" if Net.seats_in_order().size() > 0 \
			else "Waiting for the host to start…"
		col.add_child(BogeyUI.body(waiting, 15, BogeyTheme.INK))
		col.add_child(_gap(6))
		col.add_child(BogeyUI.body("The host picks the course and starts the round.", 12, BogeyTheme.INK_SOFT))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var cancel := _caps_button("Back", false, 56, 11)
	cancel.custom_minimum_size.x = 160
	cancel.pressed.connect(_on_cancel_pressed)
	row.add_child(cancel)
	if mode == Mode.HOSTING:
		var n := Net.seats_in_order().size()
		# One player is a legitimate online round (handy for testing), so
		# this is never disabled on headcount.
		start_button = _caps_button("Start round · %d player%s" % [n, "" if n == 1 else "s"], true, 56, 12)
		start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start_button.pressed.connect(_on_start_pressed)
		row.add_child(start_button)


# --- Full pages: records, settings, credits ----------------------------

func _build_page(title: String, fill: Callable) -> void:
	_clear(page_root)
	var head := HBoxContainer.new()
	page_root.add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var mark := Label.new()
	mark.text = "Pars and Chars"
	BogeyUI.set_font(mark, TITLE_FONT, 44, BogeyTheme.INK)
	names.add_child(mark)
	names.add_child(BogeyUI.heading(title, 56))
	var back := _caps_button("Back", false, 48, 11)
	back.custom_minimum_size.x = 140
	back.size_flags_vertical = Control.SIZE_SHRINK_END
	back.pressed.connect(_on_credits_back_pressed)
	head.add_child(back)
	page_root.add_child(_gap(14))
	page_root.add_child(BogeyUI.hairline(1.0))
	page_root.add_child(_gap(28))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	fill.call(body)


# The credits page. This is a licence obligation rather than a nicety:
# the Form card icons are CC BY 3.0, which requires the authors to be
# credited where the work is used, so the names have to be reachable from
# inside the game and not only from a file in the repo.
func _build_credits(body: VBoxContainer) -> void:
	body.add_theme_constant_override("separation", 0)
	for section in Credits.SECTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		var h := BogeyUI.heading(str(section.heading), 22)
		h.custom_minimum_size = Vector2(280, 0)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(h)
		var lines := PackedStringArray()
		if str(section.note) != "":
			lines.append(str(section.note))
		for line in section.lines:
			lines.append(str(line).strip_edges())
		var text := BogeyUI.body("\n".join(lines), 14, BogeyTheme.NEUTRAL_800)
		text.custom_minimum_size = Vector2(600, 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		body.add_child(BogeyUI.margin(row, 0, 14, 0, 14))
		body.add_child(BogeyUI.hairline(0.12))
	body.add_child(_gap(14))
	body.add_child(BogeyUI.body(Credits.LICENCE_NOTE, 12, BogeyTheme.NEUTRAL_600))


func _on_credits_pressed() -> void:
	Sound.play("ui_click")
	mode = Mode.CREDITS
	_rebuild_panel()


# The settings page — the same controls as the in-game popup.
func _build_settings(body: VBoxContainer) -> void:
	var settings := SettingsPanel.new(false)
	settings.custom_minimum_size = Vector2(720, 0)
	settings.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(settings)


func _on_settings_pressed() -> void:
	Sound.play("ui_click")
	mode = Mode.SETTINGS
	_rebuild_panel()


# The selected course's records: the best round and the recent ones on
# the left, the best on each hole on the right.
func _build_records(body: VBoxContainer) -> void:
	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 72)
	body.add_child(two)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(left)
	left.add_child(BogeyUI.kicker("%s · best round" % Course.active_name, BogeyTheme.INK_SOFT, 10))
	var best := Records.best_round()
	if best.is_empty():
		left.add_child(_gap(8))
		left.add_child(BogeyUI.body("No rounds finished on this course yet. Your first one sets the record.", 15, BogeyTheme.INK))
	else:
		var fig := HBoxContainer.new()
		fig.add_theme_constant_override("separation", 14)
		left.add_child(fig)
		fig.add_child(BogeyUI.heading(str(int(best.strokes)), 88))
		var d := int(best.diff)
		var dl := BogeyUI.heading(Records.diff_text(d).replace("-", "−"), 40)
		dl.add_theme_color_override("font_color",
			BogeyTheme.FAIRWAY_DEEP if d < 0 else (BogeyTheme.FLAG if d > 0 else BogeyTheme.INK))
		dl.size_flags_vertical = Control.SIZE_SHRINK_END
		fig.add_child(dl)
		left.add_child(BogeyUI.body("Set by %s on %s, %s · %d rounds, average %.1f" % [
			str(best.player), str(best.date), str(best.mode), Records.rounds_played(), Records.average()],
			14, BogeyTheme.INK_SOFT))

	left.add_child(_gap(36))
	left.add_child(BogeyUI.heading("Recent rounds", 26))
	left.add_child(BogeyUI.hairline(1.0))
	var history := Records.history()
	if history.is_empty():
		left.add_child(BogeyUI.margin(BogeyUI.body("No rounds yet.", 14), 0, 10, 0, 10))
	for e in history:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		var date := BogeyUI.label(str(e.date), 14, BogeyTheme.INK_SOFT)
		date.custom_minimum_size = Vector2(110, 0)
		r.add_child(date)
		var who := BogeyUI.label("%s · %s" % [str(e.player), str(e.mode)], 14)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.clip_text = true
		r.add_child(who)
		var s := BogeyUI.label(str(int(e.strokes)), 14, BogeyTheme.INK, 500)
		s.custom_minimum_size = Vector2(60, 0)
		r.add_child(s)
		var dd := int(e.diff)
		var dl := BogeyUI.label(Records.diff_text(dd), 14,
			BogeyTheme.FAIRWAY_DEEP if dd < 0 else (BogeyTheme.FLAG if dd > 0 else BogeyTheme.INK_SOFT))
		dl.custom_minimum_size = Vector2(50, 0)
		r.add_child(dl)
		left.add_child(BogeyUI.margin(r, 0, 9, 0, 9))
		left.add_child(BogeyUI.hairline(0.12))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(right)
	right.add_child(BogeyUI.heading("Best on each hole", 26))
	right.add_child(BogeyUI.hairline(1.0))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 0)
	right.add_child(grid)
	for n in range(1, Course.hole_count() + 1):
		var b := Records.hole_best(n)
		var par := int(HoleData.hole(n).par)
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var r := HBoxContainer.new()
		var hl := BogeyUI.label("Hole %d" % n, 14)
		hl.custom_minimum_size = Vector2(70, 0)
		r.add_child(hl)
		var pl := BogeyUI.label("Par %d" % par, 14, BogeyTheme.INK_SOFT)
		pl.custom_minimum_size = Vector2(60, 0)
		r.add_child(pl)
		var bl := BogeyUI.label("Best %d" % b if b > 0 else "—", 14)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(bl)
		var dtext := Records.diff_text(b - par) if b > 0 else ""
		var dl := BogeyUI.label(dtext, 14,
			BogeyTheme.FAIRWAY_DEEP if b > 0 and b < par else (BogeyTheme.FLAG if b > par else BogeyTheme.INK))
		dl.custom_minimum_size = Vector2(40, 0)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(dl)
		cell.add_child(BogeyUI.margin(r, 0, 7, 0, 7))
		cell.add_child(BogeyUI.hairline(0.12))
		grid.add_child(cell)


func _on_records_pressed() -> void:
	Sound.play("ui_click")
	mode = Mode.RECORDS
	_rebuild_panel()


func _on_credits_back_pressed() -> void:
	Sound.play("ui_back")
	mode = Mode.MENU
	_set_status("Choose how you want to play")
	_rebuild_panel()


# --- Menu actions ------------------------------------------------------

func _on_local_pressed(count: int) -> void:
	Sound.play("ui_confirm")
	GameSetup.reset_to_local(count)
	# A first solo round is a guided one (Lessons.gd).
	GameSetup.guided = count == 1 and bool(Settings.get_value("guided"))
	get_tree().change_scene_to_file(MAIN_SCENE)


# Back to the round that was left, where it was saved.
func _on_resume_pressed(saved: Dictionary) -> void:
	Sound.play("ui_confirm")
	RoundSave.restore_setup(saved)
	get_tree().change_scene_to_file(MAIN_SCENE)


# The tour starts on the first of its courses, whatever the picker says.
func _on_tour_pressed() -> void:
	Sound.play("ui_confirm")
	GameSetup.start_tour()
	get_tree().change_scene_to_file(MAIN_SCENE)


# You in seat 0, the chosen computer golfer in seat 1.
func _on_rival_pressed(skill: String) -> void:
	Sound.play("ui_confirm")
	GameSetup.reset_to_local(2)
	GameSetup.cpu_seats = {1: skill}
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_host_pressed() -> void:
	if not _lock().is_empty():
		_set_status("%s is locked. Pick an open course to host." % Course.active_name, true)
		return
	Sound.play("ui_confirm")
	var err := Net.host_game(_entered_name())
	if err != "":
		_set_status(err, true)
		return
	mode = Mode.HOSTING
	_set_status("Hosting — waiting for players")
	_rebuild_course()
	_rebuild_panel()


func _on_join_pressed() -> void:
	Sound.play("ui_confirm")
	var address := _addr_text.strip_edges()
	if address == "":
		_set_status("Enter the host's address first.", true)
		return
	var err := Net.join_game(address, _entered_name())
	if err != "":
		_set_status(err, true)
		return
	mode = Mode.JOINING
	_set_status("Connecting to %s…" % address)
	_rebuild_panel()


func _entered_name() -> String:
	var n := _name_text.strip_edges()
	return n if n != "" else "Player"


func _on_cancel_pressed() -> void:
	Sound.play("ui_back")
	Net.reset()
	mode = Mode.MENU
	_set_status("Choose how you want to play")
	_rebuild_course()
	_rebuild_panel()


func _on_start_pressed() -> void:
	if not Net.is_host():
		return
	Sound.play("ui_confirm")
	# The host builds every player's decks here and ships them, so no two
	# machines start the round from a different shuffle. Main.gd owns that
	# setup, so borrow an instance purely to roll it.
	var seat_list := Net.seats_in_order()
	var names: Dictionary = {}
	for seat in seat_list:
		names[int(seat)] = Net.name_for_seat(int(seat))

	var payload := _roll_round(seat_list.size(), names)
	Net.net_start_round.rpc(payload)


# Rolls a fresh round's decks without building any UI: Main.init_game()
# only touches game state, so a bare instance is enough to produce the
# starting bags, pools and Form decks.
func _roll_round(count: int, names: Dictionary) -> Dictionary:
	var scratch = load(MAIN_SCENE).instantiate()
	scratch.player_count = clampi(count, 1, MAX_PLAYERS)
	scratch.online = true
	scratch.init_game()
	scratch.apply_seat_names(names)
	# The round opens at the pro shop: every seat's rack is dealt here, so
	# it travels with the round.
	scratch.deal_opening()
	var payload: Dictionary = scratch.build_round_payload()
	scratch.free()
	payload["seat_names"] = names
	payload["player_count"] = clampi(count, 1, MAX_PLAYERS)
	return payload


# --- Net events --------------------------------------------------------

func _on_connect_failed(reason: String) -> void:
	mode = Mode.MENU
	_set_status(reason, true)
	_rebuild_course()
	_rebuild_panel()


func _on_host_lost() -> void:
	mode = Mode.MENU
	_set_status("The host closed the lobby.", true)
	_rebuild_course()
	_rebuild_panel()


func _on_round_starting(payload: Dictionary) -> void:
	# Nothing of a round played alone on this machine comes along: not a
	# tour, a guided round or a computer golfer.
	GameSetup.reset_to_local(clampi(int(payload.get("player_count", 1)), 1, MAX_PLAYERS))
	GameSetup.online = true
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
