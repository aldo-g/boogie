class_name BagCoverageView
extends Control

# ---------------------------------------------------------
# The bag's yardages on one ruler: a line a club, longest first, each
# drawn as its carry band with the sweet spot (the Mid tier) in full ink.
# Stretches no club reaches are shaded claret, so what's missing reads at
# a glance rather than from a sentence.
#
# Two things can be laid over it:
#   offer — a draft offer being passed over. It slots into the ruler where
#           it would sit in the bag, in green, with the yards it adds that
#           nothing else covers in solid green.
#   focus — a bag club being passed over while choosing a shot. It stays
#           in ink and the rest step back.
# and `pin_yards` marks the distance to the flag with a dashed claret line.
#
# Putters aren't about carry and are left off.
# ---------------------------------------------------------

const NAME_W := 112.0
const ROW_H := 26.0
const BAR_H := 12.0
const AXIS_H := 24.0
const TOP_PAD := 20.0     # room for the pin label and gap labels above the rows

var bag: Array = []
var offer: Dictionary = {}
var focus: Dictionary = {}
var pin_yards: float = -1.0
# Keep a row free for the offer, so the chart doesn't jump in height as
# the cursor moves on and off the draft cards.
var reserve_offer_row: bool = false


func setup(p_bag: Array, p_pin_yards: float = -1.0, p_reserve_offer_row: bool = false) -> void:
	bag = p_bag
	pin_yards = p_pin_yards
	reserve_offer_row = p_reserve_offer_row
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize()
	queue_redraw()


func set_offer(club: Dictionary) -> void:
	if offer == club:
		return
	offer = club
	_resize()
	queue_redraw()


func set_focus(club: Dictionary) -> void:
	if focus == club:
		return
	focus = club
	queue_redraw()


static func _carries(club: Dictionary) -> bool:
	return club.get("type", "") != "putter" and float(club.get("max_yard", 0.0)) > 0.0


func _bag_clubs() -> Array:
	var out: Array = bag.filter(_carries)
	out.sort_custom(func(a, b): return float(a.max_yard) > float(b.max_yard))
	return out


# The rows to draw: the bag's clubs, with the offer slotted in by length.
func _rows() -> Array:
	var rows: Array = []
	for c in _bag_clubs():
		rows.append({"club": c, "offer": false})
	if not offer.is_empty() and _carries(offer):
		var at := rows.size()
		for i in range(rows.size()):
			if float(offer.max_yard) > float(rows[i].club.max_yard):
				at = i
				break
		rows.insert(at, {"club": offer, "offer": true})
	return rows


func _row_count() -> int:
	var n := _bag_clubs().size()
	if reserve_offer_row or (not offer.is_empty() and _carries(offer)):
		n += 1
	return maxi(n, 1)


func _resize() -> void:
	custom_minimum_size = Vector2(0, TOP_PAD + _row_count() * ROW_H + AXIS_H)


# Stretches between the bag's shortest and longest carry that no club
# reaches, GAP_YARDS or wider — as [Vector2(from, to)].
static func gaps(clubs: Array) -> Array:
	var bands: Array = []
	for c in clubs:
		if _carries(c):
			bands.append(Vector2(float(c.min_yard), float(c.max_yard)))
	if bands.size() < 2:
		return []
	bands.sort_custom(func(a, b): return a.x < b.x)
	var out: Array = []
	var cursor: float = bands[0].y
	for i in range(1, bands.size()):
		var b: Vector2 = bands[i]
		if b.x - cursor >= DraftAdvisor.GAP_YARDS:
			out.append(Vector2(cursor, b.x))
		cursor = maxf(cursor, b.y)
	return out


# The ruler starts at the 50 below the shortest carry shown, so a bag of
# mid and long clubs isn't squeezed into the right half of the chart.
func _scale_min() -> float:
	var low := INF
	for c in bag:
		if _carries(c):
			low = minf(low, float(c.min_yard))
	if not offer.is_empty() and _carries(offer):
		low = minf(low, float(offer.min_yard))
	if low == INF:
		return 0.0
	return maxf(floorf((low - 5.0) / 50.0) * 50.0, 0.0)


func _scale_max() -> float:
	var top := 150.0
	for c in bag:
		if _carries(c):
			top = maxf(top, float(c.max_yard))
	if not offer.is_empty() and _carries(offer):
		top = maxf(top, float(offer.max_yard))
	# A flag well past every club would squash the bars, so it only stretches
	# the ruler when it's within 50 of the longest; further out it's marked
	# at the right edge with an arrow.
	if pin_yards > 0.0 and pin_yards <= top + 50.0:
		top = maxf(top, pin_yards)
	return ceilf(top / 50.0) * 50.0


