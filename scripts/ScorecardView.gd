class_name ScorecardView
extends Control

# ---------------------------------------------------------
# The card, laid out the way a scorecard is printed: holes across, OUT and
# IN after each nine, one line for par and one line per player. Sits in
# the header, so the whole round is on view in three rows.
#
# Scores are marked the way they're pencilled in: a ring round a birdie,
# two for an eagle or better, a box round a bogey, two for a double or
# worse. The column of the hole being played is tinted.
#
# Reads par and yardage straight from the active Course so it can never
# drift from the course the game actually plays — custom courses may run
# anything from 1 to 18 holes.
#   scorecard.set_round(round_scores, current_hole_index, strokes)    # solo
#   scorecard.set_card(rows, current_hole_index)                      # a group
# where each row is {name, color, scores, live, active}.
# ---------------------------------------------------------

const ROW_H := 24.0
const LABEL_W := 96.0          # the row labels: HOLE, PAR, SCORE
const NAME_W := 110.0          # ...or the players' names
const CELL_W := 32.0
const SUM_W := 44.0
const PAR_W := 52.0     # the to-par column, at the far right

var _rows: Array = []
var _current_hole: int = 1
var _cols: Array = []          # [{kind: "hole"|"out"|"in"|"tot"|"par", n: int, x: float, w: float}]
var _built_for: int = -1       # the hole count the columns were laid out for
var _label_w: float = LABEL_W  # width of the first column, as laid out


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_layout()


# A solo round: one line, yours.
func set_round(scores: Array, current_hole: int, strokes: int) -> void:
	set_card([{"name": "You", "color": BogeyTheme.INK, "scores": scores, "live": strokes, "active": false}], current_hole)


func set_card(rows: Array, current_hole: int) -> void:
	_rows = rows
	_current_hole = current_hole
	_layout()
	queue_redraw()


# Columns, left to right. A course of nine or fewer has no nines to split.
func _layout() -> void:
	var count := Course.hole_count()
	var named: bool = not _rows.is_empty() and not bool(_rows[0].get("plain", false))
	var label_w: float = NAME_W if named else LABEL_W
	if count != _built_for or label_w != _label_w:
		_built_for = count
		_label_w = label_w
		_cols.clear()
		var x := label_w
		var split := count > 9
		for n in range(1, count + 1):
			_cols.append({"kind": "hole", "n": n, "x": x, "w": CELL_W})
			x += CELL_W
			if split and n == 9:
				_cols.append({"kind": "out", "n": 0, "x": x, "w": SUM_W})
				x += SUM_W
		if split:
			_cols.append({"kind": "in", "n": 0, "x": x, "w": SUM_W})
			x += SUM_W
		_cols.append({"kind": "tot", "n": 0, "x": x, "w": SUM_W})
		x += SUM_W
		_cols.append({"kind": "par", "n": 0, "x": x, "w": PAR_W})
		x += PAR_W
		custom_minimum_size.x = x
	custom_minimum_size.y = ROW_H * (2 + maxi(_rows.size(), 1)) + 2.0


func _get_tooltip(at_position: Vector2) -> String:
	for c in _cols:
		if c.kind == "hole" and at_position.x >= c.x and at_position.x < c.x + c.w:
			var d: Dictionary = Course.hole_def(c.n)
			return "Hole %d · Par %d · %d yards" % [c.n, int(d.par), int(d.yardage)]
	return ""


# Which holes a summing column adds up.
func _span(kind: String) -> Array:
	var count := Course.hole_count()
	match kind:
		"out": return [1, mini(9, count)]
		"in": return [10, count]
	return [1, count]


