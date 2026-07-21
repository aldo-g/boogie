extends Control

# ---------------------------------------------------------
# BOOGIE PROTOTYPE
# Single hole, single player. Tests the core loop:
#   draw 3 / pick 1 (permanent growing hand, 14-card cap)
#   -> choose a club -> roll Power + Accuracy dice
#   -> resolve lie/hazard -> repeat until on the green
#   -> Green Deck push-your-luck putting
# ---------------------------------------------------------

enum State { DRAFT, DISCARD_FOR_DRAFT, CLUB_SELECT, DISCARD_FOR_HAZARD, PUTTING, DONE }

const HAND_CAP := 14
const GREEN_THRESHOLD := 20.0  # yards remaining that triggers the putting phase
const DIE_SIZES := [4, 6, 8, 10, 12]

# Faded white / dark green theme (matches Title.gd)
const COLOR_DARK_GREEN := Color(0.043, 0.129, 0.078)
const COLOR_DARK_GREEN_PANEL := Color(0.078, 0.184, 0.114)
const COLOR_FADED_WHITE := Color(0.949, 0.949, 0.925)

var state: int = State.DRAFT

var hand: Array = []
var club_deck: Array = []
var club_discard: Array = []

var green_deck: Array = []
var green_discard: Array = []

var hole_yardage: float = 380.0
var hole_par: int = 4
var distance_remaining: float = 0.0
var strokes: int = 0
var current_lie: String = "tee"

var putting_target: int = 0
var putting_progress: int = 0

var pending_new_card = null
var current_draft_options: Array = []

# --- UI node refs (built in code) ---
var status_label: Label
var log_box: RichTextLabel
var hand_label: Label
var hand_container: HBoxContainer
var options_label: Label
var options_container: HBoxContainer
var restart_button: Button


func _ready() -> void:
	build_ui()
	init_game()
	start_hole()


# ---------------------------------------------------------
# UI CONSTRUCTION
# ---------------------------------------------------------
func build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_DARK_GREEN
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
	title.add_theme_color_override("font_color", COLOR_FADED_WHITE)
	root.add_child(title)

	status_label = Label.new()
	status_label.text = "Loading..."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.add_theme_color_override("font_color", COLOR_FADED_WHITE)
	root.add_child(status_label)

	var log_panel := PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(0, 260)
	var log_panel_style := StyleBoxFlat.new()
	log_panel_style.bg_color = COLOR_DARK_GREEN_PANEL
	log_panel_style.set_corner_radius_all(4)
	log_panel_style.content_margin_left = 8
	log_panel_style.content_margin_right = 8
	log_panel_style.content_margin_top = 8
	log_panel_style.content_margin_bottom = 8
	log_panel.add_theme_stylebox_override("panel", log_panel_style)
	root.add_child(log_panel)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.fit_content = false
	log_box.custom_minimum_size = Vector2(0, 260)
	log_box.add_theme_color_override("default_color", COLOR_FADED_WHITE)
	log_panel.add_child(log_box)

	hand_label = Label.new()
	hand_label.text = "Your Hand:"
	hand_label.add_theme_color_override("font_color", COLOR_FADED_WHITE)
	root.add_child(hand_label)

	hand_container = HBoxContainer.new()
	hand_container.add_theme_constant_override("separation", 8)
	root.add_child(hand_container)

	options_label = Label.new()
	options_label.text = ""
	options_label.add_theme_color_override("font_color", COLOR_FADED_WHITE)
	root.add_child(options_label)

	options_container = HBoxContainer.new()
	options_container.add_theme_constant_override("separation", 8)
	root.add_child(options_container)

	restart_button = Button.new()
	restart_button.text = "Restart Hole"
	restart_button.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	root.add_child(restart_button)


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


func card_label(card: Dictionary) -> String:
	if card.type == "bad":
		return "%s (BAD CARD)" % card.name
	if card.type == "putter":
		return "%s (green only)" % card.name
	var tag := " [LE]" if card.limited else ""
	var s := "%s%s\n%d-%d yds, d%d" % [card.name, tag, int(card.min_yard), int(card.max_yard), card.acc_die]
	if card.ability != "":
		s += "\n(%s)" % card.ability
	return s


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
	distance_remaining = hole_yardage
	strokes = 0
	current_lie = "tee"
	restart_button.visible = false
	log_box.clear()
	log_msg("[b]Hole 1 — Par %d — %d yards[/b]" % [hole_par, int(hole_yardage)])
	state = State.DRAFT
	begin_draft_phase()
	refresh_ui()


func step_die(die: int, lie: String) -> int:
	if die == 0:
		return 0
	var idx := DIE_SIZES.find(die)
	if idx == -1:
		idx = 1
	if lie == "rough" or lie == "bunker":
		idx = max(0, idx - 1)
	return DIE_SIZES[idx]


func resolve_lie(roll: int, die_size: int) -> String:
	var ratio := float(roll) / float(die_size)
	if ratio <= 0.15:
		return "water" if randf() < 0.5 else "bunker"
	elif ratio <= 0.4:
		return "rough"
	else:
		return "fairway"


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
		state = State.CLUB_SELECT
	refresh_ui()


# --- Discard flow (shared by draft-cap and hazard-cap cases) ---
func on_discard_pick(index: int) -> void:
	var removed = hand.pop_at(index)
	log_msg("Discarded %s." % removed.name)
	hand.append(pending_new_card)
	log_msg("Added [b]%s[/b] to your hand." % pending_new_card.name)
	pending_new_card = null

	if state == State.DISCARD_FOR_DRAFT:
		state = State.CLUB_SELECT
	else:
		# was DISCARD_FOR_HAZARD -> shot already resolved, move on
		advance_after_shot()
	refresh_ui()


