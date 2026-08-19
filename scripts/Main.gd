extends Control

# ---------------------------------------------------------
# BOOGIE PROTOTYPE
# Single hole, single player. Tests the core loop:
#   draw 3 / pick 1 (permanent growing hand, 14-card cap)
#   -> choose a club -> roll Power + Accuracy dice
#   -> resolve lie/hazard -> repeat until on the green
#   -> Green Deck push-your-luck putting
# ---------------------------------------------------------

enum State { DRAFT, DISCARD_FOR_DRAFT, CLUB_SELECT, TIER_SELECT, DISCARD_FOR_HAZARD, PUTTING, DONE }

const HAND_CAP := 14

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

var green_deck: Array = []
var green_discard: Array = []

var current_hole_index: int = 1
var round_scores: Array = []  # [{"hole": int, "par": int, "strokes": int}, ...]

# Flight conditions (Section 10's weather/slope draw, once per 6-hole
# flight). Fixed for the whole round for now — always clear skies, a
# steady breeze — but kept as state, not constants, so a future flight
# draw can reroll them without touching anything that reads them.
var weather: String = "Sunny"
var wind_mph: int = 6
var wind_dir: String = "Onshore"

var hole: HoleData
var hole_yardage: float = 380.0
var hole_par: int = 4
var ball_pos: Vector2 = Vector2.ZERO  # yard-space, (0,0) at tee, +y toward pin
var shot_path: Array = []  # history of ball_pos points this hole, for drawing the trail
var strokes: int = 0
var current_lie: String = "tee"

var putting_target: int = 0
var putting_progress: int = 0

var pending_new_card = null
var current_draft_options: Array = []
var pending_club: Dictionary = {}
var pending_club_index: int = -1

