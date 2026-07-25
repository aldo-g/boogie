class_name DiceView
extends Control

# ---------------------------------------------------------
# A drawn d20: a 20-gon silhouette (reads as a rounded polygonal die at
# this size, with triangular facet lines radiating from center to sell
# "many-sided die" without full 3D) that spins and wobbles through a
# tumble, then snaps to rest with the rolled number stamped on its face.
# Used for both the Power and Accuracy rolls so the player watches the
# dice land instead of just reading roll numbers in the log.
# ---------------------------------------------------------

signal roll_finished

const SIDES := 20
const FACE_COLOR := Color(1.0, 0.992, 0.969)   # BoogieTheme.CARD_BG
const EDGE_COLOR := Color(0.169, 0.227, 0.184)  # BoogieTheme.INK
const FACET_COLOR := Color(0.169, 0.227, 0.184, 0.16)

var accent: Color = Color(0.306, 0.431, 0.251)  # BoogieTheme.FAIRWAY_DEEP by default
var label_text: String = ""

var _rotation_deg: float = 0.0
var _scale_amt: float = 1.0
var _display_value: int = 1
var _final_value: int = 1
var _settled: bool = false

var _value_label: Label
var _caption_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(84, 100)
	pivot_offset = Vector2(42, 42)

	_value_label = Label.new()
	_value_label.text = "?"
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.add_theme_font_size_override("font_size", 22)
	_value_label.add_theme_color_override("font_color", EDGE_COLOR)
	_value_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_value_label.offset_bottom = -18
	add_child(_value_label)

	_caption_label = Label.new()
	_caption_label.text = label_text
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.add_theme_font_size_override("font_size", 11)
	_caption_label.add_theme_color_override("font_color", BoogieTheme.INK_SOFT)
	_caption_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption_label.offset_top = -16
	add_child(_caption_label)
	_caption_label.text = label_text


func set_caption(text: String) -> void:
	label_text = text
	if _caption_label:
		_caption_label.text = text


# Plays the tumble: rapid rotation + cycling random face values, settling
# on final_value after duration seconds. Calls on_done (if given) once
# the die has fully stopped and displays the true result.
func roll_to(final_value: int, duration: float = 0.7, on_done: Callable = Callable()) -> void:
	_final_value = clampi(final_value, 1, SIDES)
	_settled = false
	_display_value = randi_range(1, SIDES)
	_update_value_label()

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_rotation_deg", _rotation_deg + 720.0 + randf_range(-40, 40), duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_scale_amt", 1.0, duration).from(0.6)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_settle.bind(on_done))

	# Cycle the displayed number rapidly while the die spins, slowing near the end.
	var cycles: int = 10
	for i in range(cycles):
		var t: float = float(i) / float(cycles - 1)
		var delay: float = duration * (t * t)  # ease into slower cycling near the end
		get_tree().create_timer(delay).timeout.connect(_cycle_display)

	queue_redraw()
	set_process(true)


func _cycle_display() -> void:
	if _settled:
		return
	_display_value = randi_range(1, SIDES)
	_update_value_label()
	queue_redraw()


func _settle(on_done: Callable) -> void:
	_settled = true
	_display_value = _final_value
	_rotation_deg = wrapf(_rotation_deg, 0.0, 360.0)
	_update_value_label()
	queue_redraw()
	if on_done.is_valid():
		on_done.call()
	roll_finished.emit()


func _update_value_label() -> void:
	if _value_label:
		_value_label.text = str(_display_value)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center := Vector2(42, 34)
	var radius: float = 26.0

	var pts := PackedVector2Array()
	for i in range(SIDES):
		var a: float = deg_to_rad(_rotation_deg) + (TAU * i / SIDES)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)

	var fill_col := FACE_COLOR
	draw_colored_polygon(pts, fill_col)

	# Facet lines from center to each vertex, to read as a many-sided die.
	for p in pts:
		draw_line(center, p, FACET_COLOR, 1.0)

	var closed := pts.duplicate()
	closed.append(pts[0])
	var edge_col := accent if _settled else EDGE_COLOR
	draw_polyline(closed, edge_col, _settled and 2.5 or 1.5, true)
