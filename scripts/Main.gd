extends Control

# ---------------------------------------------------------
# BOOGIE PROTOTYPE
# Single hole, single player. Tests the core loop (Section 4, Form Card
# System):
#   club draft: draw 3 / pick 1 (permanent growing hand, 14-card cap)
#   -> declare shot: choose a club + target
#   -> draw 3 Form cards, pick 1 (fully known effect, no hidden rolls)
#   -> final aim adjustment -> resolve deterministically
#   -> repeat until on the green -> putting QTE (timing meter, difficulty
#      scaled by distance to the pin)
# ---------------------------------------------------------

enum State { AIM, FORM_DRAW, DRAFT, DISCARD_FOR_DRAFT, CLUB_SELECT, DISCARD_FOR_HAZARD, PUTTING, DONE }

const HAND_CAP := 14

# Inside this distance a putt is conceded rather than played (about 2 feet).
const GIMME_YARDS := 0.7

# On-screen width of the putt meter. Deliberately wide: the hardest putt's
# sunk band is 12% of the bar, which needs the room to stay aimable.
const METER_WIDTH := 620

const Palette := preload("res://scripts/BoogieTheme.gd")

# Parchment / fairway theme, shared with Title.gd via BoogieTheme.
const COLOR_BG := Palette.PARCHMENT
const COLOR_PANEL := Palette.PARCHMENT_RAISED
const COLOR_TEXT := Palette.INK
const COLOR_TEXT_SOFT := Palette.INK_SOFT
const COLOR_ACCENT := Palette.FAIRWAY_DEEP
const COLOR_SAND := Palette.SAND_DEEP
const COLOR_WATER := Palette.WATER_DEEP
const COLOR_FLAG := Palette.FLAG

var state: int = State.DRAFT

var hand: Array = []
var club_deck: Array = []
var club_discard: Array = []

var form_deck: FormDeck

# Section 3B — the run's live brands. Only 4 of the 6 draftable brands are
# in the club deck each round; the other two are absent entirely, not
# rarer. This is where run-to-run variance lives, since the course itself
# is fixed and knowable. Revealed to the player before hole 1.
var live_brands: Array = []

var current_hole_index: int = 1
var round_scores: Array = []  # [{"hole": int, "par": int, "strokes": int}, ...]

var hole: HoleData
var hole_yardage: float = 380.0
var hole_par: int = 4
var ball_pos: Vector2 = Vector2.ZERO  # yard-space, (0,0) at tee, +y toward pin
var shot_path: Array = []  # history of ball_pos points this hole, for drawing the trail
var strokes: int = 0
var current_lie: String = "tee"
var aim_target: Vector2 = Vector2.ZERO  # yard-space, the player's clicked target for the next shot

# Putting (Section 7) — a timing QTE whose sweet spot shrinks and whose
# marker speeds up the further the ball is from the pin.
var putt_dist: float = 0.0     # yards from ball to pin for the current putt
var _putt_dir: Vector2 = Vector2(0, 1)  # unit vector pin -> ball, so misses stay on a plausible line
var putt_meter: PuttMeter
var yips_pending: bool = false  # Section 4 putting cross-trigger: taints the next putt

var pending_new_card = null
var current_draft_options: Array = []
var pending_club: Dictionary = {}
var current_form_options: Array = []  # Array[FormCard] for this shot — 3 (MID), 2 (FULL/FINESSE), or 1 forced (EXTREME_FINESSE/bunker)
var current_form_forced: bool = false  # true when there's no choice: a single created bad card, must be played

# --- UI node refs (built in code) ---
var status_label: Label
var map_view: CourseMapView
var hand_label: Label
var options_label: Label
var options_container: HBoxContainer

# Redesign additions: the header's step pill, the map caption, the
# per-stroke log cards, and the Form half of the bottom strip.
var step_holder: HBoxContainer
var map_caption: Label
var log_container: VBoxContainer
var form_label: Label
var form_hint: Label
var form_container: HBoxContainer

# Play-by-play is now a list of built cards rather than one bbcode blob,
# so entries are kept as {tag, ink, head, body} dictionaries and rebuilt
# on refresh. Newest first.
var log_entries: Array = []
var scorecard: ScorecardView
var header_meta: HFlowContainer     # live-brand/round/bag chip row, right of the title
var hole_title: Label
var shot_outlook: VBoxContainer
var form_deck_popup: PopupPanel
var form_deck_list: VBoxContainer


func _ready() -> void:
	build_ui()
	init_game()
	start_hole()


