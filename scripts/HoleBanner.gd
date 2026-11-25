extends Control

# ---------------------------------------------------------
# THE STAMP
# A rubber-stamp banner that lands over the hole map when something is
# worth marking: a hole finished (BIRDIE, PAR, DOUBLE BOGEY…), a ball
# holed from off the green, the last Bogey-Mart club leaving the bag.
#
# Purely cosmetic and never in the way: it takes no input, touches no
# game state, and clears itself. A new stamp replaces the one on screen.
# ---------------------------------------------------------

enum Tone { GREAT, GOOD, PLAIN, BAD, NOTE }

const HOLD_SEC := 1.7
const NOTE_HOLD_SEC := 0.9   # a note() is gone sooner
const TILT := -0.07   # radians — stamped by hand, not typeset

# The control it lands on (the hole map). Set by Main.
var anchor: Control

var _panel: PanelContainer
var _kicker: Label
var _title: Label
var _sub: Label
var _style: StyleBoxFlat
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_style = StyleBoxFlat.new()
	_style.bg_color = Color(BogeyTheme.CARD_BG, 0.96)
	_style.set_corner_radius_all(3)
	_style.set_border_width_all(2)
	_style.shadow_color = BogeyTheme.SHADOW_LG
	_style.shadow_size = 14
	_style.shadow_offset = Vector2(0, 5)
	_style.content_margin_left = 34
	_style.content_margin_right = 34
	_style.content_margin_top = 14
	_style.content_margin_bottom = 16

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)

	_kicker = _label(11)
	_kicker.add_theme_font_override("font", BogeyUI.sans(600, 2))
	col.add_child(_kicker)
	_title = _label(54)
	_title.add_theme_font_override("font", BogeyUI.serif(600))
	col.add_child(_title)
	_sub = _label(19)
	_sub.add_theme_font_override("font", BogeyUI.serif_italic(500))
	col.add_child(_sub)


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# The stamp's ink for each tone: [border and title, secondary text].
static func inks(tone: int) -> Array:
	match tone:
		Tone.GREAT:
			return [BogeyTheme.GOLD, BogeyTheme.GOLD_800]
		Tone.GOOD:
			return [BogeyTheme.OLIVE_700, BogeyTheme.OLIVE_800]
		Tone.BAD:
			return [BogeyTheme.ACCENT_600, BogeyTheme.ACCENT_800]
		Tone.NOTE:
			return [BogeyTheme.INK, BogeyTheme.NEUTRAL_700]
	return [BogeyTheme.NEUTRAL_700, BogeyTheme.NEUTRAL_700]


# What a finished hole is stamped with, by strokes against par.
static func result_title(diff: int, strokes: int) -> String:
	if strokes == 1:
		return "HOLE IN ONE"
	match diff:
		-3: return "ALBATROSS"
		-2: return "EAGLE"
		-1: return "BIRDIE"
		0: return "PAR"
		1: return "BOGEY"
		2: return "DOUBLE BOGEY"
		3: return "TRIPLE BOGEY"
	return "%d UNDER" % -diff if diff < 0 else "%d OVER" % diff


static func result_tone(diff: int) -> int:
	if diff <= -2:
		return Tone.GREAT
	if diff == -1:
		return Tone.GOOD
	return Tone.PLAIN if diff == 0 else Tone.BAD


# Lands the stamp. `kicker` is the small line above the title (who or
# where), `subtitle` the one below (the detail); either may be empty.
func stamp(title: String, kicker: String = "", subtitle: String = "", tone: int = Tone.PLAIN) -> void:
	_land(title, kicker, subtitle, tone, false)


# A lesser mark, for one good shot (Main._shot_payoff): smaller, sooner
# gone, and lower on the map so the green it is about stays in view.
func note(title: String, kicker: String = "", subtitle: String = "", tone: int = Tone.PLAIN) -> void:
	_land(title, kicker, subtitle, tone, true)


func _land(title: String, kicker: String, subtitle: String, tone: int, small: bool) -> void:
	var ink: Array = inks(tone)
	_title.add_theme_font_size_override("font_size", 34 if small else 54)
	_sub.add_theme_font_size_override("font_size", 15 if small else 19)
	_style.border_color = ink[0]
	_title.text = title
	_title.add_theme_color_override("font_color", ink[0])
	_kicker.text = kicker.to_upper()
	_kicker.visible = kicker != ""
	_kicker.add_theme_color_override("font_color", ink[1])
	_sub.text = subtitle
	_sub.visible = subtitle != ""
	_sub.add_theme_color_override("font_color", ink[1])

	_panel.reset_size()
	_place(0.62 if small else 0.42)
	_panel.visible = true
	_panel.rotation = TILT
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(1.35, 1.35) if small else Vector2(1.7, 1.7)

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# Comes down hard and settles, like a stamp hitting paper.
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.10)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.set_parallel(false)
	_tween.tween_interval(NOTE_HOLD_SEC if small else HOLD_SEC + (0.5 if tone == Tone.GREAT else 0.0))
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.35)
	_tween.tween_callback(func(): _panel.visible = false)


func is_showing() -> bool:
	return _panel.visible


# Centred on the anchor, a little above its middle so the ball and the
# green — usually at the top of the map — stay readable around it. `down`
# is how far down the anchor its centre sits.
func _place(down: float = 0.42) -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if anchor != null and anchor.is_inside_tree():
		rect = Rect2(anchor.global_position - global_position, anchor.size)
	var sz := _panel.get_combined_minimum_size()
	_panel.size = sz
	_panel.pivot_offset = sz / 2.0
	_panel.position = rect.position + Vector2(rect.size.x * 0.5, rect.size.y * down) - sz / 2.0
