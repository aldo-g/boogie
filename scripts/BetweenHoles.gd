extends RefCounted

# ---------------------------------------------------------
# BETWEEN HOLES — full pages over the shot screen (yardage book v2)
#   the stops: the hole just played and where to go next (or a wear-in)
#   the pro shop: the rack, dig / trade in / that'll do, the bag-full cut
#   the fitting bay: the bench of boosts, then the club they go on
#   the hut: what is there, take it or walk on
#   the card: the round complete, and the tour's packing
# ---------------------------------------------------------
# Split out of Main.gd on 2026-11-25. Loaded by Main at run time
# (Main.pages()), because this script preloads Main for its types.

const Main := preload("res://scripts/Main.gd")
const DraftRules := preload("res://scripts/DraftRules.gd")
const Route := preload("res://scripts/Route.gd")

# The game these pages are drawn for and act on. Everything a page shows is
# read from it, and everything a page does goes back through it (submit).
var main: Main


func _init(game: Main) -> void:
	main = game


func build() -> void:
	main.clear_container(main.interlude)
	main.coverage_view = null
	var cpu := main.is_cpu_turn()
	match main.state:
		Main.State.DONE:
			_page_end()
		Main.State.DISCARD_FOR_DRAFT, Main.State.DISCARD_FOR_HAZARD:
			_page_shop("cut", cpu)
		Main.State.WAITING:
			_page_stops("waiting", cpu)
		Main.State.DRAFT:
			if main._trading and not cpu:
				_page_shop("trade", cpu)
			elif main._boosting and not cpu and main.me.draft_stop == Route.FIT:
				_page_fit("club", cpu)
			elif not cpu and main.wear_due() >= 0:
				_page_stops("wear", cpu)
			elif main.me.draft_stop == "":
				_page_stops("choose", cpu)
			elif main.me.draft_stop == Route.FIT:
				_page_fit("bench", cpu)
			elif main.me.draft_stop == Route.HUT:
				_page_hut(cpu)
			else:
				_page_shop("offers", cpu)


# A page's body, inside its margins.
func _page(pad_x: int = Main.PAGE_PAD_X, pad_y: int = Main.PAGE_PAD_Y) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	main.interlude.add_child(BogeyUI.margin(col, pad_x, pad_y, pad_x, pad_y))
	return col


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# A wide-set capitals button: TO THE 8TH TEE, WALK ON, PLAY AGAIN.
func _caps_btn(text: String, primary: bool, on_press: Callable, height: int = 52, size: int = 12) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height)
	BogeyUI.style_button(b, primary, size)
	b.add_theme_font_override("font", BogeyUI.sans(600, 4))
	b.pressed.connect(on_press)
	return b


# The next tee, as words: "the 8th tee".
func _next_tee() -> String:
	return "the %s tee" % main._ordinal(main.current_hole_index + 1)


# A white card to choose: a kicker in small capitals, a name, and words at
# the foot. The whole card is the button; it edges in ink under the cursor.
func _choice_card(kicker: String, kicker_ink: Color, title: String, title_size: int,
		words: String, foot: String, min_size: Vector2, on_press: Callable,
		disabled: bool = false, foot_size: int = 12) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.disabled = disabled
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	var rest := BogeyUI._box(BogeyTheme.CARD_BG, BogeyTheme.NEUTRAL_300, 1, BogeyUI.RADIUS, 22, 20)
	var over := BogeyUI._box(BogeyTheme.CARD_BG, BogeyTheme.INK, 2, BogeyUI.RADIUS, 22, 20)
	over.shadow_color = BogeyTheme.SHADOW_MD
	over.shadow_size = 18
	over.shadow_offset = Vector2(0, 8)
	b.add_theme_stylebox_override("normal", rest)
	b.add_theme_stylebox_override("disabled", rest)
	b.add_theme_stylebox_override("hover", over)
	b.add_theme_stylebox_override("pressed", over)
	b.add_theme_stylebox_override("hover_pressed", over)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kicker != "":
		col.add_child(BogeyUI.kicker(kicker, kicker_ink, 9))
	var t := BogeyUI.heading(title, title_size)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(t)
	if words != "":
		col.add_child(BogeyUI.body(words, 14, BogeyTheme.NEUTRAL_800))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	if foot != "":
		col.add_child(BogeyUI.body(foot, foot_size, BogeyTheme.INK_SOFT if foot_size <= 12 else BogeyTheme.INK))
	for c in col.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := BogeyUI.margin(col, 22, 20, 22, 20)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(pad)
	if disabled:
		b.modulate.a = 0.55
	b.pressed.connect(on_press)
	return b