# ---------------------------------------------------------
# UI CONSTRUCTION
# ---------------------------------------------------------
func build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# --- Header: hole identity, step hint, running figures ----------------
	# The redesign splits the header into three jobs: who/where you are on
	# the left, what to do next in the middle, and the running numbers on
	# the right. The step pill is the important addition — the old header
	# left "what now?" to a line of small grey text in the log column.
	var header := BoogieUI.make_panel(BoogieUI.ruled_panel(false, false, false, true, 20))
	header.custom_minimum_size = Vector2(0, 92)
	root.add_child(header)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 24)
	header.add_child(header_row)

	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 2)
	title_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_col.custom_minimum_size = Vector2(190, 0)
	header_row.add_child(title_col)
	title_col.add_child(BoogieUI.heading("Boogie", 24))
	title_col.add_child(BoogieUI.kicker("Boogie Links", BoogieTheme.ACCENT_700))

	var hole_col := VBoxContainer.new()
	hole_col.add_theme_constant_override("separation", 2)
	hole_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(hole_col)

	hole_title = BoogieUI.heading("Hole 1 — Par 4", 28)
	hole_col.add_child(hole_title)

	status_label = BoogieUI.body("Loading...", 14, BoogieTheme.NEUTRAL_700)
	hole_col.add_child(status_label)

	# The step pill sits centered between the hole line and the figures.
	step_holder = HBoxContainer.new()
	step_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	header_row.add_child(step_holder)

	# The chip row's length varies with the run (live brands, set bonuses,
	# progress counters), so it flows onto a second line rather than
	# running off the right edge of the header.
	header_meta = HFlowContainer.new()
	header_meta.add_theme_constant_override("h_separation", 10)
	header_meta.add_theme_constant_override("v_separation", 6)
	header_meta.alignment = FlowContainer.ALIGNMENT_END
	header_meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_meta)

	# --- Middle: scorecard | hole plate | shot panel ----------------------
	var mid_row := HBoxContainer.new()
	mid_row.add_theme_constant_override("separation", 0)
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid_row)

	var card_panel := BoogieUI.make_panel(BoogieUI.ruled_panel(false, true, false, false, 18))
	card_panel.custom_minimum_size = Vector2(300, 0)
	mid_row.add_child(card_panel)

	var card_col := VBoxContainer.new()
	card_col.add_theme_constant_override("separation", 10)
	card_panel.add_child(card_col)
	# ScorecardView draws its own "SCORECARD" kicker — don't add a second.

	scorecard = ScorecardView.new()
	scorecard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_col.add_child(scorecard)

	var plate_panel := BoogieUI.make_panel(BoogieUI.ruled_panel(false, true, false, false, 20))
	plate_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_row.add_child(plate_panel)

	var plate_col := VBoxContainer.new()
	plate_col.add_theme_constant_override("separation", 10)
	plate_panel.add_child(plate_col)

	var plate_head := HBoxContainer.new()
	plate_col.add_child(plate_head)
	plate_head.add_child(BoogieUI.kicker("The hole · tee to green", BoogieTheme.ACCENT_700))
	var plate_spacer := Control.new()
	plate_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate_head.add_child(plate_spacer)
	map_caption = BoogieUI.body("", 13, BoogieTheme.NEUTRAL_700)
	map_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	plate_head.add_child(map_caption)

	map_view = CourseMapView.new()
	map_view.aim_picked.connect(_on_aim_picked)
	map_view.aim_changed.connect(_on_aim_changed)
	# Holes run tall and narrow (roughly 120-200 yds wide, 400-600 yds
	# long), so the mat is capped to a sensible width and centered rather
	# than stretched to fill the column — matted like a course-guide
	# illustration, not a wide empty frame around a thin strip.
	var hole_plate := BoogieUI.plate(map_view)
	hole_plate.custom_minimum_size = Vector2(360, 0)
	hole_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate_col.add_child(hole_plate)

	# --- Shot panel: the numbers for the shot in front of you -------------
	var shot_panel := BoogieUI.make_panel(BoogieUI.ruled_panel(true, false, false, false, 0))
	shot_panel.custom_minimum_size = Vector2(380, 0)
	mid_row.add_child(shot_panel)

	var shot_col := VBoxContainer.new()
	shot_col.add_theme_constant_override("separation", 0)
	shot_panel.add_child(shot_col)

	var this_shot := BoogieUI.make_panel(BoogieUI.ruled_panel(false, false, false, true, 20))
	shot_col.add_child(this_shot)

	shot_outlook = VBoxContainer.new()
	shot_outlook.add_theme_constant_override("separation", 12)
	this_shot.add_child(shot_outlook)

	var log_wrap := BoogieUI.make_panel(BoogieUI.ruled_panel(false, false, false, false, 20))
	log_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shot_col.add_child(log_wrap)

	var log_col := VBoxContainer.new()
	log_col.add_theme_constant_override("separation", 10)
	log_wrap.add_child(log_col)
	log_col.add_child(BoogieUI.kicker("Play-by-play", BoogieTheme.ACCENT_700))

	# Each stroke is now its own card rather than a line in one scrolling
	# block, so a glance finds the stroke you want.
	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_col.add_child(log_scroll)

	log_container = VBoxContainer.new()
	log_container.add_theme_constant_override("separation", 10)
	log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_container)

	# --- Bottom: your bag on the left, the Form hand on the right --------
	# Split, not swapped: the bag is what you own, the Form hand is what
	# this swing dealt you, and seeing both at once is the whole read of
	# the game. The Form side shows face-down placeholders until a draw
	# happens, and both sides double as the surface for the draft,
	# discard, and putting decisions.
	var strip := BoogieUI.make_panel(BoogieUI.ruled_panel(false, false, true, false, 0))
	# Tall enough for the taller of the two card faces (Form, 184) plus the
	# kicker row and the panel's own padding — the bag's 168 fits inside it.
	strip.custom_minimum_size = Vector2(0, 286)
	root.add_child(strip)

	var strip_row := HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 0)
	strip.add_child(strip_row)

	var bag_wrap := BoogieUI.make_panel(BoogieUI.panel(BoogieTheme.NEUTRAL_100, 20, 0))
	bag_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_row.add_child(bag_wrap)

	var bag_col := VBoxContainer.new()
	bag_col.add_theme_constant_override("separation", 10)
	bag_wrap.add_child(bag_col)

	var bag_head := HBoxContainer.new()
	bag_head.add_theme_constant_override("separation", 14)
	bag_col.add_child(bag_head)
	hand_label = BoogieUI.kicker("Your bag", BoogieTheme.ACCENT_700)
	hand_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bag_head.add_child(hand_label)
	options_label = BoogieUI.body("", 13, BoogieTheme.NEUTRAL_600)
	options_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A one-line caption beside the kicker: let it take the rest of the row
	# and ellipsize rather than autowrap into a one-word-per-line column.
	options_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	options_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bag_head.add_child(options_label)

	var options_scroll := ScrollContainer.new()
	options_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_col.add_child(options_scroll)

	options_container = HBoxContainer.new()
	options_container.add_theme_constant_override("separation", 12)
	options_scroll.add_child(options_container)

	var form_wrap := BoogieUI.make_panel(BoogieUI.ruled_panel(true, false, false, false, 20))
	form_wrap.custom_minimum_size = Vector2(620, 0)
	strip_row.add_child(form_wrap)

	var form_col := VBoxContainer.new()
	form_col.add_theme_constant_override("separation", 10)
	form_wrap.add_child(form_col)

	var form_head := HBoxContainer.new()
	form_head.add_theme_constant_override("separation", 14)
	form_col.add_child(form_head)
	form_label = BoogieUI.kicker("Form hand", BoogieTheme.ACCENT_700)
	form_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	form_head.add_child(form_label)
	form_hint = BoogieUI.body("", 13, BoogieTheme.NEUTRAL_600)
	form_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	form_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	form_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	form_head.add_child(form_hint)

	form_container = HBoxContainer.new()
	form_container.add_theme_constant_override("separation", 12)
	form_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_col.add_child(form_container)

	build_form_deck_popup()


# A browsable list of every Form card currently in the deck or discard
# pile, grouped by name with counts — opened from the "FORM DECK" chip in
# the header. Shuffled-deck contents wouldn't normally be visible to a
# real player, but this trades that realism for letting the player see
# exactly how degraded their Form deck has gotten after a rough round.
func build_form_deck_popup() -> void:
	form_deck_popup = PopupPanel.new()
	form_deck_popup.size = Vector2(340, 420)
	add_child(form_deck_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	form_deck_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	vbox.add_child(BoogieUI.kicker("Form deck contents", COLOR_SAND))
	vbox.add_child(BoogieUI.hairline(0.14))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	form_deck_list = VBoxContainer.new()
	form_deck_list.add_theme_constant_override("separation", 4)
	form_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form_deck_list)


func rebuild_form_deck_list() -> void:
	clear_container(form_deck_list)
	if not form_deck:
		return

	var all_cards: Array = []
	all_cards.append_array(form_deck.deck)
	all_cards.append_array(form_deck.discard)

	var counts := {}       # name -> count
	var is_good := {}      # name -> bool
	for c in all_cards:
		counts[c.name] = counts.get(c.name, 0) + 1
		is_good[c.name] = c.good

	var total := all_cards.size()
	form_deck_list.add_child(BoogieUI.body("%d cards total (%d in deck, %d in discard)" % [
		total, form_deck.deck.size(), form_deck.discard.size()], 11, COLOR_TEXT_SOFT))
	form_deck_list.add_child(BoogieUI.hairline(0.1))

	var names: Array = counts.keys()
	names.sort_custom(func(a, b):
		if is_good[a] != is_good[b]:
			return is_good[a]  # good cards first
		return a < b)

	for name in names:
		var label_color := COLOR_ACCENT if is_good[name] else COLOR_FLAG
		form_deck_list.add_child(BoogieUI.body("%s  x%d" % [name, counts[name]], 13, label_color))


func _on_form_deck_chip_pressed() -> void:
	rebuild_form_deck_list()
	form_deck_popup.popup_centered()


# Play-by-play entries. Callers still pass the same bbcode-ish strings
# they always did; this strips the markup and files each one as a card so
# the column reads as a list of strokes rather than a wall of text. A
# leading "[b]...[/b]" run becomes the card's headline, and a "Stroke N"
# opener becomes its tag.
func log_msg(text: String) -> void:
	var clean := strip_markup(text)
	if clean.strip_edges() == "":
		return

	var tag := ""
	var ink := BoogieTheme.NEUTRAL_600
	var head := ""
	var body := clean

	# "Stroke 3 — played Hook with Driver (lie: fairway)" splits into a
	# "STROKE 3" tag and the rest as the headline.
	if clean.begins_with("Stroke "):
		var dash := clean.find(" — ")
		if dash > 0:
			tag = clean.substr(0, dash)
			head = clean.substr(dash + 3)
			body = ""
			ink = BoogieTheme.ACCENT_700
	elif text.begins_with("[b]"):
		var close := text.find("[/b]")
		if close > 0:
			head = strip_markup(text.substr(3, close - 3))
			body = strip_markup(text.substr(close + 4)).strip_edges()
			tag = "Hole"
			ink = BoogieTheme.OLIVE_700

	if tag == "":
		tag = "Note"

	log_entries.push_front({"tag": tag, "ink": ink, "head": head, "body": body})
	rebuild_log()


# Drops bbcode tags so the same strings can feed plain Labels.
func strip_markup(text: String) -> String:
	var out := ""
	var depth := 0
	for i in text.length():
		var ch := text[i]
		if ch == "[":
			depth += 1
		elif ch == "]":
			if depth > 0:
				depth -= 1
		elif depth == 0:
			out += ch
	return out


func rebuild_log() -> void:
	if log_container == null:
		return
	clear_container(log_container)
	for entry in log_entries:
		log_container.add_child(BoogieUI.log_entry(
			entry.tag, entry.ink, entry.head, entry.body))


func clear_container(c: Container) -> void:
	for child in c.get_children():
		child.queue_free()


# ---------------------------------------------------------
# CARD HELPERS
# ---------------------------------------------------------
func make_club(cname: String, min_y: float, max_y: float, ctype: String,
		brand: String = Brands.NONE, limited: bool = false, ability: String = "") -> Dictionary:
	return {
		"name": cname,
		"min_yard": min_y,
		"max_yard": max_y,
		"type": ctype,          # "wood" / "iron" / "wedge" / "putter"
		"brand": brand,         # Brands.NONE for standards — see Brands.gd
		"limited": limited,
		"ability": ability
	}


