extends RefCounted

# ---------------------------------------------------------
# The one card. A club and a Form card are cut from the same stock and
# set in the same order, so a player who can read one can read the other:
#
#   ● WHOSE IT IS, OR WHAT KIND          QUALIFIER    the header
#   Name                                              Garamond
#   150–180 yds  ·  75% of deviation                  the figure line
#   Anything else it does, in words.                  Jost
#
# with one ink drawing beside it: the club's engraving, or the Form
# card's shot drawn to scale.
#
# The figure line is the same two facts on both — how far, then how
# straight — because those are the two numbers a shot multiplies together:
# the club's carry by the card's distance, the card's degrees by the share
# of deviation the club lets through.
#
# CardView and FormCardView build their faces from the pieces here, and
# take their hover, pick and dim behaviour from here too, so the two
# cannot drift apart again. Loaded by preload, not class_name:
#   const CardFace := preload("res://scripts/CardFace.gd")
# ---------------------------------------------------------

# --- The type scale ---------------------------------------------------
const NAME_SIZE := 22          # a card with room: draft card, Form row, hover detail
const NAME_SIZE_TILE := 17     # a bag tile
const NAME_SIZE_NARROW := 15   # a bag tile with all fourteen in the row
const FIGURE_SIZE := 18        # the numerals of the figure line
const UNIT_SIZE := 11          # ...and the words that label them
const KICKER_SIZE := 9
const TEXT_SIZE := 13

# --- States -----------------------------------------------------------
const DIM_ALPHA := 0.42        # a card stepped back: not playable, or passed over
const LIFT := 6.0              # how far a card comes out of its row under the cursor
const HOVER_TIME := 0.14


# ---------------------------------------------------------
# Pieces of the face
# ---------------------------------------------------------