# A small club tile for the pages' bag grids: the maker's dot, the name, the
# carry, and at the foot a line on what choosing it would do.
func _club_tile(club: Dictionary, foot: String, foot_ink: Color, on_press: Callable,
		enabled: bool = true, hover_ink: Color = BogeyTheme.INK) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(196, 150)
	b.disabled = not enabled
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	var rest := BogeyUI._box(BogeyTheme.CARD_BG, BogeyTheme.NEUTRAL_300, 1, BogeyUI.RADIUS, 12, 12)
	var over := BogeyUI._box(BogeyTheme.CARD_BG, hover_ink, 2, BogeyUI.RADIUS, 12, 12)
	b.add_theme_stylebox_override("normal", rest)
	b.add_theme_stylebox_override("disabled", rest)
	b.add_theme_stylebox_override("hover", over)
	b.add_theme_stylebox_override("pressed", over)
	b.add_theme_stylebox_override("hover_pressed", over)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := BogeyUI.dot(Brands.color(str(club.get("brand", Brands.NONE))), 6)
	dot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(dot)
	var n := BogeyUI.heading(str(club.name), 19)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(n)
	var band := BogeyUI.heading("%d–%d" % [int(club.min_yard), int(club.max_yard)], 17)
	band.add_theme_color_override("font_color", BogeyTheme.INK_SOFT)
	col.add_child(band)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var f := BogeyUI.body(foot, 11, foot_ink)
	f.max_lines_visible = 3
	col.add_child(f)
	for c in col.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := BogeyUI.margin(col, 12, 12, 12, 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(pad)
	if not enabled:
		b.modulate.a = 0.5
	b.pressed.connect(on_press)
	return b


func _tile_grid(columns: int = 7) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	return g


# The stamp, set on a page: the hole and its score, struck at an angle.
func _stamp(over: Control, title: String, sub: String, ink: Color) -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(holder)
	var s := BogeyUI._box(BogeyTheme.PARCHMENT, BogeyTheme.INK, 1, 0, 36, 16)
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 24
	s.shadow_offset = Vector2(0, 12)
	var outer := BogeyUI.make_panel(BogeyUI._box(BogeyTheme.PARCHMENT, BogeyTheme.INK, 1, 0, 5, 5))
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := BogeyUI.make_panel(s)
	outer.add_child(inner)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	inner.add_child(col)
	var k := BogeyUI.kicker("Hole %d" % main.current_hole_index, BogeyTheme.INK, 10)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(k)
	var t := BogeyUI.heading(title, 60)
	t.add_theme_color_override("font_color", ink)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var u := BogeyUI.kicker(sub, BogeyTheme.INK_SOFT, 10)
	u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(u)
	holder.add_child(outer)
	outer.resized.connect(func():
		outer.pivot_offset = outer.size / 2.0
		outer.rotation_degrees = -6.0)


# --- The stops ----------------------------------------------------------

func _page_stops(mode: String, cpu: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 80)
	main.interlude.add_child(BogeyUI.margin(row, Main.PAGE_PAD_X, Main.PAGE_PAD_Y, Main.PAGE_PAD_X, Main.PAGE_PAD_Y))

	# The hole just played, mounted, with its score stamped across it.
	var mv := CourseMapView.new()
	mv.skip_animation = true
	var plate := BogeyUI.plate(mv)
	plate.custom_minimum_size = Vector2(480, 0)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(plate)
	mv.set_hole(main.hole)
	mv.set_ball(main.hole.pin_pos, main.shot_path)
	var entry: Dictionary = main.round_scores[-1] if not main.round_scores.is_empty() \
		and int(main.round_scores[-1].hole) == main.current_hole_index else {}
	if not entry.is_empty():
		var diff: int = int(entry.strokes) - int(entry.par)
		_stamp(plate, main.score_name(diff), "%d stroke%s" % [int(entry.strokes), "" if int(entry.strokes) == 1 else "s"],
			BogeyTheme.FAIRWAY_DEEP if diff < 0 else (BogeyTheme.FLAG if diff > 0 else BogeyTheme.INK))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	# Where the round stands, in three big figures.
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 56)
	right.add_child(stats)
	if main.plays_for_keeps():
		var in_hand: int = main.strokes_in_hand()
		var fig := _big_figure("Strokes in hand", str(in_hand),
			BogeyTheme.FLAG if in_hand <= 3 else BogeyTheme.INK)
		stats.add_child(fig)
		# The hole just played is paid in or taken out in front of you, once.
		# What the hole just played paid in or took out stays beside the
		# label, and the first time the page is shown the figure counts to it.
		if main._in_hand_from >= 0 and main._in_hand_from != in_hand:
			_count_in_hand(fig, main._in_hand_from, in_hand,
				main.flourish("in hand %d" % main.current_hole_index))
	var run := main.running_score_diff()
	stats.add_child(_big_figure("Round", main.running_score_diff_text(run).replace("-", "−"),
		BogeyTheme.FAIRWAY_DEEP if run < 0 else (BogeyTheme.FLAG if run > 0 else BogeyTheme.INK)))
	var best := Records.hole_best(main.current_hole_index)
	if best > 0:
		stats.add_child(_big_figure("Your best here", str(best)))
	right.add_child(_gap(18))
	right.add_child(BogeyUI.hairline(1.0))

	match mode:
		"waiting":
			right.add_child(_gap(36))
			right.add_child(main._italic("Drafted — waiting for %s" % ", ".join(PackedStringArray(main.waiting_on_names())), 30))
			right.add_child(_gap(8))
			right.add_child(BogeyUI.body("The next hole starts when the last pick is in.", 14, BogeyTheme.INK_SOFT))
		"wear":
			_wear_block(right, main.wear_due())
		"choose":
			right.add_child(_gap(32))
			right.add_child(main._italic("Before %s, choose a stop" % _next_tee(), 30))
			var ahead := Route.ahead_text(main.wind_seed, main.current_hole_index + 1, Course.hole_count())
			var sub := "One stop, and the other is passed by."
			if ahead != "":
				sub += " Beside the pro shop ahead: %s." % ahead
			if cpu:
				sub = "%s is choosing a stop…" % main.me.name
			right.add_child(BogeyUI.margin(BogeyUI.body(sub, 13, BogeyTheme.INK_SOFT), 0, 4, 0, 20))
			var fork_note := main._lesson_note(["fork"])
			if fork_note != null:
				right.add_child(BogeyUI.margin(fork_note, 0, 0, 0, 20))
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 16)
			grid.add_theme_constant_override("v_separation", 16)
			right.add_child(grid)
			var stops := Route.stops(main.wind_seed, main.current_hole_index)
			for i in range(stops.size()):
				var id: String = stops[i]
				var tag := ""
				match id:
					Route.SHOP:
						tag = "ALWAYS OPEN"
					Route.FIT:
						tag = "On the bench: " + ", ".join(PackedStringArray(main.me.draft_boosts.map(
							func(b): return str(ClubAbilities.BOOSTS[b].name))))
					Route.RANGE:
						var bad := main.form_deck.bad_count()
						tag = "No bad cards to work out" if bad == 0 else "The worst %d of your %d bad card%s leave%s." % [
							mini(bad, ShotRules.RANGE_SESSION_PURGE), bad, "" if bad == 1 else "s", "s" if bad == 1 else ""]
					Route.HUT:
						tag = "Today: %s" % Route.EVENTS[Route.event(main.wind_seed, main.current_hole_index, main.plays_for_keeps())].title.to_lower()
				var stop_name := str(Route.STOPS[id].name).capitalize()
				if not stop_name.begins_with("The "):
					stop_name = "The " + stop_name
				var card := _choice_card("", BogeyTheme.INK, stop_name,
					32, "%s." % Route.STOPS[id].does, tag, Vector2(0, 168),
					func(): main.submit("stop", {"index": i}), cpu)
				card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(card)


