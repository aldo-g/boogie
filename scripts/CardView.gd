class_name CardView
extends Control

# ---------------------------------------------------------
# Reusable visual card for a club dictionary (see ClubRoster.make_club()).
#
# Set to the same grammar as a Form card (see CardFace.gd): the header —
# a dot in the maker's livery and the maker's name, the club's type at the
# right — then the name, the figure line (how far it carries, how much of
# a Form card's deviation it lets through), and its ability in words, with
# the club's engraving beside it. The engravings are 1920s printer's cuts
# (see assets/art/CREDITS.md), stored white so they print in ink.
#
# Three cuts of the one card:
#   the tile     — the bag. A narrow portrait: fourteen have to sit in one
#                  row, so it keeps to maker, name, engraving, carry, type.
#   the specimen — the draft. The club in full, and beside it what taking
#                  it would change in your bag. With four or five on offer
#                  (a called hole, a trade-in) it is cut narrow: no
#                  engraving, and the one thing that matters most beneath.
#   the detail   — what a tile shows under the cursor: the specimen's own
#                  column, so the club reads the same as the day it was
#                  drafted.
# ---------------------------------------------------------

const CardFace := preload("res://scripts/CardFace.gd")

signal picked(card_view: CardView)
# Emitted as the cursor enters/leaves the card, so the hole map can preview
# this club's reach without CardView needing to know the map exists.
signal hover_started(card_view: CardView)
signal hover_ended(card_view: CardView)

const CARD_SIZE := Vector2(296, 172)
const COMPACT_SIZE := Vector2(136, 172)
# The engraving column on a specimen.
const ART_WIDTH := 60.0
# A tile this wide or wider sets its name at the larger size. Like the
# maker's capitals and the carry's unit below, that is decided by the
# tile's width alone — never by what this one club happens to need — so
# the whole row changes together and no two tiles in a bag disagree.
const ROOMY_TILE := 118.0
# The longest carry there is, as a measure of what a tile has to hold.
const WIDEST_CARRY := [["190–255", "yds"]]
const DETAIL_WIDTH := 264.0

const CLUB_ART := {
	"wood": preload("res://assets/art/clubs/wood.svg"),
	"iron": preload("res://assets/art/clubs/iron.svg"),
	"wedge": preload("res://assets/art/clubs/wedge.svg"),
	"putter": preload("res://assets/art/clubs/putter.svg"),
}

var card: Dictionary = {}
var interactive: bool = true
var compact: bool = false

# Set before setup() to cut the card to something other than its stock
# size: the bag narrows its tiles as it fills, and the "something has to
# go" row drops the engraving to make room for what each cut would cost.
var width: float = 0.0
var height: float = 0.0
var show_art: bool = true
# Specimens only: what taking the club would change (DraftAdvisor's
# [{text, strong}]), set in a column of its own on the card's right, so
# each offer and its consequences are one object.
var notes: Array = []
const NOTES_WIDTH := 144.0
# A specimen narrower than this drops its engraving and its notes column.
const NARROW_SPECIMEN := 400.0
# The bag the club is read against, set before setup(): a Staff club plays
# differently once four of its maker's clubs are in it (ClubAbilities
# .is_awake), and the card shows it as it plays there. Empty: on its own.
var bag: Array = []
# A bag tile only: {good, bad}, the cards the club is dealt from (see
# _form_pips). Empty everywhere else.
var form: Dictionary = {}

var _panel: PanelContainer
var _size: Vector2 = CARD_SIZE
var _hover_tween: Tween
var _detail: PanelContainer   # tiles only: the hover detail
var _detail_timer: Timer      # dwell before the detail appears
var _layout_y: float = INF    # resting y from the container, captured on first hover
var _panel_style: StyleBoxFlat
var _edge: Color               # resting border colour
var _hovered: bool = false
var _selected: bool = false
var _ability_tip: String = ""  # an ability the specimen had to trim, in full
var _tip: String = ""

static var _widest_maker: float = -1.0


func setup(p_card: Dictionary, p_interactive: bool = true, p_compact: bool = false) -> void:
	card = p_card
	interactive = p_interactive
	compact = p_compact
	_build()


