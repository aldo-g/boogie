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

# --- UI node refs (built in code) ---
var status_label: Label
var map_view: CourseMapView
var log_box: RichTextLabel
var hand_label: Label
var hand_container: HBoxContainer
var options_label: Label
var options_container: HBoxContainer


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
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	add_child(root)

	var title := Label.new()
	title.text = "Boogie — Single Hole Prototype"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	root.add_child(title)

	status_label = Label.new()
	status_label.text = "Loading..."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	root.add_child(status_label)

	var mid_row := HBoxContainer.new()
	mid_row.add_theme_constant_override("separation", 10)
	mid_row.custom_minimum_size = Vector2(0, 150)
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid_row)

	var map_panel := PanelContainer.new()
	map_panel.custom_minimum_size = Vector2(340, 0)
	var map_panel_style := StyleBoxFlat.new()
	map_panel_style.bg_color = COLOR_PANEL
	map_panel_style.set_corner_radius_all(4)
	map_panel_style.content_margin_left = 6
	map_panel_style.content_margin_right = 6
	map_panel_style.content_margin_top = 6
	map_panel_style.content_margin_bottom = 6
	map_panel.add_theme_stylebox_override("panel", map_panel_style)
	mid_row.add_child(map_panel)

	map_view = CourseMapView.new()
	map_panel.add_child(map_view)

	var log_panel := PanelContainer.new()
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var log_panel_style := StyleBoxFlat.new()
	log_panel_style.bg_color = COLOR_PANEL
	log_panel_style.set_corner_radius_all(4)
	log_panel_style.content_margin_left = 8
	log_panel_style.content_margin_right = 8
	log_panel_style.content_margin_top = 8
	log_panel_style.content_margin_bottom = 8
	log_panel.add_theme_stylebox_override("panel", log_panel_style)
	mid_row.add_child(log_panel)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.fit_content = false
	log_box.add_theme_color_override("default_color", COLOR_TEXT)
	log_panel.add_child(log_box)

	hand_label = Label.new()
	hand_label.text = "Your Hand:"
	hand_label.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(hand_label)

	var hand_scroll := ScrollContainer.new()
	hand_scroll.custom_minimum_size = Vector2(0, 134)
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(hand_scroll)

	hand_container = HBoxContainer.new()
	hand_container.add_theme_constant_override("separation", 8)
	hand_scroll.add_child(hand_container)

	options_label = Label.new()
	options_label.text = ""
	options_label.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(options_label)

	var options_scroll := ScrollContainer.new()
	options_scroll.custom_minimum_size = Vector2(0, 210)
	options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(options_scroll)

	options_container = HBoxContainer.new()
	options_container.add_theme_constant_override("separation", 8)
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
	hole = HoleData.hole_1()
	hole_yardage = hole.yardage
	hole_par = hole.par
	ball_pos = hole.tee_pos
	shot_path = [hole.tee_pos]
	strokes = 0
	current_lie = "tee"
	log_box.clear()
	log_msg("[b]Hole 1 — Par %d — %d yards[/b]" % [hole_par, int(hole_yardage)])
	map_view.set_hole(hole)
	map_view.set_ball(ball_pos, shot_path)
	state = State.CLUB_SELECT
	refresh_ui()


# --- Draft phase: draw 3, pick 1, permanently into hand ---
func begin_draft_phase() -> void:
	state = State.DRAFT
	current_draft_options = []
	for i in range(3):
		current_draft_options.append(draw_from_deck(club_deck, club_discard))
	refresh_ui()


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
func on_club_select(index: int, playable_indices: Array) -> void:
	var hand_index: int = playable_indices[index]
	pending_club = hand[hand_index]
	state = State.TIER_SELECT
	refresh_ui()