# --- UI node refs (built in code) ---
var status_label: Label
var map_view: CourseMapView
var log_box: RichTextLabel
var hand_label: Label
var options_label: Label
var options_container: HBoxContainer
var dice_panel: PanelContainer
var power_die: DiceView
var accuracy_die: DiceView
var dice_result_label: Label
var scorecard: ScorecardView
var header_meta: HBoxContainer      # weather/wind/round/bag chip row, right of the title
var hole_title: Label


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

	# --- Header: title, hole line, condition chips -------------------------
	var header := BoogieUI.make_panel(BoogieUI.ruled_panel(false, false, false, true, 16))
	header.custom_minimum_size = Vector2(0, 76)
	root.add_child(header)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 18)
	header_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	header.add_child(header_row)

	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 2)
	title_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(title_col)
	title_col.add_child(BoogieUI.kicker("Boogie Links"))
	var title := BoogieUI.heading("Hole 1 — Par 4", 26)
	hole_title = title
	title_col.add_child(title)

	status_label = Label.new()
	status_label.text = "Loading..."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	header_row.add_child(status_label)

	header_meta = HBoxContainer.new()
	header_meta.add_theme_constant_override("separation", 8)
	header_meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(header_meta)

	# --- Middle: card column | plate | log column --------------------------
	var mid_row := HBoxContainer.new()
	mid_row.add_theme_constant_override("separation", 0)
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid_row)

	var card_panel := BoogieUI.make_panel(BoogieUI.ruled_panel(false, true, false, false, 12))
	card_panel.custom_minimum_size = Vector2(288, 0)
	mid_row.add_child(card_panel)

	scorecard = ScorecardView.new()
	card_panel.add_child(scorecard)

	var plate_panel := BoogieUI.make_panel(BoogieUI.ruled_panel(false, true, false, false, 14))
	plate_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_row.add_child(plate_panel)

	var plate_col := VBoxContainer.new()
	plate_col.add_theme_constant_override("separation", 8)
	plate_panel.add_child(plate_col)
	plate_col.add_child(BoogieUI.kicker("The hole"))

	map_view = CourseMapView.new()
	# Holes run tall and narrow (roughly 120-200 yds wide, 400-600 yds
	# long), so the mat is capped to a sensible width and centered rather
	# than stretched to fill the column — matted like a course-guide
	# illustration, not a wide empty frame around a thin strip.
	var hole_plate := BoogieUI.plate(map_view)
	hole_plate.custom_minimum_size = Vector2(420, 0)
	hole_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate_col.add_child(hole_plate)

	var log_panel := BoogieUI.make_panel(BoogieUI.ruled_panel(false, false, false, false, 12))
	log_panel.custom_minimum_size = Vector2(326, 0)
	mid_row.add_child(log_panel)

	var log_col := VBoxContainer.new()
	log_col.add_theme_constant_override("separation", 7)
	log_panel.add_child(log_col)
	log_col.add_child(BoogieUI.kicker("Play-by-play"))

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.fit_content = false
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.add_theme_color_override("default_color", COLOR_TEXT)
	log_col.add_child(log_box)

	# Dice sit over the plate rather than in a panel that appears and
	# vanishes from the layout — the sheet never reflows mid-shot.
	dice_panel = PanelContainer.new()
	dice_panel.visible = false
	dice_panel.add_theme_stylebox_override("panel", BoogieUI.panel(COLOR_PANEL, 10))
	dice_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	dice_panel.offset_left = -95
	dice_panel.offset_right = 95
	dice_panel.offset_top = 24
	dice_panel.offset_bottom = 160
	map_view.add_child(dice_panel)

	var dice_vbox := VBoxContainer.new()
	dice_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_vbox.add_theme_constant_override("separation", 6)
	dice_panel.add_child(dice_vbox)

	var dice_row := HBoxContainer.new()
	dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_row.add_theme_constant_override("separation", 10)
	dice_vbox.add_child(dice_row)

	power_die = DiceView.new()
	power_die.accent = Palette.FAIRWAY_DEEP
	power_die.set_caption("Power")
	dice_row.add_child(power_die)

	accuracy_die = DiceView.new()
	accuracy_die.accent = Palette.WATER_DEEP
	accuracy_die.set_caption("Accuracy")
	dice_row.add_child(accuracy_die)

	dice_result_label = Label.new()
	dice_result_label.text = ""
	dice_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	dice_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_result_label.add_theme_font_size_override("font_size", 12)
	dice_result_label.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	dice_vbox.add_child(dice_result_label)

	# --- Bag strip: one row, whatever decision is in front of you right now —
	# a label column on the left, a horizontally-scrolling row of cards or
	# buttons on the right. Same shape whether that's your bag with a club
	# expanding into its swing tiers, a discard pick, a draft offer, or the
	# putting green's draw/bank pair.
	var strip := BoogieUI.make_panel(BoogieUI.ruled_panel(false, false, true, false, 12))
	strip.custom_minimum_size = Vector2(0, 174)
	root.add_child(strip)

	var strip_row := HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 14)
	strip.add_child(strip_row)

	var strip_label_col := VBoxContainer.new()
	strip_label_col.custom_minimum_size = Vector2(160, 0)
	strip_label_col.add_theme_constant_override("separation", 5)
	strip_row.add_child(strip_label_col)

	hand_label = BoogieUI.kicker("Your bag")
	strip_label_col.add_child(hand_label)

	options_label = BoogieUI.body("", 12, COLOR_TEXT_SOFT)
	strip_label_col.add_child(options_label)

	var options_scroll := ScrollContainer.new()
	options_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_row.add_child(options_scroll)

	options_container = HBoxContainer.new()
	options_container.add_theme_constant_override("separation", 9)
	options_scroll.add_child(options_container)


func log_msg(text: String) -> void:
	log_box.append_text(text + "\n")


func clear_container(c: Container) -> void:
	for child in c.get_children():
		child.queue_free()


# ---------------------------------------------------------
# CARD HELPERS
# ---------------------------------------------------------
func make_club(cname: String, min_y: float, max_y: float, acc_die: int, ctype: String, limited: bool = false, ability: String = "") -> Dictionary:
	return {
		"name": cname,
		"min_yard": min_y,
		"max_yard": max_y,
		"acc_die": acc_die,
		"type": ctype,          # "wood" / "iron" / "wedge" / "putter" / "bad"
		"limited": limited,
		"ability": ability
	}


# ---------------------------------------------------------
# SETUP
# ---------------------------------------------------------
func init_game() -> void:
	hand = [
		make_club("Driver", 200, 260, 8, "wood"),
		make_club("7-Iron", 100, 150, 6, "iron"),
		make_club("Putter", 0, 0, 0, "putter")
	]

	club_deck = build_club_pool()
	club_deck.shuffle()
	club_discard = []

	green_deck = build_green_deck()
	green_deck.shuffle()
	green_discard = []