# ---------------------------------------------------------
# SETUP
# ---------------------------------------------------------
func init_game() -> void:
	# The starting set is Bogey-Mart (Section 3A): a cheap supermarket
	# three-piece, deliberately the worst gear in the game. Shorter bands,
	# and — the sharper penalty — NARROWER ones, which drops you into the
	# 2-card Form draw far more often than a real club would. Escaping this
	# set is the run's first goal.
	hand = [
		make_club("Bogey-Mart Driver", 190, 235, "wood", Brands.STARTER),
		make_club("Bogey-Mart 7-Iron", 95, 140, "iron", Brands.STARTER),
		make_club("Bogey-Mart Putter", 0, 0, "putter", Brands.STARTER)
	]

	live_brands = roll_live_brands()
	club_deck = build_club_pool()
	club_deck.shuffle()
	club_discard = []

	form_deck = FormDeck.new()


# Section 3B — picks this run's 4 live brands, under the pairing rule:
# at least two distinct axes must be represented. Four brands all
# attacking the same axis would collapse the run into a single strategy,
# so the constraint guarantees every run offers two real directions to
# commit to. Retries rather than repairs — the pool is tiny and a valid
# draw is overwhelmingly likely, so a simple reroll is clearer than
# patching a bad set.
func roll_live_brands() -> Array:
	var all: Array = Brands.DRAFTABLE.duplicate()
	for attempt in range(32):
		all.shuffle()
		var pick: Array = all.slice(0, 4)
		var axes := {}
		for b in pick:
			axes[Brands.AXIS.get(b, "")] = true
		if axes.size() >= 2:
			return pick
	# Unreachable in practice (any 4 of these 6 already span 2+ axes), but
	# return something valid rather than an empty pool if it ever is.
	return all.slice(0, 4)


# The shared club deck (Section 3C). Standards are brandless and always
# present, so the deck always covers every yardage gap and is never
# unplayable. Branded clubs sit on top of that base and are the draft's
# real content — but only the run's live brands are included (Section 3B).
#
# Yardage lives here, on individual cards, where it's a local stat the
# player reads. Set bonuses never touch yardage — see Brands.gd.
func build_club_pool() -> Array:
	var pool: Array = []

	# --- Standards: brandless, always in the pool, 3 copies each ---
	for i in range(3):
		pool.append(make_club("Driver", 200, 260, "wood"))
		pool.append(make_club("3-Wood", 180, 220, "wood"))
		pool.append(make_club("5-Iron", 140, 180, "iron"))
		pool.append(make_club("7-Iron", 100, 150, "iron"))
		pool.append(make_club("9-Iron", 80, 110, "iron"))
		pool.append(make_club("Pitching Wedge", 50, 90, "wedge"))
		pool.append(make_club("Sand Wedge", 20, 60, "wedge"))
		pool.append(make_club("Putter", 0, 0, "putter"))

	# --- Branded: only this run's live brands (Section 3B) ---
	for brand in live_brands:
		pool.append_array(branded_clubs(brand))

	# --- Limited editions: rare, one copy each, live brands only ---
	for card in limited_clubs():
		if card.brand == Brands.NONE or live_brands.has(card.brand):
			pool.append(card)

	return pool


# Section 3C limited editions: one copy each, a Created-card ability, and
# a pair rider that keys off a specific partner in the Bag rather than a
# count. These are the draft's "I need one more thing" hooks.
func limited_clubs() -> Array:
	return [
		make_club("Gold Cleek", 145, 185, "iron", "titanist", true,
			"Once per hole, create a Pure Strike. With a Titanist Wood in bag: twice per hole"),
		make_club("The Bulger", 210, 270, "wood", "slazinger", true,
			"Create a Big Strike from rough/bunker. With any Wedge in bag: no lie requirement"),
		make_club("Old Tom's Niblick", 30, 70, "wedge", "macgregorian", true,
			"Creates a Flop Shot on landing in a bunker. With a MacGregorian Wood: also Bump and Run on fairway"),
		make_club("The Rutter", 35, 80, "wedge", "callowell", true,
			"Purges a bad Form card on each hazard. With a Callowell Iron in bag: purges two"),
		make_club("Old Reliable Putter", 0, 0, "putter", "pingwell", true,
			"Once per round, create Steady Hands. With another Ping-Well club: once every six holes"),
		make_club("Persimmon Spoon", 175, 225, "wood", "macgregorian", true,
			"Playable from rough with no penalty. With a 2nd MacGregorian: playable from any lie"),
		make_club("The Equaliser", 120, 170, "iron", "nimbus", true,
			"With 3+ distinct brands in your bag, counts as EVERY brand for set purposes"),
	]


# Every club belonging to one brand. Each brand spans enough categories
# and enough cards to actually reach a 7-set, and each carries riders that
# express its axis locally — the set bonus expresses the same idea as a
# rule (Brands.gd).
func branded_clubs(brand: String) -> Array:
	match brand:
		"titanist":
			# Tour precision: tight bands, strong buffering, unforgiving.
			return [
				make_club("Titanist Pro Driver", 205, 250, "wood", brand, false, "Buffers deviation 20% better; -30% distance from rough"),
				make_club("Titanist 4-Iron", 155, 190, "iron", brand, false, "Buffers deviation 25% better"),
				make_club("Titanist 6-Iron", 125, 160, "iron", brand, false, "Buffers deviation 25% better"),
				make_club("Titanist 8-Iron", 90, 125, "iron", brand, false, "Buffers deviation 25% better"),
				make_club("Titanist Tour Wedge", 45, 85, "wedge", brand, false, "Buffers deviation 25% better"),
				make_club("Titanist Blade Putter", 0, 0, "putter", brand, false, "Once per round, a second putt attempt"),
				make_club("Titanist Fairway 5", 165, 205, "wood", brand, false, "Buffers deviation 20% better"),
			]
		"callowell":
			# Forgiveness: wide bands, blunts bad cards, low ceiling.
			return [
				make_club("Callowell Big Deal Driver", 195, 255, "wood", brand, false, "Chunk and Top hit at half severity"),
				make_club("Callowell 6-Iron", 115, 175, "iron", brand, false, "The widest iron in the game"),
				make_club("Callowell Rescue", 130, 185, "iron", brand, false, "Playable from rough with no distance penalty"),
				make_club("Callowell 9-Iron", 75, 120, "iron", brand, false, "Wide band"),
				make_club("Callowell Gap Wedge", 40, 85, "wedge", brand, false, "Shank cannot downgrade your lie"),
				make_club("Callowell Sand Wedge", 20, 65, "wedge", brand, false, "Wide band"),
				make_club("Callowell Mallet Putter", 0, 0, "putter", brand, false, "Forgiving on long putts"),
			]
		"pingwell":
			# Fitted feel: rewards playing a club at its comfortable middle.
			return [
				make_club("Ping-Well i-Series 3", 165, 210, "iron", brand, false, "Widened Mid tier"),
				make_club("Ping-Well i-Series 5", 135, 185, "iron", brand, false, "Widened Mid tier"),
				make_club("Ping-Well i-Series 8", 85, 130, "iron", brand, false, "Widened Mid tier"),
				make_club("Ping-Well Driver", 198, 248, "wood", brand, false, "Widened Mid tier"),
				make_club("Ping-Well Lob Wedge", 15, 55, "wedge", brand, false, "Creates Flop Shot on any hazard lie"),
				make_club("Ping-Well Gap Wedge", 45, 90, "wedge", brand, false, "Widened Mid tier"),
				make_club("Ping-Well Mallet Putter", 0, 0, "putter", brand, false, "Steady Hands widens the sunk band twice as much"),
			]
		"macgregorian":
			# Heritage: low running ball, built for scrappy lies.
			return [
				make_club("MacGregorian Persimmon Driver", 185, 245, "wood", brand, false, "The only Wood playable from a bunker"),
				make_club("MacGregorian Brassie", 170, 215, "wood", brand, false, "Bump and Run gains +20 yds roll"),
				make_club("MacGregorian Spoon", 150, 195, "wood", brand, false, "Ignores the rough's distance penalty"),
				make_club("MacGregorian Mashie", 120, 165, "iron", brand, false, "Ignores the rough's distance penalty"),
				make_club("MacGregorian Mid-Mashie", 140, 185, "iron", brand, false, "Ignores the rough's distance penalty"),
				make_club("MacGregorian Niblick", 45, 95, "wedge", brand, false, "Landing in a hazard adds no bad card to the Form deck"),
				make_club("MacGregorian Jigger", 0, 0, "putter", brand, false, "Putts from the fringe as though on the green"),
			]
		"slazinger":
			# Distance at a price: long, and worse at buffering.
			return [
				make_club("Slazinger Cannon Driver", 215, 285, "wood", brand, false, "Longest in the game; buffers deviation 30% worse"),
				make_club("Slazinger Launch Wood", 190, 240, "wood", brand, false, "Big Strike grants max band +10"),
				make_club("Slazinger Power Iron", 150, 200, "iron", brand, false, "Long for an iron; buffers 20% worse"),
				make_club("Slazinger Deep Iron", 125, 175, "iron", brand, false, "Buffers 20% worse"),
				make_club("Slazinger Blast Wedge", 35, 90, "wedge", brand, false, "Extra distance out of bunkers"),
				make_club("Slazinger Long Iron", 175, 225, "iron", brand, false, "Buffers 20% worse"),
				make_club("Slazinger Heavy Putter", 0, 0, "putter", brand, false, "Strong on long putts, wild on short ones"),
			]
		"nimbus":
			# Hybrid tech: covers gaps, no strong opinion.
			return [
				make_club("Nimbus Hybrid 3", 160, 215, "iron", brand, false, "Counts as both Wood and Iron"),
				make_club("Nimbus Hybrid 5", 130, 180, "iron", brand, false, "Counts as both Wood and Iron"),
				make_club("Nimbus Hybrid 7", 105, 155, "iron", brand, false, "Counts as both Wood and Iron"),
				make_club("Nimbus All-Rounder", 105, 165, "iron", brand, false, "Wide band, no rider"),
				make_club("Nimbus Driver", 195, 250, "wood", brand, false, "Counts as both Wood and Iron"),
				make_club("Nimbus Utility Wedge", 30, 80, "wedge", brand, false, "Once per hole, playable from any lie with no penalty"),
				make_club("Nimbus Putter", 0, 0, "putter", brand, false, "No rider — pure flexible filler"),
			]
	return []