# The line at the head of every card: a dot, whose card it is or what kind,
# and a qualifier set to the right. A club's dot is its maker's livery; a
# Form card's is green or claret. With no dot colour (alpha 0) the dot is
# left out; with `caps` off the text is set in plain lower case, for a
# column too narrow for wide-set capitals.
static func header(dot_color: Color, text: String, ink: Color,
		right_text: String = "", right_ink: Color = BogeyTheme.NEUTRAL_600,
		caps: bool = true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.custom_minimum_size = Vector2(0, 13)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dot_color.a > 0.0 and text != "":
		row.add_child(BogeyUI.dot(dot_color, 6))
	var l: Label
	if caps:
		l = BogeyUI.kicker(text, ink, KICKER_SIZE)
	else:
		l = BogeyUI.label(text, 11, ink, 500)
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	if right_text != "":
		var r := BogeyUI.kicker(right_text, right_ink, KICKER_SIZE)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(r)
	return row


# Width of a string set as a kicker (small wide capitals).
static func caps_width(text: String) -> float:
	return BogeyUI.sans(600, 2).get_string_size(
		text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, KICKER_SIZE).x


# The card's name. Wraps to `most` lines inside `avail` and trims after.
static func name_label(text: String, font_size: int, avail: float, most: int = 2) -> Label:
	var l := Label.new()
	# Non-breaking hyphens, so "7-Iron" never splits as "7-" and "Iron".
	l.text = text.replace("-", "‑")
	BogeyUI.set_font(l, BogeyUI.serif(600), font_size, BogeyTheme.INK)
	l.add_theme_constant_override("line_spacing", -3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if avail > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.max_lines_visible = most
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hold_lines(l, BogeyUI.serif(600), font_size, avail, most)
	return l


# How many lines `text` takes when set in `avail`.
static func line_count(text: String, font: Font, font_size: int, avail: float) -> int:
	var line_h: float = font.get_height(font_size)
	var need: float = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
		maxf(avail, 1.0), font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y
	return maxi(int(round(need / maxf(line_h, 1.0))), 1)


# A wrapping label that trims with an ellipsis asks for only one line of
# height, and gets exactly that. This measures the text against the width
# it will be set in and holds the lines it needs, up to `most`. Returns
# the number of lines held.
static func hold_lines(l: Label, font: Font, font_size: int, avail: float, most: int) -> int:
	var lines: int = clampi(line_count(l.text, font, font_size, avail), 1, most)
	var line_h: float = font.get_height(font_size)
	var spacing: float = l.get_theme_constant("line_spacing") if l.has_theme_constant_override("line_spacing") else 0.0
	l.custom_minimum_size.y = line_h * lines + spacing * (lines - 1)
	return lines


# The figure line: each part a datum and the word that labels it —
# ["150–180", "yds"], ["15°", "left"] — the datum in Garamond figures, the
# label small beside it, parts divided by a middle dot. Drawn on one
# baseline rather than set in labels, which cannot share one across two
# faces. If the parts will not fit `avail` side by side, each takes a line.
static func figure(parts: Array, avail: float = 0.0, font_size: int = FIGURE_SIZE,
		ink: Color = BogeyTheme.INK) -> Control:
	var datum_font := BogeyUI.serif(600)
	var unit_font := BogeyUI.sans(450)
	var unit_size := _unit_size(font_size)
	var runs := _figure_runs(parts, font_size)
	var total := _runs_width(runs)
	var stacked: bool = avail > 0.0 and total > avail and runs.size() > 1

	# Lining figures stand at about cap height, well inside the face's own
	# line box, so the line is set tighter than a Label would set it.
	var line_h: float = roundf(font_size * 1.2)
	var baseline: float = roundf(font_size * 0.92)
	var widest := 0.0
	for r in runs:
		widest = maxf(widest, r[3])

	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(
		ceilf(widest if stacked else total), line_h * (runs.size() if stacked else 1))
	c.draw.connect(func():
		var x := 0.0
		var y := baseline
		for i in runs.size():
			var r: Array = runs[i]
			if i > 0:
				if stacked:
					x = 0.0
					y += line_h
				else:
					c.draw_circle(Vector2(x + FIGURE_SEP / 2.0, y - font_size * 0.26), 1.2,
						BogeyTheme.NEUTRAL_500, true, -1.0, true)
					x += FIGURE_SEP
			c.draw_string(datum_font, Vector2(x, y), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
			if r[1] != "":
				c.draw_string(unit_font, Vector2(x + r[2] + FIGURE_GAP, y), r[1],
					HORIZONTAL_ALIGNMENT_LEFT, -1, unit_size, BogeyTheme.NEUTRAL_700)
			x += r[3])
	return c


# Width of a figure line's parts set side by side.
static func figure_width(parts: Array, font_size: int = FIGURE_SIZE) -> float:
	return _runs_width(_figure_runs(parts, font_size))


const FIGURE_GAP := 4.0    # between a datum and its label
const FIGURE_SEP := 17.0   # the middle dot and the air either side of it


static func _unit_size(font_size: int) -> int:
	return UNIT_SIZE if font_size >= FIGURE_SIZE else UNIT_SIZE - 1


# Each part measured: [datum, label, datum width, whole width].
static func _figure_runs(parts: Array, font_size: int) -> Array:
	var datum_font := BogeyUI.serif(600)
	var unit_font := BogeyUI.sans(450)
	var unit_size := _unit_size(font_size)
	var runs: Array = []
	for p in parts:
		var datum := str(p[0])
		var unit := str(p[1]) if p.size() > 1 else ""
		var dw: float = datum_font.get_string_size(datum, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var uw: float = 0.0
		if unit != "":
			uw = FIGURE_GAP + unit_font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, unit_size).x
		runs.append([datum, unit, dw, dw + uw])
	return runs


static func _runs_width(runs: Array) -> float:
	var total := 0.0
	for r in runs:
		total += r[3]
	return total + FIGURE_SEP * maxi(runs.size() - 1, 0)


# Everything else the card does, in words. A remark is set grey at the
# regular weight; the line that is the card's own — a club's ability — in
# ink at 500.
static func words(text: String, ink: Color = BogeyTheme.NEUTRAL_700, weight: int = 450) -> Label:
	var l := Label.new()
	l.text = text
	BogeyUI.set_font(l, BogeyUI.sans(weight), TEXT_SIZE, ink)
	# Set a little closer than running text elsewhere: a card is a small page.
	l.add_theme_constant_override("line_spacing", 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------
# States
# ---------------------------------------------------------

# The card's edge and shadow for the state it is in. At rest: a hairline in
# `rest_edge` and the faintest shadow. Under the cursor: an ink edge and a
# deeper shadow, so the card reads as lifted off its row. Selected — the
# club in hand, the Form card being played — a full ink edge, held.
# `stripe` is the width of a coloured rule down the left edge, which keeps
# its room whatever the state.
static func apply_state(style: StyleBoxFlat, rest_edge: Color, hovered: bool,
		selected: bool, stripe: int = 0) -> void:
	if style == null:
		return
	style.border_color = BogeyTheme.INK if (hovered or selected) else rest_edge
	style.set_border_width_all(2 if selected else 1)
	if stripe > 0:
		style.border_width_left = stripe
	style.shadow_color = BogeyTheme.SHADOW_MD if hovered else BogeyTheme.SHADOW_SM
	style.shadow_size = 14 if hovered else 6
	style.shadow_offset = Vector2(0, 6) if hovered else Vector2(0, 2)


static func set_dimmed(c: CanvasItem, on: bool) -> void:
	c.modulate.a = DIM_ALPHA if on else 1.0


# ---------------------------------------------------------
# Motion
# ---------------------------------------------------------

# The pick: a small swell and settle, then `done`. The same beat for a
# club and a Form card, so choosing feels like one act wherever it happens.
static func pick_pop(c: Control, done: Callable) -> void:
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(1.04, 1.04), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(0.98, 0.98), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(done)


# The cards passed over, once one has been taken.
static func fade_out(c: Control, delay: float = 0.0) -> void:
	var tw := c.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 0.0, 0.18)
	tw.parallel().tween_property(c, "scale", Vector2(0.96, 0.96), 0.18)