func _big_figure(label: String, value: String, ink: Color = BogeyTheme.INK) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.add_child(BogeyUI.kicker(label, BogeyTheme.INK_SOFT, 10))
	var v := BogeyUI.heading(value, 72)
	v.add_theme_color_override("font_color", ink)
	col.add_child(v)
	return col


# Strokes in hand moving after a hole: what the hole paid or cost is said
# beside the label in green or claret, and while `counting` the figure
# starts where it stood and steps to where it stands, a tick a stroke.
func _count_in_hand(fig: Control, from: int, to: int, counting: bool) -> void:
	var kicker := fig.get_child(0) as Label
	var value := fig.get_child(1) as Label
	if kicker == null or value == null:
		return
	var gain := to - from
	kicker.text = "%s  %s%d" % [kicker.text, "+" if gain > 0 else "−", absi(gain)]
	kicker.add_theme_color_override("font_color", BogeyTheme.FAIRWAY_DEEP if gain > 0 else BogeyTheme.FLAG)
	if not counting:
		return
	value.text = str(from)
	var tw := main.create_tween()
	tw.bind_node(value)
	tw.tween_interval(0.5)
	var step := 1 if gain > 0 else -1
	for v in range(from + step, to + step, step):
		tw.tween_callback(func():
			value.text = str(v)
			Sound.play_pitched("ui_click", 1.25 if gain > 0 else 0.8, -2.0))
		tw.tween_interval(0.18)


# A club worn in: what the wear does to it — groove a good shot, lose a
# bad one, or take the maker's gain. The draft follows.
func _wear_block(into: VBoxContainer, index: int) -> void:
	var club: Dictionary = main.hand[index]
	into.add_child(_gap(36))
	into.add_child(BogeyUI.kicker("Worn in", BogeyTheme.INK_SOFT, 10))
	into.add_child(BogeyUI.margin(BogeyUI.heading("Your %s has worn in" % club.name, 40), 0, 6, 0, 0))
	into.add_child(BogeyUI.margin(BogeyUI.body(
		"It has found the fairway or the green often enough to be trusted. Choose what the wear does to it; the stop follows.",
		15, BogeyTheme.NEUTRAL_800), 0, 8, 0, 22))
	var wear_note := main._lesson_note(["wear"])
	if wear_note != null:
		into.add_child(BogeyUI.margin(wear_note, 0, 0, 0, 22))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	into.add_child(grid)
	var choices := ClubAbilities.wear_choices(club)
	for i in range(choices.size()):
		var c: Dictionary = choices[i]
		var kick := "Groove"
		var ink: Color = BogeyTheme.FAIRWAY
		var words := "Whenever its %s is dealt, one more card is dealt beside it." % c.shot
		match str(c.kind):
			"drop":
				kick = "Strip"
				ink = BogeyTheme.FLAG
				words = "Its %s leaves your Form deck for good." % c.shot
			"maker":
				kick = "The maker's gain"
				ink = BogeyTheme.GOLD
				words = str(ClubAbilities.gain_info(str(c.shot)).get("does", ""))
		var card := _choice_card(kick, ink, str(c.text), 30, "", words, Vector2(0, 200),
			func(): main.submit("wear", {"index": index, "choice": i}))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)