func on_tier_select(tier: int) -> void:
	var card := pending_club
	pending_club = {}
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
	log_msg("Power roll: %d vs Sweet Spot [%d-%d] (width %d) -> %s, %d yards." % [
		power.roll, power.bounds.x, power.bounds.y, power.width, power.outcome, int(power.distance)])
	log_msg("Accuracy roll: %d vs Sweet Spot [%d-%d] -> %s, %s %d°." % [
		accuracy.roll, accuracy.bounds.x, accuracy.bounds.y, accuracy.band,
		ShotResolver.side_label(accuracy.side), accuracy.degree])

	if not active_bad_card.is_empty():
		log_msg("[color=#%s](%s triggered and was discarded.)[/color]" % [COLOR_TEXT_SOFT.to_html(false), active_bad_card.name])
		hand.erase(active_bad_card)
		club_discard.append(active_bad_card)

	if active_bad_card.get("name", "") == "Lost Ball":
		strokes += 1
		log_msg("[color=#%s]Lost Ball — +1 penalty stroke on top of this shot.[/color]" % COLOR_FLAG.to_html(false))

	_animating = true
	map_view.play_aim_animation(power.distance, float(accuracy.degree), accuracy.side, card.max_yard, func():
		_resolve_shot_landing(before_pos, power, accuracy)
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


func finish_hole() -> void:
	var diff := strokes - hole_par
	var diff_text := "Even par"
	if diff < 0:
		diff_text = "%d under par" % -diff
	elif diff > 0:
		diff_text = "%d over par" % diff
	log_msg("\n[b]Holed out![/b] Total strokes: %d (par %d) — %s" % [strokes, hole_par, diff_text])
	log_msg("\n[b]End of hole.[/b] Draw 3, pick 1 to add to your hand permanently.")
	begin_draft_phase()


# Called once the end-of-hole draft pick has been resolved (with or without
# a forced discard) — the hole is now fully over.
func finish_hole_done() -> void:
	state = State.DONE
	var diff := strokes - hole_par
	var diff_text := "Even par"
	if diff < 0:
		diff_text = "%d under par" % -diff
	elif diff > 0:
		diff_text = "%d over par" % diff
	log_msg("\n[b]Demo complete.[/b] Final score: %d (%s). Hit Restart Hole to play again." % [strokes, diff_text])


func _on_restart_pressed() -> void:
	init_game()
	start_hole()


# ---------------------------------------------------------
# UI REFRESH
# ---------------------------------------------------------
var _animating: bool = false  # blocks refresh_ui() from clobbering an in-flight pick animation


func refresh_ui() -> void:
	var dist_to_pin: float = ball_pos.distance_to(hole.pin_pos) if hole else 0.0
	status_label.text = "%d yards to pin | Lie: %s | Strokes so far: %d" % [int(dist_to_pin), current_lie, strokes]

	if _animating:
		return

	rebuild_hand_row()

	clear_container(options_container)

	match state:
		State.DRAFT:
			options_label.text = "Draw 3, pick 1 to add to your hand:"
			for i in range(current_draft_options.size()):
				var cv := make_card_view(current_draft_options[i])
				cv.picked.connect(_make_draft_pick_callback(i))
				options_container.add_child(cv)

		State.DISCARD_FOR_DRAFT, State.DISCARD_FOR_HAZARD:
			options_label.text = "Hand full — choose a card to discard:"
			for i in range(hand.size()):
				var cv := make_card_view(hand[i])
				cv.picked.connect(_make_discard_callback(i))
				options_container.add_child(cv)

		State.CLUB_SELECT:
			options_label.text = "Choose a club to play:"
			if current_lie == "bunker":
				options_label.text += " (bunker — irons/wedges only)"
			var playable_indices: Array = []
			for i in range(hand.size()):
				var c = hand[i]
				if c.type == "putter" or c.type == "bad":
					continue
				if current_lie == "bunker" and c.type == "wood":
					continue
				playable_indices.append(i)
			for j in range(playable_indices.size()):
				var card = hand[playable_indices[j]]
				var cv := make_card_view(card)
				cv.picked.connect(_make_club_callback(j, playable_indices))
				options_container.add_child(cv)

		State.TIER_SELECT:
			options_label.text = "Playing %s — choose your swing:" % pending_club.name
			for tier in [ShotResolver.Tier.FULL, ShotResolver.Tier.MID, ShotResolver.Tier.FINESSE, ShotResolver.Tier.EXTREME_FINESSE]:
				var yard_range: Vector2 = ShotResolver.tier_yardage_range(pending_club, tier)
				var b := Button.new()
				b.text = "%s\n(~%d-%d yds)" % [ShotResolver.tier_name(tier), int(yard_range.x), int(yard_range.y)]
				b.custom_minimum_size = Vector2(160, 60)
				b.pressed.connect(_make_tier_callback(tier))
				options_container.add_child(b)

		State.PUTTING:
			options_label.text = "Putting — push your luck (%d/%d):" % [putting_progress, putting_target]
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
			var diff := strokes - hole_par
			var diff_text := "even par"
			if diff < 0:
				diff_text = "%d under par" % -diff
			elif diff > 0:
				diff_text = "%d over par" % diff
			options_label.text = "Demo complete — %d strokes (%s)." % [strokes, diff_text]
			var restart_btn := Button.new()
			restart_btn.text = "Restart Hole"
			restart_btn.custom_minimum_size = Vector2(160, 60)
			restart_btn.pressed.connect(_on_restart_pressed)
			options_container.add_child(restart_btn)


func rebuild_hand_row() -> void:
	clear_container(hand_container)
	for card in hand:
		var cv := make_card_view(card, false, true)
		hand_container.add_child(cv)


func make_card_view(card: Dictionary, interactive: bool = true, compact: bool = false) -> CardView:
	var cv := CardView.new()
	cv.setup(card, interactive, compact)
	return cv


# --- Draft pick: pop, then fly the chosen card into the hand row before
# actually mutating game state, so the pick reads as a physical action. ---
func _on_draft_card_picked(cv: CardView, index: int) -> void:
	_animating = true
	for other in options_container.get_children():
		if other != cv:
			other.play_fade_out()

	var target_pos: Vector2 = hand_container.global_position + Vector2(hand_container.size.x, hand_container.size.y * 0.5)
	cv.play_fly_to_hand(target_pos, func():
		_animating = false
		on_draft_pick(index)
	)


# --- Callback factories (needed so each card view captures the right index) ---
func _make_draft_pick_callback(i: int) -> Callable:
	return func(cv): _on_draft_card_picked(cv, i)


func _make_discard_callback(i: int) -> Callable:
	return func(_cv): on_discard_pick(i)


func _make_club_callback(i: int, playable_indices: Array) -> Callable:
	return func(_cv): on_club_select(i, playable_indices)


func _make_tier_callback(tier: int) -> Callable:
	return func(): on_tier_select(tier)