# Draws the top card, reshuffling the discard pile back in when the deck
# runs dry. Returns an empty Dictionary if both are exhausted — callers must
# check with is_empty() rather than assuming a card came back, since
# pop_back() on an empty Array returns null and would fail this signature.
func draw_from_deck(deck: Array, discard: Array) -> Dictionary:
	if deck.is_empty() and not discard.is_empty():
		log_msg("[i]Deck empty — reshuffling discard pile back in.[/i]")
		deck.append_array(discard)
		discard.clear()
		deck.shuffle()
	if deck.is_empty():
		return {}
	return deck.pop_back()


# ---------------------------------------------------------
# HOLE FLOW
# ---------------------------------------------------------
func start_hole() -> void:
	hole = HoleData.hole(current_hole_index)
	hole_yardage = hole.yardage
	hole_par = hole.par
	ball_pos = hole.tee_pos
	shot_path = [hole.tee_pos]
	strokes = 0
	current_lie = "tee"
	yips_pending = false
	log_entries.clear()
	rebuild_log()
	log_msg("[b]Hole %d — Par %d — %d yards[/b]" % [current_hole_index, hole_par, int(hole_yardage)])
	map_view.set_hole(hole)
	map_view.set_ball(ball_pos, shot_path)
	# Clears any aim line left over from the previous hole's last shot —
	# otherwise it points at wherever that old target was, which is
	# nonsensical geometry once the ball's moved to a brand new hole's tee.
	map_view.set_aim_target(ball_pos)
	state = State.CLUB_SELECT
	refresh_ui()


# Opens the click-to-aim step once a club is chosen: locks the crosshair's
# distance from the ball to that club's own yardage range (so you can't
# aim somewhere it can't reach) and defaults the target to the pin,
# clamped into that range — a player who doesn't bother re-aiming still
# gets a sane default. Moving the mouse over the map previews the crosshair
# live (see _on_aim_changed); a click commits immediately at that spot.
func begin_aim_for_shot() -> void:
	map_view.set_aiming(true, pending_club.min_yard, pending_club.max_yard, pending_club)
	map_view.set_aim_target(hole.pin_pos)
	aim_target = map_view.aim_target
	state = State.AIM
	refresh_ui()


# The crosshair moved (mouse hover, before any click) while still aiming —
# keep Main.gd's own aim_target in sync so the shot outlook panel (swing
# tier, yardage, and the bad-odds warning) always reflects where the
# crosshair is actually sitting, not just its last position. Only rebuilds
# the outlook panel, not the whole strip/header — this fires on every
# mouse-move event while aiming, so a full refresh_ui() would rebuild the
# header chips every frame for no reason.
func _on_aim_changed(target: Vector2) -> void:
	if state != State.AIM:
		return
	aim_target = target
	rebuild_shot_outlook()


# The player clicked to commit their aim — now draw the 3 Form cards for
# this swing.
func _on_aim_picked(target: Vector2) -> void:
	if state != State.AIM:
		return
	aim_target = target
	begin_form_draw()


# Which swing tier this declared shot represents: where the aim distance
# falls in the club's own yardage band (Section 4 "Club suitability").
func swing_tier_for_shot() -> int:
	var dist: float = ball_pos.distance_to(aim_target)
	var lo: float = pending_club.min_yard
	var hi: float = pending_club.max_yard
	if lo <= 0.0 and hi <= 0.0:
		return ShotResolver.Tier.MID
	if dist < lo:
		return upgrade_tier(ShotResolver.Tier.EXTREME_FINESSE)
	var span := hi - lo
	if span <= 0.0:
		return ShotResolver.Tier.MID
	# Ping-Well 2 widens the Mid band from the middle third to the middle
	# half, so more shots land on the comfortable 3-card draw.
	var mid_span: float = Brands.mid_tier_span(hand)
	var mid_lo: float = 0.5 - mid_span / 2.0
	var mid_hi: float = 0.5 + mid_span / 2.0

	var frac: float = (dist - lo) / span
	var tier: int = ShotResolver.Tier.MID
	if frac >= mid_hi:
		tier = ShotResolver.Tier.FULL
	elif frac < mid_lo:
		tier = ShotResolver.Tier.FINESSE
	return upgrade_tier(tier)


# Ping-Well 4 plays every club one tier better than its distance implies;
# Ping-Well 7 abolishes Extreme Finesse outright. Both are applied here so
# every caller (draw count, UI text, outlook panel) sees the same tier.
func upgrade_tier(tier: int) -> int:
	if tier == ShotResolver.Tier.EXTREME_FINESSE and Brands.abolishes_extreme_finesse(hand):
		return ShotResolver.Tier.FINESSE
	if Brands.tier_upgrade_steps(hand) <= 0:
		return tier
	# "One tier better" means toward MID, the most repeatable swing —
	# never past it, since MID is already the best draw in the game.
	match tier:
		ShotResolver.Tier.EXTREME_FINESSE:
			return ShotResolver.Tier.FINESSE
		ShotResolver.Tier.FINESSE, ShotResolver.Tier.FULL:
			return ShotResolver.Tier.MID
	return tier


func begin_form_draw() -> void:
	var tier := swing_tier_for_shot()
	# MacGregorian 4 plays you OUT of rough/bunker as though you were on the
	# fairway, which removes the bunker's forced-card treatment entirely.
	var force_extreme: bool = current_lie == "bunker" and not Brands.plays_as_fairway(hand)
	var result := form_deck.draw_for_shot(tier, force_extreme,
		Brands.bonus_draw_cards(hand), Brands.drops_worst_draw(hand))
	current_form_options = result.cards
	current_form_forced = result.forced

	if current_form_forced:
		var reason := "playing from the sand" if force_extreme and tier != ShotResolver.Tier.EXTREME_FINESSE else "below this club's range"
		log_msg("\n[b]Playing %s[/b] (%s) — %s creates a bad Form card. No choice, you're forced to play it." % [
			pending_club.name, ShotResolver.tier_name(tier), reason.capitalize()])
	else:
		log_msg("\n[b]Playing %s[/b] (%s) — drawing %d Form card%s." % [
			pending_club.name, ShotResolver.tier_name(tier), current_form_options.size(),
			"" if current_form_options.size() == 1 else "s"])
	state = State.FORM_DRAW
	refresh_ui()