# --- The pro shop -------------------------------------------------------

func _page_shop(mode: String, cpu: bool) -> void:
	var page := _page(72, 48)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	page.add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 6)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(names)
	var chart := VBoxContainer.new()
	chart.custom_minimum_size = Vector2(620, 0)
	head.add_child(chart)

	var shown := main.current_draft_options.size()
	var keeps: int = clampi(main.me.draft_keeps, 1, maxi(shown, 1))
	match mode:
		"cut":
			names.add_child(BogeyUI.kicker("Bag full · %d / %d" % [main.hand.size(), Main.HAND_CAP], BogeyTheme.INK_SOFT, 10))
			names.add_child(BogeyUI.heading("Something has to go", 60))
			main.add_coverage_chart(chart, "Hover a club to see the yards it covers")
		"trade":
			names.add_child(BogeyUI.kicker("After hole %d · trade in" % main.current_hole_index, BogeyTheme.INK_SOFT, 10))
			names.add_child(BogeyUI.heading("The Pro Shop", 60))
			main.add_coverage_chart(chart, "")
		_:
			names.add_child(BogeyUI.kicker("%s · take %s" % [
				"Before the first tee" if main._opening else "After hole %d" % main.current_hole_index,
				"one" if keeps == 1 else str(keeps)], BogeyTheme.INK_SOFT, 10))
			names.add_child(BogeyUI.heading("The Pro Shop", 60))
			var cap := draft_caption()
			if cpu:
				cap = "%s is at the rack." % main.me.name
			if cap != "It joins your bag for the rest of the round.":
				names.add_child(main._italic(cap, 22))
			var lesson_keys: Array = ["shop"]
			if main.current_hole_index >= 2:
				lesson_keys.append("sets")
			if main.opens("hunt"):
				lesson_keys.append("hunt")
			if main.current_draft_options.any(func(c): return ClubAbilities.is_staff(c)):
				lesson_keys.append("staff")
			if main.current_draft_options.any(func(c): return ClubAbilities.curse(c) != ""):
				lesson_keys.append("second_hand")
			var lesson := null if cpu else main._lesson_note(lesson_keys)
			if lesson != null:
				names.add_child(BogeyUI.margin(lesson, 0, 10, 0, 0))
			main.add_coverage_chart(chart, "Hover an offer to slot it into your yardages")

	match mode:
		"offers":
			# The rack, and under it the shop's other moves in a row.
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 28)
			row.size_flags_vertical = Control.SIZE_EXPAND_FILL
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			page.add_child(row)
			var rack := HBoxContainer.new()
			rack.add_theme_constant_override("separation", 20)
			rack.alignment = BoxContainer.ALIGNMENT_CENTER
			rack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(rack)
			main._rack = rack
			var offer_width := main.draft_card_width(shown)
			var dealt := 0.0   # how many beats into the deal the next new club lands
			for i in range(shown):
				var offer: Dictionary = main.current_draft_options[i]
				var cv := main.make_draft_card(offer, not cpu,
					DraftAdvisor.gains(main.hand, offer, Main.HAND_CAP), offer_width)
				cv.picked.connect(main._make_draft_pick_callback(i))
				# Passing over an offer slots it into the yardage chart.
				cv.hover_started.connect(func(_v): main._set_coverage_offer(offer))
				cv.hover_ended.connect(func(_v): main._set_coverage_offer({}))
				rack.add_child(cv)
				# A club new to the rack is dealt on to it, not just there.
				if not cpu and main.flourish("rack %d %d %s" % [main.active_index, main.current_hole_index,
						str(offer.get("name", ""))]):
					_deal_in(cv, dealt, _worth_a_beat(offer))
					dealt += 1.6 if _worth_a_beat(offer) else 1.0
			var side := make_draft_side(cpu)
			side.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			row.add_child(side)
		"trade":
			page.add_child(_gap(36))
			page.add_child(main._italic("Give up a club for one more offer. Under each, what losing it costs.", 24))
			page.add_child(_gap(20))
			var grid := _tile_grid()
			page.add_child(grid)
			for i in range(main.hand.size()):
				var club: Dictionary = main.hand[i]
				var losses := DraftAdvisor.losses(main.hand, club)
				var foot := "Nothing depends on it" if losses.is_empty() else str(losses[0].text)
				var ink: Color = BogeyTheme.FLAG if not losses.is_empty() and losses[0].strong else BogeyTheme.NEUTRAL_700
				# A bag always holds a putter: the only one is not for trading.
				var stays: bool = not DraftRules.can_leave(main.hand, i)
				if stays:
					foot = "Your only putter stays"
				var t := _club_tile(club, foot, ink, main._make_trade_callback(i).bind(null), not stays)
				if not losses.is_empty():
					t.tooltip_text = "\n".join(PackedStringArray(losses.map(func(n): return str(n.text))))
				grid.add_child(t)
			page.add_child(_gap(16))
			var back := Button.new()
			back.text = "KEEP THEM ALL"
			BogeyUI.style_link_button(back, 10)
			back.add_theme_color_override("font_color", BogeyTheme.INK)
			back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			back.pressed.connect(_on_trade_cancelled)
			page.add_child(back)
		"cut":
			page.add_child(_gap(36))
			var what := str(main.pending_new_card.name) if main.pending_new_card is Dictionary and not (main.pending_new_card as Dictionary).is_empty() else "the new club"
			page.add_child(main._italic("Your bag is full. Tap a club to drop it for %s." % what, 24))
			page.add_child(_gap(20))
			var grid := _tile_grid()
			page.add_child(grid)
			for i in range(main.hand.size()):
				var club: Dictionary = main.hand[i]
				var losses := DraftAdvisor.losses(main.hand, club)
				var foot := "Nothing depends on it" if losses.is_empty() else str(losses[0].text)
				# ...and is not cut either, unless it is a putter coming in.
				var stays: bool = not DraftRules.can_leave(main.hand, i, main.pending_new_card)
				if stays:
					foot = "Your only putter stays"
				var t := _club_tile(club, foot, BogeyTheme.NEUTRAL_700, main._make_discard_callback(i).bind(null),
					not cpu and not stays, BogeyTheme.FLAG)
				t.mouse_entered.connect(func(): main._set_coverage_focus(club))
				t.mouse_exited.connect(func(): main._set_coverage_focus({}))
				if not losses.is_empty():
					t.tooltip_text = "\n".join(PackedStringArray(losses.map(func(n): return str(n.text))))
				grid.add_child(t)