func build_club_pool() -> Array:
	var pool: Array = []
	# Standard clubs, a few copies each so the deck has some depth
	for i in range(3):
		pool.append(make_club("Driver", 200, 260, 8, "wood"))
		pool.append(make_club("3-Wood", 180, 220, 8, "wood"))
		pool.append(make_club("5-Iron", 140, 180, 6, "iron"))
		pool.append(make_club("7-Iron", 100, 150, 6, "iron"))
		pool.append(make_club("9-Iron", 80, 110, 6, "iron"))
		pool.append(make_club("Pitching Wedge", 50, 90, 4, "wedge"))
		pool.append(make_club("Sand Wedge", 20, 60, 4, "wedge"))

	# Limited editions — same club families, better stats or an ability
	pool.append(make_club("Tour Driver X", 210, 270, 10, "wood", true, "Ignore rough penalty once"))
	pool.append(make_club("Precision Wedge", 30, 70, 6, "wedge", true, "Reroll accuracy die once"))
	pool.append(make_club("Gold 5-Iron", 145, 185, 8, "iron", true, "+10 yards in dry weather"))

	return pool


func build_green_deck() -> Array:
	var deck: Array = []
	for v in [1, 1, 2, 2, 3, 3, 4, 4, 5, 6]:
		deck.append({"kind": "number", "value": v})
	for i in range(4):
		deck.append({"kind": "miss"})
	return deck


func draw_from_deck(deck: Array, discard: Array) -> Dictionary:
	if deck.is_empty():
		log_msg("[i]Deck empty — reshuffling discard pile back in.[/i]")
		deck.append_array(discard)
		discard.clear()
		deck.shuffle()
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
	log_box.clear()
	log_msg("[b]Hole %d — Par %d — %d yards[/b]" % [current_hole_index, hole_par, int(hole_yardage)])
	map_view.set_hole(hole)
	map_view.set_ball(ball_pos, shot_path)
	state = State.CLUB_SELECT
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
		current_draft_options.append(card)
		# Also exclude this hole's other options from the remaining draws,
		# so the 3 offers can't repeat a name amongst themselves either.
		owned_names[card.name] = true
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
		if not owned_names.has(card.name):
			found = card
			found_unowned = true
			break
		set_aside.append(card)

	if found_unowned:
		club_deck.append_array(set_aside)
	else:
		# Exhausted the pool without finding an unowned club — every card
		# left shares a name with something already owned. Put the set-aside
		# cards back first, then just draw whatever's next (a duplicate),
		# rather than leave current_draft_options short.
		club_deck.append_array(set_aside)
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


# --- Club select -> tier select -> shot resolution ---
func on_club_select(hand_index: int) -> void:
	pending_club = hand[hand_index]
	pending_club_index = hand_index
	state = State.TIER_SELECT
	refresh_ui()


func on_tier_select(tier: int) -> void:
	var card := pending_club
	pending_club = {}
	pending_club_index = -1
	play_shot(card, tier)


func play_shot(card: Dictionary, tier: int) -> void:
	# Bad cards are self-consuming: trigger on the very next shot, then discard.
	var active_bad_card: Dictionary = {}
	for c in hand:
		if c.type == "bad":
			active_bad_card = c
			break

	var effective_tier := tier
	if active_bad_card.get("name", "") == "Duffed":
		effective_tier = ShotResolver.Tier.EXTREME_FINESSE

	var accuracy_width_mod := 0
	if active_bad_card.get("name", "") == "Yips":
		accuracy_width_mod = -2

	var result := ShotResolver.resolve_shot(card, effective_tier, current_lie, 0, accuracy_width_mod)
	var power: Dictionary = result.power
	var accuracy: Dictionary = result.accuracy

	if active_bad_card.get("name", "") == "Shank":
		accuracy.band = "OFF"

	strokes += 1
	var before_pos := ball_pos

	log_msg("\n[b]Stroke %d[/b] — played %s, %s (lie: %s)" % [strokes, card.name, ShotResolver.tier_name(tier), current_lie])

	_animating = true
	# The tier tiles that led here are now stale — clear them out so a
	# leftover click can't re-enter on_tier_select() with pending_club
	# already emptied.
	clear_container(options_container)
	_play_dice_then_shot(card, power, accuracy, active_bad_card, before_pos)