# --- Draft phase: draw 3, pick 1, permanently into hand ---
func begin_draft_phase() -> void:
	state = State.DRAFT
	var owned_names := {}
	for c in hand:
		owned_names[c.name] = true

	current_draft_options = []
	for i in range(3):
		var card := draw_unowned_club(owned_names)
		if card.is_empty():
			# The shared club deck is genuinely exhausted (every card is
			# either in a bag or already offered this hole). Offer a shorter
			# draft rather than a phantom card.
			break
		current_draft_options.append(card)
		# Also exclude this hole's other options from the remaining draws,
		# so the 3 offers can't repeat a name amongst themselves either.
		owned_names[card.name] = true

	if current_draft_options.is_empty():
		# Nothing left to offer at all — skip the draft and move on, so the
		# round can still finish instead of stalling on an empty pick.
		log_msg("[i]The club deck is exhausted — no draft this hole.[/i]")
		finish_hole_done()
		return
	refresh_ui()


# Draws a club whose name isn't in owned_names, setting aside (not
# discarding) any duplicates it passes over along the way, then returns
# them to the deck once a match is found or the whole pool is exhausted —
# so a duplicate is never permanently lost and can't be re-drawn in a loop.
# Falls back to a duplicate only if every card in deck + discard shares a
# name with something already owned (impossible to avoid at that point).
func draw_unowned_club(owned_names: Dictionary) -> Dictionary:
	var set_aside: Array = []
	var pool_size: int = club_deck.size() + club_discard.size()
	var found: Dictionary = {}
	var found_unowned := false
	for i in range(max(pool_size, 1)):
		var card := draw_from_deck(club_deck, club_discard)
		if card.is_empty():
			# Deck and discard are both exhausted — everything left is held
			# in set_aside. Stop here and let the fallback below put those
			# cards back and draw a duplicate from them.
			break
		if not owned_names.has(card.name):
			found = card
			found_unowned = true
			break
		set_aside.append(card)

	# The set-aside cards always go back, on every path — they're the only
	# copy of those clubs, so dropping them would shrink the pool for good.
	club_deck.append_array(set_aside)

	if not found_unowned:
		# Exhausted the pool without finding an unowned club — every card
		# left shares a name with something already owned. Draw whatever's
		# next (a duplicate) rather than leave the draft short.
		found = draw_from_deck(club_deck, club_discard)

	return found


func on_draft_pick(index: int) -> void:
	var card: Dictionary = current_draft_options[index]
	for i in range(current_draft_options.size()):
		if i != index:
			club_discard.append(current_draft_options[i])

	if hand.size() >= HAND_CAP:
		pending_new_card = card
		log_msg("Hand is full (%d cards) — discard one to make room for [b]%s[/b]." % [HAND_CAP, card.name])
		state = State.DISCARD_FOR_DRAFT
	else:
		hand.append(card)
		log_msg("Added [b]%s[/b] to your hand." % card.name)
		finish_hole_done()
	refresh_ui()


# --- Discard flow (shared by draft-cap and hazard-cap cases) ---
func on_discard_pick(index: int) -> void:
	var removed = hand.pop_at(index)
	log_msg("Discarded %s." % removed.name)
	hand.append(pending_new_card)
	log_msg("Added [b]%s[/b] to your hand." % pending_new_card.name)
	pending_new_card = null

	if state == State.DISCARD_FOR_DRAFT:
		finish_hole_done()
	else:
		# was DISCARD_FOR_HAZARD -> shot already resolved, move on
		advance_after_shot()
	refresh_ui()


# --- Club select -> aim (crosshair, locked to the club's range) -> Form draw -> pick -> resolve ---
func on_club_select(hand_index: int) -> void:
	pending_club = hand[hand_index]
	begin_aim_for_shot()


# The player picked one of the 3 drawn Form cards. Its effect is now fully
# known (Section 4 step 3) — resolve immediately using the aim already
# confirmed before the draw. There is no further "final aim adjustment"
# input beyond that confirmed aim in this prototype pass; the confirmed
# aim *is* the aim the player commits to knowing the card's effect (they
# saw all 3 cards before choosing, so the choice among them already
# encodes their read).
func on_form_pick(index: int) -> void:
	var card: FormCard = current_form_options[index]
	form_deck.return_unpicked(current_form_options, index)
	current_form_options = []
	current_form_forced = false
	play_shot(pending_club, card)


func play_shot(club: Dictionary, card: FormCard) -> void:
	if card.is_yips:
		# Callowell 7 also stops a bad card tainting a putt.
		if Brands.blocks_yips(hand):
			log_msg("[color=#%s]Yips — shrugged off (Callowell).[/color]" % COLOR_TEXT_SOFT.to_html(false))
		else:
			log_msg("[color=#%s]Yips! Taints your next putt if you're forced to play it near the green.[/color]" % COLOR_FLAG.to_html(false))
			yips_pending = true

	var aimed_distance: float = ball_pos.distance_to(aim_target)
	var result := ShotResolver.resolve_shot(club, aimed_distance, current_lie, card,
		Brands.ignores_terrain_penalty(hand) or Brands.plays_as_fairway(hand),
		Brands.deviation_mult(hand, current_lie, card),
		Brands.severity_mult(hand))

	strokes += 1
	var before_pos := ball_pos

	log_msg("[b]Stroke %d[/b] — played %s with %s (lie: %s)" % [strokes, card.name, club.name, current_lie])
	log_msg("%s: %s" % [card.name, card.effect_text()])

	pending_club = {}
	_animating = true
	clear_container(options_container)

	var aim_dir: Vector2 = (aim_target - before_pos).normalized()
	if aim_dir.length_squared() < 0.0001:
		aim_dir = (hole.pin_pos - before_pos).normalized()
	if aim_dir.length_squared() < 0.0001:
		aim_dir = Vector2.UP

	map_view.play_aim_animation(aim_dir, result.distance, float(result.degree), result.side, club.max_yard, func():
		_resolve_shot_landing(before_pos, aim_dir, result)
	)


func _resolve_shot_landing(before_pos: Vector2, aim_dir: Vector2, result: Dictionary) -> void:
	_animating = false

	# Vector2.rotated() turns clockwise for +angle in Godot's Y-down convention,
	# so Draw (curves left) needs a positive angle here to end up on -x.
	var sign: float = 0.0
	if result.side == ShotResolver.Side.DRAW:
		sign = 1.0
	elif result.side == ShotResolver.Side.FADE:
		sign = -1.0
	var angle_rad: float = deg_to_rad(float(result.degree)) * sign
	var shot_dir := aim_dir.rotated(angle_rad)
	var landing_pos: Vector2 = before_pos + shot_dir * result.distance

	var lie_result := hole.terrain_at(landing_pos)
	log_msg("Distance: %d yards -> landed in %s, %d yards from the pin." % [
		int(result.distance), lie_result, int(landing_pos.distance_to(hole.pin_pos))])

	var hazard_hit := false
	if lie_result == "water":
		strokes += 1
		ball_pos = before_pos
		current_lie = "rough" if hole.terrain_at(before_pos) != "fairway" else "fairway"
		log_msg("[color=#%s]Splash! Water hazard — +1 penalty stroke, dropped back near your previous position.[/color]" % COLOR_WATER.to_html(false))
		hazard_hit = true
	elif lie_result == "bunker":
		ball_pos = landing_pos
		current_lie = "bunker"
		log_msg("[color=#%s]In the sand.[/color]" % COLOR_SAND.to_html(false))
		hazard_hit = true
	elif lie_result == "rough":
		ball_pos = landing_pos
		current_lie = "rough"
	elif lie_result == "green":
		ball_pos = landing_pos
		current_lie = "green"
	else:
		ball_pos = landing_pos
		current_lie = "fairway"

	# Callowell 7: bad cards can no longer downgrade your lie.
	if result.downgrades_lie and current_lie != "green" and not Brands.blocks_lie_downgrade(hand):
		current_lie = ShotResolver.lie_downgrade(current_lie)
		log_msg("[color=#%s]Shank — lie downgraded to %s.[/color]" % [COLOR_FLAG.to_html(false), current_lie])
		hazard_hit = true

	shot_path.append(ball_pos)
	map_view.set_ball(ball_pos, shot_path)
	# Clears the just-played aim line — otherwise the old target (now stale,
	# from wherever the previous shot was aimed) keeps drawing next to the
	# ball's new position until the player starts aiming again.
	map_view.set_aim_target(ball_pos)

	if hazard_hit:
		maybe_add_bad_card_to_form_deck(lie_result)

	advance_after_shot()