func _build() -> void:
	_size = COMPACT_SIZE if compact else CARD_SIZE
	if width > 0.0:
		_size.x = width
	if height > 0.0:
		_size.y = height
	custom_minimum_size = _size
	pivot_offset = _size / 2.0
	# Centred in the row rather than stretched to it, so there is headroom
	# for the hover lift inside the strip's clipping edge.
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var limited: bool = card.get("limited", false)
	# Limited editions are framed in gilt on a warm face — the draft is
	# where you need to spot them.
	_edge = BogeyTheme.GOLD if limited else BogeyTheme.NEUTRAL_300

	_panel = PanelContainer.new()
	_panel.position = Vector2.ZERO
	_panel.size = _size
	_panel_style = BogeyUI.card_style(10 if compact else 14, 9 if compact else 12, _edge)
	if limited:
		_panel_style.bg_color = BogeyTheme.GOLD_100
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# The face is cut to the card's size and whatever is set on it has to
	# fit; anything that does not is trimmed, never allowed to push the
	# card out over its neighbours.
	_panel.clip_contents = true
	add_child(_panel)

	if compact:
		_build_tile(limited)
	else:
		_build_specimen(limited)
	_panel.size = _size
	_refresh_tip()

	if interactive:
		_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_panel.mouse_entered.connect(_on_hover_start)
		_panel.mouse_exited.connect(_on_hover_end)
		_panel.gui_input.connect(_on_panel_input)


# ---------------------------------------------------------
# The cuts
# ---------------------------------------------------------

# The bag tile: maker, name, engraving, carry, type — top to bottom.
func _build_tile(limited: bool) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	var avail := _size.x - 22.0
	var roomy := _size.x >= ROOMY_TILE

	# Wide-set capitals if the longest maker's name would fit this tile,
	# plain lower case if not. A brandless club keeps the line's height,
	# so names sit level along the bag.
	var brand_id: String = card.get("brand", "")
	vbox.add_child(CardFace.header(Brands.color(brand_id), Brands.display_name(brand_id),
		BogeyTheme.NEUTRAL_700, "", BogeyTheme.NEUTRAL_600, _maker_fits_in_caps(avail)))

	vbox.add_child(CardFace.name_label(_short_name(),
		CardFace.NAME_SIZE_TILE if roomy else CardFace.NAME_SIZE_NARROW, avail))

	if show_art:
		var art := _engraving(30, limited)
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(art)
	else:
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(gap)

	# The carry is the number a club is chosen by, so it is set as a figure.
	var with_unit: bool = CardFace.figure_width(WIDEST_CARRY) <= avail
	var carry: Array = _carry_figure()
	vbox.add_child(CardFace.figure([carry if with_unit else [carry[0], ""]]))
	if int(form.get("good", 0)) + int(form.get("bad", 0)) > 0:
		vbox.add_child(_form_pips())

	# "LIMITED · WEDGE" where a tile has room for the longest of them; on a
	# narrower one the gilt frame says Limited and the label keeps to the type.
	var type_text: String = card.get("type", "")
	var kind_ink: Color = BogeyTheme.GOLD_800 if limited else BogeyTheme.NEUTRAL_600
	if limited and CardFace.caps_width("Limited · putter") <= avail:
		type_text = "Limited · " + type_text
	elif ClubAbilities.is_staff(card):
		# A Staff club says so where there is room, and goes green once the
		# bag has woken it.
		if CardFace.caps_width("Staff · wedge") <= avail:
			type_text = "Staff · " + type_text
		if ClubAbilities.is_awake(bag, card):
			kind_ink = BogeyTheme.FAIRWAY_DEEP
	# What has been done to the club (ClubAbilities, "Growth"): a curse
	# says its name in claret; wear and boosts are counted beside the type.
	var cursed := ClubAbilities.curse(card)
	var grown: int = int(card.get("level", 0)) + (card.get("boosts", []) as Array).size()
	# ...and the marks toward the next level, while there is one to earn.
	var marks: int = int(card.get("marks", 0)) % ClubAbilities.WEAR_MARKS
	if cursed != "":
		type_text = str(ClubAbilities.curse_info(cursed).name)
		kind_ink = BogeyTheme.FLAG
	elif ClubAbilities.wear_pending(card) > 0:
		type_text = "Worn in"
		kind_ink = BogeyTheme.FAIRWAY_DEEP
	else:
		if grown > 0:
			type_text += " +%d" % grown
		if marks > 0 and int(card.get("level", 0)) < ClubAbilities.MAX_LEVEL:
			type_text += "  %d/%d" % [marks, ClubAbilities.WEAR_MARKS]
	var kind := BogeyUI.kicker(type_text, kind_ink, CardFace.KICKER_SIZE)
	kind.clip_text = true
	kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(kind)


