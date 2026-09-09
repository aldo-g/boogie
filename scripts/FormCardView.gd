class_name FormCardView
extends Control

# ---------------------------------------------------------
# Visual card for a single FormCard, used in the draw-3-pick-1 picker.
# Same card-shell language as CardView (rounded panel, colored top
# border, hover lift, pick pop) but shows the card's fully-known effect
# text instead of club stats — this is Section 4's "nothing is hidden"
# principle made visible: the exact deviation and distance change are
# printed right on the card before the player picks it.
# ---------------------------------------------------------

signal picked(card_view: FormCardView)

const CARD_SIZE := Vector2(186, 184)

var form_card: FormCard
var interactive: bool = true

var _panel: PanelContainer
var _hover_tween: Tween


static func accent_color(card: FormCard) -> Color:
	return BoogieTheme.FAIRWAY_DEEP if card.good else BoogieTheme.FLAG


func setup(p_card: FormCard, p_interactive: bool = true) -> void:
	form_card = p_card
	interactive = p_interactive
	_build()


func _build() -> void:
	custom_minimum_size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0

	var accent := accent_color(form_card)

	var shadow := PanelContainer.new()
	shadow.position = Vector2(3, 5)
	shadow.size = CARD_SIZE
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0, 0, 0, 0.16)
	shadow_style.set_corner_radius_all(10)
	shadow.add_theme_stylebox_override("panel", shadow_style)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)

	_panel = PanelContainer.new()
	_panel.position = Vector2.ZERO
	_panel.size = CARD_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = BoogieTheme.CARD_BG
	style.set_corner_radius_all(10)
	style.border_color = accent
	style.set_border_width_all(2)
	style.border_width_top = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_panel.add_child(vbox)

	# Filled pill rather than a bare caption — good/bad is the first thing
	# to register on a Form card, and a tag carries further than 9px text.
	vbox.add_child(BoogieUI.tag(
		"Good form" if form_card.good else "Bad form",
		BoogieTheme.OLIVE_200 if form_card.good else BoogieTheme.ACCENT_200,
		BoogieTheme.OLIVE_800 if form_card.good else BoogieTheme.ACCENT_800))

	var name_label := Label.new()
	name_label.text = form_card.name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", BoogieTheme.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_label)

	vbox.add_child(BoogieUI.hairline(0.14))

	var effect_label := Label.new()
	effect_label.text = form_card.effect_text()
	effect_label.add_theme_font_size_override("font_size", 13)
	effect_label.add_theme_color_override("font_color", BoogieTheme.NEUTRAL_700)
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	effect_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(effect_label)

	if interactive:
		_panel.mouse_entered.connect(_on_hover_start)
		_panel.mouse_exited.connect(_on_hover_end)
		_panel.gui_input.connect(_on_panel_input)


func _on_hover_start() -> void:
	if not interactive:
		return
	_animate_scale(Vector2(1.06, 1.06), 0.12)
	z_index = 5


func _on_hover_end() -> void:
	if not interactive:
		return
	_animate_scale(Vector2.ONE, 0.12)
	z_index = 0


func _on_panel_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_pick_pop()


func _animate_scale(target: Vector2, duration: float) -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_pick_pop() -> void:
	interactive = false
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.14, 1.14), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): picked.emit(self))


func play_fade_out(delay: float = 0.0) -> void:
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.parallel().tween_property(self, "scale", Vector2(0.9, 0.9), 0.18)