# Section 5 "Bad cards from hazards": landing in rough/bunker/water carries
# a chance of adding a bad Form card into the shared Form deck (not the
# Bag) — degrading future draws for the rest of the round.
func maybe_add_bad_card_to_form_deck(lie_result: String) -> void:
	# MacGregorian 2: hazards stop feeding bad cards into the Form deck, so
	# a rough patch no longer compounds for the rest of the round.
	if Brands.blocks_form_decay(hand):
		return
	if randf() < (1.0 / 3.0):
		var card := form_deck.add_bad_card_to_deck()
		log_msg("[color=#%s](The %s left a %s card in your Form deck.)[/color]" % [
			COLOR_TEXT_SOFT.to_html(false), lie_result, card.name])


func advance_after_shot() -> void:
	if current_lie == "green":
		start_putting()
	else:
		state = State.CLUB_SELECT
	refresh_ui()


# --- Putting phase (Section 7) ---
# A timing check rather than a card draw: a marker sweeps the putt meter and
# the player stops it. Distance to the pin sets both how wide the sunk band
# is and how fast the marker travels, so a tap-in is nearly automatic and a
# long lag putt is a genuine nerve test.
func start_putting() -> void:
	state = State.PUTTING
	putt_dist = ball_pos.distance_to(hole.pin_pos)
	_putt_dir = (ball_pos - hole.pin_pos).normalized()
	if _putt_dir == Vector2.ZERO:
		_putt_dir = Vector2(0, 1)
	log_msg("\n[b]On the green.[/b] %s to the pin — stop the marker in the green band to hole it." % putt_distance_text())
	refresh_ui()


func putt_distance_text() -> String:
	# Under a few yards it reads more naturally in feet, the way a golfer
	# would actually call a short putt.
	if putt_dist < 4.0:
		return "%d ft" % maxi(1, int(round(putt_dist * 3.0)))
	return "%d yds" % int(round(putt_dist))


func on_putt_stopped(result: String, accuracy: float) -> void:
	strokes += 1

	if yips_pending:
		yips_pending = false
		log_msg("[color=#%s]The Yips strike — the putt misses regardless of how well you struck it.[/color]" % COLOR_FLAG.to_html(false))
		putt_dist = maxf(1.0, putt_dist * 0.35)
		sync_ball_to_putt(randf_range(-0.8, 0.8))
		state = State.PUTTING
		refresh_ui()
		return

	match result:
		"sunk":
			log_msg("[color=#%s]Dead centre — in the hole![/color]" % COLOR_ACCENT.to_html(false))
			putt_dist = 0.0
			sync_ball_to_putt()
			finish_hole()
			return
		"close":
			# A good-but-not-perfect strike leaves a short one. The better
			# the timing, the closer it finishes.
			putt_dist = minf(lerpf(2.2, 0.6, accuracy), maxf(putt_dist * 0.5, GIMME_YARDS))
			sync_ball_to_putt(randf_range(-0.5, 0.5))
			log_msg("Good pace — slides by, leaving %s." % putt_distance_text())
		_:
			# A miss scales with how wild the timing was, and with how long
			# the putt was to begin with: badly struck lag putts can race
			# well past, short ones only ever dribble off line. Each miss is
			# still capped at the distance it came from, so a putt can never
			# get longer — the sequence always walks toward the hole.
			var leave: float = lerpf(0.25, 0.06, accuracy) * maxf(putt_dist, 3.0)
			putt_dist = clampf(leave, GIMME_YARDS, minf(putt_dist, 12.0))
			sync_ball_to_putt(randf_range(-1.2, 1.2))
			log_msg("[color=#%s]Mishit — pushed off line, %s left.[/color]" % [
				COLOR_FLAG.to_html(false), putt_distance_text()])

	# The gimme: once you're inside tap-in range there's no drama left to
	# play for, so it's conceded rather than asking for another timing check
	# the player cannot meaningfully fail. Also guarantees the putting loop
	# terminates instead of grinding on a very short putt forever.
	if putt_dist <= GIMME_YARDS:
		strokes += 1
		putt_dist = 0.0
		sync_ball_to_putt()
		log_msg("[color=#%s]Tap-in conceded.[/color]" % COLOR_TEXT_SOFT.to_html(false))
		finish_hole()
		return

	state = State.PUTTING
	refresh_ui()


# Moves the ball on the map to match the current putt distance. Each miss
# leaves it a little offline rather than perfectly pin-high, so the trail
# reads like a real putt that slid past instead of a number shrinking.
func sync_ball_to_putt(offline: float = 0.0) -> void:
	var dir := _putt_dir.rotated(offline)
	ball_pos = hole.pin_pos + dir * putt_dist
	shot_path.append(ball_pos)
	if map_view:
		map_view.set_ball(ball_pos, shot_path)
		map_view.set_aim_target(ball_pos)


# Builds the putt meter plus its strike button into the options row, and
# starts the marker sweeping for the current distance. Called on every
# refresh while putting, since refresh_ui() clears the container.
func build_putt_controls() -> void:
	# The options row lives in a ScrollContainer that sizes children to their
	# minimum, so the meter needs an explicit width — it has to be wide to be
	# readable, since on a long putt the sunk band is only a few percent of it.
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(METER_WIDTH, 0)
	col.add_theme_constant_override("separation", 8)

	putt_meter = PuttMeter.new()
	putt_meter.custom_minimum_size = Vector2(METER_WIDTH, 0)
	putt_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	putt_meter.stopped.connect(on_putt_stopped)
	col.add_child(putt_meter)

	var strike_btn := Button.new()
	strike_btn.text = "Strike  (Space)"
	strike_btn.custom_minimum_size = Vector2(0, 42)
	strike_btn.pressed.connect(_on_strike_pressed)
	col.add_child(strike_btn)

	options_container.add_child(col)
	putt_meter.begin(putt_dist)


func _on_strike_pressed() -> void:
	if putt_meter and putt_meter.active:
		putt_meter.stop_putt()


# Space bar is the natural input for a timing check — the button stays for
# mouse players, but nobody should have to chase a cursor to hit a beat.
func _unhandled_key_input(event: InputEvent) -> void:
	if state != State.PUTTING:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_SPACE:
		_on_strike_pressed()
		get_viewport().set_input_as_handled()


func score_diff_text(diff: int) -> String:
	if diff < 0:
		return "%d under par" % -diff
	elif diff > 0:
		return "%d over par" % diff
	return "Even par"


func score_name(diff: int) -> String:
	match diff:
		-2: return "Eagle"
		-1: return "Birdie"
		0: return "Par"
		1: return "Bogey"
		2: return "Double Bogey"
	if diff <= -3:
		return "%d Under" % -diff
	return "Triple Bogey+" if diff == 3 else "%d Over" % diff


func finish_hole() -> void:
	var diff := strokes - hole_par
	log_msg("\n[b]Holed out![/b] Total strokes: %d (par %d) — %s" % [strokes, hole_par, score_diff_text(diff)])
	round_scores.append({"hole": current_hole_index, "par": hole_par, "strokes": strokes})
	log_msg("\n[b]End of hole.[/b] Draw 3, pick 1 to add to your hand permanently.")
	begin_draft_phase()


# Called once the end-of-hole draft pick has been resolved (with or without
# a forced discard) — the hole is now fully over. Either advances to the
# next hole, or — after hole 18 — ends the round and shows the scorecard.
func finish_hole_done() -> void:
	if current_hole_index >= HoleData.HOLE_COUNT:
		finish_round()
	else:
		current_hole_index += 1
		start_hole()


func finish_round() -> void:
	state = State.DONE
	log_entries.clear()
	rebuild_log()
	log_msg("[b]Round Complete — Boogie Links[/b]\n")
	var total_strokes := 0
	var total_par := 0
	for entry in round_scores:
		total_strokes += entry.strokes
		total_par += entry.par
		log_msg("Hole %2d — Par %d — %d strokes — %s" % [entry.hole, entry.par, entry.strokes, score_name(entry.strokes - entry.par)])
	var diff := total_strokes - total_par
	log_msg("\n[b]Total: %d (%s)[/b]" % [total_strokes, score_diff_text(diff)])
	refresh_ui()


func _on_restart_pressed() -> void:
	current_hole_index = 1
	round_scores = []
	init_game()
	start_hole()


