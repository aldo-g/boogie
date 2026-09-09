class_name BoogieUI
extends RefCounted

# ---------------------------------------------------------
# Shared styling helpers for the sheet layout — panels, hairlines, kickers
# and chips, all on BoogieTheme's palette. Keeps build_ui() readable and
# stops every screen inventing its own StyleBoxFlat.
# ---------------------------------------------------------

const PAD := 14


static func panel(bg: Color = BoogieTheme.PARCHMENT, pad: int = PAD, radius: int = 4) -> StyleBoxFlat:
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
	var s := panel(BoogieTheme.PARCHMENT, pad)
	s.border_color = Color(BoogieTheme.INK, 0.22)
	s.border_width_left = 1 if left else 0
	s.border_width_right = 1 if right else 0
	s.border_width_top = 1 if top else 0
	s.border_width_bottom = 1 if bottom else 0
	return s


static func make_panel(style: StyleBoxFlat) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	return p


# Small letter-spaced section label — "SCORECARD", "PLAY-BY-PLAY".
static func kicker(text: String, color: Color = BoogieTheme.SAND_DEEP) -> Label:
	var l := Label.new()
	var spaced := ""
	for i in text.to_upper().length():
		spaced += text.to_upper()[i]
		if i < text.length() - 1:
			spaced += " "
	l.text = spaced
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", color)
	return l


static func heading(text: String, size: int = 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", BoogieTheme.INK)
	return l


static func body(text: String, size: int = 13, color: Color = BoogieTheme.INK_SOFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


static func hairline(alpha: float = 0.2) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(BoogieTheme.INK, alpha)
	r.custom_minimum_size = Vector2(0, 1)
	return r


# Outlined pill — used for flight conditions, bag count, running score.
static func chip(text: String, accent: Color = BoogieTheme.INK_SOFT, filled: bool = false) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = accent if filled else Color(0, 0, 0, 0)
	s.set_corner_radius_all(99)
	s.border_color = accent
	s.set_border_width_all(1)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	var p := make_panel(s)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", BoogieTheme.PARCHMENT if filled else accent)
	p.add_child(l)
	return p


# The plate: a photograph-style mat around the hole map, so the board reads
# as an illustration tipped into the sheet rather than a viewport.
static func plate(content: Control, mat: int = 10) -> PanelContainer:
	var outer := make_panel(panel(BoogieTheme.PARCHMENT_RAISED, mat, 2))
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := make_panel(panel(BoogieTheme.CARD_BG, 1, 0))
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(content)
	outer.add_child(inner)
	return outer


# ---------------------------------------------------------
# Redesign helpers — the mockup's component vocabulary.
# ---------------------------------------------------------

# Rounded pill on a tonal fill, no border. The mockup leans on these for
# category tags (Wood/Iron/Limited) and Form-card kinds, where a filled
# chip reads faster than an outlined one at 10px.
static func tag(text: String, bg: Color, ink: Color) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(99)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	var p := make_panel(s)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", ink)
	p.add_child(l)
	return p


# A labelled figure on a tonal ground — "LIE / Fairway", "STROKES / 2".
# Three of these sit in a row under the big yards-to-pin number.
static func stat_block(label_text: String, value_text: String, bg: Color = BoogieTheme.NEUTRAL_200) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	var p := make_panel(s)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	p.add_child(col)

	var cap := Label.new()
	cap.text = label_text.to_upper()
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", BoogieTheme.NEUTRAL_700)
	col.add_child(cap)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 16)
	val.add_theme_color_override("font_color", BoogieTheme.INK)
	col.add_child(val)
	return p


# The big number + unit pair the shot panel opens with. Returns the value
# Label so callers can retext it without rebuilding the row.
static func big_stat(value_text: String, unit_text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 54)
	val.add_theme_color_override("font_color", BoogieTheme.INK)
	val.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(val)

	var unit := Label.new()
	unit.text = unit_text.to_upper()
	unit.add_theme_font_size_override("font_size", 12)
	unit.add_theme_color_override("font_color", BoogieTheme.NEUTRAL_600)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(unit)
	return [row, val]


# A soft-filled note box — the lie explainer under the stat row.
static func note_box(text: String, bg: Color, border: Color, ink: Color) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 11
	s.content_margin_bottom = 11
	var p := make_panel(s)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", ink)
	p.add_child(l)
	return p


# One play-by-play entry: a coloured tag, a bold headline, and body copy.
# Replaces the single scrolling RichTextLabel so each stroke is its own
# card and the eye can find "Stroke 3" without re-reading the wall.
static func log_entry(tag_text: String, tag_ink: Color, head_text: String, body_text: String) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = BoogieTheme.NEUTRAL_100
	s.set_corner_radius_all(12)
	s.border_color = BoogieTheme.RULE
	s.set_border_width_all(1)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 11
	s.content_margin_bottom = 11
	var p := make_panel(s)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	p.add_child(col)

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	col.add_child(head_row)

	var tag_label := Label.new()
	tag_label.text = tag_text.to_upper()
	tag_label.add_theme_font_size_override("font_size", 10)
	tag_label.add_theme_color_override("font_color", tag_ink)
	tag_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(tag_label)

	if head_text != "":
		var head := Label.new()
		head.text = head_text
		head.add_theme_font_size_override("font_size", 14)
		head.add_theme_color_override("font_color", BoogieTheme.INK)
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.autowrap_mode = TextServer.AUTOWRAP_WORD
		head_row.add_child(head)

	if body_text != "":
		var body_label := Label.new()
		body_label.text = body_text
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		body_label.add_theme_font_size_override("font_size", 13)
		body_label.add_theme_color_override("font_color", BoogieTheme.NEUTRAL_700)
		col.add_child(body_label)
	return p


# The step pill in the header — a numbered circle plus the current
# instruction, so "what do I do now" is one glance, not a hunt.
static func step_pill(step_text: String, hint_text: String) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = BoogieTheme.ACCENT_100
	s.set_corner_radius_all(99)
	s.border_color = BoogieTheme.ACCENT_300
	s.set_border_width_all(1)
	s.content_margin_left = 14
	s.content_margin_right = 20
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	var p := make_panel(s)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)

	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = BoogieTheme.SAND
	dot_style.set_corner_radius_all(99)
	dot_style.content_margin_left = 8
	dot_style.content_margin_right = 8
	dot_style.content_margin_top = 3
	dot_style.content_margin_bottom = 3
	var dot := make_panel(dot_style)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_label := Label.new()
	dot_label.text = step_text
	dot_label.add_theme_font_size_override("font_size", 13)
	dot_label.add_theme_color_override("font_color", BoogieTheme.PARCHMENT)
	dot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.add_child(dot_label)
	row.add_child(dot)

	var hint := Label.new()
	hint.text = hint_text
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", BoogieTheme.ACCENT_800)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	return p


# Stacked figure chip for the header's right rail — "THRU 3 / +2".
static func meta_stat(label_text: String, value_text: String, bg: Color, ink: Color) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(99)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	var p := make_panel(s)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_END
	p.add_child(col)

	var cap := Label.new()
	cap.text = label_text.to_upper()
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", ink)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(cap)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 19)
	val.add_theme_color_override("font_color", ink)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(val)
	return p