# The cards this club is dealt from right now, a dot each: green for a shot,
# claret for a miss. What picking the club puts at stake, without a hover.
func _form_pips() -> Control:
	var good := int(form.get("good", 0))
	var n := good + int(form.get("bad", 0))
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 8)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var step := minf(9.0, c.size.x / n)
		for i in range(n):
			c.draw_circle(Vector2(step * (i + 0.5), 4.0), minf(2.8, step * 0.38),
				BogeyTheme.FAIRWAY_DEEP if i < good else BogeyTheme.FLAG))
	return c


# The draft specimen: the engraving, the club in full, and what taking it
# would change.
func _build_specimen(limited: bool) -> void:
	if _size.x < NARROW_SPECIMEN:
		_build_narrow_specimen()
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	var plate := VBoxContainer.new()
	plate.add_theme_constant_override("separation", 4)
	plate.custom_minimum_size = Vector2(ART_WIDTH, 0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(plate)
	var art := _engraving(60, limited)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	plate.add_child(art)
	if limited:
		# Captioned like a plate in a book.
		var caption := BogeyUI.kicker("Limited", BogeyTheme.GOLD_800, CardFace.KICKER_SIZE)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(caption)

	var col := _club_column(_text_width(), _size.y - 24.0, false)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	if notes.is_empty():
		return
	var divider := ColorRect.new()
	divider.color = Color(BogeyTheme.INK, 0.1)
	divider.custom_minimum_size = Vector2(1, 0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(divider)

	var note_col := VBoxContainer.new()
	note_col.add_theme_constant_override("separation", 6)
	note_col.custom_minimum_size = Vector2(NOTES_WIDTH, 0)
	note_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(note_col)
	var head := BogeyUI.kicker("If you take it", BogeyTheme.NEUTRAL_600, CardFace.KICKER_SIZE)
	head.custom_minimum_size = Vector2(0, 13)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_col.add_child(head)
	for n in notes.slice(0, 3):
		var strong: bool = n.get("strong", false)
		var l := BogeyUI.body(str(n.text), 12, BogeyTheme.INK if strong else BogeyTheme.NEUTRAL_600)
		if strong:
			l.add_theme_font_override("font", BogeyUI.sans(500))
		var most: int = 5 if notes.size() == 1 else (3 if notes.size() == 2 else 2)
		l.max_lines_visible = most
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		CardFace.hold_lines(l, BogeyUI.sans(500 if strong else 450), 12, NOTES_WIDTH, most)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note_col.add_child(l)


# The specimen cut narrow, for a draft showing four or five: the club's
# column the full width of the card, and under a rule the first of its
# notes — DraftAdvisor puts the one that matters most first. The rest are
# on the hover.
func _build_narrow_specimen() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)

	var avail := _size.x - 28.0
	var note: Label = null
	var note_room := 0.0
	if not notes.is_empty():
		var n: Dictionary = notes[0]
		var strong: bool = n.get("strong", false)
		var font := BogeyUI.sans(500 if strong else 450)
		note = BogeyUI.body(str(n.text), 12, BogeyTheme.INK if strong else BogeyTheme.NEUTRAL_600)
		note.add_theme_font_override("font", font)
		note.max_lines_visible = 2
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		CardFace.hold_lines(note, font, 12, avail, 2)
		note_room = note.custom_minimum_size.y + 11.0

	var club := _club_column(avail, _size.y - 24.0 - note_room, false)
	club.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(club)
	if note != null:
		col.add_child(BogeyUI.hairline(0.1))
		col.add_child(note)


# The club in full: header, name, the figure line, and its ability. The
# same column is the body of a specimen and the whole of the hover detail.
# `room` is the height it has to fit, or 0 for as much as it needs; the
# ability is trimmed to the lines that leaves, and kept whole for the
# card's tooltip. `spell_out` adds what only the detail has room for.
func _club_column(avail: float, room: float, spell_out: bool) -> VBoxContainer:
	var limited: bool = card.get("limited", false)
	var ctype: String = card.get("type", "")
	var sep := 3
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", sep)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The maker leads — brand is the read the draft turns on (Section 3A) —
	# and the type closes the line. A club with no maker opens on its type.
	var brand_id: String = card.get("brand", "")
	var brand_name := Brands.display_name(brand_id)
	var staff := ClubAbilities.is_staff(card)
	var awake := ClubAbilities.is_awake(bag, card)
	# A narrow specimen has no plate to caption, so its header says Limited.
	var says_limited: bool = limited and (spell_out or (not compact and _size.x < NARROW_SPECIMEN))
	var type_text := ("Limited · " if says_limited else "") + ("Staff · " if staff else "") + ctype
	var type_ink: Color = BogeyTheme.GOLD_800 if limited else BogeyTheme.NEUTRAL_600
	if awake:
		type_ink = BogeyTheme.FAIRWAY_DEEP
	var head: Control
	if brand_name != "":
		head = CardFace.header(Brands.color(brand_id), brand_name, BogeyTheme.NEUTRAL_700,
			type_text, type_ink)
	else:
		head = CardFace.header(Color(0, 0, 0, 0), type_text, type_ink)
	col.add_child(head)

	var title := CardFace.name_label(_short_name() if brand_name != "" else str(card.get("name", "?")),
		CardFace.NAME_SIZE, avail)
	col.add_child(title)

	var fig := CardFace.figure([_carry_figure(), _deviation_figure()], avail)
	col.add_child(fig)

	var used: float = head.custom_minimum_size.y + title.custom_minimum_size.y \
		+ fig.custom_minimum_size.y + sep * 2

	if spell_out and ctype == "putter":
		var putt := CardFace.words("Playable anywhere. On the green, you aim the putt.")
		putt.custom_minimum_size = Vector2(avail, 0)
		col.add_child(putt)

	var ability: String = card.get("ability", "")
	if ability != "":
		var font := BogeyUI.sans(500)
		var l := CardFace.words(ability, BogeyTheme.GOLD_800 if limited else BogeyTheme.INK, 500)
		var spacing: float = l.get_theme_constant("line_spacing")
		var font_size: int = CardFace.TEXT_SIZE
		var line_h: float = font.get_height(font_size)
		var need := CardFace.line_count(ability, font, font_size, avail)
		var most := need
		if room > 0.0:
			# n lines stand n line-heights and n-1 spacings tall.
			most = _lines_in(room - used - sep, line_h, spacing)
			if need > most:
				# The longest abilities are set a size down before any of
				# them is trimmed.
				font_size -= 1
				l.add_theme_font_size_override("font_size", font_size)
				line_h = font.get_height(font_size)
				need = CardFace.line_count(ability, font, font_size, avail)
				most = _lines_in(room - used - sep, line_h, spacing)
		if need > most:
			l.max_lines_visible = most
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_ability_tip = ability
		var lines := mini(need, most)
		l.custom_minimum_size = Vector2(avail if room <= 0.0 else 0.0,
			line_h * lines + spacing * (lines - 1))
		col.add_child(l)

	# What only the detail has room for: whether a Staff club is awake in
	# this bag, and the shot the club brought to the Form deck.
	if spell_out and staff and not bag.is_empty():
		var held := int(Brands.counts(bag).get(brand_id, 0))
		var state_text := "Awake: %d %s clubs in the bag." % [held, brand_name] if awake \
			else "Asleep: %d of %d %s clubs in the bag." % [held, Brands.STAFF_TIER, brand_name]
		var state_line := CardFace.words(state_text,
			BogeyTheme.FAIRWAY_DEEP if awake else BogeyTheme.FLAG, 500)
		state_line.custom_minimum_size = Vector2(avail, 0)
		col.add_child(state_line)
	var putter := ClubAbilities.is_putter(card)
	if spell_out and ClubAbilities.grows(card):
		var bad := Brands.baggage(card)
		var brings := CardFace.words("Its shots: %s%s." % [Brands.shots_text(card),
			"" if bad == "" else ". A %s came with it" % bad])
		brings.custom_minimum_size = Vector2(avail, 0)
		col.add_child(brings)
	if spell_out and (putter or ClubAbilities.grows(card)):
		# How far it has come: what it has gained, and the marks to the next.
		var wear := ClubAbilities.growth_text(card)
		if putter and int(card.get("level", 0)) > 0:
			wear += ": wider putt bands"
		if ClubAbilities.wear_pending(card) > 0:
			wear += ("" if wear == "" else ". ") + "Worn in: a choice waits at the draft"
		elif int(card.get("level", 0)) < ClubAbilities.MAX_LEVEL:
			wear += ("" if wear == "" else ". ") + "%d of %d %s to wear in" % [
				int(card.get("marks", 0)) % ClubAbilities.WEAR_MARKS, ClubAbilities.WEAR_MARKS,
				"one-putts from 15 ft or more" if putter else "marks"]
		var wear_line := CardFace.words(wear + ".", BogeyTheme.FAIRWAY_DEEP)
		wear_line.custom_minimum_size = Vector2(avail, 0)
		col.add_child(wear_line)
		var cursed := ClubAbilities.curse(card)
		if cursed != "":
			var what := ClubAbilities.curse_info(cursed)
			var curse_line := CardFace.words("%s: %s. Mended by a %s at a fitting bay." % [what.name,
				str(what.does).to_lower(), str(ClubAbilities.BOOSTS[ClubAbilities.MENDS[cursed]].name).to_lower()],
				BogeyTheme.FLAG, 500)
			curse_line.custom_minimum_size = Vector2(avail, 0)
			col.add_child(curse_line)
	return col


# How many lines of text `room` pixels can hold.
static func _lines_in(room: float, line_h: float, spacing: float) -> int:
	return maxi(int(floor((room + spacing) / (line_h + spacing))), 1)


# Whether a column `avail` wide can set any maker's name in capitals
# beside its dot.
static func _maker_fits_in_caps(avail: float) -> bool:
	if _widest_maker < 0.0:
		for maker in Brands.DISPLAY.values():
			_widest_maker = maxf(_widest_maker, CardFace.caps_width(str(maker)))
	return _widest_maker + 11.0 <= avail


# Width of the column a specimen's text is set in.
func _text_width() -> float:
	var w: float = _size.x - 28.0 - ART_WIDTH - 12.0
	if not notes.is_empty():
		w -= NOTES_WIDTH + 25.0
	return w


# The maker's line already says "Titanist", so a name that opens with the
# maker would say it twice.
func _short_name() -> String:
	var name_text := str(card.get("name", "?"))
	var brand_name := Brands.display_name(card.get("brand", ""))
	if brand_name != "" and name_text.begins_with(brand_name + " "):
		return name_text.substr(brand_name.length() + 1)
	return name_text


# --- The two figures (see CardFace.gd) -----------------------------------

# How far: the club's carry band.
func _carry_figure() -> Array:
	return ["%d–%d" % [int(card.get("min_yard", 0)), int(card.get("max_yard", 0))], "yds"]


# How straight: the share of a Form card's deviation this club lets
# through — its type's (ShotResolver.BUFFER_BY_TYPE) as its own ability
# changes it. The other half of a Form card's "15° left".
func _deviation_figure() -> Array:
	var pct: int = int(round(ClubAbilities.buffer(card, bag) * 100.0))
	if pct <= 0:
		return ["No", "deviation"]
	if pct == 100:
		return ["Full", "deviation"]
	return ["%d%%" % pct, "deviation"]


# The club illustration for this card's type, printed in ink — gilt on a
# Limited. A type with no engraving leaves the plate blank.
func _engraving(min_height: float, limited: bool = false) -> Control:
	var ctype: String = card.get("type", "iron")
	var art := TextureRect.new()
	if CLUB_ART.has(ctype):
		art.texture = CLUB_ART[ctype]
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.self_modulate = Color(BogeyTheme.GOLD_800, 0.85) if limited else Color(BogeyTheme.NEUTRAL_800, 0.72)
	art.custom_minimum_size = Vector2(0, min_height)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


# ---------------------------------------------------------
# States
# ---------------------------------------------------------

# Hover text for the whole card. Set on the face, which is what takes the
# mouse — a tooltip on the card itself would never be reached. An ability
# the specimen had to trim is always given in full first.
func set_tip(text: String) -> void:
	_tip = text
	_refresh_tip()


func _refresh_tip() -> void:
	if _panel == null:
		return
	var parts := PackedStringArray()
	if _ability_tip != "":
		parts.append(_ability_tip)
	if _tip != "":
		parts.append(_tip)
	_panel.tooltip_text = "\n\n".join(parts)


# Marks this as the club in hand: a full ink edge, held for as long as the
# shot is being aimed and played.
func set_selected(on: bool) -> void:
	_selected = on
	CardFace.apply_state(_panel_style, _edge, _hovered, _selected)


# Steps a card back — the rest of the bag while one club is in hand, or a
# club the lie won't let you play.
func set_dimmed(on: bool) -> void:
	CardFace.set_dimmed(self, on)


# ---------------------------------------------------------
# The hover detail (tiles only)
# ---------------------------------------------------------

# A tile has room for maker, name, type and carry — but not for how much
# deviation the club lets through, or its ability, and that is exactly
# what you need in order to choose between two clubs that reach the same
# distance. So under the cursor a tile shows the club's full column, set
# the same as on the specimen it was drafted from.
#
# Built lazily on first hover and kept for the life of the card: these
# are short-lived nodes (rebuilt every refresh_ui) and the text never
# changes once set.
func _build_detail() -> void:
	if _detail:
		return

	var limited: bool = card.get("limited", false)
	var style := BogeyUI.card_style(14, 12, BogeyTheme.GOLD if limited else BogeyTheme.NEUTRAL_400)
	if limited:
		style.bg_color = BogeyTheme.GOLD_100
	style.shadow_color = BogeyTheme.SHADOW_LG
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 6)

	_detail = PanelContainer.new()
	_detail.add_theme_stylebox_override("panel", style)
	# The detail is a read-out, not a target: it must never eat the hover
	# that is keeping it open, or it would flicker as the cursor crossed it.
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	_detail.z_index = 100
	_detail.visible = false
	_detail.add_child(_club_column(DETAIL_WIDTH - 28.0, 0.0, true))

	# Parented to the viewport rather than to this card on purpose: the bag
	# row sits inside a ScrollContainer, whose clip_contents would cut off
	# anything drawn above the card. A viewport child is positioned in
	# global coordinates (see _place_detail) and clipped by nothing.
	var host := get_viewport()
	if host == null:
		# Not in the tree yet — nothing can be hovering us, so drop the
		# half-built detail and let the next hover rebuild it.
		_detail.queue_free()
		_detail = null
		return
	host.add_child(_detail)
	if not tree_exiting.is_connected(_free_detail):
		tree_exiting.connect(_free_detail)


