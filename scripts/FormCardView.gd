class_name FormCardView
extends PanelContainer

# ---------------------------------------------------------
# One Form card in the draw-and-pick column beside the hole map.
#
# Set to the same grammar as a club (see CardFace.gd): a drawing on the
# left, then the header, the name, the figure line — how far, how
# straight — and anything else in words. Section 4's "nothing is hidden"
# principle made visible: the exact distance and deviation are printed on
# the card before the player picks it.
#
# What marks it as a Form card is the rule down its left edge, green for
# good Form and claret for bad: the card's whole verdict in one stroke,
# which is what the eye wants when it runs down a hand of three.
#
# The drawing is the shot itself, in plan and to scale: a dotted line to
# the target, and the ball's flight bending off it by the card's degrees
# and stopping at the card's distance. Drawn from the card's numbers, so
# every card has one and no two cards share it.
# ---------------------------------------------------------

const CardFace := preload("res://scripts/CardFace.gd")

signal picked(card_view: FormCardView)
# Emitted as the cursor enters/leaves the card, so the hole map can preview
# where this card would put the ball.
signal hover_started(card_view: FormCardView)
signal hover_ended(card_view: FormCardView)

# The least a row stands; a card with more to say grows to hold it.
const MIN_HEIGHT := 74.0
# The rule down the left edge.
const STRIPE := 3
const PAD_LEFT := 10
const PAD_Y := 8
# The shot drawing: its column, and how long a full-distance shot is drawn.
const ART_WIDTH := 36.0
const SHOT_LENGTH := 50.0

var form_card: FormCard
var interactive: bool = true

var _style: StyleBoxFlat
var _hover_tween: Tween
var _layout_x: float = INF    # resting x from the column, captured on first hover
var _hovered: bool = false
var _selected: bool = false


static func accent_color(card: FormCard) -> Color:
	return BogeyTheme.FAIRWAY if card.good else BogeyTheme.FLAG


func setup(p_card: FormCard, p_interactive: bool = true) -> void:
	form_card = p_card
	interactive = p_interactive
	_build()


