class_name BogeyUI
extends RefCounted

# ---------------------------------------------------------
# Shared type and styling helpers, on BogeyTheme's palette.
#
# The look is a printed yardage book: white stock, black ink, hairline
# rules, and two typefaces — a Garamond for anything you'd read aloud (a
# club's name, a hole, the yards to the pin) and a geometric sans for
# anything that labels it. Sections are parted by rules and white space,
# never by filled boxes, and nothing is a pill.
# ---------------------------------------------------------

const PAD := 14

const FONT_SERIF := preload("res://assets/fonts/CormorantGaramond-VF.ttf")
const FONT_SERIF_ITALIC := preload("res://assets/fonts/CormorantGaramond-Italic-VF.ttf")
const FONT_SANS := preload("res://assets/fonts/Jost-VF.ttf")
# The wordmark's hand.
const FONT_SCRIPT := preload("res://assets/fonts/AlexBrush-Regular.ttf")

# Corner radius for anything card-like. Small on purpose: tailored, not bubbly.
const RADIUS := 3

static var _fonts: Dictionary = {}
static var _theme: Theme


# ---------------------------------------------------------
# Type
# ---------------------------------------------------------

# A cut of one of the variable fonts above. Cached: a FontVariation is a
# resource, and every label on screen would otherwise make its own.
static func _cut(key: String, base: Font, weight: int, tracking: int, lining: bool) -> Font:
	var id := "%s/%d/%d" % [key, weight, tracking]
	if _fonts.has(id):
		return _fonts[id]
	var ts := TextServerManager.get_primary_interface()
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {ts.name_to_tag("wght"): weight}
	v.spacing_glyph = tracking
	if lining:
		# Cormorant's figures are old-style by default, which reads as
		# prose; yardages and scores want lining figures.
		v.opentype_features = {ts.name_to_tag("lnum"): 1}
	_fonts[id] = v
	return v


# Display face: names, holes, and every number worth reading from across the room.
static func serif(weight: int = 600) -> Font:
	return _cut("serif", FONT_SERIF, weight, 0, true)


# The caddy's voice, and captions.
static func serif_italic(weight: int = 500) -> Font:
	return _cut("serif-italic", FONT_SERIF_ITALIC, weight, 0, true)


# Text face. `tracking` is extra pixels between glyphs — small caps labels
# are set wide, running text is not.
static func sans(weight: int = 450, tracking: int = 0) -> Font:
	return _cut("sans", FONT_SANS, weight, tracking, false)