# Places the detail above the card, nudged horizontally so it can never
# hang off the edge of the window — the bag row runs to both margins, so
# the first and last cards would otherwise push it out of view.
func _place_detail() -> void:
	_detail.reset_size()
	var card_size := _size
	var size_now := _detail.size
	# Centred over the card and sitting just above it, in global space.
	# Anchored to the card's resting y, not its live one: the hover lift is
	# still animating when the detail appears, and tracking it would make
	# the panel drift those few pixels as it fades in.
	var anchor := global_position
	if _layout_y != INF:
		anchor.y += _layout_y - position.y
	var pos := anchor + Vector2(
		(card_size.x - size_now.x) * 0.5, -size_now.y - 10.0)

	# Clear the whole bag panel, not just the card. Sitting "just above the
	# card" puts the detail on top of the bag's own header and brand rack,
	# which is what made it look clipped — the panel it overlapped simply
	# painted a hard edge across it. Lifting it clear of the panel's top
	# edge means it always opens into the empty board area above.
	var panel_top := _bag_panel_top()
	if panel_top != INF:
		pos.y = min(pos.y, panel_top - size_now.y - 8.0)

	# Keep it on screen: the bag row runs to both margins, so the first and
	# last cards would otherwise push the detail off the edge.
	var margin := 8.0
	var view := get_viewport_rect().size
	pos.x = clampf(pos.x, margin, view.x - size_now.x - margin)
	# If there is genuinely no room above, flip below the card instead.
	if pos.y < margin:
		pos.y = global_position.y + card_size.y + 10.0
	_detail.position = pos