# ---------------------------------------------------------
# UI REFRESH
# ---------------------------------------------------------
var _animating: bool = false  # blocks refresh_ui() from clobbering an in-flight pick animation


func running_score_diff() -> int:
	var total_strokes := 0
	var total_par := 0
	for entry in round_scores:
		total_strokes += entry.strokes
		total_par += entry.par
	return total_strokes - total_par


func running_score_diff_text(diff: int) -> String:
	if diff == 0:
		return "E"
	return ("+%d" % diff) if diff > 0 else ("%d" % diff)


# Brands in the Bag that haven't reached a tier yet, or have reached one
# and are climbing toward the next — "CALLOWELL 3/4". Only brands the
# player actually holds appear, so the row stays short.
func brand_progress_chips() -> Array:
	var out: Array = []
	var counts := Brands.counts(hand)
	for brand in counts:
		if brand == Brands.STARTER:
			continue  # Bogey-Mart has no set bonus — nothing to progress toward
		var n: int = int(counts[brand])
		var next: int = Brands.next_tier(n)
		if next == 0:
			continue  # top tier reached; the active-bonus chip says it all
		out.append("%s %d/%d" % [Brands.display_name(brand).to_upper(), n, next])
	out.sort()
	return out


func refresh_ui() -> void:
	var dist_to_pin: float = ball_pos.distance_to(hole.pin_pos) if hole else 0.0
	# On the green a putt is better read in feet, matching the putt meter's
	# own label — "1 yards to pin" reads wrong for a tap-in.
	var dist_text: String = ("%d ft to pin" % maxi(1, int(round(dist_to_pin * 3.0)))) \
		if (current_lie == "green" and dist_to_pin < 4.0) \
		else ("%d yards to pin" % int(dist_to_pin))
	status_label.text = "%s · lie: %s · %d strokes" % [
		dist_text, current_lie, strokes]

	if scorecard:
		scorecard.set_round(round_scores, current_hole_index, strokes)
	if hole_title and hole:
		hole_title.text = "Hole %d — Par %d — %d yards" % [current_hole_index, hole_par, int(hole_yardage)]
	if map_caption and hole:
		map_caption.text = "%d yards · par %d" % [int(hole_yardage), hole_par]

	if header_meta:
		clear_container(header_meta)
		# Section 3B: the run's live brands, shown from the start — the
		# player plans around a known pool rather than guessing at it.
		for b in live_brands:
			header_meta.add_child(BoogieUI.chip(Brands.display_name(b).to_upper(), BoogieTheme.ACCENT_700))
		header_meta.add_child(BoogieUI.meta_stat(
			"Thru %d" % round_scores.size(),
			running_score_diff_text(running_score_diff()),
			BoogieTheme.OLIVE_200, BoogieTheme.OLIVE_900))
		header_meta.add_child(BoogieUI.meta_stat(
			"Bag", "%d/%d" % [hand.size(), HAND_CAP],
			BoogieTheme.NEUTRAL_200, BoogieTheme.NEUTRAL_800))
		# Section 3A: the live set-bonus counter. Active bonuses read as
		# "TITANIST 4" in the accent colour; brands still short of their
		# next tier show progress ("CALLOWELL 3/4") so the player can always
		# see how close a set is.
		for bonus in Brands.active_bonuses(hand):
			header_meta.add_child(BoogieUI.chip("%s %d" % [
				bonus.name.to_upper(), bonus.tier], BoogieTheme.ACCENT_700))
		for progress in brand_progress_chips():
			header_meta.add_child(BoogieUI.chip(progress, BoogieTheme.NEUTRAL_600))
		if form_deck:
			header_meta.add_child(make_form_deck_chip_button())

	if _animating:
		return

	rebuild_shot_outlook()
	clear_container(options_container)
	clear_container(form_container)

	# The step pill: which numbered beat of the shot flow you're on, and
	# the one instruction that goes with it.
	var step_num := "1"
	var step_hint := ""

	match state:
		State.AIM:
			step_num = "2"
			step_hint = "Move over the hole and click to commit your aim"
			hand_label.text = "AIMING WITH %s" % pending_club.name.to_upper()
			options_label.text = "Locked to %d-%d yds — tap another club to switch." % [
				int(pending_club.min_yard), int(pending_club.max_yard)]
			rebuild_bag_row()
			build_form_placeholders("Drawn the moment you commit your aim")

		State.FORM_DRAW:
			step_num = "3"
			if current_form_forced:
				step_hint = "No choice — play the card the club created"
				form_label.text = "FORCED"
				form_hint.text = "This card was created for you. Tap it to play."
			else:
				step_hint = "Read all %d, then keep one" % current_form_options.size()
				form_label.text = "DRAW %d, PICK 1" % current_form_options.size()
				form_hint.text = "Read each card's known effect, then pick one to play."
			hand_label.text = "YOUR BAG %d/%d" % [hand.size(), HAND_CAP]
			options_label.text = "Locked in: %s." % pending_club.name
			rebuild_bag_row()
			for i in range(current_form_options.size()):
				var fv := make_form_card_view(current_form_options[i])
				fv.picked.connect(_make_form_pick_callback(i))
				form_container.add_child(fv)

		State.DRAFT:
			step_num = "·"
			step_hint = "End of hole — add one club to your bag"
			# Normally 3, but a nearly-exhausted club deck can offer fewer.
			hand_label.text = "DRAW %d, PICK 1" % current_draft_options.size()
			options_label.text = "Add one to your bag, permanently."
			for i in range(current_draft_options.size()):
				var cv := make_card_view(current_draft_options[i])
				cv.picked.connect(_make_draft_pick_callback(i))
				options_container.add_child(cv)
			build_form_placeholders("No Form draw between holes")

		State.DISCARD_FOR_DRAFT, State.DISCARD_FOR_HAZARD:
			step_num = "·"
			step_hint = "Bag is full — something has to go"
			hand_label.text = "BAG FULL (%d)" % HAND_CAP
			options_label.text = "Tap a card to drop it for %s." % pending_new_card.name
			for i in range(hand.size()):
				var cv := make_card_view(hand[i])
				cv.picked.connect(_make_discard_callback(i))
				options_container.add_child(cv)
			build_form_placeholders("No Form draw while you're cutting the bag")

		State.CLUB_SELECT:
			step_num = "1"
			step_hint = "Pick a club from your bag"
			hand_label.text = "YOUR BAG %d/%d" % [hand.size(), HAND_CAP]
			options_label.text = "Tap a club, then aim on the hole."
			if current_lie == "bunker":
				options_label.text += "  (bunker — irons/wedges only)"
			rebuild_bag_row()
			build_form_placeholders("Drawn fresh for every single shot")

		State.PUTTING:
			step_num = "·"
			step_hint = "On the green — stop the marker in the band"
			hand_label.text = "PUTTING — %s" % putt_distance_text().to_upper()
			options_label.text = "The further out you are, the tighter the band gets."
			build_putt_controls()
			build_form_placeholders("No Form draw on the green — putting is a timing check")

		State.DONE:
			var total_strokes := 0
			var total_par := 0
			for entry in round_scores:
				total_strokes += entry.strokes
				total_par += entry.par
			var diff := total_strokes - total_par
			step_num = "·"
			step_hint = "Round complete"
			hand_label.text = "ROUND COMPLETE"
			options_label.text = "%d strokes (%s)." % [total_strokes, score_diff_text(diff)]
			var restart_btn := Button.new()
			restart_btn.text = "Restart Round"
			restart_btn.custom_minimum_size = Vector2(180, 60)
			restart_btn.pressed.connect(_on_restart_pressed)
			options_container.add_child(restart_btn)
			build_form_placeholders("")

	if step_holder:
		clear_container(step_holder)
		if step_hint != "":
			step_holder.add_child(BoogieUI.step_pill(step_num, step_hint))


# Face-down Form slots. The Form half of the strip is always present, so
# outside a draw it shows how many cards the current swing would earn
# rather than collapsing to nothing — the count itself is information.
func build_form_placeholders(note: String) -> void:
	form_label.text = "FORM HAND"
	form_hint.text = note

	var count := 3
	if state == State.AIM and not pending_club.is_empty():
		var tier := swing_tier_for_shot()
		if current_lie == "bunker" or tier == ShotResolver.Tier.EXTREME_FINESSE:
			count = 1
		else:
			count = FormDeck.TIER_DRAW_COUNT.get(tier, 3)
		form_hint.text = "This swing draws %d" % count
	elif state != State.CLUB_SELECT:
		count = 0

	for i in count:
		form_container.add_child(make_form_placeholder())


