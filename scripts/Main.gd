extends Control

# ---------------------------------------------------------
# PARS AND CHARS PROTOTYPE
# Single hole, single player. Tests the core loop (Section 4, Form Card
# System):
#   club draft: draw 3 / pick 1 (permanent growing hand, 14-card cap)
#   -> declare shot: choose a club + target
#   -> draw 3 Form cards, pick 1 (fully known effect, no hidden rolls)
#   -> final aim adjustment -> resolve deterministically
#   -> repeat until on the green -> putting QTE (timing meter, difficulty
#      scaled by distance to the pin)
# ---------------------------------------------------------

# WAITING: this machine's player has drafted and the others haven't
# (online, where everyone drafts at once). Appended so the existing values,
# which travel in snapshots, keep their numbers.
enum State { AIM, FORM_DRAW, DRAFT, DISCARD_FOR_DRAFT, CLUB_SELECT, DISCARD_FOR_HAZARD, PUTTING, DONE, WAITING }

const HAND_CAP := 14


# On-screen width of the putt meter. Deliberately wide: the hardest putt's
# sunk band is 12% of the bar, which needs the room to stay aimable.
const METER_WIDTH := 620

const Palette := preload("res://scripts/BogeyTheme.gd")
const Caddy := preload("res://scripts/Caddy.gd")
const Rivals := preload("res://scripts/Rivals.gd")
const HoleBanner := preload("res://scripts/HoleBanner.gd")
const CardFace := preload("res://scripts/CardFace.gd")

# Parchment / fairway theme, shared with Title.gd via BogeyTheme.
const COLOR_BG := Palette.PARCHMENT
const COLOR_PANEL := Palette.PARCHMENT_RAISED
const COLOR_TEXT := Palette.INK
const COLOR_TEXT_SOFT := Palette.INK_SOFT
const COLOR_ACCENT := Palette.FAIRWAY_DEEP
const COLOR_SAND := Palette.SAND_DEEP
const COLOR_WATER := Palette.WATER_DEEP
const COLOR_FLAG := Palette.FLAG

var state: int = State.DRAFT

# ---------------------------------------------------------
# PLAYERS (Section 7 — Modes)
#
# A round holds 1..4 Players. Hot-seat: they share this one screen and
# take turns, so exactly one is "active" at a time and the whole UI is
# drawn for that player only.
#
# Every per-player field below (hand, ball_pos, strokes, ...) is a
# PROPERTY that reads and writes through to `me` — the active Player.
# That keeps the rest of this file reading exactly as it did when there
# was only one player, while the state itself lives in Player.gd. Set
# `me` and the entire UI follows.
# ---------------------------------------------------------
var players: Array = []          # Array[Player], in seating order
var active_index: int = 0        # whose turn it is — index into players
var player_count: int = 1

# --- Computer golfers (local rounds only) ------------------------------
# Seat index -> Rivals.gd skill id, copied from GameSetup in _ready(). A
# Main built any other way (the harnesses, the title screen's scratch
# instance that rolls an online round) has none unless it sets this.
var cpu_seats: Dictionary = {}
# Seat index -> the GreedyBot playing it. Built by init_game().
var _bots: Dictionary = {}
# How long a computer golfer pauses before each action, as a multiple of
# CPU_BEAT — long enough to follow what it's doing. 0 acts on the next
# frame, which is what the harness uses.
var cpu_pace: float = 1.0
var _cpu_beat: bool = false      # a pause before the next computer action is running
var _cpu_wait: float = 0.0       # seconds left of that pause
var _cpu_task: int = -1          # worker task planning a computer golfer's shot; -1 = none

# --- Online play -------------------------------------------------------
# False for solo and hot-seat. When false, any input is legitimate: one
# screen is shared and whoever is sitting at it is whoever is up.
var online: bool = false

# The seat this machine controls in an online round. Only meaningful when
# `online` — hot-seat deliberately plays every seat from one keyboard.
var my_seat: int = 0

# Set by the net harness to trace RPC traffic; off in normal play.
var _net_trace: bool = false

# Seats whose peer dropped while a shot was animating. Applied once the
# animation is done — see on_peer_dropped().
var _pending_drops: Array = []

# Players still owing an end-of-hole draft, in order. On one screen drafts
# run one player at a time, because each is a choice made at that screen.
var _draft_queue: Array = []

# Online, everyone drafts at once instead: each machine shows its own
# player's draft, and the next hole starts when the last pick is in. Each
# player's progress is Player.draft_stage. Shared round state — every
# machine agrees on it.
var _simul_draft: bool = false

# ---------------------------------------------------------
# RANDOMNESS GATING
#
# Every per-action random result in the tee-to-green game goes through
# _roll(). Solo and hot-seat leave _injected_rolls empty, so _roll() just
# calls the generator and behaves exactly as the bare randf()/randi_range()
# did before — this is deliberately a no-op for local play.
#
# When a result has instead been decided elsewhere (the authoritative host
# in an online round, or a replay/determinism test), those results are
# pushed into _injected_rolls first and _roll() hands them back in order.
# The surrounding logic is then identical on every machine, which means
# the log lines, the branch taken, and the resulting state all match
# without any of that code knowing about the network.
#
# _consumed_rolls records what a roll-producing machine actually used, in
# order, so it can be sent to the other machines.
# ---------------------------------------------------------
var _injected_rolls: Array = []   # results decided elsewhere, consumed FIFO
var _consumed_rolls: Array = []   # what this machine generated, in order
var _recording_rolls: bool = false

# Stand-in used only before init_game() has built the real players — a
# getter can fire while the UI is still being constructed, and reading
# sane defaults is better than a null dereference.
var _fallback: Player = Player.new("—")

# The active player. All the per-player properties below delegate here.
var me: Player:
	get:
		if players.is_empty():
			return _fallback
		return players[active_index]


# --- Per-player state, delegated to `me` ---------------------------------
# These exist so the ~270 call sites elsewhere in this file keep working
# unchanged. Read/write them exactly as before.

var hand: Array:
	get: return me.hand
	set(v): me.hand = v

var club_deck: Array:
	get: return me.club_deck
	set(v): me.club_deck = v

var club_discard: Array:
	get: return me.club_discard
	set(v): me.club_discard = v

var form_deck: FormDeck:
	get: return me.form_deck
	set(v): me.form_deck = v

# Section 3B — the run's live brands. Only 4 of the 6 draftable brands are
# in the club deck each round; the other two are absent entirely, not
# rarer. This is where run-to-run variance lives, since the course itself
# is fixed and knowable. Revealed to the player before hole 1. Rolled
# per player, so each player's pool is shaped independently.
var live_brands: Array:
	get: return me.live_brands
	set(v): me.live_brands = v

var round_scores: Array:
	get: return me.round_scores
	set(v): me.round_scores = v

var ball_pos: Vector2:
	get: return me.ball_pos
	set(v): me.ball_pos = v

var shot_path: Array:
	get: return me.shot_path
	set(v): me.shot_path = v

var strokes: int:
	get: return me.strokes
	set(v): me.strokes = v

var current_lie: String:
	get: return me.current_lie
	set(v): me.current_lie = v

var aim_target: Vector2:
	get: return me.aim_target
	set(v): me.aim_target = v

var putt_dist: float:
	get: return me.putt_dist
	set(v): me.putt_dist = v

var _putt_dir: Vector2:
	get: return me.putt_dir
	set(v): me.putt_dir = v

var yips_pending: bool:
	get: return me.yips_pending
	set(v): me.yips_pending = v

# Holds a club Dictionary, or null when nothing is pending — hence Variant.
var pending_new_card: Variant:
	get: return me.pending_new_card
	set(v): me.pending_new_card = v

var current_draft_options: Array:
	get: return me.current_draft_options
	set(v): me.current_draft_options = v

var pending_club: Dictionary:
	get: return me.pending_club
	set(v): me.pending_club = v

var current_form_options: Array:
	get: return me.current_form_options
	set(v): me.current_form_options = v

var current_form_forced: bool:
	get: return me.current_form_forced
	set(v): me.current_form_forced = v

func is_multiplayer() -> bool:
	return player_count > 1


# --- Shared round state (not per player) --------------------------------
var current_hole_index: int = 1
# One per round; every hole's wind is derived from it (see Wind.gd). Sent
# in the round payload so all machines play the same wind.
var wind_seed: int = 0
var _restart_armed: bool = false  # Restart pressed once mid-round, awaiting confirm

var hole: HoleData
var hole_yardage: float = 380.0
var hole_par: int = 4

var putt_meter: PuttMeter

# --- The sheet's fixed measures, in pixels at the 1600x1000 base size ---
const LEFT_WIDTH := 316        # the hole-and-shot column
const RIGHT_WIDTH := 372       # the Form hand and play-by-play column
const SIDE_PAD := 28           # page margin, left and right
const PLATE_WIDTH := 460       # the hole map's mount
const STRIP_HEIGHT := 252      # the bag strip
const BAG_GAP := 8             # between cards in the bag
const BAG_CARD_MAX := 136.0    # a bag card with room to spare...
const BAG_CARD_MIN := 100.0    # ...and with all fourteen in the row
const DRAFT_CARD_WIDTH := 456.0  # a draft offer: the club, and what taking it changes

# --- UI node refs (built in code) ---
var map_view: CourseMapView
var hand_label: Label
var options_label: Label
var options_container: HBoxContainer   # the strip's one row: the bag, the draft, the putt meter
var options_scroll: ScrollContainer

var step_holder: HBoxContainer         # the step line over the map
var form_label: Label
var form_hint: Label
var form_container: VBoxContainer      # the Form hand, a column beside the map
var _family_rows: Dictionary = {}      # the form table's rows, by club family
var form_deck_holder: HBoxContainer    # the "Deck" link, right of the Form kicker

# The hole's record, newest first — see log_msg(). Recorded, not shown.
var log_entries: Array = []
var scorecard: ScorecardView
var brand_rack: HBoxContainer          # brand swatches, in the bag header — hover for the set's clubs and bonuses
var hole_title: Label
var hole_caption: Label                # "Par 4 · 380 yards", under the hole title
var turn_banner: PanelContainer        # "Player 2 to play" — hot-seat only
var turn_banner_label: Label
var restart_link: Button
var shot_outlook: VBoxContainer
var ability_box: VBoxContainer         # club abilities and set powers for this moment — under the shot panel
var form_deck_popup: PopupPanel
var form_deck_list: VBoxContainer
var caddy: Caddy                   # the arctic char who pops up with advice — see Caddy.gd
var hole_banner: HoleBanner        # the stamp that lands on the map when a hole is finished
var _caddy_card: String = ""       # the Form card behind the shot in flight, for him to remark on


func _ready() -> void:
	# Chosen on the title screen. Clamped so running Main.tscn directly
	# (or a stale value) can't produce a zero-player round.
	player_count = clampi(GameSetup.player_count, 1, 4)
	online = GameSetup.online
	my_seat = clampi(GameSetup.my_seat, 0, player_count - 1) if online else 0
	cpu_seats = {} if online else GameSetup.cpu_seats.duplicate()
	build_ui()

	if online and not GameSetup.round_payload.is_empty():
		# Online: the host already rolled every deck and sent it, so adopt
		# that rather than rolling our own — otherwise no two machines
		# would start the round holding the same cards.
		apply_round_payload(GameSetup.round_payload)
		apply_seat_names(GameSetup.seat_names)
	else:
		init_game()
		if online:
			apply_seat_names(GameSetup.seat_names)

	if online:
		connect_net_signals()

	start_hole()


# Subscribes to the connection events this round needs. Its own method
# rather than inline setup, so anything that builds a round without going
# through _ready() still gets disconnect handling — the harness does
# exactly that, and so would any future headless mode.
#
# Listens on this node's own API rather than the Net autoload, so it works
# under a bare connection too.
func connect_net_signals() -> void:
	if multiplayer == null:
		return
	if not multiplayer.peer_connected.is_connected(_on_peer_joined):
		multiplayer.peer_connected.connect(_on_peer_joined)
	if not multiplayer.peer_disconnected.is_connected(on_peer_dropped):
		multiplayer.peer_disconnected.connect(on_peer_dropped)
	if not multiplayer.server_disconnected.is_connected(on_host_lost):
		multiplayer.server_disconnected.connect(on_host_lost)
	# Peers that connected during the lobby, before this round existed.
	for pid in multiplayer.get_peers():
		_on_peer_joined(pid)


# Labels each seat with the name agreed in the lobby. Seats the lobby
# didn't name keep their default.
func apply_seat_names(names: Dictionary) -> void:
	for seat in names:
		var i := int(seat)
		if i >= 0 and i < players.size():
			var n := str(names[seat]).strip_edges()
			if n != "":
				players[i].name = n


# ---------------------------------------------------------
# UI CONSTRUCTION
# ---------------------------------------------------------
func build_ui() -> void:
	theme = BogeyUI.theme()

	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# --- Header: the wordmark, the card, the way out -----------------------
	# The scorecard is the header. It answers "how am I doing" for the whole
	# round in three printed rows, which leaves nothing else to say up here.
	# The side cells are cut to the widths of the columns beneath them, so
	# the card sits centred over the hole map rather than over the window.
	var header_style := BogeyUI.ruled_panel(false, false, false, true, 0)
	header_style.content_margin_left = SIDE_PAD
	header_style.content_margin_right = SIDE_PAD
	header_style.content_margin_top = 14
	header_style.content_margin_bottom = 14
	var header := BogeyUI.make_panel(header_style)
	root.add_child(header)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 0)
	header.add_child(header_row)

	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", -4)
	title_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_col.custom_minimum_size = Vector2(LEFT_WIDTH - SIDE_PAD, 0)
	header_row.add_child(title_col)
	var wordmark := Label.new()
	wordmark.text = "Pars and Chars"
	BogeyUI.set_font(wordmark, BogeyUI.FONT_SCRIPT, 36, BogeyTheme.INK)
	title_col.add_child(wordmark)
	title_col.add_child(BogeyUI.kicker(Course.active_name))

	scorecard = ScorecardView.new()
	scorecard.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	scorecard.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(scorecard)

	# Settings, Restart and the way out: reachable from every state, and
	# quiet — three words in small capitals, not three boxes.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 24)
	nav.alignment = BoxContainer.ALIGNMENT_END
	nav.custom_minimum_size = Vector2(RIGHT_WIDTH - SIDE_PAD, 0)
	nav.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(nav)
	nav.add_child(_nav_link("Settings", "Volume, shot speed and the putt key",
		_on_header_settings_pressed))
	restart_link = _nav_link("Restart", "Abandon this round and start a new one from hole 1",
		_on_header_restart_pressed)
	nav.add_child(restart_link)
	# Back to the title, or to the editor when this round is a test of a
	# course being built.
	nav.add_child(_nav_link("Editor" if GameSetup.return_to_editor else "Menu", "Leave this round",
		_on_header_menu_pressed))

	# --- Middle: the shot | the hole | the Form hand ----------------------
	var mid_row := HBoxContainer.new()
	mid_row.add_theme_constant_override("separation", 0)
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid_row)

	# Left: where you are and what the shot in front of you is. Scrolls
	# rather than grows, so a long read can never push the bag off screen.
	var left_panel := BogeyUI.make_panel(BogeyUI.ruled_panel(false, true, false, false, 0))
	left_panel.custom_minimum_size = Vector2(LEFT_WIDTH, 0)
	mid_row.add_child(left_panel)

	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_panel.add_child(left_scroll)

	var this_shot_col := VBoxContainer.new()
	this_shot_col.add_theme_constant_override("separation", 12)
	var left_margin := BogeyUI.margin(this_shot_col, SIDE_PAD, 16, 24, 6)
	left_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_margin)

	# Whose turn it is. In a hot-seat round this is the single most
	# important thing on screen — the wrong player taking a shot is
	# unrecoverable — so it heads the column, ruled in that player's seat
	# colour. Hidden entirely in a solo round.
	turn_banner = BogeyUI.make_panel(_turn_banner_style(BogeyTheme.INK))
	turn_banner_label = BogeyUI.heading("", 24)
	turn_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turn_banner.add_child(turn_banner_label)
	turn_banner.visible = false
	this_shot_col.add_child(turn_banner)

	var hole_head := VBoxContainer.new()
	hole_head.add_theme_constant_override("separation", -2)
	this_shot_col.add_child(hole_head)
	hole_title = BogeyUI.heading("Hole 1", 40)
	hole_head.add_child(hole_title)
	hole_caption = BogeyUI.kicker("")
	hole_head.add_child(hole_caption)

	shot_outlook = VBoxContainer.new()
	shot_outlook.add_theme_constant_override("separation", 12)
	this_shot_col.add_child(shot_outlook)

	# Kept apart from shot_outlook, which rebuilds on every mouse move
	# while aiming — a button rebuilt under the cursor can't be clicked.
	ability_box = VBoxContainer.new()
	ability_box.add_theme_constant_override("separation", 6)
	this_shot_col.add_child(ability_box)

	# Centre: the hole, and nothing else. One line above it says what to
	# do next; the side view sits beneath.
	var plate_col := VBoxContainer.new()
	plate_col.add_theme_constant_override("separation", 12)
	var plate_margin := BogeyUI.margin(plate_col, 24, 16, 24, 12)
	plate_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_row.add_child(plate_margin)

	step_holder = HBoxContainer.new()
	step_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	step_holder.custom_minimum_size = Vector2(0, 28)
	plate_col.add_child(step_holder)

	map_view = CourseMapView.new()
	map_view.aim_picked.connect(_on_aim_committed)
	map_view.aim_changed.connect(_on_aim_changed)
	# Holes run tall and narrow (roughly 120-200 yds wide, 400-600 yds
	# long), so the mount is a portrait plate, centred in the column, rather
	# than a wide frame around a thin strip.
	var hole_plate := BogeyUI.plate(map_view)
	hole_plate.custom_minimum_size = Vector2(PLATE_WIDTH, 0)
	hole_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate_col.add_child(hole_plate)

	# Side view of the same hole, matched to the plate's width.
	var profile := ElevationProfileView.new()
	profile.map = map_view
	profile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate_col.add_child(profile)
	profile.custom_minimum_size.x = PLATE_WIDTH
	hole_plate.resized.connect(func(): profile.custom_minimum_size.x = hole_plate.size.x)

	# Right: the Form hand, and nothing else. The Form cards live here,
	# beside the map, because that is where you look while choosing one —
	# each card previews its landing on the hole as you pass over it.
	# Between draws the column is left as white space.
	var right_panel := BogeyUI.make_panel(BogeyUI.ruled_panel(true, false, false, false, 0))
	right_panel.custom_minimum_size = Vector2(RIGHT_WIDTH, 0)
	mid_row.add_child(right_panel)

	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(right_scroll)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 10)
	var right_margin := BogeyUI.margin(right_col, 24, 22, SIDE_PAD, 16)
	right_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right_margin)

	var form_head := HBoxContainer.new()
	form_head.add_theme_constant_override("separation", 12)
	right_col.add_child(form_head)
	form_label = BogeyUI.kicker("Form hand", BogeyTheme.INK)
	form_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_head.add_child(form_label)
	form_deck_holder = HBoxContainer.new()
	form_head.add_child(form_deck_holder)

	form_hint = BogeyUI.body("", 13, BogeyTheme.NEUTRAL_600)
	right_col.add_child(form_hint)

	form_container = VBoxContainer.new()
	form_container.add_theme_constant_override("separation", 8)
	right_col.add_child(form_container)

	# --- Bottom: the bag -----------------------------------------------------
	# The whole width, so a full bag of fourteen sits in one row with no
	# scrolling. The same row doubles as the surface for the draft, the
	# "something has to go" cut, and the putt meter. Fixed in height: the
	# hole above it never changes size between one state and the next.
	var strip_style := BogeyUI.panel(BogeyTheme.PARCHMENT_RAISED, 0)
	strip_style.border_color = BogeyTheme.RULE
	strip_style.border_width_top = 1
	strip_style.content_margin_left = SIDE_PAD
	strip_style.content_margin_right = SIDE_PAD
	strip_style.content_margin_top = 14
	strip_style.content_margin_bottom = 14
	var strip := BogeyUI.make_panel(strip_style)
	strip.custom_minimum_size = Vector2(0, STRIP_HEIGHT)
	root.add_child(strip)

	var bag_col := VBoxContainer.new()
	bag_col.add_theme_constant_override("separation", 8)
	strip.add_child(bag_col)

	var bag_head := HBoxContainer.new()
	bag_head.add_theme_constant_override("separation", 14)
	bag_col.add_child(bag_head)
	hand_label = BogeyUI.kicker("Your bag", BogeyTheme.INK)
	hand_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bag_head.add_child(hand_label)
	options_label = BogeyUI.label("", 13, BogeyTheme.NEUTRAL_600)
	options_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A one-line caption beside the kicker: it takes the rest of the row and
	# ellipsizes rather than wrapping.
	options_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bag_head.add_child(options_label)

	# The brand rack sits with the bag: these swatches are a read on the
	# clubs directly beneath them. Each carries a hover tooltip naming the
	# clubs of that brand you actually hold and the bonus the next one
	# unlocks — see brand_chip_tooltip().
	brand_rack = HBoxContainer.new()
	brand_rack.add_theme_constant_override("separation", 20)
	brand_rack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bag_head.add_child(brand_rack)

	options_scroll = ScrollContainer.new()
	options_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_col.add_child(options_scroll)

	options_container = HBoxContainer.new()
	options_container.add_theme_constant_override("separation", BAG_GAP)
	# Centred, so a three-club bag on the first tee sits under the hole
	# rather than stranded at the left edge.
	options_container.alignment = BoxContainer.ALIGNMENT_CENTER
	options_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_scroll.add_child(options_container)

	build_form_deck_popup()

	# The stamp for finished holes, over the hole map.
	hole_banner = HoleBanner.new()
	hole_banner.anchor = map_view
	add_child(hole_banner)

	# Added last so he swims over everything else. He sits on the bag
	# strip, in the margin between the shot column and the hole.
	caddy = Caddy.new()
	caddy.anchor_above = strip
	caddy.left_inset = LEFT_WIDTH + 10.0
	add_child(caddy)