func _draw() -> void:
	var font := BogeyUI.sans(450)
	var font_b := BogeyUI.sans(600)
	var x0 := NAME_W
	var x1 := size.x - 6.0
	var span := maxf(x1 - x0, 10.0)
	var top_yd := _scale_max()
	var low_yd := _scale_min()
	var to_x := func(yd: float) -> float: return x0 + clampf((yd - low_yd) / (top_yd - low_yd), 0.0, 1.0) * span
	var rows := _rows()
	var rows_top := TOP_PAD
	var rows_bottom := TOP_PAD + _row_count() * ROW_H

	# Gaps: a claret wash down the whole chart, the yards above it. Any part
	# the offer would cover turns green instead.
	var bag_gaps := gaps(bag)
	var fills: Array = []
	if not offer.is_empty() and _carries(offer):
		fills = DraftAdvisor.uncovered(offer, bag)
	for g in bag_gaps:
		var gx0: float = to_x.call(g.x)
		var gx1: float = to_x.call(g.y)
		draw_rect(Rect2(gx0, rows_top, gx1 - gx0, rows_bottom - rows_top), Color(BogeyTheme.ACCENT_200, 0.7))
		var label := "%d–%d" % [int(g.x), int(g.y)]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var cx := (gx0 + gx1) * 0.5
		draw_string(font_b, Vector2(clampf(cx - w * 0.5, x0, x1 - w), 12.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BogeyTheme.FLAG)
	for f in fills:
		var fx0: float = to_x.call(f.x)
		var fx1: float = to_x.call(f.y)
		draw_rect(Rect2(fx0, rows_top, fx1 - fx0, rows_bottom - rows_top), Color(BogeyTheme.OLIVE_200, 0.8))

	# Ticks every 50 yards, faint rules up through the rows.
	var yd := low_yd
	while yd <= top_yd + 0.1:
		var tx: float = to_x.call(yd)
		draw_line(Vector2(tx, rows_top), Vector2(tx, rows_bottom), BogeyTheme.RULE, 1.0)
		var t := "%d" % int(yd)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(clampf(tx - tw * 0.5, x0 - 2.0, size.x - tw), rows_bottom + 16.0), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BogeyTheme.NEUTRAL_600)
		yd += 50.0
	draw_string(font, Vector2(0, rows_bottom + 16.0), "yards", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		BogeyTheme.NEUTRAL_500)

	# One row a club.
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		var c: Dictionary = r.club
		var is_offer: bool = r.offer
		var y := rows_top + i * ROW_H
		var mid := y + ROW_H * 0.5
		var stepped_back := not focus.is_empty() and not is_same(c, focus) and c != focus
		var a := 0.3 if stepped_back else 1.0

		var name := ("+ " if is_offer else "") + str(c.get("name", ""))
		var name_ink: Color = BogeyTheme.OLIVE_800 if is_offer else BogeyTheme.INK
		draw_string(font_b if (is_offer or not focus.is_empty() and not stepped_back) else font,
			Vector2(0, mid + 4.0), name, HORIZONTAL_ALIGNMENT_LEFT, NAME_W - 8.0, 12,
			Color(name_ink, a), TextServer.JUSTIFICATION_NONE)

		var lo := float(c.min_yard)
		var hi := float(c.max_yard)
		var sweet := ShotResolver.tier_yardage_range(c, ShotResolver.Tier.MID)
		var band := Rect2(to_x.call(lo), mid - BAR_H * 0.5, to_x.call(hi) - to_x.call(lo), BAR_H)
		if is_offer:
			draw_rect(band, BogeyTheme.OLIVE_300)
			for f in fills:
				var fx0: float = to_x.call(f.x)
				draw_rect(Rect2(fx0, band.position.y, to_x.call(f.y) - fx0, BAR_H), BogeyTheme.OLIVE_600)
			draw_rect(band, BogeyTheme.OLIVE_800, false, 1.0)
		else:
			draw_rect(band, Color(BogeyTheme.NEUTRAL_300, a))
			var sx0: float = to_x.call(sweet.x)
			draw_rect(Rect2(sx0, band.position.y, to_x.call(sweet.y) - sx0, BAR_H),
				Color(BogeyTheme.INK if not focus.is_empty() and not stepped_back else BogeyTheme.NEUTRAL_700, a))

	# The flag: a dashed claret line at its distance.
	if pin_yards > 0.0:
		var px: float = to_x.call(pin_yards)
		var yy := rows_top - 2.0
		while yy < rows_bottom:
			draw_line(Vector2(px, yy), Vector2(px, minf(yy + 4.0, rows_bottom)), BogeyTheme.FLAG, 1.5)
			yy += 7.0
		var pl := ("pin %d" if pin_yards <= top_yd else "pin %d →") % int(pin_yards)
		var pw := font_b.get_string_size(pl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font_b, Vector2(clampf(px - pw * 0.5, x0, size.x - pw), 12.0), pl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BogeyTheme.FLAG)