# A dashed, muted card the same size as a real Form card, so the row
# doesn't jump when the draw lands.
func make_form_placeholder() -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = BoogieTheme.NEUTRAL_200
	s.set_corner_radius_all(12)
	s.border_color = BoogieTheme.NEUTRAL_400
	s.set_border_width_all(2)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	var p := BoogieUI.make_panel(s)
	p.custom_minimum_size = Vector2(180, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	col.add_child(BoogieUI.tag("Awaiting draw", BoogieTheme.NEUTRAL_300, BoogieTheme.NEUTRAL_700))
	col.add_child(BoogieUI.body("Face down", 17, BoogieTheme.NEUTRAL_600))
	return p


func make_card_view(card: Dictionary, interactive: bool = true, compact: bool = false) -> CardView:
	var cv := CardView.new()
	cv.setup(card, interactive, compact)
	return cv


func make_form_card_view(card: FormCard, interactive: bool = true) -> FormCardView:
	var fv := FormCardView.new()
	fv.setup(card, interactive)
	return fv


# A clickable pill matching BoogieUI.chip()'s look, opening the Form deck
# contents popup — BoogieUI.chip() itself is a plain, non-interactive
# PanelContainer, so this builds an equivalent Button instead.
func make_form_deck_chip_button() -> Button:
	var b := Button.new()
	b.text = "FORM DECK %d/%d" % [form_deck.deck.size(), form_deck.discard.size()]
	b.flat = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(99)
	style.border_color = COLOR_SAND
	style.set_border_width_all(1)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	b.add_theme_stylebox_override("pressed", style)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", COLOR_SAND)
	b.add_theme_color_override("font_hover_color", COLOR_SAND)
	b.pressed.connect(_on_form_deck_chip_pressed)
	return b


# Shot outlook, shown in the log column while a club is chosen (AIM and
# FORM_DRAW): the club, its yardage band, and the swing tier this aim
# implies — visible the moment you're deciding, not just once cards
# are drawn.
# The shot panel. Where the old outlook only appeared while aiming, this
# is always on: distance to the pin, your lie, strokes played, and what
# the lie is doing to you. When a club is in hand it also shows the swing
# tier and its draw consequence, which is the read the game turns on.
func rebuild_shot_outlook() -> void:
	clear_container(shot_outlook)
	shot_outlook.visible = true

	shot_outlook.add_child(BoogieUI.kicker("This shot", BoogieTheme.ACCENT_700))

	var dist_to_pin: float = ball_pos.distance_to(hole.pin_pos) if hole else 0.0
	var on_green := current_lie == "green"
	var big := BoogieUI.big_stat(
		str(maxi(1, int(round(dist_to_pin * 3.0)))) if (on_green and dist_to_pin < 4.0) else str(int(round(dist_to_pin))),
		"ft to pin" if (on_green and dist_to_pin < 4.0) else "yds to pin")
	shot_outlook.add_child(big[0])

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	shot_outlook.add_child(stats)
	stats.add_child(BoogieUI.stat_block("Lie", current_lie.capitalize()))
	stats.add_child(BoogieUI.stat_block("Strokes", str(strokes)))
	stats.add_child(BoogieUI.stat_block("Par", str(hole_par) if hole else "—"))

	# What this lie costs you — Section 5's terrain modifiers, said plainly
	# rather than left for the player to remember.
	var lie_note := ""
	match current_lie:
		"tee":
			lie_note = "Tee — full aimed distance, every club playable."
		"fairway":
			lie_note = "Fairway — full aimed distance, every club playable, no draw penalty."
		"rough":
			lie_note = "Rough — whatever distance you aim for flies at 80%. A Flop Shot ignores it entirely."
		"bunker":
			lie_note = "Bunker — 50% distance, woods unplayable, and the club forces one fresh bad Form card on you."
		"green":
			lie_note = "On the green — putting switches to the timing meter, and the sunk band narrows with distance."
	if lie_note != "":
		var risky := current_lie == "rough" or current_lie == "bunker"
		shot_outlook.add_child(BoogieUI.note_box(
			lie_note,
			BoogieTheme.ACCENT_100 if risky else BoogieTheme.OLIVE_100,
			BoogieTheme.ACCENT_300 if risky else BoogieTheme.OLIVE_300,
			BoogieTheme.ACCENT_900 if risky else BoogieTheme.OLIVE_900))

	# Club-specific read, only once a club is actually in hand.
	if (state == State.AIM or state == State.FORM_DRAW) and not pending_club.is_empty():
		shot_outlook.add_child(BoogieUI.hairline(0.14))

		var club_row := VBoxContainer.new()
		club_row.add_theme_constant_override("separation", 2)
		shot_outlook.add_child(club_row)
		club_row.add_child(BoogieUI.kicker("Club in hand", BoogieTheme.NEUTRAL_600))
		club_row.add_child(BoogieUI.body("%s — %d-%d yds" % [
			pending_club.name, int(pending_club.min_yard), int(pending_club.max_yard)],
			15, BoogieTheme.INK))

		var tier := swing_tier_for_shot()
		var aim_dist: float = ball_pos.distance_to(aim_target)
		club_row.add_child(BoogieUI.body("%s — aiming %d yds" % [
			ShotResolver.tier_name(tier), int(round(aim_dist))], 13, BoogieTheme.NEUTRAL_700))

		var tier_hint := ""
		var tier_is_risky := false
		match tier:
			ShotResolver.Tier.FULL:
				tier_hint = "⚠ Swinging all-out — draws only 2 Form cards, less room to dodge a bad one."
				tier_is_risky = true
			ShotResolver.Tier.MID:
				tier_hint = "Comfortable, repeatable swing — draws 3 Form cards, best choice."
			ShotResolver.Tier.FINESSE:
				tier_hint = "⚠ Delicate touch — draws only 2 Form cards, less room to dodge a bad one."
				tier_is_risky = true
			ShotResolver.Tier.EXTREME_FINESSE:
				tier_hint = "⚠ Below this club's range — no draw at all, a bad Form card is created and you must play it."
				tier_is_risky = true
		shot_outlook.add_child(BoogieUI.body(
			tier_hint, 12, BoogieTheme.ACCENT_700 if tier_is_risky else BoogieTheme.NEUTRAL_600))

		if current_lie == "bunker" and tier != ShotResolver.Tier.EXTREME_FINESSE:
			shot_outlook.add_child(BoogieUI.body(
				"⚠ Playing from the sand — forces the same treatment as Extreme Finesse: no draw, a bad Form card is created and you must play it.",
				12, BoogieTheme.ACCENT_700))


# Builds the bag row for CLUB_SELECT: every card in hand, in hand order.
func rebuild_bag_row() -> void:
	var playable := {}
	for i in range(hand.size()):
		var c = hand[i]
		if c.type == "putter":
			continue
		if current_lie == "bunker" and c.type == "wood":
			continue
		playable[i] = true

	for i in range(hand.size()):
		var card = hand[i]
		var cv := make_card_view(card, state == State.CLUB_SELECT and playable.has(i), true)
		if cv.interactive:
			cv.picked.connect(_make_club_callback(i))
		options_container.add_child(cv)


# --- Draft pick: pop, then fade the whole offer row out before actually
# mutating game state, so the pick still reads as a deliberate action. ---
func _on_draft_card_picked(cv: CardView, index: int) -> void:
	_animating = true
	for other in options_container.get_children():
		other.play_fade_out()

	get_tree().create_timer(0.25).timeout.connect(func():
		_animating = false
		on_draft_pick(index)
	)


# --- Form pick: same pop-then-fade treatment as a draft pick. ---
func _on_form_card_picked(fv: FormCardView, index: int) -> void:
	_animating = true
	for other in options_container.get_children():
		other.play_fade_out()

	get_tree().create_timer(0.25).timeout.connect(func():
		_animating = false
		on_form_pick(index)
	)


# --- Callback factories (needed so each card view captures the right index) ---
func _make_draft_pick_callback(i: int) -> Callable:
	return func(cv): _on_draft_card_picked(cv, i)


func _make_form_pick_callback(i: int) -> Callable:
	return func(fv): _on_form_card_picked(fv, i)


func _make_discard_callback(i: int) -> Callable:
	return func(_cv): on_discard_pick(i)


func _make_club_callback(hand_index: int) -> Callable:
	return func(_cv): on_club_select(hand_index)