func _build() -> void:
	custom_minimum_size = Vector2(0, MIN_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(func(): pivot_offset = size / 2.0)

	var accent := accent_color(form_card)
	var deep: Color = BogeyTheme.FAIRWAY_DEEP if form_card.good else BogeyTheme.FLAG

	_style = BogeyUI.card_style(14, PAD_Y)
	_style.content_margin_left = STRIPE + PAD_LEFT
	CardFace.apply_state(_style, BogeyTheme.NEUTRAL_300, false, false, STRIPE)
	add_theme_stylebox_override("panel", _style)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# The rule, drawn over the panel's own left border, which only reserves
	# the room for it.
	var edge_holder := Control.new()
	edge_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge_holder)
	edge_holder.draw.connect(func():
		edge_holder.draw_rect(Rect2(-(STRIPE + PAD_LEFT), -PAD_Y,
			STRIPE, edge_holder.size.y + PAD_Y * 2), accent))

	var art := Control.new()
	art.custom_minimum_size = Vector2(ART_WIDTH, SHOT_LENGTH + 10.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(_draw_shot.bind(art))
	row.add_child(art)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	# At the right, where a club card names its type, the club family the
	# card was dealt from. A created card says that instead: it belongs to
	# no family, and exhausts rather than returning to the deck.
	col.add_child(CardFace.header(accent, "Good form" if form_card.good else "Bad form", deep,
		"Created" if form_card.created else str(FormCard.FAMILY_LABEL.get(form_card.family, ""))))
	col.add_child(CardFace.name_label(form_card.name, CardFace.NAME_SIZE, 0.0))
	col.add_child(CardFace.figure([form_card.distance_figure(), form_card.line_figure()]))

	var detail := form_card.detail_text()
	if detail != "":
		col.add_child(BogeyUI.margin(CardFace.words(detail), 0, 1, 0, 0))

	if interactive:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(_on_hover_start)
		mouse_exited.connect(_on_hover_end)
		gui_input.connect(_on_panel_input)


# The shot in plan, to one scale on every card: the ball at the foot, the
# target ringed at the head, the line between them dotted. The flight is
# drawn in the card's colour — bending off the line by its degrees, as
# long as its distance — to a dot where the ball finishes. Whatever part
# of that is run along the ground rather than carry is dashed.
func _draw_shot(d: Control) -> void:
	var c := form_card
	var accent := accent_color(c)
	var ball := Vector2(d.size.x / 2.0, (d.size.y + SHOT_LENGTH) / 2.0)
	var pin := ball - Vector2(0, SHOT_LENGTH)

	d.draw_dashed_line(ball, pin + Vector2(0, 4.5), BogeyTheme.NEUTRAL_400, 1.0, 2.0)
	d.draw_arc(pin, 4.0, 0.0, TAU, 24, BogeyTheme.NEUTRAL_600, 1.0, true)

	var share: float = 1.14 if c.to_max_band else clampf(c.distance_mult, 0.2, 1.14)
	var angle: float = deg_to_rad(c.degrees) * c.side
	var length: float = SHOT_LENGTH * share
	var finish := ball + Vector2(sin(angle), -cos(angle)) * length
	# It starts on the line and bends away, as a hook or a slice does.
	var bend := ball + Vector2(0, -length * 0.5)

	var steps := 24
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t: float = float(i) / steps
		pts.append(ball.lerp(bend, t).lerp(bend.lerp(finish, t), t))

	# Bump and Run lands part-way and runs the rest of the same path.
	var carry_steps: int = steps
	if c.run_share > 0.0:
		carry_steps = clampi(int(round(steps * (1.0 - c.run_share))), 2, steps)
	d.draw_polyline(pts.slice(0, carry_steps + 1), accent, 1.8, true)
	for i in range(carry_steps, steps):
		if (i - carry_steps) % 4 >= 2:
			d.draw_line(pts[i], pts[i + 1], accent, 1.8, true)

	# A ball that runs out carries on past where it landed.
	var rest := finish
	if c.run_share <= 0.0 and c.roll_mult > 1.05:
		var heading := (finish - bend).normalized()
		rest = finish + heading * minf((c.roll_mult - 1.0) * 10.0, 12.0)
		d.draw_dashed_line(finish, rest, accent, 1.8, 2.5, true, true)

	d.draw_circle(rest, 3.0, accent, true, -1.0, true)
	d.draw_circle(ball, 2.6, BogeyTheme.CARD_BG, true, -1.0, true)
	d.draw_arc(ball, 2.6, 0.0, TAU, 20, BogeyTheme.INK, 1.0, true)


# Marks this as the card being played — the one a computer golfer has
# chosen, shown before it is played: a full ink edge, as on the club in hand.
func set_selected(on: bool) -> void:
	_selected = on
	CardFace.apply_state(_style, BogeyTheme.NEUTRAL_300, _hovered, _selected, STRIPE)


# Steps the card back: the ones passed over.
func set_dimmed(on: bool) -> void:
	CardFace.set_dimmed(self, on)


func _on_hover_start() -> void:
	if not interactive:
		return
	_hovered = true
	CardFace.apply_state(_style, BogeyTheme.NEUTRAL_300, true, _selected, STRIPE)
	_animate_draw(-CardFace.LIFT)
	z_index = 5
	hover_started.emit(self)


func _on_hover_end() -> void:
	if not interactive:
		return
	_hovered = false
	CardFace.apply_state(_style, BogeyTheme.NEUTRAL_300, false, _selected, STRIPE)
	_animate_draw(0.0)
	z_index = 0
	hover_ended.emit(self)


func _on_panel_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		interactive = false
		CardFace.pick_pop(self, func(): picked.emit(self))


# Hover feedback, the same as a club's: the card comes a few pixels out of
# its row toward the hole map — sideways here, since the Form hand is a
# column where the bag is a row. Animates `position`, which the column
# sets on layout, so it is re-applied from the laid-out spot each time
# rather than accumulating.
func _animate_draw(offset_x: float) -> void:
	if _hover_tween:
		_hover_tween.kill()
	if _layout_x == INF:
		_layout_x = position.x
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "position:x", _layout_x + offset_x, CardFace.HOVER_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func play_fade_out(delay: float = 0.0) -> void:
	CardFace.fade_out(self, delay)