# Rolls the Power die, then the Accuracy die, logging each as it settles —
# so the player watches the dice land instead of reading numbers cold —
# then hands off to the existing aim/flight animation once both are done.
func _play_dice_then_shot(card: Dictionary, power: Dictionary, accuracy: Dictionary, active_bad_card: Dictionary, before_pos: Vector2) -> void:
	dice_panel.visible = true
	dice_result_label.text = "Rolling for Power..."

	power_die.roll_to(power.roll, 0.65, func():
		log_msg("Power roll: %d vs Sweet Spot [%d-%d] (width %d) -> %s, %d yards." % [
			power.roll, power.bounds.x, power.bounds.y, power.width, power.outcome, int(power.distance)])
		dice_result_label.text = "Power: %s\nRolling for Accuracy..." % power.outcome.capitalize()

		accuracy_die.roll_to(accuracy.roll, 0.65, func():
			log_msg("Accuracy roll: %d vs Sweet Spot [%d-%d] -> %s, %s %d°." % [
				accuracy.roll, accuracy.bounds.x, accuracy.bounds.y, accuracy.band,
				ShotResolver.side_label(accuracy.side), accuracy.degree])
			dice_result_label.text = "Power: %s\nAccuracy: %s" % [power.outcome.capitalize(), accuracy.band.capitalize()]

			if not active_bad_card.is_empty():
				log_msg("[color=#%s](%s triggered and was discarded.)[/color]" % [COLOR_TEXT_SOFT.to_html(false), active_bad_card.name])
				hand.erase(active_bad_card)
				club_discard.append(active_bad_card)

			if active_bad_card.get("name", "") == "Lost Ball":
				strokes += 1
				log_msg("[color=#%s]Lost Ball — +1 penalty stroke on top of this shot.[/color]" % COLOR_FLAG.to_html(false))

			get_tree().create_timer(0.35).timeout.connect(func():
				dice_panel.visible = false
				map_view.play_aim_animation(power.distance, float(accuracy.degree), accuracy.side, card.max_yard, func():
					_resolve_shot_landing(before_pos, power, accuracy)
				)
			)
		)
	)


func _resolve_shot_landing(before_pos: Vector2, power: Dictionary, accuracy: Dictionary) -> void:
	_animating = false

	var aim_dir: Vector2 = (hole.pin_pos - before_pos).normalized()
	if aim_dir.length_squared() < 0.0001:
		aim_dir = Vector2.UP
	# Vector2.rotated() turns clockwise for +angle in Godot's Y-down convention,
	# so Draw (curves left) needs a positive angle here to end up on -x.
	var sign: float = 0.0
	if accuracy.side == ShotResolver.Side.DRAW:
		sign = 1.0
	elif accuracy.side == ShotResolver.Side.FADE:
		sign = -1.0
	var angle_rad: float = deg_to_rad(float(accuracy.degree)) * sign
	var shot_dir := aim_dir.rotated(angle_rad)
	var landing_pos: Vector2 = before_pos + shot_dir * power.distance

	var lie_result := hole.terrain_at(landing_pos)
	log_msg("Distance: %d yards -> landed in %s, %d yards from the pin." % [
		int(power.distance), lie_result, int(landing_pos.distance_to(hole.pin_pos))])

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

	shot_path.append(ball_pos)
	map_view.set_ball(ball_pos, shot_path)

	if hazard_hit and randf() < (1.0 / 6.0):
		maybe_add_bad_card(lie_result)
		return  # bad-card flow will call advance_after_shot() itself if needed

	advance_after_shot()


const BAD_CARDS := ["Yips", "Shank", "Lost Ball", "Duffed"]


func maybe_add_bad_card(lie_result: String) -> void:
	# Weight odds heavier toward Bunker/Water than Rough per Section 5.
	var name: String = BAD_CARDS[randi_range(0, BAD_CARDS.size() - 1)]
	var bad := make_club(name, 0, 0, 0, "bad")
	log_msg("[color=#%s]Picked up a %s card![/color]" % [COLOR_FLAG.to_html(false), name])
	if hand.size() >= HAND_CAP:
		pending_new_card = bad
		state = State.DISCARD_FOR_HAZARD
		log_msg("Hand is full — discard a card to make room for the %s." % name)
		refresh_ui()
	else:
		hand.append(bad)
		advance_after_shot()


func advance_after_shot() -> void:
	if current_lie == "green":
		start_putting()
	else:
		state = State.CLUB_SELECT
	refresh_ui()


# --- Putting phase ---
func start_putting() -> void:
	state = State.PUTTING
	var dist_to_pin: float = ball_pos.distance_to(hole.pin_pos)
	putting_target = clamp(int(round(dist_to_pin / 3.0)) + 3, 4, 12)
	putting_progress = 0
	log_msg("\n[b]On the green.[/b] Target to sink the putt: %d" % putting_target)
	refresh_ui()