func _draw() -> void:
	if _cols.is_empty():
		return
	var label_font := BogeyUI.sans(600, 2)
	var num_font := BogeyUI.sans(500)
	var score_font := BogeyUI.serif(700)
	var soft := BogeyTheme.NEUTRAL_600
	var faint := BogeyTheme.NEUTRAL_500

	# The hole in play, tinted top to bottom.
	for c in _cols:
		if c.kind == "hole" and c.n == _current_hole:
			draw_rect(Rect2(c.x, ROW_H, c.w, size.y - ROW_H), Color(BogeyTheme.INK, 0.055))
			# The hole in play, its number set white on an ink block.
			draw_rect(Rect2(c.x + 2.0, 3.0, c.w - 4.0, ROW_H - 6.0), BogeyTheme.INK)

	# --- HOLE -----------------------------------------------------------
	var y := 0.0
	_text(label_font, "HOLE", 0, y, _label_w, 10, soft, HORIZONTAL_ALIGNMENT_LEFT)
	for c in _cols:
		match c.kind:
			"hole":
				var here: bool = c.n == _current_hole
				_text(BogeyUI.sans(700) if here else num_font, str(c.n), c.x, y, c.w, 12,
					BogeyTheme.NEUTRAL_100 if here else faint)
			"out": _text(label_font, "OUT", c.x, y, c.w, 9, soft)
			"in": _text(label_font, "IN", c.x, y, c.w, 9, soft)
			"tot": _text(label_font, "TOT", c.x, y, c.w, 9, soft)
			"par": _text(label_font, "+/−", c.x, y, c.w, 9, soft)

	# --- PAR ------------------------------------------------------------
	y += ROW_H
	_text(label_font, "PAR", 0, y, _label_w, 10, soft, HORIZONTAL_ALIGNMENT_LEFT)
	for c in _cols:
		if c.kind == "hole":
			_text(num_font, str(int(Course.hole_def(c.n).par)), c.x, y, c.w, 13, soft)
		elif c.kind != "par":
			var span := _span(c.kind)
			var total := 0
			for n in range(span[0], span[1] + 1):
				total += int(Course.hole_def(n).par)
			_text(num_font, str(total), c.x, y, c.w, 13, soft)

	y += ROW_H
	draw_line(Vector2(0, y + 0.5), Vector2(size.x, y + 0.5), Color(BogeyTheme.INK, 0.3), 1.0)
	y += 2.0

	# --- One line per player ----------------------------------------------
	for row in _rows:
		var by_hole := {}
		for entry in row.scores:
			by_hole[int(entry.hole)] = entry
		var active: bool = row.get("active", false)
		if active:
			draw_rect(Rect2(0, y, size.x, ROW_H), Color(BogeyTheme.INK, 0.04))

		# Name: a plain label solo; a seat-colour dot and the name in a group.
		var name_x := 0.0
		if row.get("plain", false):
			_text(label_font, str(row.name).to_upper(), 0, y, _label_w, 10, soft, HORIZONTAL_ALIGNMENT_LEFT)
		else:
			name_x = 14.0
			draw_circle(Vector2(5.0, y + ROW_H * 0.5), 3.5, row.get("color", BogeyTheme.INK), true, -1.0, true)
			_text(BogeyUI.sans(600 if active else 450), str(row.name), name_x, y, _label_w - name_x - 6.0, 13,
				BogeyTheme.INK if active else soft, HORIZONTAL_ALIGNMENT_LEFT)

		var strokes_total := 0
		var par_total := 0
		for entry in row.scores:
			strokes_total += int(entry.strokes)
			par_total += int(entry.par)

		for c in _cols:
			match c.kind:
				"hole":
					if by_hole.has(c.n):
						var e: Dictionary = by_hole[c.n]
						_score(score_font, int(e.strokes), int(e.strokes) - int(e.par), c.x, y, c.w)
					elif c.n == _current_hole:
						var live: int = int(row.get("live", 0))
						_text(score_font, str(live) if live > 0 else "·", c.x, y, c.w, 17, faint)
				"par":
					if not row.scores.is_empty():
						var diff := strokes_total - par_total
						_text(score_font, _diff_text(diff), c.x, y, c.w, 18, _score_color(diff))
				_:
					var span := _span(c.kind)
					var sum := 0
					var any := false
					for n in range(span[0], span[1] + 1):
						if by_hole.has(n):
							sum += int(by_hole[n].strokes)
							any = true
					if any:
						_text(score_font, str(sum), c.x, y, c.w, 17, BogeyTheme.NEUTRAL_800)
		y += ROW_H


# A played hole's score, with its pencil mark.
func _score(font: Font, strokes: int, diff: int, x: float, y: float, w: float) -> void:
	var col := _score_color(diff)
	var centre := Vector2(x + w * 0.5, y + ROW_H * 0.5)
	if diff < 0:
		draw_arc(centre, 10.0, 0, TAU, 32, col, 1.0, true)
		if diff <= -2:
			draw_arc(centre, 7.5, 0, TAU, 28, col, 1.0, true)
	elif diff > 0:
		draw_rect(Rect2(centre - Vector2(9.5, 9.5), Vector2(19, 19)), col, false, 1.0)
		if diff >= 2:
			draw_rect(Rect2(centre - Vector2(7, 7), Vector2(14, 14)), col, false, 1.0)
	_text(font, str(strokes), x, y, w, 14 if absi(diff) >= 2 else 17, col)


# One string, centred vertically in its row and aligned within its cell.
func _text(font: Font, text: String, x: float, y: float, w: float, font_size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var baseline := y + (ROW_H + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(x, baseline), text, align, w, font_size, color)


static func _diff_text(diff: int) -> String:
	if diff == 0:
		return "E"
	return ("+%d" % diff) if diff > 0 else ("−%d" % -diff)


func _score_color(diff: int) -> Color:
	if diff < 0:
		return BogeyTheme.FAIRWAY_DEEP
	elif diff > 0:
		return BogeyTheme.FLAG
	return BogeyTheme.INK