# Deals one offer on to the rack: it comes up out of nothing `beat` beats
# after the first, with the slide of a card. A club worth a second look (a
# limited edition, a Staff club, one that would make a set) lands with a
# bell and swells once, and holds the next club back a little longer.
const DEAL_BEAT := 0.13

func _deal_in(cv: CardView, beat: float, special: bool) -> void:
	cv.modulate.a = 0.0
	cv.pivot_offset = (cv.custom_minimum_size if cv.custom_minimum_size.x > 0.0 else cv._size) / 2.0
	var tw := main.create_tween()
	tw.bind_node(cv)
	tw.tween_interval(DEAL_BEAT * beat)
	tw.tween_callback(func(): Sound.play("card_slide"))
	tw.set_parallel(true)
	tw.tween_property(cv, "modulate:a", 1.0, 0.16)
	# from(): the rack is a container, which resets a child's scale when it sorts.
	tw.tween_property(cv, "scale", Vector2.ONE, 0.2).from(Vector2(0.94, 0.94)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if special:
		tw.set_parallel(false)
		tw.tween_callback(func(): Sound.play_pitched("chime", 1.5, -5.0))
		tw.tween_property(cv, "scale", Vector2(1.05, 1.05), 0.1)
		tw.tween_property(cv, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _worth_a_beat(offer: Dictionary) -> bool:
	if bool(offer.get("limited", false)) or ClubAbilities.is_staff(offer):
		return true
	# Would it make a set (or the next tier of one)?
	var was := Brands.counts(main.hand)
	var now := Brands.counts(main.hand + [offer])
	for b in now:
		if Brands.tier_reached(int(now[b])) > Brands.tier_reached(int(was.get(b, 0))):
			return true
	return false


# The pro shop's other moves, in a column beside the offers (DraftRules.gd):
# a dig for fresh offers, a club traded in for one more — and, once
# something has been kept from a draft that keeps two, a way to stop there.
func make_draft_side(cpu: bool) -> Control:
	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	var shown := main.current_draft_options.size()
	if main.opens("hunt") and DraftRules.can_dig(main.hand, main.me.draft_taken, main.me.draft_digs, shown):
		var costs := DraftRules.dig_costs_card(main.hand)
		col.add_child(_side_button("Dig", "%d fresh · %s" % [shown, "a bad card in" if costs else "no charge"],
			"Send these back and see %d fresh club%s.\n%s" % [shown, "" if shown == 1 else "s",
				"A bad card joins your Form deck, in a family you don't choose." if costs \
				else "Old Faithful digs for nothing."],
			func(): main.submit("dig", {}), cpu, false))
	if main.opens("hunt") and DraftRules.can_trade(main.hand, main.me.draft_taken, main.me.draft_traded, shown):
		col.add_child(_side_button("Trade in", "A club out, one more in",
			"Give up a club from your bag for one more offer.\nThe club is gone for good, and the shot it brought leaves your Form deck.",
			_on_trade_pressed, cpu, false))
	if main.me.draft_taken > 0:
		col.add_child(_side_button("That'll do", "Keep what you have",
			"Stop here and leave the rest on the rack.", func(): main.submit("done", {}), cpu, true))
	return col


# One of the side column's moves: what it is in capitals, under it what it costs.
func _side_button(title: String, sub: String, tip: String, on_press: Callable,
		disabled: bool, primary: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(Main.DRAFT_SIDE_WIDTH, 66)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	BogeyUI.style_button(b, primary, 12)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink: Color = BogeyTheme.NEUTRAL_100 if primary else BogeyTheme.INK
	var name_label := BogeyUI.kicker(title, ink, 12)
	name_label.add_theme_font_override("font", BogeyUI.sans(600, 3))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	var sub_label := BogeyUI.label(sub, 12, Color(ink, 0.7))
	sub_label.clip_text = true
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub_label)
	var pad := BogeyUI.margin(col, 16, 14, 12, 14)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(pad)
	b.pressed.connect(on_press)
	b.disabled = disabled
	return b


func _on_trade_pressed() -> void:
	Sound.play("ui_click")
	main._trading = true
	main.refresh_ui()


func _on_trade_cancelled() -> void:
	Sound.play("ui_back")
	main._trading = false
	main.refresh_ui()


func _on_boost_pressed(boost: String) -> void:
	Sound.play("ui_click")
	main._boosting = true
	main._boost_pick = boost
	main._tape_pick = 0
	main.refresh_ui()


func _on_boost_cancelled() -> void:
	Sound.play("ui_back")
	main._boosting = false
	main.refresh_ui()


# --- The fitting bay ----------------------------------------------------

func _page_fit(mode: String, cpu: bool) -> void:
	var page := _page(Main.PAGE_PAD_X, 56)
	var head := HBoxContainer.new()
	page.add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 6)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(BogeyUI.kicker("Before %s" % _next_tee(), BogeyTheme.INK_SOFT, 10))
	if mode == "bench":
		names.add_child(BogeyUI.heading("The Fitting Bay", 60))
		names.add_child(BogeyUI.body("%s. Only the right one mends a curse." % (
			"%s is on the bench" % main.me.name if cpu else "Choose a boost, then the club it goes on"),
			15, BogeyTheme.NEUTRAL_800))
		var leave := _caps_btn("Leave the bay", false, func(): main.submit("leave", {}), 48, 11)
		leave.custom_minimum_size.x = 200
		leave.disabled = cpu
		leave.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(leave)
	else:
		var boost: Dictionary = ClubAbilities.BOOSTS[main._boost_pick]
		names.add_child(BogeyUI.heading(str(boost.name), 60))
		names.add_child(BogeyUI.body("%s. Choose the club it goes on." % boost.does, 15, BogeyTheme.NEUTRAL_800))
	page.add_child(_gap(16))
	page.add_child(BogeyUI.hairline(1.0))

	if mode == "bench":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		page.add_child(BogeyUI.margin(row, 0, 72, 0, 0))
		for boost in main.me.draft_boosts:
			var what: Dictionary = ClubAbilities.BOOSTS[boost]
			var can: bool = main.hand.any(func(c): return ClubAbilities.can_boost(c, boost))
			var card := _choice_card("Boost", BogeyTheme.FAIRWAY, str(what.name), 40, "",
				str(what.does) if can else "No club of yours can take it",
				Vector2(300, 300), func(): _on_boost_pressed(boost), cpu or not can, 16)
			row.add_child(card)
		return

	# The club the boost goes on — Lead tape first asks which shot it adds.
	var boost := main._boost_pick
	if boost == "lead_tape":
		var tapes := HBoxContainer.new()
		tapes.add_theme_constant_override("separation", 12)
		page.add_child(BogeyUI.margin(tapes, 0, 24, 0, 0))
		tapes.add_child(BogeyUI.margin(BogeyUI.kicker("The shot it adds", BogeyTheme.INK_SOFT, 10), 0, 14, 8, 0))
		for i in range(main.me.draft_tape.size()):
			var shot := str(main.me.draft_tape[i])
			var b := Button.new()
			b.text = shot
			b.tooltip_text = FormCard.make(shot).effect_text()
			b.custom_minimum_size = Vector2(180, 44)
			b.focus_mode = Control.FOCUS_NONE
			BogeyUI.style_button(b, i == main._tape_pick, 14)
			b.pressed.connect(func():
				main._tape_pick = i
				main.refresh_ui())
			tapes.add_child(b)
	var grid := _tile_grid()
	page.add_child(BogeyUI.margin(grid, 0, 32, 0, 0))
	for i in range(main.hand.size()):
		var club: Dictionary = main.hand[i]
		var can := ClubAbilities.can_boost(club, boost)
		var note := "Putters take no boost" if not ClubAbilities.grows(club) else "Already has one"
		if ClubAbilities.curse(club) != "":
			note = "Cursed: it needs a %s" % str(ClubAbilities.BOOSTS[ClubAbilities.MENDS[ClubAbilities.curse(club)]].name).to_lower()
		if can:
			var cursed := ClubAbilities.curse(club)
			note = str(ClubAbilities.BOOSTS[boost].does)
			if cursed != "":
				note = "Mends its %s" % str(ClubAbilities.curse_info(cursed).name).to_lower()
			elif boost == "lead_tape":
				note = "Adds a %s to its shots" % str(main.me.draft_tape[main._tape_pick])
		grid.add_child(_club_tile(club, note, BogeyTheme.FAIRWAY_DEEP if can else BogeyTheme.INK_SOFT,
			func(): main.submit("boost", {"boost": boost, "index": i, "shot": main._tape_pick}), can))
	var back := Button.new()
	back.text = "BACK TO THE BENCH"
	BogeyUI.style_link_button(back, 10)
	back.add_theme_color_override("font_color", BogeyTheme.INK)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_on_boost_cancelled)
	page.add_child(BogeyUI.margin(back, 0, 16, 0, 0))