func on_putt_draw() -> void:
	var card := draw_from_deck(green_deck, green_discard)
	green_discard.append(card)
	if card.kind == "miss":
		strokes += 1
		log_msg("Drew a Miss card — lip out! Stroke used, progress reset. (%d/%d)" % [putting_progress, putting_target])
		putting_progress = 0
	else:
		putting_progress += card.value
		log_msg("Drew %d — running total %d / %d." % [card.value, putting_progress, putting_target])
		if putting_progress >= putting_target:
			strokes += 1
			finish_hole()
			return
	refresh_ui()


func on_putt_bank() -> void:
	strokes += 1
	log_msg("Banked at %d/%d — lagged it close." % [putting_progress, putting_target])
	putting_target = 2
	putting_progress = 0
	refresh_ui()


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
	log_box.clear()
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


func refresh_ui() -> void:
	var dist_to_pin: float = ball_pos.distance_to(hole.pin_pos) if hole else 0.0
	status_label.text = "%d yards to pin · lie: %s · %d strokes" % [
		int(dist_to_pin), current_lie, strokes]

	if scorecard:
		scorecard.set_round(round_scores, current_hole_index, strokes)
	if hole_title and hole:
		hole_title.text = "Hole %d — Par %d — %d yards" % [current_hole_index, hole_par, int(hole_yardage)]
	if header_meta:
		clear_container(header_meta)
		header_meta.add_child(BoogieUI.chip(weather.to_upper(), COLOR_SAND))
		header_meta.add_child(BoogieUI.chip("WIND %d MPH · %s" % [wind_mph, wind_dir.to_upper()], COLOR_WATER))
		header_meta.add_child(BoogieUI.chip("THRU %d · %s" % [round_scores.size(), running_score_diff_text(running_score_diff())], COLOR_ACCENT))
		header_meta.add_child(BoogieUI.chip("BAG %d/%d" % [hand.size(), HAND_CAP], COLOR_TEXT_SOFT))

	if _animating:
		return

	clear_container(options_container)

	match state:
		State.DRAFT:
			hand_label.text = "DRAW 3, PICK 1"
			options_label.text = "Add one to your bag, permanently."
			for i in range(current_draft_options.size()):
				var cv := make_card_view(current_draft_options[i])
				cv.picked.connect(_make_draft_pick_callback(i))
				options_container.add_child(cv)

		State.DISCARD_FOR_DRAFT, State.DISCARD_FOR_HAZARD:
			hand_label.text = "BAG FULL (%d)" % HAND_CAP
			options_label.text = "Tap a card to drop it for %s." % pending_new_card.name
			for i in range(hand.size()):
				var cv := make_card_view(hand[i])
				cv.picked.connect(_make_discard_callback(i))
				options_container.add_child(cv)

		State.CLUB_SELECT, State.TIER_SELECT:
			hand_label.text = "YOUR BAG %d/%d" % [hand.size(), HAND_CAP]
			options_label.text = "Tap a club, then a swing."
			if current_lie == "bunker":
				options_label.text += "\n(bunker — irons/wedges only)"
			rebuild_bag_row()

		State.PUTTING:
			hand_label.text = "PUSH YOUR LUCK"
			options_label.text = "%d / %d — draw again, or bank it." % [putting_progress, putting_target]
			var draw_btn := Button.new()
			draw_btn.text = "Draw"
			draw_btn.custom_minimum_size = Vector2(100, 60)
			draw_btn.pressed.connect(on_putt_draw)
			options_container.add_child(draw_btn)

			var bank_btn := Button.new()
			bank_btn.text = "Bank / Stop"
			bank_btn.custom_minimum_size = Vector2(100, 60)
			bank_btn.pressed.connect(on_putt_bank)
			options_container.add_child(bank_btn)

		State.DONE:
			var total_strokes := 0
			var total_par := 0
			for entry in round_scores:
				total_strokes += entry.strokes
				total_par += entry.par
			var diff := total_strokes - total_par
			hand_label.text = "ROUND COMPLETE"
			options_label.text = "%d strokes (%s)." % [total_strokes, score_diff_text(diff)]
			var restart_btn := Button.new()
			restart_btn.text = "Restart Round"
			restart_btn.custom_minimum_size = Vector2(160, 60)
			restart_btn.pressed.connect(_on_restart_pressed)
			options_container.add_child(restart_btn)