# Global y of the top edge of the panel this card sits in, or INF if it
# can't be determined. Walks up to the nearest PanelContainer ancestor —
# the bag/draft strip — rather than hard-coding a height, so the detail
# keeps clearing it if that layout ever changes.
func _bag_panel_top() -> float:
	var n := get_parent()
	while n != null:
		if n is PanelContainer:
			return (n as PanelContainer).global_position.y
		n = n.get_parent()
	return INF


# Shown after a short dwell, not instantly: sweeping the cursor across the
# bag to reach the club you already want shouldn't strobe a panel over
# every card on the way.
func _show_detail() -> void:
	# A specimen already says everything the detail would.
	if not compact:
		return
	_build_detail()
	if not is_instance_valid(_detail):
		return
	if _detail_timer:
		_detail_timer.stop()
	else:
		_detail_timer = Timer.new()
		_detail_timer.one_shot = true
		_detail_timer.timeout.connect(_on_detail_timeout)
		add_child(_detail_timer)
	_detail_timer.start(0.35)


func _on_detail_timeout() -> void:
	# The cursor may have left during the dwell, or the card been taken out
	# of play by a pick, between the timer starting and firing.
	if not interactive or not is_visible_in_tree() or not is_instance_valid(_detail):
		return
	_detail.modulate.a = 0.0
	_detail.visible = true
	_place_detail()
	var tw := create_tween()
	tw.tween_property(_detail, "modulate:a", 1.0, 0.10)