# --- The hut ------------------------------------------------------------

func _page_hut(cpu: bool) -> void:
	var what: Dictionary = Route.EVENTS[Route.event(main.wind_seed, main.current_hole_index, main.plays_for_keeps())]
	var center := CenterContainer.new()
	main.interlude.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	col.custom_minimum_size = Vector2(1000, 0)
	center.add_child(col)
	var k := BogeyUI.kicker("The hut · before %s" % _next_tee(), BogeyTheme.INK_SOFT, 10)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(k)
	var t := BogeyUI.heading(str(what.title), 72)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(t)
	var words := BogeyUI.body(str(what.text), 18, BogeyTheme.NEUTRAL_800)
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.custom_minimum_size = Vector2(640, 0)
	words.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(words)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(BogeyUI.margin(row, 0, 12, 0, 0))
	var walk := _caps_btn("Walk on", false, func(): main.submit("leave", {}), 56)
	walk.custom_minimum_size.x = 180
	walk.disabled = cpu
	row.add_child(walk)
	var take := _caps_btn(str(what.take), true, func(): main.submit("event", {}), 56)
	take.custom_minimum_size.x = 220
	take.disabled = cpu
	row.add_child(take)
	if cpu:
		var w := main._italic("%s is at the hut…" % main.me.name, 22)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(w)