# One of the header's text links.
func _nav_link(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	BogeyUI.style_link_button(b)
	b.pressed.connect(on_press)
	return b


# The turn line's rule, in the seat colour of whoever is up.
func _turn_banner_style(seat: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = seat
	s.border_width_left = 4
	s.content_margin_left = 12
	s.content_margin_top = 2
	s.content_margin_bottom = 4
	return s


# Restart asks twice mid-round. While it is waiting for the second press
# the link itself says so, in claret, so the prompt can't be missed.
func _show_restart_armed(on: bool) -> void:
	if restart_link == null:
		return
	restart_link.text = "PRESS AGAIN TO RESTART" if on else "RESTART"
	var ink: Color = BogeyTheme.FLAG if on else BogeyTheme.NEUTRAL_600
	restart_link.add_theme_color_override("font_color", ink)
	restart_link.add_theme_color_override("font_focus_color", ink)
	restart_link.add_theme_color_override("font_hover_color", BogeyTheme.ACCENT_800 if on else BogeyTheme.INK)


# A browsable list of every Form card currently in the deck or discard
# pile, grouped by name with counts — opened from the "FORM DECK" chip in
# the header. Shuffled-deck contents wouldn't normally be visible to a
# real player, but this trades that realism for letting the player see
# exactly how degraded their Form deck has gotten after a rough round.
func build_form_deck_popup() -> void:
	form_deck_popup = PopupPanel.new()
	form_deck_popup.size = Vector2(380, 480)
	add_child(form_deck_popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	form_deck_popup.add_child(vbox)

	vbox.add_child(BogeyUI.heading("Form deck", 30))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	form_deck_list = VBoxContainer.new()
	form_deck_list.add_theme_constant_override("separation", 0)
	form_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form_deck_list)


func rebuild_form_deck_list() -> void:
	clear_container(form_deck_list)
	if not form_deck:
		return

	var all_cards: Array = form_deck.deck + form_deck.discard
	var summary := BogeyUI.body("%d cards — %d still to draw, %d played. A swing is dealt only from the family of the club in hand." % [
		all_cards.size(), form_deck.deck.size(), form_deck.discard.size()], 13, COLOR_TEXT_SOFT)
	form_deck_list.add_child(BogeyUI.margin(summary, 0, 0, 0, 10))

	# A family at a time: its good and bad counts, then a line a card.
	var form := form_deck.family_form()
	for fam in FormCard.FAMILIES:
		var counts := {}       # name -> count
		var is_good := {}      # name -> bool
		for c in all_cards:
			if c.family != fam:
				continue
			counts[c.name] = counts.get(c.name, 0) + 1
			is_good[c.name] = c.good
		if counts.is_empty():
			continue

		var head := HBoxContainer.new()
		var fam_label := BogeyUI.kicker(FormCard.FAMILY_LABEL[fam], BogeyTheme.INK)
		fam_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(fam_label)
		head.add_child(BogeyUI.kicker("%d good · %d bad" % [form[fam].good, form[fam].bad], BogeyTheme.NEUTRAL_600))
		form_deck_list.add_child(BogeyUI.margin(head, 0, 12, 4, 6))
		form_deck_list.add_child(BogeyUI.hairline(0.2))

		var names: Array = counts.keys()
		names.sort_custom(func(x, y):
			if is_good[x] != is_good[y]:
				return is_good[x]  # good cards first
			return x < y)
		for name in names:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.add_child(BogeyUI.dot(BogeyTheme.FAIRWAY if is_good[name] else BogeyTheme.FLAG, 7))
			var name_label := BogeyUI.label(str(name), 14, BogeyTheme.INK)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			row.add_child(BogeyUI.label("× %d" % counts[name], 14, COLOR_TEXT_SOFT))
			form_deck_list.add_child(BogeyUI.margin(row, 0, 6, 4, 6))
			form_deck_list.add_child(BogeyUI.hairline(0.07))


func _on_form_deck_chip_pressed() -> void:
	rebuild_form_deck_list()
	form_deck_popup.popup_centered()


# Hands the caddy an event to maybe comment on. Online, he only talks to
# the player at this machine: advice about someone else's ball is noise.
# `everyone` is for news that applies to the whole group, like the wind.
# `wait` is for his last word on the round: it follows his line about the
# last hole instead of being lost to it (see Caddy.react()).
func caddy_says(kind: String, ctx: Dictionary = {}, everyone: bool = false, wait: bool = false) -> void:
	if caddy == null:
		return
	# He's the player's caddy: he doesn't narrate a computer golfer's shots.
	if not everyone and (not is_my_turn() or is_cpu_turn()):
		return
	caddy.react(kind, ctx, wait)


# The record of the hole — every stroke, penalty and ruling, newest
# first — as {tag, head, body} entries. Callers pass bbcode-ish strings;
# this strips the markup, takes a leading "[b]...[/b]" run as the entry's
# headline and a "Stroke N" opener as its tag.
#
# Recorded, not shown: the sheet has no play-by-play column. What the
# player needs from the last shot is in the shot panel.
func log_msg(text: String) -> void:
	var clean := strip_markup(text)
	if clean.strip_edges() == "":
		return

	var tag := "Note"
	var head := ""
	var body := clean

	# "Stroke 3 — played Hook with Driver (lie: fairway)" splits into a
	# "Stroke 3" tag and the rest as the headline.
	if clean.begins_with("Stroke "):
		var dash := clean.find(" — ")
		if dash > 0:
			tag = clean.substr(0, dash)
			head = clean.substr(dash + 3)
			body = ""
	elif text.begins_with("[b]"):
		var close := text.find("[/b]")
		if close > 0:
			head = strip_markup(text.substr(3, close - 3))
			body = strip_markup(text.substr(close + 4))
			tag = "Hole"

	log_entries.push_front({"tag": tag, "head": head.strip_edges(), "body": body.strip_edges()})


# Drops bbcode tags, leaving the plain words.
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


func clear_container(c: Container) -> void:
	for child in c.get_children():
		child.queue_free()


# ---------------------------------------------------------
# CARD HELPERS
# ---------------------------------------------------------
# Keeps the bag racked longest-first, putter last — see ClubRoster.sort_bag().
# Called after any change to the bag.
func sort_hand() -> void:
	ClubRoster.sort_bag(hand)


# Indices into `hand` of the clubs the active player may play from their
# current lie. Never empty: the putter is playable from anywhere.
func playable_club_indices() -> Array:
	var out: Array = []
	for i in range(hand.size()):
		if ShotRules.club_playable(hand, hand[i], current_lie):
			out.append(i)
	return out


# ---------------------------------------------------------
# SETUP
# ---------------------------------------------------------
func init_game() -> void:
	# A shot being planned reads the players about to be replaced.
	_cpu_reset()
	players = []
	_bots = {}
	for i in range(player_count):
		var p := make_player(default_player_name(i))
		var skill := str(cpu_seats.get(i, ""))
		if not online and Rivals.has(skill):
			p.cpu_skill = skill
			p.name = Rivals.name_of(skill)
			# Seeded off the clock, not the global generator: the bot draws
			# from its own, and a round with a rival should shuffle exactly
			# as the same round without one.
			_bots[i] = Rivals.make_bot(skill, hash([Time.get_ticks_usec(), i]))
		players.append(p)
	active_index = 0
	wind_seed = randi()


# --- Online round setup ------------------------------------------------
# Everything a machine needs to start the same round as everyone else.
#
# Only the deck-derived parts matter here: bags, draft pools, live brands
# and Form decks are all shuffle results, so they cannot be re-rolled
# locally and must be sent. The course travels as its definitions (see
# Course.to_wire) — a custom course exists only on the host's machine —
# and every peer then builds the identical geometry from them.
#
# Shapes are deliberately plain: club entries are already Dictionaries of
# scalars, and a FormCard is reconstructible from its name alone, so the
# whole payload is wire-safe without a custom serializer.
func build_round_payload() -> Dictionary:
	var out: Array = []
	for p in players:
		out.append({
			"name": p.name,
			"hand": p.hand.duplicate(true),
			"club_deck": p.club_deck.duplicate(true),
			"club_discard": p.club_discard.duplicate(true),
			"live_brands": p.live_brands.duplicate(),
			"form_deck": form_card_names(p.form_deck.deck),
			"form_discard": form_card_names(p.form_deck.discard),
		})
	return {"players": out, "course": Course.to_wire(Course.active()), "wind_seed": wind_seed}


# Rebuilds this machine's players from the host's payload, so every peer
# begins the round holding identical decks in identical order.
func apply_round_payload(payload: Dictionary) -> void:
	# Sanitised on the way in: the host is trusted to run the round, but a
	# course is data from another machine and the game must stay playable.
	if not (online and Net.is_host()):
		var course := Course.from_wire(payload.get("course", {}))
		if course.is_empty():
			Course.use_builtin()
		else:
			Course.use(course)
	wind_seed = int(payload.get("wind_seed", 0))
	var entries: Array = payload.get("players", [])
	players = []
	for e in entries:
		var p := Player.new(str(e.get("name", "Player")))
		p.hand = (e.get("hand", []) as Array).duplicate(true)
		p.club_deck = (e.get("club_deck", []) as Array).duplicate(true)
		p.club_discard = (e.get("club_discard", []) as Array).duplicate(true)
		p.live_brands = (e.get("live_brands", []) as Array).duplicate()
		p.form_deck = FormDeck.new()
		p.form_deck.deck = form_cards_from_names(e.get("form_deck", []))
		p.form_deck.discard = form_cards_from_names(e.get("form_discard", []))
		players.append(p)
	player_count = players.size()
	active_index = 0


# A FormCard is fully described by its name — every card in the game comes
# from FormCard.make() — plus whether a club created it and which club
# family it belongs to, so decks travel as name lists: created cards
# marked by a leading "+", the family after an "@" ("Hook@wood").
const CREATED_MARK := "+"
const FAMILY_MARK := "@"


func form_card_names(cards: Array) -> Array:
	var names: Array = []
	for c in cards:
		names.append((CREATED_MARK if c.created else "") + c.name
			+ ((FAMILY_MARK + c.family) if c.family != "" else ""))
	return names


func form_cards_from_names(names: Array) -> Array:
	var cards: Array = []
	for n in names:
		var s := str(n)
		var made := s.begins_with(CREATED_MARK)
		if made:
			s = s.substr(CREATED_MARK.length())
		var fam := ""
		var at := s.rfind(FAMILY_MARK)
		if at >= 0:
			fam = s.substr(at + FAMILY_MARK.length())
			s = s.substr(0, at)
		var card := FormCard.make(s).of_family(fam)
		cards.append(card.as_created() if made else card)
	return cards


# Default seat names. Single-player keeps the old unnamed framing ("You"),
# since there's nobody to distinguish from.
func default_player_name(index: int) -> String:
	if human_seat_count() <= 1:
		return "You"
	return "Player %d" % (index + 1)


# How many seats a person plays. Online, all of them.
func human_seat_count() -> int:
	if online:
		return player_count
	var n := 0
	for i in range(player_count):
		if not Rivals.has(str(cpu_seats.get(i, ""))):
			n += 1
	return n


# True when the seat is played by the computer.
func is_cpu_seat(seat: int) -> bool:
	return not online and seat >= 0 and seat < players.size() and players[seat].cpu_skill != ""


# True while it is a computer golfer's move. Everything a person can
# press goes through submit(), which refuses while this holds.
func is_cpu_turn() -> bool:
	return state != State.DONE and is_cpu_seat(active_index)


# The one person in a round against the computer, or null when there are
# several people (or none).
func lone_human() -> Player:
	var found: Player = null
	for i in range(players.size()):
		if is_cpu_seat(i):
			continue
		if found != null:
			return null
		found = players[i]
	return found if _bots.size() > 0 else null


# "Your" for the unnamed solo seat, otherwise the name with its 's.
func possessive(p: Player) -> String:
	return "Your" if p.name == "You" else "%s's" % p.name


# Builds one player at the start of a run: the Bogey-Mart starter bag, an
# independently shaped draft pool (Section 3B), and that player's own Form
# deck. The clubs themselves come from ClubRoster (assets/data/clubs.json).
#
# Pool and Form deck are per player because the draft is independent (no
# sniping) and because hazard decay must land on the player who hit the
# hazard rather than on the table.
func make_player(player_name: String) -> Player:
	var p := Player.new(player_name)
	p.hand = ClubRoster.starter_bag()
	p.live_brands = ClubRoster.roll_live_brands()
	var pool: Array = ClubRoster.build_pool(p.live_brands)
	pool.shuffle()
	p.club_deck = pool
	p.club_discard = []
	p.form_deck = FormDeck.new()
	return p


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
	Sound.play("card_shuffle", 0.0, -6.0)
	# The layout, plus this round's wind and pin (both from wind_seed).
	hole = HoleData.for_round(current_hole_index, wind_seed)
	hole_yardage = hole.yardage
	hole_par = hole.par

	# Every player starts the hole on the tee. Order of play off the tee is
	# seating order (there are no distances to compare yet); from the
	# second shot on it's furthest-from-pin — see next_to_play().
	for p in players:
		p.start_hole(hole.tee_pos)
	for seat in _bots:
		_bots[seat].reset_log()
	active_index = 0

	log_entries.clear()
	log_msg("[b]Hole %d — Par %d — %d yards[/b]" % [current_hole_index, hole_par, int(hole_yardage)])
	log_msg("Wind: %s (%s off the tee)." % [Wind.strength_word(hole.wind).to_lower(),
		Wind.describe(hole.wind, hole.pin_pos - hole.tee_pos)])
	if is_multiplayer():
		log_msg("[i]%s to play.[/i]" % me.name)
	var has_water := hole.hazards.any(func(h): return h.get("type", "") == "water")
	caddy_says("tee", {"par": hole_par, "yards": hole_yardage, "wind": hole.wind,
		"dir": hole.pin_pos - hole.tee_pos, "water": has_water,
		"last_hole": current_hole_index >= Course.hole_count()}, true)
	sync_map_to_active()
	# Clears any aim line left over from the previous hole's last shot —
	# otherwise it points at wherever that old target was, which is
	# nonsensical geometry once the ball's moved to a brand new hole's tee.
	map_view.set_aim_target(ball_pos)
	state = State.CLUB_SELECT
	refresh_ui()


# Points the map at the active player: their hole, their ball, their trail,
# and in multiplayer the other players' balls as markers so you can see the
# whole group on the hole.
func sync_map_to_active() -> void:
	map_view.set_hole(hole)
	map_view.set_ball(ball_pos, shot_path)
	if map_view.has_method("set_other_balls"):
		map_view.set_other_balls(other_ball_markers())


# The other players' positions on this hole, for drawing as secondary
# markers. Holed-out players are left off — their ball is in the cup.
func other_ball_markers() -> Array:
	var markers: Array = []
	if not is_multiplayer():
		return markers
	for i in range(players.size()):
		if i == active_index:
			continue
		var p: Player = players[i]
		if p.holed_out or p.abandoned:
			continue
		markers.append({"pos": p.ball_pos, "name": p.name, "index": i})
	return markers


# Turn order (Section 7): of the players still on the hole, the one
# furthest from the pin plays next — real golf etiquette, and it keeps
# everyone's downtime short and even. Returns -1 when every player has
# holed out, which ends the hole.
func next_to_play() -> int:
	var best := -1
	var best_dist := -1.0
	for i in range(players.size()):
		var p: Player = players[i]
		if p.holed_out or p.abandoned:
			continue
		var d: float = p.distance_to(hole.pin_pos)
		if d > best_dist:
			best_dist = d
			best = i
	return best


# Hands the turn to whoever plays next. Returns false when the hole is
# over (everyone has holed out).
func advance_turn() -> bool:
	var next := next_to_play()
	if next < 0:
		return false
	var changed := next != active_index
	active_index = next
	if is_multiplayer() and changed:
		log_msg("\n[i]%s to play — %d yards from the pin.[/i]" % [
			me.name, int(me.distance_to(hole.pin_pos))])
	sync_map_to_active()
	return true


# Opens the click-to-aim step once a club is chosen: locks the crosshair's
# distance from the ball to that club's own yardage range (so you can't
# aim somewhere it can't reach) and defaults the target to the pin,
# clamped into that range — a player who doesn't bother re-aiming still
# gets a sane default. Moving the mouse over the map previews the crosshair
# live (see _on_aim_changed); a click commits immediately at that spot.
func begin_aim_for_shot() -> void:
	map_view.set_aiming(true, pending_club.min_yard, pending_club.max_yard, pending_club)
	map_view.set_aim_target(hole.pin_pos)
	# Compute the default aim from game data rather than reading back what
	# the view clamped — same answer, but the logic no longer depends on a
	# view having run first.
	aim_target = ShotResolver.clamp_aim(hole.pin_pos, ball_pos,
		float(pending_club.max_yard), hole.bounds)
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
	if state != State.AIM or is_cpu_turn():
		return
	aim_target = target
	rebuild_shot_outlook()


# The player clicked to commit their aim — now draw the 3 Form cards for
# this swing.
func _on_aim_picked(target: Vector2) -> void:
	if state != State.AIM:
		_reject("aim", "not in the aim phase")
		return
	if pending_club.is_empty():
		_reject("aim", "no club selected")
		return
	# Re-clamp here rather than trusting the incoming point. Locally this
	# is a no-op (the crosshair was already clamped by the same function),
	# but it means the rule is enforced by the game rather than by the
	# view that happened to draw it — so an aim arriving from anywhere
	# else is held to the club's reach and the hole's bounds too.
	aim_target = ShotResolver.clamp_aim(target, ball_pos,
		float(pending_club.max_yard), hole.bounds)
	begin_form_draw()


# Which swing tier the declared shot represents (Section 4 "Club
# suitability") — see ShotRules.swing_tier().
func swing_tier_for_shot() -> int:
	return ShotRules.swing_tier(hand, pending_club, ball_pos.distance_to(aim_target), me.armed)


# The lie the club in hand plays from: the real one, unless a club's
# ability plays it clean from rough or sand (ClubAbilities.plays_clean).
# Once the draw is made that decision is held on the shot ("clean_lie"),
# since a once-per-hole charge reads as spent from then on.
func play_lie() -> String:
	if me.armed.has("clean_lie") or clean_lie_ability() != "":
		return "fairway"
	return current_lie


func clean_lie_ability() -> String:
	return ClubAbilities.plays_clean(hand, pending_club, current_lie,
		me.ability_log, current_hole_index)


# Everything ClubAbilities.actives() needs to know about this moment.
func ability_context() -> Dictionary:
	return {
		"lie": current_lie, "club": pending_club, "forced": current_form_forced,
		"options": current_form_options, "armed": me.armed,
		"charges": me.ability_log, "hole": current_hole_index,
	}


# The phase name ClubAbilities.actives() takes, or "" when no ability
# can be used.
func ability_phase() -> String:
	match state:
		State.CLUB_SELECT:
			return "club_select"
		State.AIM:
			return "aim"
		State.FORM_DRAW:
			return "form"
		State.PUTTING:
			return "putting"
	return ""


func available_abilities() -> Array:
	var phase := ability_phase()
	if phase == "":
		return []
	return ClubAbilities.actives(hand, phase, ability_context())


func begin_form_draw() -> void:
	# A club playing clean from a bad lie spends its charge now, at the
	# moment it changes the draw.
	var clean := clean_lie_ability()
	var lie := play_lie()
	if clean == "utility_any_lie":
		ClubAbilities.record(me.ability_log, clean, current_hole_index)
	if clean != "":
		me.armed["clean_lie"] = true
		log_msg("[i]%s plays from the %s as though from the fairway.[/i]" % [pending_club.name, current_lie])
	for id in ["boost_tier", "ideal_club"]:
		if me.armed.has(id):
			ClubAbilities.record(me.ability_log, id, current_hole_index)

	# Created cards waiting from the last landing, plus any the club
	# brings to its own draw.
	var created: Array = me.created_next + ClubAbilities.draw_extras(pending_club, current_lie)
	me.created_next = []
	var result := ShotRules.draw_form(form_deck, hand, pending_club,
		ball_pos.distance_to(aim_target), lie, me.armed, created)
	var tier: int = result.tier
	current_form_options = result.cards
	current_form_forced = result.forced

	if current_form_forced:
		var reason := "playing from the sand" if result.from_lie else "below this club's range"
		log_msg("\n[b]Playing %s[/b] (%s) — %s creates a bad Form card. No choice, you're forced to play it." % [
			pending_club.name, ShotResolver.tier_name(tier), reason.capitalize()])
	elif result.had_forced_card:
		log_msg("\n[b]Playing %s[/b] (%s) — a bad Form card is forced on you, but you hold %s instead." % [
			pending_club.name, ShotResolver.tier_name(tier), " and ".join(PackedStringArray(created))])
	else:
		log_msg("\n[b]Playing %s[/b] (%s) — drawing %d Form card%s." % [
			pending_club.name, ShotResolver.tier_name(tier), current_form_options.size(),
			"" if current_form_options.size() == 1 else "s"])
		if not created.is_empty():
			log_msg("[i]Created for this draw: %s.[/i]" % ", ".join(PackedStringArray(created)))
	state = State.FORM_DRAW
	Sound.play("card_draw")
	caddy_says("form_draw", {"forced": current_form_forced})
	refresh_ui()


# --- Draft phase: draw 3, pick 1, permanently into hand ---
func begin_draft_phase() -> void:
	state = State.DRAFT
	if not _draw_draft_options():
		# Nothing left to offer at all — skip the draft and move on, so the
		# round can still finish instead of stalling on an empty pick.
		log_msg("[i]The club deck is exhausted — no draft this hole.[/i]")
		begin_next_draft()
		return
	Sound.play("card_draw")
	refresh_ui()


# Deals the active player's three draft options. False if their club deck
# has nothing left to offer.
func _draw_draft_options() -> bool:
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
	return not current_draft_options.is_empty()


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


# --- Action validation -------------------------------------------------
# The six entry points below are the only way a player action enters the
# game. They used to trust their arguments completely, which was fine
# while the only caller was this machine's own UI. Once an action can
# arrive from another peer (online play), an out-of-range index is a crash
# and an out-of-turn action is a desync, so each one validates first and
# refuses rather than acting.
#
# Refusals are logged to the console, not the in-game log: a rejected
# action is a bug or a bad actor, not something the player did.
# Returns the next pre-decided result if one is queued, otherwise calls
# `generate` and (when recording) notes what came out. `kind` is only for
# diagnostics — a mismatch between what was injected and what the logic
# asks for is a desync bug, and naming the roll makes it findable.
func _roll(kind: String, generate: Callable) -> Variant:
	if not _injected_rolls.is_empty():
		var entry = _injected_rolls.pop_front()
		if entry is Dictionary and entry.get("kind", kind) != kind:
			push_warning("Pars and Chars: roll order mismatch — expected '%s', got '%s'" % [
				kind, entry.get("kind", "?")])
		return entry.value if entry is Dictionary else entry
	var value = generate.call()
	if _recording_rolls:
		_consumed_rolls.append({"kind": kind, "value": value})
	return value


# Clears the roll ledger at the start of an action whose results need
# sending. Called by whichever machine owns the randomness.
func begin_roll_capture() -> void:
	_consumed_rolls = []
	_recording_rolls = true


# The rolls generated since begin_roll_capture(), ready to hand to another
# machine so it can reproduce this action exactly.
func take_captured_rolls() -> Array:
	_recording_rolls = false
	return _consumed_rolls.duplicate(true)


# Queues results decided elsewhere, to be consumed by the next action's
# _roll() calls in this same order.
func inject_rolls(rolls: Array) -> void:
	_injected_rolls = rolls.duplicate(true)


# UI entry points. These exist so the widgets don't need to know whether
# the round is local or online — they report what the player did, and
# submit() decides whether that goes straight into the game or to the host.
func _on_aim_committed(target: Vector2) -> void:
	submit("aim", {"target": target})


func _on_putt_meter_stopped(result: String, accuracy: float) -> void:
	submit("putt", {"result": result, "accuracy": accuracy})


# --- Online authority --------------------------------------------------
# Whether this machine may act for the seat currently up.
#
# Local rounds: always, because one shared screen means whoever is sitting
# at it is whoever is up — that is the whole premise of hot-seat.
# Online rounds: only your own seat, and only when it is your turn.
const HOST_PEER_ID := 1

# peer id -> seat, recorded as peers arrive.
#
# This has to be remembered rather than derived: by the time a peer
# DISCONNECTS it is already gone from multiplayer.get_peers(), so looking
# its seat up from the live peer list would fail for exactly the case
# that needs it most — retiring the seat of someone who just left.
var _peer_seats: Dictionary = {}


# Which seat a peer controls. The lobby's table is the real answer when
# there is one; otherwise the local record built as peers connected.
func seat_of_peer(peer_id: int) -> int:
	if peer_id == HOST_PEER_ID:
		return 0
	if Net.is_online() and Net.seated_count() > 0:
		var seat := Net.seat_of_peer(peer_id)
		if seat >= 0:
			return seat
	return int(_peer_seats.get(peer_id, -1))


# Assigns the next free seat to a newly connected peer, in arrival order,
# with the host holding seat 0.
func _on_peer_joined(peer_id: int) -> void:
	if _peer_seats.has(peer_id):
		return
	var taken := {0: true}
	for pid in _peer_seats:
		taken[int(_peer_seats[pid])] = true
	for seat in range(1, players.size()):
		if not taken.has(seat):
			_peer_seats[peer_id] = seat
			return


func is_my_turn() -> bool:
	if not online:
		return true
	if _simul_draft:
		return owes_draft(my_seat)
	return active_index == my_seat


# True when this machine decides outcomes. The host is also a player, so
# it runs the game exactly as a solo round does and additionally tells
# everyone else what happened.
#
# Asks THIS node's multiplayer API rather than the Net autoload, so a
# Main is authoritative with respect to whatever connection it sits
# under. That keeps the game decoupled from the single global connection
# and is what lets a host and a client run side by side in one process
# for testing.
func is_authority() -> bool:
	if not online:
		return true
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func _reject(what: String, why: String) -> void:
	push_warning("Pars and Chars: refused %s — %s" % [what, why])


# True when `index` is a valid position in `arr`.
func _valid_index(index: int, arr: Array) -> bool:
	return index >= 0 and index < arr.size()


func on_draft_pick(index: int) -> void:
	if state != State.DRAFT:
		_reject("draft pick", "not in the draft phase")
		return
	if not _valid_index(index, current_draft_options):
		_reject("draft pick", "index %d outside 0..%d" % [
			index, current_draft_options.size() - 1])
		return
	var card: Dictionary = current_draft_options[index]
	Sound.play("card_place")
	for i in range(current_draft_options.size()):
		if i != index:
			club_discard.append(current_draft_options[i])

	if hand.size() >= HAND_CAP:
		pending_new_card = card
		log_msg("Hand is full (%d cards) — discard one to make room for [b]%s[/b]." % [HAND_CAP, card.name])
		state = State.DISCARD_FOR_DRAFT
	else:
		hand.append(card)
		sort_hand()
		log_msg("Added [b]%s[/b] to your hand." % card.name)
		begin_next_draft()
	refresh_ui()


# --- Discard flow (shared by draft-cap and hazard-cap cases) ---
func on_discard_pick(index: int) -> void:
	if state != State.DISCARD_FOR_DRAFT and state != State.DISCARD_FOR_HAZARD:
		_reject("discard pick", "not in a discard phase")
		return
	if not _valid_index(index, hand):
		_reject("discard pick", "index %d outside 0..%d" % [index, hand.size() - 1])
		return
	if pending_new_card == null:
		# Nothing is waiting to come in, so discarding would shrink the bag
		# with no replacement.
		_reject("discard pick", "no incoming card to make room for")
		return
	var removed = hand.pop_at(index)
	Sound.play("card_discard")
	log_msg("Discarded %s." % removed.name)
	hand.append(pending_new_card)
	sort_hand()
	log_msg("Added [b]%s[/b] to your hand." % pending_new_card.name)
	pending_new_card = null
	if removed.get("brand", Brands.NONE) == Brands.STARTER:
		mark_starter_retired()

	if state == State.DISCARD_FOR_DRAFT:
		begin_next_draft()
	else:
		# was DISCARD_FOR_HAZARD -> shot already resolved, move on
		advance_after_shot()
	refresh_ui()


# --- Club abilities and set powers (ClubAbilities.gd) ---
# One entry point for every activated ability. Toggles arm an effect for
# the shot or putt in hand and are charged once it's used; everything else
# is charged and applied now.
func on_ability(id: String) -> void:
	if _animating:
		_reject("ability", "a shot is in flight")
		return
	var entry := {}
	for e in available_abilities():
		if e.id == id:
			entry = e
	if entry.is_empty():
		_reject("ability", "'%s' isn't available now" % id)
		return

	if entry.toggle:
		if me.armed.has(id):
			me.armed.erase(id)
			log_msg("[i]%s — switched off.[/i]" % entry.source)
		else:
			me.armed[id] = true
			log_msg("[color=#%s]%s — %s.[/color]" % [COLOR_ACCENT.to_html(false), entry.source, entry.label.to_lower()])
		Sound.play("card_slide")
		refresh_ui()
		return

	ClubAbilities.record(me.ability_log, id, current_hole_index)
	match id:
		"gold_cleek", "bulger":
			var card := FormCard.make(ClubAbilities.creates(id)).as_created()
			current_form_options.append(card)
			# A created card is always a real choice, even beside a forced one.
			current_form_forced = false
			log_msg("[color=#%s]%s — creates a %s in your hand. It exhausts whether you play it or not.[/color]" % [
				COLOR_ACCENT.to_html(false), entry.source, card.name])
		"redraw":
			var kept: Array = []
			var drawn: Array = []
			for c in current_form_options:
				if c.created:
					kept.append(c)
				else:
					drawn.append(c)
			form_deck.return_unpicked(drawn, -1)
			current_form_options = form_deck.draw_cards(drawn.size(),
				FormCard.family_of(pending_club)) + kept
			log_msg("[color=#%s]%s — the whole hand goes back; %d fresh card%s.[/color]" % [
				COLOR_ACCENT.to_html(false), entry.source, drawn.size(), "" if drawn.size() == 1 else "s"])
		"improve_lie":
			var was := current_lie
			current_lie = ClubAbilities.lie_improved(current_lie)
			log_msg("[color=#%s]%s — the lie improves from %s to %s.[/color]" % [
				COLOR_ACCENT.to_html(false), entry.source, was, current_lie])
	Sound.play("card_draw")
	refresh_ui()


# End of hole: skip the draft to purge bad cards from the Form deck — the
# way back from a run of bad holes (Section 4 "range session").
func on_range_session() -> void:
	if state != State.DRAFT:
		_reject("range session", "not in the draft phase")
		return
	if form_deck.bad_count() == 0:
		_reject("range session", "no bad cards to work out")
		return
	club_discard.append_array(current_draft_options)
	current_draft_options = []
	var purged := form_deck.purge_bad(ShotRules.RANGE_SESSION_PURGE)
	Sound.play("card_discard")
	log_msg("[color=#%s]Range session — no club this hole, but %s leave%s your Form deck.[/color]" % [
		COLOR_ACCENT.to_html(false), " and ".join(PackedStringArray(purged)), "s" if purged.size() == 1 else ""])
	begin_next_draft()
	refresh_ui()


# --- Club select -> aim (crosshair, locked to the club's range) -> Form draw -> pick -> resolve ---
func on_club_select(hand_index: int) -> void:
	if state != State.CLUB_SELECT:
		_reject("club select", "not in the club-select phase")
		return
	if not _valid_index(hand_index, hand):
		_reject("club select", "index %d outside 0..%d" % [hand_index, hand.size() - 1])
		return
	if not ShotRules.club_playable(hand, hand[hand_index], current_lie):
		# The bag row already greys these out; this stops one arriving
		# from another peer.
		_reject("club select", "%s can't be played from the %s" % [hand[hand_index].name, current_lie])
		return
	pending_club = hand[hand_index]
	Sound.play("card_slide")
	begin_aim_for_shot()


# The player picked one of the 3 drawn Form cards. Its effect is now fully
# known (Section 4 step 3) — resolve immediately using the aim already
# confirmed before the draw. There is no further "final aim adjustment"
# input beyond that confirmed aim in this prototype pass; the confirmed
# aim *is* the aim the player commits to knowing the card's effect (they
# saw all 3 cards before choosing, so the choice among them already
# encodes their read).
func on_form_pick(index: int) -> void:
	if state != State.FORM_DRAW:
		_reject("form pick", "not in the Form-draw phase")
		return
	if not _valid_index(index, current_form_options):
		_reject("form pick", "index %d outside 0..%d" % [
			index, current_form_options.size() - 1])
		return
	if pending_club.is_empty():
		# play_shot() needs the club this draw was made for.
		_reject("form pick", "no club selected for this shot")
		return
	var card: FormCard = current_form_options[index]
	form_deck.return_unpicked(current_form_options, index)
	# The played card cycles too; only a created one exhausts.
	form_deck.discard_played(card)
	current_form_options = []
	current_form_forced = false
	Sound.play("card_place")
	play_shot(pending_club, card)


func play_shot(club: Dictionary, card: FormCard) -> void:
	match ShotRules.yips_effect(hand, card):
		ShotRules.Yips.BLOCKED:
			log_msg("[color=#%s]Yips — shrugged off (Callowell).[/color]" % COLOR_TEXT_SOFT.to_html(false))
		ShotRules.Yips.TAINTS_PUTT:
			log_msg("[color=#%s]Yips! Taints your next putt if you're forced to play it near the green.[/color]" % COLOR_FLAG.to_html(false))
			yips_pending = true
			Sound.play("ui_error")
			caddy_says("yips")

	var aimed_distance: float = ball_pos.distance_to(aim_target)
	var result := ShotRules.resolve(hand, club, aimed_distance, play_lie(), card, me.armed)
	# The shot's toggles are spent (charged when the draw was made).
	for id in ["boost_tier", "ideal_club", "clean_lie"]:
		me.armed.erase(id)

	strokes += 1
	var before_pos := ball_pos
	_caddy_card = card.name

	log_msg("[b]Stroke %d[/b] — played %s with %s (lie: %s)" % [strokes, card.name, club.name, current_lie])
	log_msg("%s: %s" % [card.name, card.effect_text()])
	if card.created:
		log_msg("[i]%s was created by a club — it exhausts now it's played.[/i]" % card.name)
	if card.purges_bad > 0:
		# The family it was played from first: a good swing with the driver
		# mends the driver.
		var purged := form_deck.purge_bad(card.purges_bad, FormCard.family_of(club))
		if not purged.is_empty():
			log_msg("[color=#%s]In the Zone — a %s card leaves your Form deck.[/color]" % [
				COLOR_ACCENT.to_html(false), ", ".join(PackedStringArray(purged))])

	pending_club = {}
	_animating = true
	clear_container(options_container)
	clear_container(ability_box)
	Sound.swing(club.type)

	var aim_dir := ShotRules.aim_direction(before_pos, aim_target, hole.pin_pos)

	# Carry and run-out, decided now from the ground — the animation plays
	# out exactly this, and the landing below acts on exactly this.
	var outcome := ShotResolver.shot_outcome(hole, before_pos, aim_dir, result, club)

	map_view.play_aim_animation(aim_dir, outcome.carry, float(result.degree), result.side, club.max_yard, func():
		_resolve_shot_landing(before_pos, aim_dir, result, outcome, club)
	, outcome.roll_path, ShotResolver.flight_height(club, result))


func _resolve_shot_landing(before_pos: Vector2, aim_dir: Vector2, result: Dictionary,
		outcome: Dictionary, club: Dictionary = {}) -> void:
	_animating = false
	# A peer may have dropped mid-flight; it is safe to act on that now
	# that this closure has finished writing through `me`.
	if not _pending_drops.is_empty():
		call_deferred("_drain_pending_drops")

	# Shared with the Form-card landing preview — see
	# ShotResolver.shot_outcome(). From here on "landing" means where the
	# ball comes to rest, roll included.
	var landing_pos: Vector2 = outcome.rest
	var rolled: float = outcome.carry_pos.distance_to(landing_pos)

	var lie_result := hole.terrain_at(landing_pos)
	if rolled >= 1.0:
		log_msg("Carried %d yards, rolled %d -> finished in %s, %d yards from the pin." % [
			int(round(outcome.carry)), int(round(rolled)), lie_result,
			int(landing_pos.distance_to(hole.pin_pos))])
	else:
		log_msg("Carried %d yards -> landed in %s, %d yards from the pin." % [
			int(round(outcome.carry)), lie_result, int(landing_pos.distance_to(hole.pin_pos))])
	# What the wind and the ground did to it, kept on the shot panel until
	# the next shot so the player can read it while choosing the next club.
	if not club.is_empty():
		var breakdown := ShotRules.shot_breakdown(hole, before_pos, aim_dir, result, club, outcome)
		me.last_shot = {"club": club.name, "text": ShotRules.breakdown_text(breakdown)}
		log_msg("[color=#%s]%s[/color]" % [COLOR_TEXT_SOFT.to_html(false), me.last_shot.text])

	# A shot that finishes on the cup earns a d20, and only a natural 20
	# actually drops (see ShotResolver — the aim and the card are fully
	# visible, so the die is the one thing a player cannot read off the
	# table). Checked before terrain is applied, because sitting on the cup
	# outranks whatever the ball was flying over.
	#
	# Anything short of 20 still rattles the hole and finishes stone dead —
	# you keep the reward for a perfect shot, you just have to tap it in.
	if outcome.cup:
		var roll: int = _roll("d20", func(): return ShotResolver.roll_for_hole_out())
		if roll >= ShotResolver.HOLE_OUT_TARGET:
			ball_pos = hole.pin_pos
			current_lie = "green"
			shot_path.append(ball_pos)
			map_view.set_ball(ball_pos, shot_path)
			map_view.set_aim_target(ball_pos)
			log_msg("[color=#%s][b]d20: %d — IN THE HOLE, from %d yards![/b][/color]" % [
				COLOR_ACCENT.to_html(false), roll, int(before_pos.distance_to(hole.pin_pos))])
			map_view.drop_in_cup()
			caddy_says("hole_out", {"strokes": strokes})
			finish_hole(int(before_pos.distance_to(hole.pin_pos)))
			return
		# Rimmed out, leaving a short putt to actually play — see
		# ShotRules.rim_out_position() for why it's never a gimme.
		log_msg("[color=#%s]d20: %d — rattles the cup and stays out.[/color]" % [
			COLOR_FLAG.to_html(false), roll])
		Sound.play("rim_out")
		caddy_says("rim_out")
		ball_pos = ShotRules.rim_out_position(hole.pin_pos, landing_pos, roll)
		current_lie = "green"
		shot_path.append(ball_pos)
		map_view.set_ball(ball_pos, shot_path)
		map_view.set_aim_target(ball_pos)
		advance_after_shot()
		return

	# Penalties, drops and lie changes — see ShotRules.settle().
	var settled := ShotRules.settle(hole, before_pos, landing_pos, result.downgrades_lie, hand, club)
	strokes += int(settled.penalty)
	ball_pos = settled.ball_pos
	current_lie = settled.lie
	match lie_result:
		"out":
			log_msg("[color=#%s]Out of bounds! +1 penalty stroke, replayed from your previous position.[/color]" % COLOR_FLAG.to_html(false))
		"water":
			log_msg("[color=#%s]Splash! Water hazard — +1 penalty stroke, dropped back near your previous position.[/color]" % COLOR_WATER.to_html(false))
		"bunker":
			log_msg("[color=#%s]In the sand.[/color]" % COLOR_SAND.to_html(false))
	if settled.lie_downgraded:
		log_msg("[color=#%s]Shank — lie downgraded to %s.[/color]" % [COLOR_FLAG.to_html(false), current_lie])
	if lie_result == "rough" and current_lie == "green":
		log_msg("[i]On the fringe — the Jigger putts it from here.[/i]")
	var hazard_hit: bool = settled.hazard

	# (The sound of the landing is the map's: it plays it as the ball
	# touches down, not here once it has stopped.)
	shot_path.append(ball_pos)
	map_view.set_ball(ball_pos, shot_path)
	# Clears the just-played aim line — otherwise the old target (now stale,
	# from wherever the previous shot was aimed) keeps drawing next to the
	# ball's new position until the player starts aiming again.
	map_view.set_aim_target(ball_pos)

	# A hazard, or just the rough: either can leave a bad card behind.
	if float(settled.form_risk) > 0.0:
		maybe_add_bad_card_to_form_deck(lie_result, float(settled.form_risk),
			FormCard.family_of(club) if not club.is_empty() else "")
	apply_landing_abilities(lie_result, hazard_hit)
	caddy_says("landing", {"terrain": lie_result, "card": _caddy_card, "carry": outcome.carry,
		"distance_cap": ShotRules.lie_distance_cap(hand, current_lie)})

	advance_after_shot()


# The bag's passives once a shot has settled (ClubAbilities.on_landing):
# cards created for the next draw, and bad cards purged. Runs after Form
# decay so a purge can take back the card a hazard just added.
func apply_landing_abilities(terrain: String, hazard: bool) -> void:
	var fx := ClubAbilities.on_landing(hand, terrain, hazard, me.ability_log, current_hole_index)
	for id in fx.used:
		ClubAbilities.record(me.ability_log, id, current_hole_index)
	var by := ", ".join(PackedStringArray(fx.by))
	if not fx.create.is_empty():
		me.created_next.append_array(fx.create)
		log_msg("[color=#%s]%s — your next draw includes %s.[/color]" % [
			COLOR_ACCENT.to_html(false), by, " and ".join(PackedStringArray(fx.create))])
	if fx.purge > 0:
		var purged := form_deck.purge_bad(fx.purge)
		if not purged.is_empty():
			log_msg("[color=#%s]%s — purged %s from your Form deck.[/color]" % [
				COLOR_ACCENT.to_html(false), by, ", ".join(PackedStringArray(purged))])


# Section 5 "Bad cards from hazards": landing in rough/bunker/water carries
# a chance of adding a bad Form card into the shared Form deck (not the
# Bag) — degrading future draws for the rest of the round. `chance` is
# ShotRules.settle()'s form_risk: a third for a hazard, a fifth for rough.
# The card joins `family` — the family of the club that found the trouble
# — and is one of that family's own misses (Section 4 "Form by club
# family"), so a wild driver leaves the wedges alone.
func maybe_add_bad_card_to_form_deck(lie_result: String, chance: float, family: String = "") -> void:
	if not ShotRules.hazard_can_decay_form(hand):
		return
	if _roll("decay_chance", func(): return randf()) < chance:
		# Which bad card it is also has to match across machines, so pick
		# the name here (add_bad_card_to_deck already takes one) rather
		# than letting the deck roll it internally.
		var pool: Array = FormCard.bad_names_for(family)
		var bad_name: String = _roll("decay_card", func():
			return pool[randi_range(0, pool.size() - 1)])
		var card := form_deck.add_bad_card_to_deck(bad_name, family)
		Sound.play("ui_error")
		log_msg("[color=#%s](The %s left a %s card in your %s form.)[/color]" % [
			COLOR_TEXT_SOFT.to_html(false), lie_result, card.name,
			FormCard.FAMILY_LABEL.get(card.family, "")])
		caddy_says("bad_card")


# Called when the active player's shot is fully resolved and they are still
# on the hole. In multiplayer the turn now passes to whoever is furthest
# from the pin, which may well be this same player again.
func advance_after_shot() -> void:
	# Hand over to whoever is now furthest from the pin. In a solo round
	# this is always the same player; in a group round it can also land
	# back on the player who just played, if they are still furthest out.
	if is_multiplayer() and not advance_turn():
		# Unreachable while this player is still on the hole, but end the
		# hole rather than stall if it ever happens.
		begin_end_of_hole()
		return

	# Everything below reads through to whoever is active NOW, so the green
	# check applies to the player about to play, not the one who just did.
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

	# The same gimme on_putt_stopped() applies, enforced on arrival too: a
	# shot can now finish inside tap-in range without ever going through
	# the putt meter (a rattled hole-out does exactly that), and asking for
	# a timing check on a 2-foot putt the game concedes everywhere else
	# would be a check the player cannot meaningfully fail.
	if ShotRules.is_gimme(putt_dist):
		strokes += 1
		putt_dist = 0.0
		sync_ball_to_putt()
		log_msg("[color=#%s]Tap-in conceded.[/color]" % COLOR_TEXT_SOFT.to_html(false))
		finish_hole()
		return
	log_msg("\n[b]On the green.[/b] %s to the pin — stop the marker in the green band to hole it." % putt_distance_text())
	caddy_says("putt", {"dist": putt_dist, "dist_text": putt_distance_text()})
	refresh_ui()


func putt_distance_text() -> String:
	# Under a few yards it reads more naturally in feet, the way a golfer
	# would actually call a short putt.
	if putt_dist < 4.0:
		return "%d ft" % maxi(1, int(round(putt_dist * 3.0)))
	return "%d yds" % int(round(putt_dist))


func on_putt_stopped(result: String, accuracy: float) -> void:
	if state != State.PUTTING:
		_reject("putt result", "not in the putting phase")
		return
	if result != "sunk" and result != "close" and result != "miss":
		_reject("putt result", "unknown result '%s'" % result)
		return
	# Accuracy scales a miss's leave distance, so an out-of-range value
	# would throw the ball to a nonsense spot rather than crash. Clamp it
	# to the 0..1 the meter is documented to emit.
	accuracy = clampf(accuracy, 0.0, 1.0)

	# The Titanist Blade Putter: a putt that stays out is taken again, no
	# stroke added. Covers a Yips-tainted putt too — that's the mulligan.
	if me.armed.has("putt_retry") and (result != "sunk" or yips_pending):
		me.armed.erase("putt_retry")
		ClubAbilities.record(me.ability_log, "putt_retry", current_hole_index)
		if yips_pending:
			yips_pending = false
			log_msg("[color=#%s]The Yips strike — but the Blade Putter takes it again.[/color]" % COLOR_TEXT_SOFT.to_html(false))
		else:
			log_msg("[color=#%s]Missed — the Blade Putter takes it again, no stroke added.[/color]" % COLOR_TEXT_SOFT.to_html(false))
		Sound.play("rim_out")
		refresh_ui()
		return

	strokes += 1
	# Steady Hands is spent on the putt that actually counts.
	if me.armed.has("old_reliable"):
		me.armed.erase("old_reliable")
		ClubAbilities.record(me.ability_log, "old_reliable", current_hole_index)
		log_msg("[i]Steady Hands (Old Reliable Putter).[/i]")

	if yips_pending:
		yips_pending = false
		log_msg("[color=#%s]The Yips strike — the putt misses regardless of how well you struck it.[/color]" % COLOR_FLAG.to_html(false))
		Sound.play("ui_error")
		putt_dist = ShotRules.yips_putt_leave(putt_dist)
		sync_ball_to_putt(_roll("putt_offline_yips", func(): return randf_range(-0.8, 0.8)))
		continue_after_putt()
		return

	match result:
		"sunk":
			log_msg("[color=#%s]Dead centre — in the hole![/color]" % COLOR_ACCENT.to_html(false))
			putt_dist = 0.0
			sync_ball_to_putt()
			finish_hole()
			return
		"close":
			# A good-but-not-perfect strike leaves a short one.
			putt_dist = ShotRules.putt_leave(result, accuracy, putt_dist)
			sync_ball_to_putt(_roll("putt_offline_close", func(): return randf_range(-0.5, 0.5)))
			log_msg("Good pace — slides by, leaving %s." % putt_distance_text())
		_:
			# Capped at the distance it came from, so a putt can never get
			# longer — the sequence always walks toward the hole.
			putt_dist = ShotRules.putt_leave(result, accuracy, putt_dist)
			sync_ball_to_putt(_roll("putt_offline_miss", func(): return randf_range(-1.2, 1.2)))
			log_msg("[color=#%s]Mishit — pushed off line, %s left.[/color]" % [
				COLOR_FLAG.to_html(false), putt_distance_text()])

	# The gimme: once you're inside tap-in range there's no drama left to
	# play for, so it's conceded rather than asking for another timing check
	# the player cannot meaningfully fail. Also guarantees the putting loop
	# terminates instead of grinding on a very short putt forever.
	if ShotRules.is_gimme(putt_dist):
		strokes += 1
		putt_dist = 0.0
		sync_ball_to_putt()
		log_msg("[color=#%s]Tap-in conceded.[/color]" % COLOR_TEXT_SOFT.to_html(false))
		finish_hole()
		return

	caddy_says("putt_result", {"result": result})
	continue_after_putt()


# The ball is still out of the hole after a putt. In a solo round that just
# means putting again; in a group round the turn passes, since a player who
# has left themselves 8 yards is no longer the one furthest from the pin.
#
# "Furthest plays first" is applied to putting too rather than letting a
# player hole out continuously — that's the order Section 7 specifies, and
# it also stops one player sinking a long sequence of putts while the
# others sit watching.
func continue_after_putt() -> void:
	if is_multiplayer() and not advance_turn():
		begin_end_of_hole()
		return
	# Reads through to whoever is active now: still on the green means the
	# putt meter, otherwise they are playing a normal shot.
	if current_lie == "green":
		state = State.PUTTING
		# Re-derive the putt for the player now up, so the meter's
		# difficulty matches THEIR distance rather than the last player's.
		putt_dist = ball_pos.distance_to(hole.pin_pos)
		_putt_dir = (ball_pos - hole.pin_pos).normalized()
		if _putt_dir == Vector2.ZERO:
			_putt_dir = Vector2(0, 1)
	else:
		state = State.CLUB_SELECT
	refresh_ui()


# Moves the ball on the map to match the current putt distance. Each miss
# leaves it a little offline rather than perfectly pin-high, so the trail
# reads like a real putt that slid past instead of a number shrinking.
func sync_ball_to_putt(offline: float = 0.0) -> void:
	# A missed putt finishes on the green's low side. The size of the miss
	# is still the rolled amount; only its side comes from the slope.
	var fall: float = ShotResolver.putt_read(hole, ball_pos).fall
	if absf(fall) >= ShotResolver.PUTT_FLAT:
		offline = absf(offline) * signf(fall)
	var dir := _putt_dir.rotated(offline)
	var rolled_from := ball_pos
	ball_pos = hole.pin_pos + dir * putt_dist
	shot_path.append(ball_pos)
	if map_view:
		map_view.set_ball(ball_pos, shot_path)
		map_view.set_aim_target(ball_pos)
		# The map shows it rolling there — and dropping, if it's in.
		map_view.play_putt(rolled_from, ball_pos, putt_dist == 0.0)


# Builds the putt meter plus its strike button into the options row, and
# starts the marker sweeping for the current distance. Called on every
# refresh while putting, since refresh_ui() clears the container.
func build_putt_controls() -> void:
	# The meter needs an explicit width — it has to be wide to be readable,
	# since on a long putt the sunk band is only a few percent of it.
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(METER_WIDTH, 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 10)

	# The read: which way it breaks and how quick it is, in words, above
	# the meter that shows it in numbers.
	var read := ShotResolver.putt_read(hole, ball_pos)
	var read_label := Label.new()
	read_label.text = ShotResolver.putt_read_text(read)
	BogeyUI.set_font(read_label, BogeyUI.serif_italic(500), 19, BogeyTheme.INK)
	read_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(read_label)

	putt_meter = PuttMeter.new()
	putt_meter.custom_minimum_size = Vector2(METER_WIDTH, 0)
	putt_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	putt_meter.stopped.connect(_on_putt_meter_stopped)
	col.add_child(putt_meter)

	var strike_btn := Button.new()
	strike_btn.text = "Strike  (%s)" % Settings.putt_key_name()
	strike_btn.custom_minimum_size = Vector2(0, 44)
	BogeyUI.style_button(strike_btn, true, 15)
	strike_btn.pressed.connect(_on_strike_pressed)
	if is_cpu_turn():
		strike_btn.text = "%s is over the putt…" % me.name
		strike_btn.disabled = true
	col.add_child(strike_btn)

	options_container.add_child(col)
	putt_meter.begin(putt_dist, read.shift,
		read.band_mult * ShotRules.putt_band_mult(hand, putt_dist, me.armed))


func _on_strike_pressed() -> void:
	if is_cpu_turn():
		return
	if putt_meter and putt_meter.active:
		Sound.play("putt")
		putt_meter.stop_putt()


# Space bar is the natural input for a timing check — the button stays for
# mouse players, but nobody should have to chase a cursor to hit a beat.
func _unhandled_key_input(event: InputEvent) -> void:
	if state != State.PUTTING:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == Settings.putt_key():
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


# --- Computer golfers --------------------------------------------------
# A seat in `_bots` is played by GreedyBot through the same functions the
# UI calls for a person (on_club_select, _on_aim_picked, on_form_pick…),
# one action at a time, with a pause before each so the round can be
# followed: club, line, the Form hand, the card it keeps, then the shot.
#
# Driven by polling rather than by chaining callbacks. Every frame asks
# one question — is it a computer golfer's move, with nothing in flight? —
# so it cannot be left waiting on a signal that a restart, a dropped
# animation or an unusual turn order never sends.

# Seconds before each kind of action, at cpu_pace 1.
const CPU_BEAT := {
	State.CLUB_SELECT: 0.7,
	State.AIM: 0.8,
	State.FORM_DRAW: 1.1,
	State.PUTTING: 1.0,
	State.DRAFT: 1.1,
	State.DISCARD_FOR_DRAFT: 0.9,
	State.DISCARD_FOR_HAZARD: 0.9,
}
# How long the card it has settled on stays lit before it's played.
const CPU_SHOW_PICK := 0.75
# What the step pill says a computer golfer is doing.
const CPU_DOING := {
	State.CLUB_SELECT: "choosing a club",
	State.AIM: "picking a line",
	State.FORM_DRAW: "reading the Form cards",
	State.PUTTING: "putting",
	State.DRAFT: "drafting a club",
	State.DISCARD_FOR_DRAFT: "making room in the bag",
	State.DISCARD_FOR_HAZARD: "making room in the bag",
}

var _cpu_form_pick: int = -1     # the Form card it has shown it will play; -1 = not decided


func _process(delta: float) -> void:
	if _bots.is_empty():
		return
	if _animating or not is_cpu_turn():
		_cpu_reset()
		return
	if not _cpu_beat:
		_cpu_beat = true
		_cpu_wait = cpu_delay(float(CPU_BEAT.get(state, 0.8)))
		_cpu_show_line()
		_cpu_think_ahead()
	_cpu_wait -= delta
	if _cpu_wait > 0.0 or _cpu_thinking():
		return
	_cpu_beat = false
	cpu_act()


# Choosing a shot is the one slow thing a computer golfer does (GreedyBot
# scores every club against a spread of aims — up to half a second), so
# it's worked out on a worker thread during the pause before the club is
# picked, rather than freezing the screen when the pause ends.
#
# The thread only reads the game. Nothing a person can press changes the
# game during a computer turn (submit() refuses), and the things that
# replace it wholesale — restart, the menu, quitting — wait for the thread
# first (_cpu_join), so it never reads a round that's being torn down.
func _cpu_think_ahead() -> void:
	if state != State.CLUB_SELECT or cpu_pace <= 0.0 or _cpu_task != -1:
		return
	var bot: GreedyBot = _bots.get(active_index)
	if bot == null or bot.will_improve_lie(self):
		return
	_cpu_task = WorkerThreadPool.add_task(bot.plan_shot.bind(self), false, "Computer golfer planning a shot")


# True while the plan is still being worked out.
func _cpu_thinking() -> bool:
	if _cpu_task == -1:
		return false
	if not WorkerThreadPool.is_task_completed(_cpu_task):
		return true
	_cpu_join()
	return false


# Waits for a plan in progress. Never long: the plan is a fraction of a second.
func _cpu_join() -> void:
	if _cpu_task != -1:
		WorkerThreadPool.wait_for_task_completion(_cpu_task)
		_cpu_task = -1


func _cpu_reset() -> void:
	_cpu_join()
	_cpu_beat = false
	_cpu_form_pick = -1


func _exit_tree() -> void:
	_cpu_join()


# A pause, scaled by the pace and the player's shot-speed setting — someone
# who has asked for fast or instant shots doesn't want to wait on a rival.
func cpu_delay(seconds: float) -> float:
	var k := cpu_pace
	if Settings.instant_shots():
		k *= 0.3
	else:
		k /= maxf(Settings.shot_speed_scale(), 0.01)
	return seconds * k


# While it lines up, draw where it means to aim.
func _cpu_show_line() -> void:
	if state != State.AIM or pending_club.is_empty() or cpu_pace <= 0.0:
		return
	var bot: GreedyBot = _bots.get(active_index)
	if bot == null:
		return
	aim_target = ShotResolver.clamp_aim(bot.planned_aim(hole.pin_pos), ball_pos,
		float(pending_club.max_yard), hole.bounds)
	map_view.set_aim_target(aim_target)
	# The whole strip, not just the outlook: the face-down Form slots show
	# how many cards this aim's swing tier will draw.
	refresh_ui()


# One action for the computer golfer whose move it is.
func cpu_act() -> void:
	var bot: GreedyBot = _bots.get(active_index)
	if bot == null:
		return
	match state:
		State.FORM_DRAW:
			if _cpu_form_pick >= 0:
				var pick := _cpu_form_pick
				_cpu_form_pick = -1
				on_form_pick(pick)
				return
			# An ability first, if it wants one (the hand is then redrawn
			# and it reads it again); otherwise the card it will keep.
			var choice := bot.form_step(self)
			if choice < 0:
				return
			if cpu_pace <= 0.0:
				on_form_pick(choice)
				return
			_cpu_form_pick = choice
			_cpu_beat = true
			_cpu_wait = cpu_delay(CPU_SHOW_PICK)
			_cpu_light_form_pick(choice)
		State.PUTTING:
			Sound.play("putt")
			bot.act(self)
		_:
			if not bot.act(self):
				push_warning("Computer golfer has no move in state %d on hole %d" % [
					state, current_hole_index])


# Dims the cards it passed over and lights the one it kept.
func _cpu_light_form_pick(index: int) -> void:
	if form_container == null:
		return
	var views := form_container.get_children()
	for i in range(views.size()):
		var v: Control = views[i]
		if not (v is FormCardView):
			continue
		# The same two states the bag uses for the club in hand.
		v.set_selected(i == index)
		v.set_dimmed(i != index)


# --- Marking the moment ------------------------------------------------

# Under-par holes in a row that earn a call-out.
const STREAK_CALL := 3


# How many holes in a row, up to and including the last one played, this
# player has finished under par.
func under_par_streak(p: Player) -> int:
	var n := 0
	for i in range(p.round_scores.size() - 1, -1, -1):
		var e: Dictionary = p.round_scores[i]
		if int(e.strokes) >= int(e.par):
			break
		n += 1
	return n


# The stamp for the hole the active player has just finished.
func show_hole_banner(diff: int, holed_from: int, streak: int) -> void:
	if not _can_stamp():
		return
	var kicker := "Hole %d" % current_hole_index
	if is_multiplayer():
		kicker = "%s · hole %d" % [me.name, current_hole_index]
	var detail := "%d on a par %d" % [strokes, hole_par]
	if holed_from >= 0 and strokes > 1:
		detail = "Holed from %d yards · %s" % [holed_from, detail]
	if streak >= STREAK_CALL:
		detail += " · %d under-par holes running" % streak
	# Worked out now, stamped when the ball has dropped: by then the turn
	# may have passed to someone else.
	var title := HoleBanner.result_title(diff, strokes)
	var tone := HoleBanner.result_tone(diff)
	_after_putt_drops(func(): hole_banner.stamp(title, kicker, detail, tone))


# Runs `then` once the putt that is still rolling on the map has dropped
# and had its beat — the fanfare shouldn't beat the ball to the hole. At
# once when nothing is rolling, which is always the case with animations
# off (CourseMapView.putt_beat()). Cosmetic only: no game state waits.
func _after_putt_drops(then: Callable) -> void:
	var beat: float = map_view.putt_beat() if map_view else 0.0
	if beat <= 0.0 or not is_inside_tree():
		then.call()
		return
	create_tween().tween_callback(then).set_delay(beat)


# The round's jingle. The round now ends on the last putt rather than on a
# draft pick after it, so the jingle has to wait its turn: for the putt to
# drop, then for the last hole's own jingle (the longest runs 1.3 s).
# At once in the flow harnesses, which run no frames for a tween to use.
const ROUND_JINGLE_GAP := 1.4

func _play_round_jingle() -> void:
	var play := func(): Sound.play("jingle_round", 0.0)
	if map_view == null or map_view.skip_animation or not is_inside_tree():
		play.call()
		return
	create_tween().tween_callback(play).set_delay(map_view.putt_beat() + ROUND_JINGLE_GAP)


# The flow harnesses run with no frames, so a tween would never finish.
func _can_stamp() -> bool:
	return hole_banner != null and map_view != null and not map_view.skip_animation


# Called when a Bogey-Mart club leaves the bag. Dropping the last of them
# is the run's first milestone (Section 3A, "Retiring the set").
func mark_starter_retired() -> void:
	for club in hand:
		if club.get("brand", Brands.NONE) == Brands.STARTER:
			return
	log_msg("[color=#%s][b]The last of the Bogey-Mart set is gone.[/b] Every club in %s bag is one you chose.[/color]" % [
		COLOR_ACCENT.to_html(false), possessive(me).to_lower()])
	Sound.play("ui_confirm")
	if _can_stamp():
		var kicker := "The bag" if not is_multiplayer() else "%s bag" % possessive(me)
		hole_banner.stamp("BOGEY-MART RETIRED", kicker, "Every club in it was chosen, not issued",
			HoleBanner.Tone.NOTE)
	if not is_cpu_seat(active_index):
		caddy_says("starter_retired", {}, true)


# --- The match ---------------------------------------------------------

# Who leads the round after the hole just finished, for the log:
# "You lead Dory Mulligan by 2." Empty in a solo round or before anyone
# has a score.
func lead_text() -> String:
	var ranked: Array = players.filter(func(p): return not p.abandoned and not p.round_scores.is_empty())
	if ranked.size() < 2:
		return ""
	ranked.sort_custom(func(a, b): return a.total_strokes() < b.total_strokes())
	var first: Player = ranked[0]
	var second: Player = ranked[1]
	var gap: int = second.total_strokes() - first.total_strokes()
	if gap == 0:
		var level: Array = ranked.filter(func(p): return p.total_strokes() == first.total_strokes())
		if level.size() == ranked.size():
			return "All square."
		return "%s share the lead." % " and ".join(PackedStringArray(level.map(func(p): return p.name)))
	var behind := "" if ranked.size() > 2 else " %s" % ("you" if second.name == "You" else second.name)
	return "%s %s%s by %d." % [first.name, "lead" if first.name == "You" else "leads", behind, gap]


# Strokes `p` is ahead of the best other player still in the round:
# positive when winning, negative when behind.
func match_margin(p: Player) -> int:
	var best := -1
	for other in players:
		if other == p or other.abandoned:
			continue
		if best < 0 or other.total_strokes() < best:
			best = other.total_strokes()
	return 0 if best < 0 else best - p.total_strokes()


# The other player closest to beating `p` — the one the caddy talks about.
func closest_rival_name(p: Player) -> String:
	var rival: Player = null
	for other in players:
		if other == p or other.abandoned:
			continue
		if rival == null or other.total_strokes() < rival.total_strokes():
			rival = other
	return rival.name if rival != null else ""


# --- Restart -----------------------------------------------------------
# The header's always-available Restart. A round in progress is real work,
# so a misclick shouldn't wipe it: the first press arms, the second
# confirms. On hole 1 before a single stroke there is nothing to lose, so
# it restarts immediately.
#
# Mid-animation presses are ignored — a scene torn down while a tween is
# still driving the map would resolve its callback into a rebuilt UI.
func _on_header_restart_pressed() -> void:
	if _animating:
		return
	# "Nothing to lose" has to be true for EVERY player, not just whoever is
	# active: in a group round the active player can be sitting on the tee
	# with 0 strokes while someone else is mid-hole, and skipping the
	# confirm there would throw away their round without asking.
	var nothing_to_lose: bool = current_hole_index == 1
	if nothing_to_lose:
		for p in players:
			if p.strokes != 0 or not p.round_scores.is_empty():
				nothing_to_lose = false
				break
	Sound.play("ui_back")
	if nothing_to_lose or _restart_armed:
		restart_round()
		return

	_restart_armed = true
	_show_restart_armed(true)
	log_msg("\n[color=#%s][b]Restart?[/b] Press Restart again to abandon this round and start over from hole 1.[/color]" % COLOR_FLAG.to_html(false))
	# Disarms on its own, so an ignored prompt can't sit armed for the rest
	# of the round waiting to eat an unrelated press much later.
	var t := get_tree().create_timer(5.0)
	t.timeout.connect(func():
		if _restart_armed:
			_restart_armed = false
			_show_restart_armed(false)
			log_msg("[color=#%s]Restart cancelled.[/color]" % COLOR_TEXT_SOFT.to_html(false))
	)


# The ACTIVE player has holed out. Records their score for the hole and
# marks them done. In multiplayer the hole continues until every player is
# in, so this hands over rather than going straight to the draft.
# `holed_from` is the distance in yards when the ball went in from off the
# green (the d20 came up 20), or -1 when it was putted in.
func finish_hole(holed_from: int = -1) -> void:
	var diff := strokes - hole_par
	me.holed_out = true
	_after_putt_drops(func(): Sound.jingle(diff))
	round_scores.append({"hole": current_hole_index, "par": hole_par, "strokes": strokes})
	if records_this_seat(active_index):
		var prev_best := Records.record_hole(current_hole_index, strokes)
		if prev_best > 0 and strokes < prev_best:
			log_msg("[color=#%s]Your best on this hole — beats %d.[/color]" % [COLOR_ACCENT.to_html(false), prev_best])
	var streak := under_par_streak(me)
	show_hole_banner(diff, holed_from, streak)
	if is_cpu_seat(active_index):
		caddy_says("rival_holed", {"diff": diff, "rival": me.name}, true)
	elif streak >= STREAK_CALL and holed_from < 0:
		# A run of under-par holes outranks a remark about this one. (A
		# hole-out has just had its own line.)
		caddy_says("streak", {"count": streak})
	else:
		caddy_says("holed", {"diff": diff})

	if is_multiplayer():
		log_msg("\n[b]%s holed out![/b] %d strokes (par %d) — %s" % [
			me.name, strokes, hole_par, score_diff_text(diff)])
	else:
		log_msg("\n[b]Holed out![/b] Total strokes: %d (par %d) — %s" % [
			strokes, hole_par, score_diff_text(diff)])

	# Anyone still out on the hole plays on.
	if advance_turn():
		state = State.CLUB_SELECT
		if me.current_lie == "green":
			start_putting()
		else:
			refresh_ui()
		return

	begin_end_of_hole()


# Every player is in. Report the hole, then run the end-of-hole draft for
# each player in turn (Section 7: independent draw-3 per player, so nobody
# can take the card another player wanted).
func begin_end_of_hole() -> void:
	if is_multiplayer():
		log_msg("\n[b]Hole %d complete.[/b]" % current_hole_index)
		for p in players:
			var entry = p.round_scores[p.round_scores.size() - 1] if not p.round_scores.is_empty() else null
			if entry != null:
				log_msg("  %s — %d strokes (%s)" % [
					p.name, int(entry.strokes), score_name(int(entry.strokes) - int(entry.par))])
		var lead := lead_text()
		if lead != "":
			log_msg("[color=#%s]%s[/color]" % [COLOR_ACCENT.to_html(false), lead])
		# Halfway round a full course, the caddy takes stock of the match.
		var you := lone_human()
		if you != null and Course.hole_count() >= 4 and current_hole_index * 2 == Course.hole_count():
			caddy_says("turn", {"margin": match_margin(you), "rival": closest_rival_name(you)}, true)

	# No draft after the last hole: there is no shot left to play a new
	# club with, so the round ends here. Every way a hole can finish comes
	# through this function (the last putt, a seat retired mid-hole), so
	# one check covers solo, hot-seat and online alike.
	if current_hole_index >= Course.hole_count():
		finish_hole_done()
		return

	if online:
		begin_simultaneous_draft()
		return
	_draft_queue = []
	for i in range(players.size()):
		_draft_queue.append(i)
	begin_next_draft()


# --- Everyone drafts at once (online) ---------------------------------
# Drafts are independent — every player draws from their own pool — so
# nothing is lost by running them together, and at four players it saves
# three players watching each pick. Hot-seat keeps them one at a time:
# there, everyone shares the one screen.
const DRAFT_PICK := "pick"
const DRAFT_DISCARD := "discard"
const DRAFT_DONE := "done"


func begin_simultaneous_draft() -> void:
	_simul_draft = true
	_draft_queue = []
	log_msg("\n[b]Everyone drafts at once.[/b] Draw 3, pick 1 — the next hole starts when the last pick is in.")
	for i in range(players.size()):
		active_index = i
		if me.abandoned or not _draw_draft_options():
			me.draft_stage = DRAFT_DONE
		else:
			me.draft_stage = DRAFT_PICK
	Sound.play("card_draw")
	if not _finish_simultaneous_draft_if_done():
		view_seat(my_seat)
		refresh_ui()


func owes_draft(seat: int) -> bool:
	return seat >= 0 and seat < players.size() \
		and (players[seat].draft_stage == DRAFT_PICK or players[seat].draft_stage == DRAFT_DISCARD)


# Points this machine's view — and so `me` and `state` — at one seat's
# draft. In a simultaneous draft, `state` describes the seat being viewed.
func view_seat(seat: int) -> void:
	active_index = clampi(seat, 0, players.size() - 1)
	match me.draft_stage:
		DRAFT_PICK:
			state = State.DRAFT
		DRAFT_DISCARD:
			state = State.DISCARD_FOR_DRAFT
		_:
			state = State.WAITING


# Runs a draft action for `seat`, then returns the view to this machine's
# own seat. Every machine replays the same actions in the same order, so
# they agree on every player's stage — and on the moment the last pick
# starts the next hole.
func apply_as_seat(seat: int, kind: String, payload: Dictionary) -> void:
	view_seat(seat)
	_apply_action(kind, payload)
	if not _simul_draft:
		return  # that was the last pick, and the next hole has begun
	if state == State.DISCARD_FOR_DRAFT:
		me.draft_stage = DRAFT_DISCARD
	view_seat(my_seat)


func _finish_simultaneous_draft_if_done() -> bool:
	for i in range(players.size()):
		if owes_draft(i):
			return false
	_simul_draft = false
	for p in players:
		p.draft_stage = ""
	finish_hole_done()
	return true


func waiting_on_names() -> Array:
	var out: Array = []
	for i in range(players.size()):
		if owes_draft(i):
			out.append(players[i].name)
	return out


# Runs the next queued player's end-of-hole draft, or moves on to the next
# hole once every player has drafted.
func begin_next_draft() -> void:
	if _simul_draft:
		# This player's draft is done; the hole moves on once everyone's is.
		me.draft_stage = DRAFT_DONE
		state = State.WAITING
		_finish_simultaneous_draft_if_done()
		return
	if _draft_queue.is_empty():
		finish_hole_done()
		return
	active_index = int(_draft_queue.pop_front())
	sync_map_to_active()
	if is_multiplayer():
		log_msg("\n[b]%s draft.[/b] Draw 3, pick 1 to add to the bag permanently." % possessive(me))
	else:
		log_msg("\n[b]End of hole.[/b] Draw 3, pick 1 to add to your hand permanently.")
	begin_draft_phase()


# Called once the end-of-hole draft pick has been resolved (with or without
# a forced discard) — the hole is now fully over — and straight from
# begin_end_of_hole() after the last hole, which has no draft. Either
# advances to the next hole or ends the round and shows the scorecard.
func finish_hole_done() -> void:
	if current_hole_index >= Course.hole_count():
		finish_round()
	else:
		current_hole_index += 1
		start_hole()


func finish_round() -> void:
	state = State.DONE
	_play_round_jingle()
	log_entries.clear()
	log_msg("[b]Round Complete — %s[/b]\n" % Course.active_name)
	record_finished_round()

	if is_multiplayer():
		# Leaderboard first — in a group round the result is the comparison,
		# and the hole-by-hole detail for one player matters less than who
		# won. Stroke play: lowest total wins.
		var standings := players.duplicate()
		standings.sort_custom(func(a, b): return a.total_strokes() < b.total_strokes())

		log_msg("[b]Final standings[/b]")
		var place := 0
		var shown := 0
		var prev_strokes := -1
		for p in standings:
			shown += 1
			# Ties share a place, the way a real card reads.
			if p.total_strokes() != prev_strokes:
				place = shown
				prev_strokes = p.total_strokes()
			log_msg("  %d. %s — %d strokes (%s)" % [
				place, p.name, p.total_strokes(), score_diff_text(p.score_diff())])

		var best: Player = standings[0]
		var tied: Array = []
		for p in standings:
			if p.total_strokes() == best.total_strokes():
				tied.append(p.name)
		if tied.size() > 1:
			log_msg("\n[b]Tied — %s, on %d strokes.[/b]" % [
				", ".join(tied), best.total_strokes()])
		else:
			log_msg("\n[b]%s %s, on %d strokes (%s).[/b]" % [
				best.name, "win" if best.name == "You" else "wins",
				best.total_strokes(), score_diff_text(best.score_diff())])
		# Against the computer, the caddy has the last word on the match.
		var you := lone_human()
		if you != null and not you.abandoned:
			caddy_says("match", {"margin": match_margin(you), "rival": closest_rival_name(you),
				"diff": you.score_diff(), "holes": you.round_scores.size()}, true, true)
		refresh_ui()
		return

	var total_strokes := 0
	var total_par := 0
	for entry in round_scores:
		total_strokes += entry.strokes
		total_par += entry.par
		log_msg("Hole %2d — Par %d — %d strokes — %s" % [entry.hole, entry.par, entry.strokes, score_name(entry.strokes - entry.par)])
	var diff := total_strokes - total_par
	log_msg("\n[b]Total: %d (%s)[/b]" % [total_strokes, score_diff_text(diff)])
	caddy_says("round", {"diff": diff, "holes": round_scores.size()}, false, true)
	refresh_ui()


# The actual reset, shared by the header button and the end-of-round
# "Restart Round" button. init_game() rebuilds the bag, brands, Form deck
# and draft pools, so a new run inherits nothing from the last one.
# --- Records and settings ---------------------------------------------

# Records are kept for players on this machine: every seat in solo and
# hot-seat, only your own online. A test round from the course editor is
# a course being built, not one being played, so it records nothing.
func records_this_seat(seat: int) -> bool:
	if GameSetup.return_to_editor:
		return false
	if online and seat != my_seat:
		return false
	# A computer golfer's round isn't yours to hold a record with.
	if is_cpu_seat(seat):
		return false
	return seat < players.size() and not players[seat].abandoned


func round_mode() -> String:
	if online:
		return "online"
	if not _bots.is_empty():
		return "vs computer"
	return "hot-seat" if is_multiplayer() else "solo"


# Saves each local player's finished round and says how it stands.
func record_finished_round() -> void:
	for i in range(players.size()):
		if not records_this_seat(i):
			continue
		var p: Player = players[i]
		if p.round_scores.size() < Course.hole_count():
			continue
		var r := Records.record_round(p.name, p.total_strokes(), p.total_par(), round_mode())
		var who := "" if not is_multiplayer() else "%s — " % p.name
		var prev: Dictionary = r.previous_best
		if prev.is_empty():
			log_msg("[color=#%s][b]%sFirst round on %s — that's the record to beat.[/b][/color]" % [
				COLOR_ACCENT.to_html(false), who, Course.active_name])
		elif r.new_best:
			log_msg("[color=#%s][b]%sNew course record! %d beats %d.[/b][/color]" % [
				COLOR_ACCENT.to_html(false), who, p.total_strokes(), int(prev.strokes)])
		else:
			log_msg("[i]%sCourse record: %d (%s), by %s.[/i]" % [
				who, int(prev.strokes), Records.diff_text(int(prev.diff)), str(prev.player)])
	log_msg("")


var _settings_popup: PopupPanel


func _on_header_settings_pressed() -> void:
	Sound.play("ui_click")
	if _settings_popup == null:
		_settings_popup = PopupPanel.new()
		var settings := SettingsPanel.new()
		settings.custom_minimum_size = Vector2(460, 0)
		settings.closed.connect(func(): _settings_popup.hide())
		_settings_popup.add_child(settings)
		add_child(_settings_popup)
		# Pick up a new putt key once the popup closes.
		_settings_popup.popup_hide.connect(func():
			if state == State.PUTTING:
				refresh_ui())
	_settings_popup.popup_centered()
	_fit_popup.call_deferred(_settings_popup)


# A wrapped line of text reports a tall minimum until it has been given a
# width, so a popup opens sized for text it doesn't have. One frame on,
# with the layout settled, cut it back to its contents.
func _fit_popup(popup: Window) -> void:
	await get_tree().process_frame
	if is_instance_valid(popup) and popup.visible:
		popup.reset_size()
		popup.move_to_center()


func _on_header_menu_pressed() -> void:
	_cpu_join()
	Sound.play("ui_back")
	var target := "res://scenes/CourseEditor.tscn" if GameSetup.return_to_editor else "res://scenes/Title.tscn"
	GameSetup.return_to_editor = false
	get_tree().change_scene_to_file(target)


func restart_round() -> void:
	current_hole_index = 1
	_restart_armed = false
	_show_restart_armed(false)
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


# The hover text behind a brand chip in the bag rack. Answers the two
# questions the chip itself can't fit: which clubs of this brand am I
# actually carrying, and what does the next one buy me? Brands in the
# run's pool that you hold none of still get a chip, greyed — knowing a
# set is available and empty is as much of a plan as knowing it's half
# built.
func brand_chip_tooltip(brand: String) -> String:
	var owned: Array = []
	for club in hand:
		if club.get("brand", Brands.NONE) == brand:
			owned.append("  %s (%d-%d yds)" % [
				club.name, int(club.min_yard), int(club.max_yard)])
	# The count comes from Brands.counts(), never from owned.size(): that
	# is the same figure the set bonuses are computed from, so the tooltip
	# can never claim a tier the rules don't actually grant.
	var n: int = int(Brands.counts(hand).get(brand, 0))

	var lines: Array = [Brands.display_name(brand).to_upper()]
	if n == 0:
		lines.append("None in the bag.")
	else:
		lines.append("In the bag (%d):" % n)
		lines.append_array(owned)

	var tier: int = Brands.tier_reached(n)
	lines.append("")
	if tier > 0:
		lines.append("ACTIVE — set of %d:" % tier)
		lines.append("  %s" % String(Brands.BONUS_TEXT.get(brand, {}).get(tier, "")))
	var next: int = Brands.next_tier(n)
	if next > 0:
		# The gap is what turns the chip into a decision at draft time.
		lines.append("%d more for the set of %d:" % [next - n, next])
		lines.append("  %s" % String(Brands.BONUS_TEXT.get(brand, {}).get(next, "")))
	elif tier > 0:
		lines.append("Top tier reached.")
	return "\n".join(lines)


# Rebuilds the brand rack in the bag header: one swatch per brand in this
# run's live pool, plus any brand you somehow hold that isn't in it. It
# reads "TITANIST 4" once a tier is live, "CALLOWELL 1/2" while climbing,
# and just the name when you hold none — and every one of them carries
# the full hover breakdown.
func rebuild_brand_rack() -> void:
	if not brand_rack:
		return
	clear_container(brand_rack)

	var counts := Brands.counts(hand)
	var brands: Array = live_brands.duplicate()
	for b in counts:
		if not brands.has(b):
			brands.append(b)

	for brand in brands:
		var n: int = int(counts.get(brand, 0))
		var tier: int = Brands.tier_reached(n)
		var next: int = Brands.next_tier(n)
		var label: String = Brands.display_name(brand).to_upper()
		# Each carries its brand's livery as a dot, so the rack doubles as
		# the key for the dots on the bag cards below it. A solid dot and
		# full ink once a tier is live; a ring and grey while climbing.
		var accent: Color = Brands.color(brand)
		if tier > 0:
			label += " %d" % tier
		elif next > 0 and n > 0:
			label += " %d/%d" % [n, next]
		var chip := BogeyUI.chip(label, accent, tier > 0)
		var tip: String = brand_chip_tooltip(brand)
		# Godot resolves a tooltip from the topmost control under the
		# cursor, which here is the chip's inner Label — so the text goes
		# on the whole subtree, and every part of it takes the mouse so
		# the panel still catches the gaps around the label.
		chip.tooltip_text = tip
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		for child in chip.get_children():
			if child is Control:
				child.tooltip_text = tip
				child.mouse_filter = Control.MOUSE_FILTER_STOP
		brand_rack.add_child(chip)


func refresh_ui() -> void:
	refresh_turn_ui()

	# A computer golfer's turn is watched, not played: the cards are shown
	# but can't be picked, and the crosshair is theirs.
	var cpu := is_cpu_turn()
	if map_view:
		map_view.input_locked = cpu

	if scorecard:
		if is_multiplayer():
			# A group's card: a line each, the player who is up marked.
			var rows: Array = []
			for i in range(players.size()):
				var p: Player = players[i]
				rows.append({"name": p.name, "color": CourseMapView.seat_color(i),
					"scores": p.round_scores, "live": p.strokes, "active": i == active_index})
			scorecard.set_card(rows, current_hole_index)
		else:
			scorecard.set_round(round_scores, current_hole_index, strokes)
	if hole_title and hole:
		if state == State.DONE:
			hole_title.text = "Final card"
			hole_caption.text = Course.active_name
		else:
			hole_title.text = "Hole %d" % current_hole_index
			hole_caption.text = "Par %d  ·  %d yards" % [hole_par, int(hole_yardage)]

	if form_deck_holder:
		clear_container(form_deck_holder)
		if form_deck:
			form_deck_holder.add_child(make_form_deck_chip_button())

	rebuild_brand_rack()

	if _animating:
		return

	rebuild_shot_outlook()
	rebuild_ability_box()
	clear_container(options_container)
	clear_container(form_container)
	form_hint.visible = true

	# The step line: which numbered beat of the shot flow you're on, and
	# the one instruction that goes with it.
	var step_num := "1"
	var step_hint := ""
	var bag_text := "Your bag  %d / %d" % [hand.size(), HAND_CAP]

	match state:
		State.AIM:
			step_num = "2"
			step_hint = "Aim on the hole, then click to commit"
			hand_label.text = bag_text
			options_label.text = "Aiming with %s — it reaches %d–%d yds." % [
				pending_club.name, int(pending_club.min_yard), int(pending_club.max_yard)]
			rebuild_bag_row()
			build_form_placeholders("Drawn the moment you commit your aim.")

		State.FORM_DRAW:
			step_num = "3"
			if current_form_forced:
				step_hint = "No choice — play the card the club created"
				form_label.text = "%s form · forced" % FormCard.FAMILY_LABEL[FormCard.family_of(pending_club)]
				form_hint.text = "This card was created for you. Tap it to play."
			else:
				step_hint = "Read all %d, then keep one" % current_form_options.size()
				form_label.text = "%s form · draw %d, keep 1" % [
					FormCard.FAMILY_LABEL[FormCard.family_of(pending_club)], current_form_options.size()]
				form_hint.text = "Read the cards against the wind and the ground, then keep one."
			hand_label.text = bag_text
			options_label.text = "Playing %s." % pending_club.name
			rebuild_bag_row()
			for i in range(current_form_options.size()):
				var fv := make_form_card_view(current_form_options[i], not cpu)
				fv.picked.connect(_make_form_pick_callback(i))
				form_container.add_child(fv)

		State.DRAFT:
			step_num = "·"
			step_hint = "End of the hole — add one club to your bag"
			# Normally 3, but a nearly-exhausted club deck can offer fewer.
			hand_label.text = "Draw %d, keep 1" % current_draft_options.size()
			options_label.text = "It joins your bag for the rest of the round."
			for i in range(current_draft_options.size()):
				var cv := make_draft_card(current_draft_options[i], not cpu,
					DraftAdvisor.gains(hand, current_draft_options[i], HAND_CAP))
				cv.picked.connect(_make_draft_pick_callback(i))
				options_container.add_child(cv)
			var bad := form_deck.bad_count()
			if bad > 0:
				var range_btn := make_range_card(mini(ShotRules.RANGE_SESSION_PURGE, bad), bad)
				range_btn.pressed.connect(func(): submit("range", {}))
				range_btn.disabled = cpu
				options_container.add_child(range_btn)
			build_form_placeholders("No Form draw between holes.")

		State.DISCARD_FOR_DRAFT, State.DISCARD_FOR_HAZARD:
			step_num = "·"
			step_hint = "Bag is full — something has to go"
			hand_label.text = "Bag full  %d / %d" % [hand.size(), HAND_CAP]
			options_label.text = "Tap a club to drop it for %s." % pending_new_card.name
			var cut_width := bag_card_width(hand.size())
			for i in range(hand.size()):
				# Cut short, with no engraving, to leave room beneath for
				# what dropping it would cost.
				var cv := make_card_view(hand[i], not cpu, true, cut_width, 116.0, false)
				cv.picked.connect(_make_discard_callback(i))
				# What cutting it would cost, so the cut is a read, not a guess.
				options_container.add_child(card_with_cost(cv, DraftAdvisor.losses(hand, hand[i])))
			build_form_placeholders("No Form draw while you're cutting the bag.")

		State.WAITING:
			step_num = "·"
			step_hint = "Drafted — waiting for the others"
			hand_label.text = bag_text
			options_label.text = "Still drafting: %s." % ", ".join(PackedStringArray(waiting_on_names()))
			build_form_placeholders("The next hole starts when the last pick is in.")

		State.CLUB_SELECT:
			step_num = "1"
			step_hint = "Pick a club from your bag"
			hand_label.text = bag_text
			options_label.text = "Pass over a club to see its reach on the hole."
			if current_lie == "bunker":
				options_label.text = "In the bunker — no woods."
			rebuild_bag_row()
			build_form_placeholders("Drawn fresh for every shot, once you commit your aim.")

		State.PUTTING:
			step_num = "·"
			step_hint = "On the green — stop the marker in the band"
			hand_label.text = "Putting  ·  %s" % putt_distance_text()
			options_label.text = "The further out you are, the tighter the band."
			build_putt_controls()
			build_form_placeholders("No Form draw on the green — a putt is a timing check.")

		State.DONE:
			var total_strokes := 0
			var total_par := 0
			for entry in round_scores:
				total_strokes += entry.strokes
				total_par += entry.par
			var diff := total_strokes - total_par
			step_num = "·"
			step_hint = "Round complete"
			hand_label.text = "Round complete"
			options_label.text = "%d strokes (%s)." % [total_strokes, score_diff_text(diff)]
			var restart_btn := Button.new()
			restart_btn.text = "Play another round"
			restart_btn.custom_minimum_size = Vector2(220, 52)
			restart_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			BogeyUI.style_button(restart_btn, true, 15)
			restart_btn.pressed.connect(restart_round)
			options_container.add_child(restart_btn)
			build_form_placeholders("")

	if cpu:
		# Same strip, but it's their bag and their move you're looking at.
		step_num = "·"
		step_hint = "%s is %s" % [me.name, CPU_DOING.get(state, "thinking")]
		var whose := possessive(me)
		match state:
			State.DRAFT:
				hand_label.text = "%s draft" % whose
			State.DISCARD_FOR_DRAFT, State.DISCARD_FOR_HAZARD:
				hand_label.text = "%s bag is full" % whose
			State.PUTTING:
				hand_label.text = "%s putt  ·  %s" % [whose, putt_distance_text()]
			_:
				hand_label.text = "%s bag  %d / %d" % [whose, hand.size(), HAND_CAP]
		options_label.text = "Computer golfer — %s." % Rivals.blurb_of(me.cpu_skill).to_lower()
		if state == State.FORM_DRAW:
			form_hint.text = "%s reads the same cards you would." % me.name

	if step_holder:
		clear_container(step_holder)
		if step_hint != "":
			step_holder.add_child(BogeyUI.step_pill(step_num, step_hint))


# The Form hand at rest. Outside a draw the column holds one line saying
# when the next draw comes — and, once a club is in hand, how many cards
# this swing would earn, since that count is the read the aim turns on.
func build_form_placeholders(note: String) -> void:
	form_label.text = "Form hand"
	form_hint.text = note
	form_hint.visible = note != ""

	var swinging := ""
	if state == State.AIM and not pending_club.is_empty():
		swinging = FormCard.family_of(pending_club)
		var created: int = me.created_next.size() + ClubAbilities.draw_extras(pending_club, current_lie).size()
		var count: int = ShotRules.form_choice_count(hand, swing_tier_for_shot(), play_lie(), created)
		form_hint.text = "This swing draws %d from your %s form — %s." % [count,
			FormCard.FAMILY_LABEL[swinging], "you keep one" if count > 1 else "no choice"]
		form_hint.visible = true
		form_container.add_child(make_form_placeholder(count))

	# Between draws the column shows what the next one will be dealt from.
	_family_rows = {}
	if state != State.PUTTING and state != State.DONE:
		form_container.add_child(make_family_form_table(swinging))


# Your form with each kind of club: a line a family, how many good cards
# and how many bad it has in play. A swing is dealt only from the family
# of the club in hand (Section 4 "Form by club family"), so this is the
# read a club choice turns on — a cold driver is a reason to hit an iron.
# `active` is the family being swung; the others step back. With none,
# passing over a club in the bag picks its family out (light_family()).
func make_family_form_table(active: String = "") -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var form := form_deck.family_form()
	for fam in FormCard.FAMILIES:
		var good: int = form[fam].good
		var bad: int = form[fam].bad
		if good + bad == 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := BogeyUI.kicker(FormCard.FAMILY_LABEL[fam], BogeyTheme.INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(BogeyUI.label("%d good" % good, 13, BogeyTheme.NEUTRAL_700))
		# Claret when two cards in five are bad, green when none are.
		var bad_ink: Color = BogeyTheme.NEUTRAL_700
		if bad == 0:
			bad_ink = BogeyTheme.FAIRWAY_DEEP
		elif float(bad) / float(good + bad) >= 0.4:
			bad_ink = BogeyTheme.FLAG
		var bad_label := BogeyUI.label("%d bad" % bad, 13, bad_ink, 500)
		bad_label.custom_minimum_size = Vector2(46, 0)
		bad_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(bad_label)
		col.add_child(BogeyUI.hairline(0.1))
		var line := BogeyUI.margin(row, 0, 6, 0, 6)
		col.add_child(line)
		_family_rows[fam] = line
	col.add_child(BogeyUI.hairline(0.1))
	light_family(active)
	return BogeyUI.margin(col, 0, 8, 0, 0)


# Picks one family out of the form table and steps the others back; ""
# shows them all alike.
func light_family(family: String) -> void:
	for fam in _family_rows:
		var row: Control = _family_rows[fam]
		if is_instance_valid(row):
			row.modulate.a = 1.0 if family == "" or fam == family else 0.4


# The cards this swing would draw, face down: a row of small outlines,
# one per card. Says "three" (or "two", or "one") without a word.
func make_form_placeholder(count: int = 3) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 34)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		for i in count:
			var r := Rect2(i * 30.0 + 0.5, 0.5, 22.0, 31.0)
			c.draw_rect(r, BogeyTheme.CARD_BG)
			c.draw_rect(r, BogeyTheme.NEUTRAL_400, false, 1.0))
	return c


func make_card_view(card: Dictionary, interactive: bool = true, compact: bool = false,
		width: float = 0.0, height: float = 0.0, show_art: bool = true) -> CardView:
	var cv := CardView.new()
	cv.width = width
	cv.height = height
	cv.show_art = show_art
	cv.setup(card, interactive, compact)
	return cv


# A draft offer: the club in full, and on the same card what taking it
# would change in your bag — see DraftAdvisor. The lines that matter most
# are in full ink.
func make_draft_card(card: Dictionary, interactive: bool, notes: Array) -> CardView:
	var cv := CardView.new()
	cv.width = DRAFT_CARD_WIDTH
	cv.notes = notes if not notes.is_empty() \
		else [{"text": "Nothing else in your bag changes.", "strong": false}]
	cv.setup(card, interactive, false)
	if notes.size() > 3:
		cv.set_tip("\n".join(PackedStringArray(notes.map(func(n): return str(n.text)))))
	return cv


# The draft's fourth offer, set as the cards beside it are (see
# CardFace.gd): pass on the club and work bad cards out of the Form deck.
# A button, so it takes the keyboard and disables like one.
func make_range_card(purge: int, bad: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, CardView.CARD_SIZE.y)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BogeyUI.style_button(b, false, 13)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var avail := 150.0 - 28.0
	col.add_child(CardFace.header(Color(0, 0, 0, 0), "Instead", BogeyTheme.NEUTRAL_600))
	col.add_child(CardFace.name_label("Range session", CardFace.NAME_SIZE, avail))
	col.add_child(CardFace.figure([["%d" % purge, "bad card%s out" % ("" if purge == 1 else "s")]], avail))
	var words := CardFace.words("Take no club. %d bad Form card%s in your deck." % [
		bad, "" if bad == 1 else "s"])
	words.custom_minimum_size = Vector2(avail, 0)
	col.add_child(words)

	var pad := BogeyUI.margin(col, 14, 12, 14, 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(pad)
	return b


# How wide a bag card may be with `count` of them in the row: as wide as
# the stock tile while there is room, narrowing so a full bag still fits
# the strip without scrolling.
func bag_card_width(count: int) -> float:
	var avail: float = options_scroll.size.x if options_scroll and options_scroll.size.x > 0.0 \
		else size.x - SIDE_PAD * 2.0
	if avail <= 0.0:
		avail = 1600.0 - SIDE_PAD * 2.0
	var n: int = maxi(count, 1)
	return clampf(floorf((avail - BAG_GAP * (n - 1)) / n), BAG_CARD_MIN, BAG_CARD_MAX)


func make_form_card_view(card: FormCard, interactive: bool = true) -> FormCardView:
	var fv := FormCardView.new()
	fv.setup(card, interactive)
	return fv


# The link beside the Form kicker: how much of the deck is left, opening
# the Form deck contents popup.
func make_form_deck_chip_button() -> Button:
	var b := Button.new()
	var left: int = form_deck.deck.size()
	var used: int = form_deck.discard.size()
	b.text = "Deck  %d" % left
	b.tooltip_text = "%d Form cards left to draw, %d in the discard pile.\nClick to see what's in the deck." % [left, used]
	b.focus_mode = Control.FOCUS_NONE
	BogeyUI.style_link_button(b, 10)
	b.pressed.connect(_on_form_deck_chip_pressed)
	return b


# Keeps the hot-seat column honest: who is up. Hidden in a solo round, so
# single-player looks exactly as it would with nobody else at the table.
# (Where everyone stands is on the scorecard — a line per player.)
func refresh_turn_ui() -> void:
	if turn_banner == null:
		return
	turn_banner.visible = is_multiplayer()
	if not is_multiplayer() or turn_banner_label == null:
		return
	turn_banner.add_theme_stylebox_override("panel",
		_turn_banner_style(CourseMapView.seat_color(active_index)))
	if _simul_draft:
		turn_banner_label.text = "%s — draft a club (everyone drafts at once)" % me.name \
			if owes_draft(active_index) else "Waiting for %s to draft" % \
			", ".join(PackedStringArray(waiting_on_names()))
	elif state == State.DRAFT or state == State.DISCARD_FOR_DRAFT:
		turn_banner_label.text = "%s — draft a club" % me.name
	elif state == State.DONE:
		turn_banner_label.text = "Round complete"
	else:
		turn_banner_label.text = "%s to play" % me.name


# The shot panel, always on: the one number that matters — how far to the
# pin — then a short spec sheet (lie, wind, strokes, your best here) and
# what the lie is doing to you. When a club is in hand it also shows the
# swing tier and its draw consequence, which is the read the game turns on.
func rebuild_shot_outlook() -> void:
	clear_container(shot_outlook)
	shot_outlook.visible = true

	# Between shots there is no shot to describe: with the round over the
	# panel sums it up, and while a club is being drafted it shows what
	# the hole just played came to.
	if state == State.DONE:
		_build_round_summary()
		return
	if (state == State.DRAFT or state == State.DISCARD_FOR_DRAFT or state == State.WAITING) \
			and not round_scores.is_empty() and int(round_scores[-1].hole) == current_hole_index:
		_build_hole_result(round_scores[-1])
		return

	var dist_to_pin: float = ball_pos.distance_to(hole.pin_pos) if hole else 0.0
	var on_green := current_lie == "green"
	# On the green a putt is better read in feet, matching the putt meter's
	# own label — "1 yard to the pin" reads wrong for a tap-in.
	var in_feet := on_green and dist_to_pin < 4.0
	var big := BogeyUI.big_stat(
		str(maxi(1, int(round(dist_to_pin * 3.0)))) if in_feet else str(int(round(dist_to_pin))),
		"Feet to the pin" if in_feet else "Yards to the pin")
	shot_outlook.add_child(big[0])

	var risky := current_lie == "rough" or current_lie == "bunker"
	var specs := VBoxContainer.new()
	specs.add_theme_constant_override("separation", 0)
	shot_outlook.add_child(specs)
	specs.add_child(BogeyUI.hairline(0.14))
	specs.add_child(BogeyUI.spec_row("Lie", current_lie.capitalize(),
		BogeyTheme.FLAG if risky else BogeyTheme.INK))
	# The wind, read against the line you're playing: toward the aim once
	# there is one, otherwise toward the pin. Putts don't feel it.
	if hole and not on_green:
		var line: Vector2 = (aim_target - ball_pos) if (state == State.AIM or state == State.FORM_DRAW) \
			and aim_target.distance_to(ball_pos) > 1.0 else (hole.pin_pos - ball_pos)
		specs.add_child(BogeyUI.hairline(0.07))
		var wind_row := BogeyUI.spec_row("Wind", Wind.describe(hole.wind, line))
		wind_row.tooltip_text = "Read against the line you're playing.\nHigh shots ride the wind, low ones punch under it."
		specs.add_child(wind_row)
	specs.add_child(BogeyUI.hairline(0.07))
	specs.add_child(BogeyUI.spec_row("Strokes", str(strokes)))
	var hole_best := Records.hole_best(current_hole_index)
	if hole_best > 0:
		specs.add_child(BogeyUI.hairline(0.07))
		specs.add_child(BogeyUI.spec_row("Your best", str(hole_best)))
	specs.add_child(BogeyUI.hairline(0.14))

	# What this lie costs you — Section 5's terrain modifiers, said plainly
	# rather than left for the player to remember.
	var lie_note := ""
	match current_lie:
		"tee":
			lie_note = "Full aimed distance, every club playable."
		"fairway":
			lie_note = "Full aimed distance, every club playable, no draw penalty."
		"rough":
			lie_note = "Whatever distance you aim for flies at 80%. A Flop Shot ignores it entirely."
		"bunker":
			lie_note = "50% distance, woods unplayable, and the club forces one fresh bad Form card on you."
		"green":
			lie_note = "Putting switches to the timing meter, and the sunk band narrows with distance."
	if lie_note != "":
		if risky:
			shot_outlook.add_child(BogeyUI.note_box(lie_note,
				BogeyTheme.ACCENT_100, BogeyTheme.ACCENT_500, BogeyTheme.ACCENT_800))
		else:
			shot_outlook.add_child(BogeyUI.body(lie_note, 13, BogeyTheme.NEUTRAL_600))

	# The last shot, taken apart — what to learn before choosing the next.
	if not me.last_shot.is_empty() and (state == State.CLUB_SELECT or state == State.PUTTING):
		var last := VBoxContainer.new()
		last.add_theme_constant_override("separation", 3)
		shot_outlook.add_child(last)
		last.add_child(BogeyUI.kicker("Last shot  ·  %s" % me.last_shot.club))
		last.add_child(BogeyUI.body(str(me.last_shot.text), 13, BogeyTheme.NEUTRAL_700))

	# Club-specific read, only once a club is actually in hand.
	if (state == State.AIM or state == State.FORM_DRAW) and not pending_club.is_empty():
		var club_col := VBoxContainer.new()
		club_col.add_theme_constant_override("separation", 1)
		shot_outlook.add_child(club_col)
		club_col.add_child(BogeyUI.kicker("Club in hand"))
		var club_name := BogeyUI.heading(str(pending_club.name), 26)
		club_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		club_name.add_theme_constant_override("line_spacing", -6)
		club_col.add_child(club_name)

		var tier := swing_tier_for_shot()
		var aim_dist: float = ball_pos.distance_to(aim_target)
		club_col.add_child(BogeyUI.body("%s · aiming %d of %d–%d yds" % [
			ShotResolver.tier_name(tier), int(round(aim_dist)),
			int(pending_club.min_yard), int(pending_club.max_yard)], 13, BogeyTheme.NEUTRAL_700))

		var tier_hint := ""
		var tier_is_risky := false
		match tier:
			ShotResolver.Tier.FULL:
				tier_hint = "Swinging all-out — draws only 2 Form cards, less room to dodge a bad one."
				tier_is_risky = true
			ShotResolver.Tier.MID:
				tier_hint = "A comfortable, repeatable swing — draws 3 Form cards, the best choice."
			ShotResolver.Tier.FINESSE:
				tier_hint = "A delicate touch — draws only 2 Form cards, less room to dodge a bad one."
				tier_is_risky = true
			ShotResolver.Tier.EXTREME_FINESSE:
				tier_hint = "Below this club's range — no draw at all: a bad Form card is created and you must play it."
				tier_is_risky = true
		if tier_is_risky:
			shot_outlook.add_child(BogeyUI.note_box(tier_hint,
				BogeyTheme.ACCENT_100, BogeyTheme.ACCENT_500, BogeyTheme.ACCENT_800))
		else:
			shot_outlook.add_child(BogeyUI.note_box(tier_hint,
				BogeyTheme.OLIVE_100, BogeyTheme.OLIVE_500, BogeyTheme.OLIVE_800))

		if ShotRules.lie_forces_card(hand, play_lie()) and tier != ShotResolver.Tier.EXTREME_FINESSE:
			shot_outlook.add_child(BogeyUI.note_box(
				"Playing from the sand — the same treatment as Extreme Finesse: no draw, a bad Form card is created and you must play it.",
				BogeyTheme.ACCENT_100, BogeyTheme.ACCENT_500, BogeyTheme.ACCENT_800))


# The shot panel between holes: the hole just finished, as its score.
func _build_hole_result(entry: Dictionary) -> void:
	var diff: int = int(entry.strokes) - int(entry.par)
	var big := BogeyUI.big_stat(str(int(entry.strokes)),
		"Stroke" if int(entry.strokes) == 1 else "Strokes")
	shot_outlook.add_child(big[0])
	var specs := VBoxContainer.new()
	specs.add_theme_constant_override("separation", 0)
	shot_outlook.add_child(specs)
	specs.add_child(BogeyUI.hairline(0.14))
	specs.add_child(BogeyUI.spec_row("Result", score_name(diff),
		BogeyTheme.FAIRWAY_DEEP if diff < 0 else (BogeyTheme.FLAG if diff > 0 else BogeyTheme.INK)))
	specs.add_child(BogeyUI.hairline(0.07))
	specs.add_child(BogeyUI.spec_row("Round", "%s thru %d" % [
		running_score_diff_text(running_score_diff()), round_scores.size()]))
	var hole_best := Records.hole_best(current_hole_index)
	if hole_best > 0:
		specs.add_child(BogeyUI.hairline(0.07))
		specs.add_child(BogeyUI.spec_row("Your best", str(hole_best)))
	specs.add_child(BogeyUI.hairline(0.14))


# The shot panel once the last putt has dropped: the round, summed up.
# A group gets its leaderboard — lowest total first, as stroke play reads.
func _build_round_summary() -> void:
	var specs := VBoxContainer.new()
	specs.add_theme_constant_override("separation", 0)
	if is_multiplayer():
		var standings := players.duplicate()
		standings.sort_custom(func(a, b): return a.total_strokes() < b.total_strokes())
		var best: Player = standings[0]
		# Everyone on the low score shares it — a tie is reported as a tie.
		var low: Array = []
		for p in standings:
			if p.total_strokes() == best.total_strokes():
				low.append(p.name)
		shot_outlook.add_child(BogeyUI.big_stat(str(best.total_strokes()),
			"Low round" if low.size() == 1 else "Tied for low round")[0])
		var who := BogeyUI.heading(" & ".join(PackedStringArray(low)), 24)
		who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		who.add_theme_constant_override("line_spacing", -6)
		shot_outlook.add_child(who)
		shot_outlook.add_child(specs)
		specs.add_child(BogeyUI.hairline(0.14))
		for p in standings:
			specs.add_child(BogeyUI.spec_row(p.name, "%d  (%s)" % [
				p.total_strokes(), running_score_diff_text(p.score_diff())]))
			specs.add_child(BogeyUI.hairline(0.07))
		return

	var total_strokes := 0
	var total_par := 0
	for entry in round_scores:
		total_strokes += int(entry.strokes)
		total_par += int(entry.par)
	var diff := total_strokes - total_par
	shot_outlook.add_child(BogeyUI.big_stat(str(total_strokes), "Strokes")[0])
	shot_outlook.add_child(specs)
	specs.add_child(BogeyUI.hairline(0.14))
	specs.add_child(BogeyUI.spec_row("To par", score_diff_text(diff),
		BogeyTheme.FAIRWAY_DEEP if diff < 0 else (BogeyTheme.FLAG if diff > 0 else BogeyTheme.INK)))
	specs.add_child(BogeyUI.hairline(0.07))
	specs.add_child(BogeyUI.spec_row("Course par", str(total_par)))
	specs.add_child(BogeyUI.hairline(0.07))
	specs.add_child(BogeyUI.spec_row("Holes", str(round_scores.size())))
	specs.add_child(BogeyUI.hairline(0.14))


# The abilities the active player can use right now, as buttons, plus a
# note of any created cards waiting for their next draw.
func rebuild_ability_box() -> void:
	if ability_box == null:
		return
	clear_container(ability_box)
	var list := available_abilities()
	var waiting: Array = me.created_next
	var show_waiting := not waiting.is_empty() and (state == State.CLUB_SELECT or state == State.AIM)
	ability_box.visible = not list.is_empty() or show_waiting
	if not ability_box.visible:
		return
	ability_box.add_child(BogeyUI.hairline(0.14))
	ability_box.add_child(BogeyUI.kicker("Abilities", BogeyTheme.INK))
	if show_waiting:
		ability_box.add_child(BogeyUI.body("Your next Form draw includes %s (created)." % \
			" and ".join(PackedStringArray(waiting)), 13, BogeyTheme.OLIVE_800))
	for e in list:
		# One line each: the name on the button, how many are left at its
		# right edge. Which club gives it, and how often, is on the hover.
		var armed: bool = e.toggle and e.armed
		var left := "%d left %s" % [e.left, ClubAbilities.period_text(e.period)]
		var b := Button.new()
		b.text = str(e.label)
		b.tooltip_text = "%s\n%s · %s" % [e.label, left, e.source]
		if armed:
			b.tooltip_text += "\nOn — tap to switch off."
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		BogeyUI.style_button(b, armed, 13)
		# Cut closer than a stock button — there may be three of these —
		# with room kept clear on the right for the count.
		for key in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := b.get_theme_stylebox(key).duplicate() as StyleBoxFlat
			box.content_margin_top = 7
			box.content_margin_bottom = 7
			box.content_margin_left = 12
			box.content_margin_right = 62
			b.add_theme_stylebox_override(key, box)
		b.pressed.connect(_on_ability_pressed.bind(e.id))
		b.disabled = is_cpu_turn()
		var count := BogeyUI.label("On" if armed else "%d left" % e.left, 12,
			BogeyTheme.NEUTRAL_300 if armed else BogeyTheme.NEUTRAL_600)
		count.set_anchors_preset(Control.PRESET_FULL_RECT)
		count.offset_right = -12
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(count)
		ability_box.add_child(b)


func _on_ability_pressed(id: String) -> void:
	submit("ability", {"id": id})


# Builds the bag row: every card in the bag, longest club first and the
# putter last — see sort_hand(). While you're choosing, a club the lie
# won't let you play is stepped back; once one is in hand it is edged in
# ink and the rest step back instead, so the row itself says which club
# is being played.
func rebuild_bag_row() -> void:
	var playable := {}
	for i in range(hand.size()):
		if ShotRules.club_playable(hand, hand[i], current_lie):
			playable[i] = true

	var choosing := state == State.CLUB_SELECT
	# The club in hand, by identity first: two clubs of the same name are
	# two cards, and only one of them is being swung.
	var in_hand := -1
	if not choosing and not pending_club.is_empty():
		for i in range(hand.size()):
			if is_same(hand[i], pending_club):
				in_hand = i
				break
		if in_hand < 0:
			in_hand = hand.find(pending_club)

	var width := bag_card_width(hand.size())
	for i in range(hand.size()):
		var card = hand[i]
		var cv := make_card_view(card,
			choosing and playable.has(i) and not is_cpu_turn(), true, width)
		if cv.interactive:
			cv.picked.connect(_make_club_callback(i))
			# Hovering a club previews its reach on the hole map, so two
			# clubs can be compared by passing the cursor over each.
			cv.hover_started.connect(_on_club_hover_start.bind(card))
			cv.hover_ended.connect(_on_club_hover_end)
		if choosing:
			cv.set_dimmed(not playable.has(i))
		elif in_hand >= 0:
			cv.set_selected(i == in_hand)
			cv.set_dimmed(i != in_hand)
		options_container.add_child(cv)


# --- Draft pick: pop, then fade the whole offer row out before actually
# mutating game state, so the pick still reads as a deliberate action. ---
func _on_draft_card_picked(cv: CardView, index: int) -> void:
	if is_cpu_turn():
		return
	_animating = true
	_fade_out(options_container)

	get_tree().create_timer(0.25).timeout.connect(func():
		_animating = false
		submit("draft", {"index": index})
	)


# --- Form pick: same pop-then-fade treatment as a draft pick. ---
func _on_form_card_picked(fv: FormCardView, index: int) -> void:
	if is_cpu_turn():
		return
	_animating = true
	_fade_out(form_container)

	get_tree().create_timer(0.25).timeout.connect(func():
		_animating = false
		submit("form", {"index": index})
	)


# Fades every card in a row once one of them has been picked. A card may
# sit inside a box with its draft notes, and the row also holds plain
# buttons (the range session), which simply fade.
func _fade_out(row: Container) -> void:
	for other in row.get_children():
		if other.has_method("play_fade_out"):
			other.play_fade_out()
		else:
			create_tween().tween_property(other, "modulate:a", 0.0, 0.18)


# A bag card with the cost of cutting it written underneath: the one
# thing that most depends on it, in claret, or a quiet all-clear. The
# full list is on the hover.
func card_with_cost(cv: CardView, losses: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(cv)
	var text := "Nothing depends on it"
	var ink: Color = BogeyTheme.NEUTRAL_600
	if not losses.is_empty():
		text = str(losses[0].text)
		ink = BogeyTheme.FLAG if losses[0].strong else BogeyTheme.NEUTRAL_700
		cv.set_tip("\n".join(PackedStringArray(losses.map(func(n): return str(n.text)))))
	var l := BogeyUI.body(text, 11, ink)
	# Three lines held under every card, so the row of cards stays level
	# whether a note runs to one line or three.
	l.custom_minimum_size = Vector2(cv.custom_minimum_size.x, 56)
	l.max_lines_visible = 3
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(l)
	return col


# --- Callback factories (needed so each card view captures the right index) ---
func _make_draft_pick_callback(i: int) -> Callable:
	return func(cv): _on_draft_card_picked(cv, i)


func _make_form_pick_callback(i: int) -> Callable:
	return func(fv): _on_form_card_picked(fv, i)


func _make_discard_callback(i: int) -> Callable:
	return func(_cv): submit("discard", {"index": i})


# --- Club hover: preview that club's reach on the hole map -------------
func _on_club_hover_start(_cv: CardView, card: Dictionary) -> void:
	if map_view:
		map_view.set_preview_club(card)
	light_family(FormCard.family_of(card))


func _on_club_hover_end(_cv: CardView) -> void:
	if map_view:
		map_view.set_preview_club({})
	light_family("")


func _make_club_callback(hand_index: int) -> Callable:
	return func(_cv): submit("club", {"index": hand_index})


# ---------------------------------------------------------
# NETWORK LAYER (online rounds only)
#
# Shape of every exchange:
#   1. A client sends what it wants to do           (req_* , any_peer)
#   2. The host validates it, sets active_index to that seat, and calls
#      the ordinary hot-seat function — unmodified
#   3. The host broadcasts what happened            (net_* , authority)
#
# Step 2 is the whole trick. Every per-player write in this file goes
# through `me`, which is players[active_index], so pointing active_index
# at the submitting seat makes the existing local code the authoritative
# code. There is no separate server implementation to keep in step.
#
# Two rules about call_local, which is the easiest thing to get wrong:
#   - req_* are call_local=false. A client sends them; it must not also
#     apply them locally, or it would act without the host's agreement.
#   - net_* are call_local=false too, because the host has ALREADY
#     applied the outcome by running the logic in step 2. Calling local
#     would apply it twice.
# The one exception is Net.net_start_round, which is call_local=true
# precisely because the host has not yet done that work.
#
# Everything is reliable and ordered. This is a turn-based card game
# sending a handful of messages a minute, so ordering matters enormously
# and bandwidth not at all.
# ---------------------------------------------------------

# Sends an action to the host, or applies it directly in a local round.
# Every UI callback goes through here rather than calling the game
# functions, so there is one place that knows whether we're online.
func submit(kind: String, payload: Dictionary) -> void:
	# A computer golfer is up: nothing a person presses is theirs to play.
	# (The bot calls the game's functions itself — see cpu_act().)
	if is_cpu_turn():
		return
	if not online:
		_apply_action(kind, payload)
		return
	if not is_my_turn():
		_reject(kind, "not this seat's turn")
		return
	if is_authority():
		# The host needs no round trip; it is the authority.
		_host_apply(my_seat, kind, payload)
	else:
		rpc_id(HOST_PEER_ID, "req_action", kind, payload)


# Host side: an action arrived from a client.
@rpc("any_peer", "reliable")
func req_action(kind: String, payload: Dictionary) -> void:
	if not is_authority():
		return
	var seat := seat_of_peer(multiplayer.get_remote_sender_id())
	if seat < 0:
		_reject(kind, "sender holds no seat")
		return
	_host_apply(seat, kind, payload)


# The authoritative step: point the game at the acting seat, record the
# rolls the action consumes, run it, then tell everyone.
func _host_apply(seat: int, kind: String, payload: Dictionary) -> void:
	var simul := _simul_draft
	if simul:
		# Everyone drafts at once: any seat still owing a draft may act, but
		# only with a draft action.
		if not owes_draft(seat) or not ["draft", "discard", "range"].has(kind):
			_reject(kind, "seat %d has no draft to make" % seat)
			return
	elif seat != active_index:
		# Out of turn. Expected occasionally — a client can click as the
		# turn passes — so refuse quietly rather than treating it as an
		# error.
		_reject(kind, "seat %d acted out of turn (seat %d is up)" % [seat, active_index])
		return

	begin_roll_capture()
	if simul:
		apply_as_seat(seat, kind, payload)
		refresh_ui()
	else:
		_apply_action(kind, payload)
	var rolls: Array = take_captured_rolls()

	if _net_trace:
		print("  [host] broadcasting %s seat=%d peers=%s" % [
			kind, seat, str(multiplayer.get_peers())])
	rpc("net_action_applied", seat, kind, payload, rolls, snapshot_decks())


# Client side: the host resolved an action. Replay it with the host's
# rolls injected, then adopt the host's deck state — the parts that come
# from a shuffle and so cannot be reproduced locally.
@rpc("authority", "reliable")
func net_action_applied(seat: int, kind: String, payload: Dictionary,
		rolls: Array, decks: Dictionary) -> void:
	if _net_trace:
		print("  [client] received %s seat=%d" % [kind, seat])
	inject_rolls(rolls)
	if _simul_draft:
		apply_as_seat(seat, kind, payload)
	else:
		active_index = clampi(seat, 0, players.size() - 1)
		_apply_action(kind, payload)
	apply_deck_snapshot(decks)
	refresh_ui()


# Routes an action to the function the UI used to call directly.
func _apply_action(kind: String, payload: Dictionary) -> void:
	match kind:
		"club":
			on_club_select(int(payload.get("index", -1)))
		"aim":
			_on_aim_picked(payload.get("target", Vector2.ZERO))
		"form":
			on_form_pick(int(payload.get("index", -1)))
		"draft":
			on_draft_pick(int(payload.get("index", -1)))
		"discard":
			on_discard_pick(int(payload.get("index", -1)))
		"putt":
			on_putt_stopped(str(payload.get("result", "")),
				float(payload.get("accuracy", 0.0)))
		"ability":
			on_ability(str(payload.get("id", "")))
		"range":
			on_range_session()
		_:
			_reject("action", "unknown kind '%s'" % kind)


# --- Deck state --------------------------------------------------------
# Draws come off a shuffled deck, so a client cannot reproduce them from
# the action and the rolls alone — the resulting order IS the information.
# Committing an aim triggers the Form draw and entering the draft draws
# the club options, so these travel with every action rather than only
# some, which is cheaper than tracking which actions touched a deck.
func snapshot_decks() -> Dictionary:
	var out: Array = []
	for p in players:
		out.append({
			"hand": p.hand.duplicate(true),
			"club_deck": p.club_deck.duplicate(true),
			"club_discard": p.club_discard.duplicate(true),
			"form_deck": form_card_names(p.form_deck.deck),
			"form_discard": form_card_names(p.form_deck.discard),
			"form_options": form_card_names(p.current_form_options),
			"form_forced": p.current_form_forced,
			"draft_options": p.current_draft_options.duplicate(true),
			"pending_club": p.pending_club.duplicate(true),
			"pending_new_card": p.pending_new_card,
			"ability_log": p.ability_log.duplicate(true),
			"armed": p.armed.duplicate(),
			"created_next": p.created_next.duplicate(),
			"draft_stage": p.draft_stage,
		})
	return {"players": out, "active_index": active_index, "state": state,
		"hole": current_hole_index, "draft_queue": _draft_queue.duplicate(),
		"simul_draft": _simul_draft}


func apply_deck_snapshot(decks: Dictionary) -> void:
	var entries: Array = decks.get("players", [])
	for i in range(mini(entries.size(), players.size())):
		var e: Dictionary = entries[i]
		var p: Player = players[i]
		p.hand = (e.get("hand", []) as Array).duplicate(true)
		p.club_deck = (e.get("club_deck", []) as Array).duplicate(true)
		p.club_discard = (e.get("club_discard", []) as Array).duplicate(true)
		p.form_deck.deck = form_cards_from_names(e.get("form_deck", []))
		p.form_deck.discard = form_cards_from_names(e.get("form_discard", []))
		p.current_form_options = form_cards_from_names(e.get("form_options", []))
		p.current_form_forced = bool(e.get("form_forced", false))
		p.current_draft_options = (e.get("draft_options", []) as Array).duplicate(true)
		p.pending_club = (e.get("pending_club", {}) as Dictionary).duplicate(true)
		p.pending_new_card = e.get("pending_new_card", null)
		p.ability_log = (e.get("ability_log", {}) as Dictionary).duplicate(true)
		p.armed = (e.get("armed", {}) as Dictionary).duplicate()
		p.created_next = (e.get("created_next", []) as Array).duplicate()
		p.draft_stage = str(e.get("draft_stage", ""))

	# The host's turn and phase are authoritative. next_to_play() compares
	# float distances, so recomputing them locally could tie differently —
	# cheaper and safer to be told.
	_simul_draft = bool(decks.get("simul_draft", false))
	if _simul_draft:
		# Mid-draft the host's turn and phase are the host's own view; this
		# machine shows its own seat's draft instead.
		view_seat(my_seat)
	else:
		if decks.has("active_index"):
			active_index = clampi(int(decks["active_index"]), 0, players.size() - 1)
		if decks.has("state"):
			state = int(decks["state"])
	if decks.has("draft_queue"):
		_draft_queue = (decks["draft_queue"] as Array).duplicate()
	# A hole change has to be adopted too, since start_hole() may have run
	# on the host as part of this action.
	if decks.has("hole") and int(decks["hole"]) != current_hole_index:
		current_hole_index = int(decks["hole"])
		hole = HoleData.for_round(current_hole_index, wind_seed)
		hole_yardage = hole.yardage
		hole_par = hole.par
		sync_map_to_active()


# ---------------------------------------------------------
# DISCONNECTS (online rounds)
# ---------------------------------------------------------

# A peer went away. Host only — clients learn about it from the broadcast,
# so every machine retires the seat the same way rather than each deciding
# for itself.
#
# Deferred when a shot is in flight: _resolve_shot_landing runs from an
# animation callback holding a closure that writes through `me`, so moving
# active_index out from under it would write a resolved shot into the
# wrong player. The queue is drained once the animation finishes.
func on_peer_dropped(peer_id: int) -> void:
	if not online or not is_authority():
		return
	var seat := seat_of_peer(peer_id)
	if seat < 0:
		return
	_pending_drops.append(seat)
	_drain_pending_drops()


func _drain_pending_drops() -> void:
	if _animating or _pending_drops.is_empty():
		return
	while not _pending_drops.is_empty():
		var seat: int = int(_pending_drops.pop_front())
		_retire_seat(seat)
		rpc("net_seat_abandoned", seat)


# Retires a seat so the round can finish without it. The player concedes
# the hole rather than being deleted: their card keeps a score, the
# standings still make sense, and every other seat plays on.
func _retire_seat(seat: int) -> void:
	if seat < 0 or seat >= players.size():
		return
	var p: Player = players[seat]
	if p.abandoned:
		return
	p.abandoned = true
	log_msg("\n[b]%s left the game.[/b]" % p.name)

	# Concede the current hole if they were still playing it, so the hole
	# can complete and the scorecard isn't left with a gap.
	if not p.holed_out:
		p.holed_out = true
		var conceded: int = maxi(p.strokes, hole_par + 3)
		p.round_scores.append({
			"hole": current_hole_index, "par": hole_par, "strokes": conceded})

	# They may have been mid-draft, which would otherwise stall the queue.
	_draft_queue = _draft_queue.filter(func(i): return int(i) != seat)
	if _simul_draft:
		p.draft_stage = DRAFT_DONE
		if not _finish_simultaneous_draft_if_done():
			view_seat(my_seat)
			refresh_ui()
		return

	if active_index == seat:
		# They were up. Hand over, or finish the hole if nobody is left.
		if advance_turn():
			state = State.CLUB_SELECT
			if me.current_lie == "green":
				start_putting()
			else:
				refresh_ui()
		else:
			begin_end_of_hole()
	else:
		refresh_ui()


# Clients: adopt the host's decision about a departed seat.
@rpc("authority", "reliable")
func net_seat_abandoned(seat: int) -> void:
	_retire_seat(seat)


# The host went away. There is no migration — it owned every decision and
# every deck — so the round ends rather than limping on.
func on_host_lost() -> void:
	if not online:
		return
	log_msg("\n[b]The host left — the round can't continue.[/b]")
	state = State.DONE
	refresh_ui()