# --- Club select + shot resolution ---
func on_club_select(index: int, playable_indices: Array) -> void:
	var hand_index: int = playable_indices[index]
	var card: Dictionary = hand[hand_index]
	play_shot(card)


func play_shot(card: Dictionary) -> void:
	var eff_die := step_die(card.acc_die, current_lie)
	var power_roll := randf()
	var shot_distance: float = lerp(card.min_yard, card.max_yard, power_roll)

	if current_lie == "bunker":
		shot_distance = min(shot_distance, card.max_yard * 0.5)

	var acc_roll := 1
	var lie_result := "fairway"
	if eff_die > 0:
		acc_roll = randi_range(1, eff_die)
		lie_result = resolve_lie(acc_roll, eff_die)

	strokes += 1
	var before := distance_remaining
	distance_remaining = max(0.0, distance_remaining - shot_distance)

	log_msg("\n[b]Stroke %d[/b] — played %s (lie: %s)" % [strokes, card.name, current_lie])
	log_msg("Power roll -> %d yards. Accuracy roll: %d/d%d -> %s." % [int(shot_distance), acc_roll, eff_die, lie_result])
	log_msg("Distance: %d -> %d yards remaining." % [int(before), int(distance_remaining)])

	var hazard_hit := false
	if lie_result == "water":
		strokes += 1
		current_lie = "rough"
		log_msg("[color=cyan]Splash! Water hazard — +1 penalty stroke, dropped in the rough.[/color]")
		hazard_hit = true
	elif lie_result == "bunker":
		current_lie = "bunker"
		log_msg("[color=orange]In the sand.[/color]")
		hazard_hit = true
	elif lie_result == "rough":
		current_lie = "rough"
	else:
		current_lie = "fairway"

	if hazard_hit and randf() < 0.4:
		maybe_add_bad_card()
		return  # bad-card flow will call advance_after_shot() itself if needed

	advance_after_shot()


func maybe_add_bad_card() -> void:
	var bad := make_club("Shank", 0, 0, 4, "bad")
	log_msg("[color=red]Picked up a Shank card![/color]")
	if hand.size() >= HAND_CAP:
		pending_new_card = bad
		state = State.DISCARD_FOR_HAZARD
		log_msg("Hand is full — discard a card to make room for the Shank.")
		refresh_ui()
	else:
		hand.append(bad)
		advance_after_shot()


func advance_after_shot() -> void:
	if distance_remaining <= GREEN_THRESHOLD:
		current_lie = "green"
		start_putting()
	else:
		begin_draft_phase()
	refresh_ui()


# --- Putting phase ---
func start_putting() -> void:
	state = State.PUTTING
	putting_target = clamp(int(round(distance_remaining / 3.0)) + 3, 4, 12)
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
	state = State.DONE
	var diff := strokes - hole_par
	var diff_text := "Even par"
	if diff < 0:
		diff_text = "%d under par" % -diff
	elif diff > 0:
		diff_text = "%d over par" % diff
	log_msg("\n[b]Holed out![/b] Total strokes: %d (par %d) — %s" % [strokes, hole_par, diff_text])
	restart_button.visible = true
	refresh_ui()


func _on_restart_pressed() -> void:
	init_game()
	start_hole()


# ---------------------------------------------------------
# UI REFRESH
# ---------------------------------------------------------
func refresh_ui() -> void:
	status_label.text = "%d yards remaining | Lie: %s | Strokes so far: %d" % [int(distance_remaining), current_lie, strokes]

	# Hand display
	clear_container(hand_container)
	for card in hand:
		var l := Label.new()
		l.text = card_label(card)
		l.custom_minimum_size = Vector2(140, 0)
		l.add_theme_color_override("font_color", COLOR_FADED_WHITE)
		hand_container.add_child(l)

	clear_container(options_container)

	match state:
		State.DRAFT:
			options_label.text = "Draw 3, pick 1 to add to your hand:"
			for i in range(current_draft_options.size()):
				var b := Button.new()
				b.text = card_label(current_draft_options[i])
				b.custom_minimum_size = Vector2(160, 60)
				b.pressed.connect(_make_draft_callback(i))
				options_container.add_child(b)

		State.DISCARD_FOR_DRAFT, State.DISCARD_FOR_HAZARD:
			options_label.text = "Hand full — choose a card to discard:"
			for i in range(hand.size()):
				var b := Button.new()
				b.text = "Discard: " + card_label(hand[i])
				b.custom_minimum_size = Vector2(160, 60)
				b.pressed.connect(_make_discard_callback(i))
				options_container.add_child(b)

		State.CLUB_SELECT:
			options_label.text = "Choose a club to play:"
			var playable_indices: Array = []
			for i in range(hand.size()):
				if hand[i].type != "putter":
					playable_indices.append(i)
			for j in range(playable_indices.size()):
				var card = hand[playable_indices[j]]
				var b := Button.new()
				b.text = "Play: " + card_label(card)
				b.custom_minimum_size = Vector2(160, 60)
				b.pressed.connect(_make_club_callback(j, playable_indices))
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
			options_label.text = "Hole complete."


# --- Callback factories (needed so each button captures the right index) ---
func _make_draft_callback(i: int) -> Callable:
	return func(): on_draft_pick(i)


func _make_discard_callback(i: int) -> Callable:
	return func(): on_discard_pick(i)


func _make_club_callback(i: int, playable_indices: Array) -> Callable:
	return func(): on_club_select(i, playable_indices)