# --- The card -----------------------------------------------------------

func _page_end() -> void:
	var center := CenterContainer.new()
	main.interlude.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	center.add_child(col)

	var total_strokes := 0
	var total_par := 0
	for entry in main.round_scores:
		total_strokes += int(entry.strokes)
		total_par += int(entry.par)
	var diff := total_strokes - total_par

	var kick := "%s · round complete" % Course.active_name
	var headline := "%d — %s" % [total_strokes, main.score_diff_text(diff)]
	if main._run_over:
		kick = "%s · out of strokes" % Course.active_name
		headline = "The run ended after %d hole%s" % [main.round_scores.size(), "" if main.round_scores.size() == 1 else "s"]
	if main.is_multiplayer():
		headline = _winner_line()
	if main.on_tour():
		kick = "The tour · %s · %d of %d" % [Course.active_name, GameSetup.tour_leg + 1, Main.TOUR.size()]
	var k := BogeyUI.kicker(kick, BogeyTheme.INK_SOFT, 10)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(k)
	var h := BogeyUI.heading(headline, 56)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(BogeyUI.margin(h, 0, 8, 0, 0))
	# What the round did, a line each: the course record, the holes where
	# a best was beaten, the course it opened.
	var record: Dictionary = main._round_record
	if bool(record.get("new_best", false)) and not (record.get("previous", {}) as Dictionary).is_empty():
		var was_best := int((record.previous as Dictionary).get("strokes", 0))
		var rec := BogeyUI.heading("A new course record: %d beats %d" % [total_strokes, was_best], 26)
		rec.add_theme_color_override("font_color", BogeyTheme.GOLD_800)
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rec.set_meta("ring", true)
		col.add_child(BogeyUI.margin(rec, 0, 10, 0, 0))
	if not main.is_multiplayer() and main.me.bests > 0:
		var bests := BogeyUI.body("Your best beaten on %d hole%s." % [main.me.bests, "" if main.me.bests == 1 else "s"],
			15, BogeyTheme.FAIRWAY_DEEP)
		bests.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(BogeyUI.margin(bests, 0, 8, 0, 0))
	if main._opened_course != "":
		var opened := BogeyUI.heading("%s is now open" % main._opened_course, 26)
		opened.add_theme_color_override("font_color", BogeyTheme.FAIRWAY_DEEP)
		opened.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		opened.set_meta("ring", true)
		col.add_child(BogeyUI.margin(opened, 0, 10, 0, 0))

	# The card itself, printed large.
	var card := ScorecardView.new()
	if main.is_multiplayer():
		var rows: Array = []
		for i in range(main.players.size()):
			var p: Player = main.players[i]
			rows.append({"name": p.name, "color": CourseMapView.seat_color(i),
				"scores": p.round_scores, "live": 0, "active": false})
		card.set_card(rows, -1)
	else:
		card.set_round(main.round_scores, -1, 0)
	var big := 1.3
	card.scale = Vector2(big, big)
	var holder := Control.new()
	holder.custom_minimum_size = card.custom_minimum_size * big
	holder.add_child(card)
	var sheet := BogeyUI.make_panel(BogeyUI.card_style(28, 22))
	sheet.add_child(holder)
	sheet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(BogeyUI.margin(sheet, 0, 32, 0, 0))

	var bag_line := main.bag_summary()
	if main.on_tour():
		bag_line = "The tour, %s. %s" % [main.tour_total_text(), bag_line]
	var bl := BogeyUI.body(bag_line, 13, BogeyTheme.INK_SOFT)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(BogeyUI.margin(bl, 0, 14, 0, 0))
	var end_note := main._lesson_note(["end"])
	if end_note != null:
		end_note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(BogeyUI.margin(end_note, 0, 22, 0, 0))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var menu := _caps_btn("Menu", false, main._on_header_menu_pressed, 52, 11)
	menu.custom_minimum_size.x = 140
	if main.tour_continues():
		# Pack for the next course: the bag down to what travels, then on.
		var next_course := main.tour_course_name(GameSetup.tour_leg + 1)
		var over: int = main.hand.size() - Main.TOUR_KEEP
		if over > 0:
			col.add_child(_gap(28))
			col.add_child(BogeyUI.hairline(1.0))
			var ph := HBoxContainer.new()
			ph.add_child(BogeyUI.heading("Pack for %s: leave %d behind" % [next_course, over], 30))
			col.add_child(BogeyUI.margin(ph, 0, 14, 0, 0))
			col.add_child(BogeyUI.body("%d clubs travel, with everything they have gained. Tap a club to leave it behind." % Main.TOUR_KEEP,
				13, BogeyTheme.NEUTRAL_800))
			var grid := _tile_grid(mini(main.hand.size(), 14))
			grid.add_theme_constant_override("h_separation", 6)
			col.add_child(BogeyUI.margin(grid, 0, 14, 0, 0))
			for i in range(main.hand.size()):
				var club: Dictionary = main.hand[i]
				var stays: bool = not DraftRules.can_leave(main.hand, i)
				var losses := DraftAdvisor.losses(main.hand, club)
				var foot := "Your only putter travels" if stays else ("" if losses.is_empty() else str(losses[0].text))
				var t := _club_tile(club, foot, BogeyTheme.FLAG, func(): main._on_pack_leave(i), not stays, BogeyTheme.FLAG)
				t.custom_minimum_size = Vector2(96, 110)
				grid.add_child(t)
		buttons.add_child(_caps_btn("Start the tour again", false, main.restart_round, 52, 11))
		var go := _caps_btn("Tee off at %s" % next_course, true, main._on_tour_next, 52, 12)
		go.custom_minimum_size.x = 300
		go.disabled = over > 0
		buttons.add_child(go)
	else:
		buttons.add_child(menu)
		var again := _caps_btn("Start the tour again" if main.on_tour() else "Play again", true, main.restart_round, 52, 12)
		again.custom_minimum_size.x = 220
		buttons.add_child(again)
	col.add_child(BogeyUI.margin(buttons, 0, 32, 0, 0))

	# The first time the card is shown it is tallied, not just there.
	if main.flourish("tally"):
		_tally(col, h, headline, total_strokes if not main.is_multiplayer() and not main._run_over else -1)


