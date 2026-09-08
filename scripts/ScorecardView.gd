class_name ScorecardView
extends VBoxContainer

# ---------------------------------------------------------
# The card column: all eighteen holes, always visible, with par, yardage
# and your score. The hole you're playing is tinted; flights are parted by
# hairlines after 6 and 12; the running total sits at the foot.
#
# Reads par/yardage straight from HoleData.HOLES so it can never drift
# from the course the game actually plays.
#   scorecard.set_round(round_scores, current_hole_index, strokes)
# ---------------------------------------------------------

const ROW_H := 21

var _rows: Array = []          # [{ "hole": Label, "par": Label, "yds": Label, "score": Label, "bg": ColorRect }]
var _total_label: Label
var _thru_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	custom_minimum_size = Vector2(258, 0)
	_build()


func _build() -> void:
	add_child(BoogieUI.kicker("Scorecard"))

	var head := _make_row("H", "PAR", "YDS", "SCR", true)
	add_child(head)
	add_child(BoogieUI.hairline(0.4))

	for n in range(1, HoleData.HOLE_COUNT + 1):
		var d: Dictionary = HoleData.HOLES[n]
		var row := _make_row(str(n), str(d.par), str(int(d.yardage)), "—", false)
		add_child(row)
		_rows.append(row.get_meta("cells"))
		if n == 6 or n == 12:
			add_child(BoogieUI.hairline(0.3))
		elif n < HoleData.HOLE_COUNT:
			add_child(BoogieUI.hairline(0.08))

	add_child(BoogieUI.hairline(0.4))

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	_thru_label = BoogieUI.body("Thru 0", 12, BoogieTheme.INK_SOFT)
	_thru_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_thru_label)
	_total_label = BoogieUI.body("E", 14, BoogieTheme.INK)
	foot.add_child(_total_label)
	add_child(foot)


func _make_row(hole: String, par: String, yds: String, score: String, is_head: bool) -> Control:
	var wrap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	wrap.add_theme_stylebox_override("panel", style)
	wrap.custom_minimum_size = Vector2(0, ROW_H)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	wrap.add_child(row)

	var size := 10 if is_head else 13
	var color := BoogieTheme.INK_SOFT if is_head else BoogieTheme.INK

	var cells := {}
	var specs := [["hole", hole, 34], ["par", par, 40], ["yds", yds, 52], ["score", score, 0]]
	for spec in specs:
		var l := Label.new()
		l.text = spec[1]
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color if spec[0] != "yds" else BoogieTheme.INK_SOFT)
		if spec[2] > 0:
			l.custom_minimum_size = Vector2(spec[2], 0)
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		cells[spec[0]] = l
	cells["wrap"] = wrap
	cells["style"] = style
	wrap.set_meta("cells", cells)
	return wrap


func set_round(scores: Array, current_hole: int, strokes: int) -> void:
	var by_hole := {}
	for entry in scores:
		by_hole[entry.hole] = entry

	var total_strokes := 0
	var total_par := 0
	for i in range(_rows.size()):
		var n: int = i + 1
		var cells: Dictionary = _rows[i]
		var style: StyleBoxFlat = cells.style
		var played: bool = by_hole.has(n)
		var is_current: bool = n == current_hole

		if played:
			var e: Dictionary = by_hole[n]
			cells.score.text = str(e.strokes)
			cells.score.add_theme_color_override("font_color", _score_color(e.strokes - e.par))
			total_strokes += e.strokes
			total_par += e.par
		elif is_current:
			cells.score.text = str(strokes) if strokes > 0 else "·"
			cells.score.add_theme_color_override("font_color", BoogieTheme.INK)
		else:
			cells.score.text = "—"
			cells.score.add_theme_color_override("font_color", Color(BoogieTheme.INK_SOFT, 0.45))

		style.bg_color = Color(BoogieTheme.FAIRWAY, 0.16) if is_current else Color(0, 0, 0, 0)
		var dim: float = 1.0 if (played or is_current) else 0.5
		cells.hole.add_theme_color_override("font_color", Color(BoogieTheme.INK, dim))
		cells.par.add_theme_color_override("font_color", Color(BoogieTheme.INK, dim))
		cells.yds.add_theme_color_override("font_color", Color(BoogieTheme.INK_SOFT, dim))

	_thru_label.text = "Thru %d" % scores.size()
	var diff := total_strokes - total_par
	_total_label.text = "E" if diff == 0 else (("+%d" % diff) if diff > 0 else str(diff))
	_total_label.add_theme_color_override("font_color", _score_color(diff))


func _score_color(diff: int) -> Color:
	if diff < 0:
		return BoogieTheme.FAIRWAY_DEEP
	elif diff > 0:
		return BoogieTheme.FLAG
	return BoogieTheme.INK
