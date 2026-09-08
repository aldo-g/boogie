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