func make_card_view(card: Dictionary, interactive: bool = true, compact: bool = false) -> CardView:
	var cv := CardView.new()
	cv.setup(card, interactive, compact)
	return cv


# Builds the bag row for CLUB_SELECT/TIER_SELECT: every card in hand, in
# hand order, shown compact. The one you tapped (pending_club_index, only
# set during TIER_SELECT) expands in place into its four swing tiles
# instead of swapping to a separate row — "tap a club, its swings unfold
# on the card itself."
func rebuild_bag_row() -> void:
	var playable := {}
	for i in range(hand.size()):
		var c = hand[i]
		if c.type == "putter" or c.type == "bad":
			continue
		if current_lie == "bunker" and c.type == "wood":
			continue
		playable[i] = true

	for i in range(hand.size()):
		var card = hand[i]
		if state == State.TIER_SELECT and i == pending_club_index:
			options_container.add_child(make_expanded_club_card(card))
		else:
			var cv := make_card_view(card, state == State.CLUB_SELECT and playable.has(i), true)
			if cv.interactive:
				cv.picked.connect(_make_club_callback(i))
			options_container.add_child(cv)


# The expanded inline swing-tier widget: one wide card replacing the tapped
# club's compact view, its four swings shown side by side.
func make_expanded_club_card(club: Dictionary) -> Control:
	var accent := CardView.type_color(club.get("type", "iron"))

	var outer := PanelContainer.new()
	outer.custom_minimum_size = Vector2(300, 138)
	var style := StyleBoxFlat.new()
	style.bg_color = BoogieTheme.CARD_BG
	style.set_corner_radius_all(10)
	style.border_color = accent
	style.set_border_width_all(2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	outer.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	outer.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = club.name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(name_label)

	var range_label := Label.new()
	range_label.text = "%d-%d yds" % [int(club.get("min_yard", 0)), int(club.get("max_yard", 0))]
	range_label.add_theme_font_size_override("font_size", 11)
	range_label.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	header.add_child(range_label)

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 5)
	tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tiles)

	for tier in [ShotResolver.Tier.FULL, ShotResolver.Tier.MID, ShotResolver.Tier.FINESSE, ShotResolver.Tier.EXTREME_FINESSE]:
		tiles.add_child(make_tier_tile(club, tier))

	return outer


# One swing tile inside the expanded club card: tier name, its yardage
# band, and the clean-shot / on-line odds for the current lie, computed
# straight from ShotResolver's Sweet Spot math so the guidance never
# drifts from what the dice actually do.
func make_tier_tile(club: Dictionary, tier: int) -> Button:
	var yard_range: Vector2 = ShotResolver.tier_yardage_range(club, tier)
	var power_odds := ShotResolver.power_odds(club, tier, current_lie)
	var acc_odds := ShotResolver.accuracy_odds(club, tier, current_lie)

	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.clip_text = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(vbox)
	b.add_child(margin)

	var title := Label.new()
	title.text = ShotResolver.tier_name(tier)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	var yard_line := Label.new()
	yard_line.text = "%d-%d" % [int(yard_range.x), int(yard_range.y)]
	yard_line.add_theme_font_size_override("font_size", 9)
	yard_line.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	yard_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(yard_line)

	var clean_line := Label.new()
	clean_line.text = "clean %d%%" % int(round(power_odds.clean * 100))
	clean_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	clean_line.add_theme_font_size_override("font_size", 9)
	clean_line.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	clean_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(clean_line)

	var acc_line := Label.new()
	acc_line.text = "on-line %d%%" % int(round(acc_odds.good * 100))
	acc_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	acc_line.add_theme_font_size_override("font_size", 9)
	acc_line.add_theme_color_override("font_color", COLOR_FLAG if acc_odds.off_miss > 0.5 else COLOR_TEXT_SOFT)
	acc_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(acc_line)

	b.pressed.connect(_make_tier_callback(tier))
	return b


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


# --- Callback factories (needed so each card view captures the right index) ---
func _make_draft_pick_callback(i: int) -> Callable:
	return func(cv): _on_draft_card_picked(cv, i)


func _make_discard_callback(i: int) -> Callable:
	return func(_cv): on_discard_pick(i)


func _make_club_callback(hand_index: int) -> Callable:
	return func(_cv): on_club_select(hand_index)


func _make_tier_callback(tier: int) -> Callable:
	return func(): on_tier_select(tier)