# The card told a line at a time: the score counted up, then each thing
# below it in turn, the ones worth a bell (a record, a course opened) with
# one. `count_to` is the strokes the headline counts up to, or -1 for a
# headline that is not a score.
const TALLY_BEAT := 0.32

func _tally(col: VBoxContainer, head: Label, headline: String, count_to: int) -> void:
	var at := 0.25
	for child in col.get_children():
		var line := child as Control
		if line == null:
			continue
		line.modulate.a = 0.0
		var tw := main.create_tween()
		tw.bind_node(line)
		tw.tween_interval(at)
		# A margin wraps each line; the bell is asked for on the line itself.
		var inner: Node = line.get_child(0) if line.get_child_count() > 0 else line
		if inner.has_meta("ring"):
			tw.tween_callback(func(): Sound.chime(6, -4.0))
		tw.tween_property(line, "modulate:a", 1.0, 0.25)
		if inner == head and count_to > 0:
			# The strokes run up from nothing, then the verdict lands.
			head.text = "0"
			tw.tween_method(func(v: float): head.text = str(roundi(v)), 0.0, float(count_to), 0.8)
			tw.tween_callback(func():
				head.text = headline
				Sound.play("card_place"))
			at += 0.8
		at += TALLY_BEAT


# The headline of a group's card: who won, and by how much — a tie said as one.
func _winner_line() -> String:
	var standings: Array = main.players.filter(func(p): return not p.round_scores.is_empty())
	if standings.size() < 2:
		return "Round complete"
	standings.sort_custom(func(a, b): return a.total_strokes() < b.total_strokes())
	var low: int = standings[0].total_strokes()
	var tied: Array = standings.filter(func(p): return p.total_strokes() == low)
	if tied.size() > 1:
		return "%s tie on %d" % [" & ".join(PackedStringArray(tied.map(func(p): return p.name))), low]
	var gap: int = standings[1].total_strokes() - low
	var who: String = standings[0].name
	return "%s %s by %d" % [who, "win" if who == "You" else "wins", gap]


# What the draft's caption says about how it was earned.
func draft_caption() -> String:
	if main.me.draft_taken > 0:
		return "One kept. Keep another, or call it done."
	if main._opening:
		return "The round starts here: %d of these join the Bogey-Mart set you own." % main.me.draft_keeps
	match main.me.call_result:
		DraftRules.MADE:
			return "You called %s and made it: more to choose from, and %d to keep." % [
				DraftRules.CALL_NAME, main.me.draft_keeps]
		DraftRules.MISSED:
			return "You called %s and missed: a short rack this hole." % DraftRules.CALL_NAME
	return "It joins your bag for the rest of the round."