func _hide_detail() -> void:
	if _detail_timer:
		_detail_timer.stop()
	if is_instance_valid(_detail):
		_detail.visible = false


# The detail is parented to the viewport, so it does NOT die with this card.
# Bag rows are rebuilt (and freed) on every refresh_ui, so without this the
# details would pile up in the viewport, one per card per refresh.
func _free_detail() -> void:
	if is_instance_valid(_detail):
		_detail.queue_free()
	_detail = null


# ---------------------------------------------------------
# Motion
# ---------------------------------------------------------

func _on_hover_start() -> void:
	if not interactive:
		return
	_hovered = true
	# No scale-up: the card holding its size keeps the bag row stable. A
	# small rise is enough to say "this one" without the text resampling
	# as it grows; the edge goes to full ink and the shadow deepens.
	_animate_lift(-CardFace.LIFT)
	z_index = 5
	_show_detail()
	CardFace.apply_state(_panel_style, _edge, true, _selected)
	hover_started.emit(self)


func _on_hover_end() -> void:
	if not interactive:
		return
	_hovered = false
	_animate_lift(0.0)
	z_index = 0
	_hide_detail()
	CardFace.apply_state(_panel_style, _edge, false, _selected)
	hover_ended.emit(self)


func _on_panel_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Before clearing `interactive`: _on_hover_end() bails on a
		# non-interactive card, so the detail has to come down here or it
		# would be stranded on screen after the pick.
		_hide_detail()
		interactive = false
		CardFace.pick_pop(self, func(): picked.emit(self))


# Hover feedback: a few pixels of rise rather than a zoom. Animates
# `position`, which the HBoxContainer sets on layout — so it is re-applied
# relative to the laid-out spot each time rather than accumulating.
func _animate_lift(offset_y: float) -> void:
	if _hover_tween:
		_hover_tween.kill()
	if _layout_y == INF:
		_layout_y = position.y
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "position:y", _layout_y + offset_y, CardFace.HOVER_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Plays a short "fly toward the hand" exit animation, then calls on_done.
func play_fly_to_hand(target_global_pos: Vector2, on_done: Callable) -> void:
	_hide_detail()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position", target_global_pos, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector2(0.4, 0.4), 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(on_done)


func play_fade_out(delay: float = 0.0) -> void:
	_hide_detail()
	CardFace.fade_out(self, delay)