# The project's look for stock controls — default face, tooltips, popups,
# scrollbars — so nothing falls back to Godot's grey. Each screen's root
# Control takes this as its theme.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = sans()
	t.default_font_size = 14

	t.set_color("font_color", "Label", BogeyTheme.INK)

	var tip := _box(BogeyTheme.INK, Color(0, 0, 0, 0), 0, RADIUS, 12, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", BogeyTheme.NEUTRAL_100)
	t.set_font_size("font_size", "TooltipLabel", 13)

	var popup := _box(BogeyTheme.CARD_BG, BogeyTheme.NEUTRAL_400, 1, RADIUS + 1, 24, 22)
	t.set_stylebox("panel", "PopupPanel", popup)

	for bar in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxEmpty.new()
		track.content_margin_left = 3
		track.content_margin_right = 3
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("scroll_focus", bar, track)
		t.set_stylebox("grabber", bar, _box(BogeyTheme.NEUTRAL_400, Color(0, 0, 0, 0), 0, 3, 0, 0))
		t.set_stylebox("grabber_highlight", bar, _box(BogeyTheme.NEUTRAL_500, Color(0, 0, 0, 0), 0, 3, 0, 0))
		t.set_stylebox("grabber_pressed", bar, _box(BogeyTheme.NEUTRAL_600, Color(0, 0, 0, 0), 0, 3, 0, 0))

	# Sliders: a hairline track and an ink thumb.
	var slider := StyleBoxFlat.new()
	slider.bg_color = BogeyTheme.NEUTRAL_300
	slider.content_margin_top = 1
	slider.content_margin_bottom = 1
	var slider_fill := slider.duplicate() as StyleBoxFlat
	slider_fill.bg_color = BogeyTheme.INK
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	_theme = t
	return t


static func set_font(l: Control, font: Font, size: int, color: Color) -> void:
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


# ---------------------------------------------------------
# Surfaces
# ---------------------------------------------------------

static func panel(bg: Color = BogeyTheme.PARCHMENT, pad: int = PAD, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


# A panel with hairline edges on the named sides — the sheet is parted by
# rules, not by filled blocks.
static func ruled_panel(left: bool = false, right: bool = false, top: bool = false, bottom: bool = false, pad: int = PAD) -> StyleBoxFlat:
	var s := panel(BogeyTheme.PARCHMENT, pad)
	s.border_color = BogeyTheme.RULE
	s.border_width_left = 1 if left else 0
	s.border_width_right = 1 if right else 0
	s.border_width_top = 1 if top else 0
	s.border_width_bottom = 1 if bottom else 0
	return s


static func make_panel(style: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	return p


# A white card: hairline edge, the faintest shadow. Every card on screen —
# club, Form, popup — is cut from this.
static func card_style(pad_x: int = 12, pad_y: int = 10, border: Color = BogeyTheme.NEUTRAL_300) -> StyleBoxFlat:
	var s := _box(BogeyTheme.CARD_BG, border, 1, RADIUS, pad_x, pad_y)
	s.shadow_color = BogeyTheme.SHADOW_SM
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s


static func margin(content: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_child(content)
	return m


# ---------------------------------------------------------
# Text
# ---------------------------------------------------------

# Small, wide-set capitals — the label over a figure, the name of a section.
static func kicker(text: String, color: Color = BogeyTheme.INK_SOFT, size: int = 10) -> Label:
	var l := Label.new()
	l.text = text
	l.uppercase = true
	set_font(l, sans(600, 2), size, color)
	return l


static func heading(text: String, size: int = 26) -> Label:
	var l := Label.new()
	l.text = text
	set_font(l, serif(600), size, BogeyTheme.INK)
	return l


static func body(text: String, size: int = 13, color: Color = BogeyTheme.INK_SOFT) -> Label:
	var l := Label.new()
	l.text = text
	set_font(l, sans(), size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


# A single line that never wraps — for anything set in a row beside
# something else, where a wrapping label would collapse to a column.
static func label(text: String, size: int = 13, color: Color = BogeyTheme.INK, weight: int = 450) -> Label:
	var l := Label.new()
	l.text = text
	set_font(l, sans(weight), size, color)
	return l


static func hairline(alpha: float = 0.12) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(BogeyTheme.INK, alpha)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# A small round swatch — a brand's livery or a player's seat colour,
# reduced to the one dot that tells them apart.
static func dot(color: Color, diameter: int = 7, filled: bool = true) -> Control:
	var d := Control.new()
	d.custom_minimum_size = Vector2(diameter, diameter)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.draw.connect(func():
		var c := d.size / 2.0
		var r := diameter / 2.0
		if filled:
			d.draw_circle(c, r, color, true, -1.0, true)
		else:
			d.draw_arc(c, r - 0.75, 0, TAU, 24, color, 1.5, true))
	return d


# A swatch and a label: "● TITANIST 7". `strong` sets it in full ink —
# used for a set that is live, as against one still being collected.
# Returns a PanelContainer so callers can hang a tooltip on it.
static func chip(text: String, accent: Color = BogeyTheme.INK_SOFT, strong: bool = false) -> PanelContainer:
	var p := make_panel(StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	row.add_child(dot(accent, 7, strong))
	var l := kicker(text, BogeyTheme.INK if strong else BogeyTheme.NEUTRAL_600)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return p


# The plate: the hole map mounted like a print — a narrow white mat and a
# hairline — so the board reads as an illustration tipped into the sheet.
static func plate(content: Control, mat: int = 6) -> PanelContainer:
	var s := _box(BogeyTheme.CARD_BG, BogeyTheme.NEUTRAL_400, 1, 2, mat, mat)
	s.shadow_color = BogeyTheme.SHADOW_MD
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	var outer := make_panel(s)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(content)
	return outer


# A sewn-in label: tiny capitals on a tonal ground, square-cornered.
static func tag(text: String, bg: Color, ink: Color) -> PanelContainer:
	var s := _box(bg, Color(0, 0, 0, 0), 0, 2, 6, 2)
	var p := make_panel(s)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.add_child(kicker(text, ink, 9))
	return p


# A labelled figure — "ROUNDS / 12". The label is a kicker, the figure is
# set in the display face.
static func stat_block(label_text: String, value_text: String, _bg: Color = BogeyTheme.NEUTRAL_200) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = BogeyTheme.RULE
	s.border_width_top = 1
	s.content_margin_top = 8
	s.content_margin_bottom = 4
	var p := make_panel(s)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	p.add_child(col)
	col.add_child(kicker(label_text))

	var val := Label.new()
	val.text = value_text
	set_font(val, serif(600), 22, BogeyTheme.INK)
	col.add_child(val)
	return p


# One line of a spec sheet: a label on the left, its value on the right.
# Returns the row; the value wraps under itself if it runs long.
static func spec_row(label_text: String, value_text: String, value_color: Color = BogeyTheme.INK) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var cap := kicker(label_text)
	cap.custom_minimum_size = Vector2(72, 0)
	cap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(cap)
	var val := body(value_text, 14, value_color)
	val.add_theme_font_override("font", sans(500))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 5)
	wrap.add_theme_constant_override("margin_bottom", 5)
	wrap.add_child(row)
	return wrap


# The one number the panel is about, with its unit set small beneath it.
# Drawn rather than set in a Label: a Label reserves the face's whole line
# box, which at this size is a third again taller than the figures, and
# that air is better spent elsewhere in the column.
# Returns [block, the numeral's Control].
static func big_stat(value_text: String, unit_text: String, px: int = 88) -> Array:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	var font := serif(500)
	var figure_h: float = px * 0.66   # lining figures stand at about cap height
	var num := Control.new()
	num.custom_minimum_size = Vector2(
		font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, figure_h + 4.0)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.draw.connect(func():
		# Nudged left so the figure's stem, not its side bearing, meets the margin.
		num.draw_string(font, Vector2(-px * 0.03, figure_h + 2.0), value_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, px, BogeyTheme.INK))
	col.add_child(num)

	col.add_child(kicker(unit_text))
	return [col, num]


# A marginal note: a short rule down the left and the text beside it. The
# rule's colour says what kind of note — claret for a cost, green for good
# news, grey for a plain remark. `_bg` is unused; notes sit on the page.
static func note_box(text: String, _bg: Color, rule: Color, ink: Color) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = rule
	s.border_width_left = 2
	s.content_margin_left = 12
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	var p := make_panel(s)
	var l := body(text, 13, ink)
	p.add_child(l)
	return p


# The step line over the map — a ringed numeral plus the one instruction
# that goes with it, so "what do I do now" is one glance.
static func step_pill(step_text: String, hint_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	if step_text.is_valid_int():
		var ring := Control.new()
		ring.custom_minimum_size = Vector2(22, 22)
		ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var font := sans(600)
		ring.draw.connect(func():
			var c := ring.size / 2.0
			ring.draw_arc(c, 10.0, 0, TAU, 40, BogeyTheme.INK, 1.0, true)
			var w := font.get_string_size(step_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			ring.draw_string(font, Vector2(c.x - w / 2.0, c.y + 4.0), step_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BogeyTheme.INK))
		row.add_child(ring)

	var hint := Label.new()
	hint.text = hint_text
	set_font(hint, serif_italic(500), 20, BogeyTheme.INK)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	return row


# ---------------------------------------------------------
# Controls
# ---------------------------------------------------------

static func _box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = RADIUS, pad_x: int = 18, pad_y: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


# Primary = solid ink, for the one action a screen wants you to take;
# secondary = a hairline box for everything else.
static func style_button(b: Button, primary: bool = false, font_size: int = 14) -> Button:
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	var ink: Color
	if primary:
		normal = _box(BogeyTheme.INK, BogeyTheme.INK, 1)
		hover = _box(BogeyTheme.NEUTRAL_800, BogeyTheme.NEUTRAL_800, 1)
		pressed = _box(Color.BLACK, Color.BLACK, 1)
		ink = BogeyTheme.NEUTRAL_100
	else:
		normal = _box(BogeyTheme.CARD_BG, BogeyTheme.NEUTRAL_400, 1)
		hover = _box(BogeyTheme.CARD_BG, BogeyTheme.INK, 1)
		pressed = _box(BogeyTheme.NEUTRAL_200, BogeyTheme.INK, 1)
		ink = BogeyTheme.INK
	var disabled := _box(BogeyTheme.NEUTRAL_200, BogeyTheme.NEUTRAL_300, 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, ink)
	b.add_theme_color_override("font_disabled_color", BogeyTheme.NEUTRAL_500)
	b.add_theme_font_override("font", sans(500))
	b.add_theme_font_size_override("font_size", font_size)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


# Text-only button for navigation — no box at all, small wide capitals
# that darken under the cursor. Set the button's text in capitals.
static func style_link_button(b: Button, font_size: int = 11) -> Button:
	b.flat = true
	for key in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", BogeyTheme.NEUTRAL_600)
	b.add_theme_color_override("font_hover_color", BogeyTheme.INK)
	b.add_theme_color_override("font_pressed_color", BogeyTheme.INK)
	b.add_theme_color_override("font_hover_pressed_color", BogeyTheme.INK)
	b.add_theme_color_override("font_focus_color", BogeyTheme.NEUTRAL_600)
	b.add_theme_font_override("font", sans(600, 2))
	b.add_theme_font_size_override("font_size", font_size)
	b.text = b.text.to_upper()
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func style_line_edit(e: LineEdit, font_size: int = 15) -> LineEdit:
	e.add_theme_stylebox_override("normal", _box(BogeyTheme.CARD_BG, BogeyTheme.NEUTRAL_400, 1, RADIUS, 12, 8))
	e.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), BogeyTheme.INK, 1, RADIUS, 12, 8))
	e.add_theme_color_override("font_color", BogeyTheme.INK)
	e.add_theme_color_override("font_placeholder_color", BogeyTheme.NEUTRAL_500)
	e.add_theme_color_override("caret_color", BogeyTheme.INK)
	e.add_theme_color_override("selection_color", BogeyTheme.NEUTRAL_300)
	e.add_theme_color_override("font_selected_color", BogeyTheme.INK)
	e.add_theme_font_size_override("font_size", font_size)
	return e
