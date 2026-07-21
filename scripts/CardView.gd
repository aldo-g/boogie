class_name CardView
extends Control

# ---------------------------------------------------------
# Reusable visual card for a club/bad-card dictionary (see Main.gd's
# make_club()). Draws a card-shaped panel with a type-colored header,
# a procedural club icon, and stat text — plus hover lift and a pick
# "pop" animation. No external art: everything is StyleBoxFlat/draw calls.
# ---------------------------------------------------------

signal picked(card_view: CardView)

const CARD_SIZE := Vector2(150, 190)
const COMPACT_SIZE := Vector2(96, 122)

var card: Dictionary = {}
var interactive: bool = true
var compact: bool = false

var _panel: PanelContainer
var _header: Label
var _icon: Control
var _stats: Label
var _ability: Label
var _ribbon: Label
var _base_scale: Vector2 = Vector2.ONE
var _hover_tween: Tween


static func type_color(ctype: String) -> Color:
	match ctype:
		"wood": return BoogieTheme.FAIRWAY_DEEP
		"iron": return BoogieTheme.WATER_DEEP
		"wedge": return BoogieTheme.SAND_DEEP
		"putter": return BoogieTheme.INK_SOFT
		"bad": return BoogieTheme.FLAG
	return BoogieTheme.INK_SOFT


func setup(p_card: Dictionary, p_interactive: bool = true, p_compact: bool = false) -> void:
	card = p_card
	interactive = p_interactive
	compact = p_compact
	_build()


func _build() -> void:
	var card_size := COMPACT_SIZE if compact else CARD_SIZE
	custom_minimum_size = card_size
	pivot_offset = card_size / 2.0

	var accent := type_color(card.get("type", "iron"))

	var shadow := PanelContainer.new()
	shadow.position = Vector2(3, 5)
	shadow.size = card_size
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0, 0, 0, 0.16)
	shadow_style.set_corner_radius_all(10)
	shadow.add_theme_stylebox_override("panel", shadow_style)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)

	_panel = PanelContainer.new()
	_panel.position = Vector2.ZERO
	_panel.size = card_size
	var style := StyleBoxFlat.new()
	style.bg_color = BoogieTheme.CARD_BG
	style.set_corner_radius_all(10)
	style.border_color = accent
	style.set_border_width_all(2)
	style.border_width_top = 6 if not compact else 4
	var margin: int = 10 if not compact else 5
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2 if compact else 4)
	_panel.add_child(vbox)

	_header = Label.new()
	_header.text = card.get("name", "?")
	_header.add_theme_font_size_override("font_size", 11 if compact else 15)
	_header.add_theme_color_override("font_color", BoogieTheme.INK)
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_header)

	if compact:
		_icon = Control.new()
		_icon.custom_minimum_size = Vector2(0, 30)
		_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_icon.draw.connect(_draw_icon.bind(_icon))
		vbox.add_child(_icon)

		_stats = Label.new()
		_stats.text = _compact_stats_text()
		_stats.add_theme_font_size_override("font_size", 9)
		_stats.add_theme_color_override("font_color", BoogieTheme.INK_SOFT)
		_stats.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(_stats)

		if interactive:
			_panel.mouse_entered.connect(_on_hover_start)
			_panel.mouse_exited.connect(_on_hover_end)
			_panel.gui_input.connect(_on_panel_input)
		return

	if card.get("limited", false):
		_ribbon = Label.new()
		_ribbon.text = "LIMITED EDITION"
		_ribbon.add_theme_font_size_override("font_size", 9)
		_ribbon.add_theme_color_override("font_color", BoogieTheme.SAND_DEEP)
		vbox.add_child(_ribbon)

	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(0, 46)
	_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon.draw.connect(_draw_icon.bind(_icon))
	vbox.add_child(_icon)

	var rule := ColorRect.new()
	rule.color = BoogieTheme.RULE
	rule.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(rule)

	_stats = Label.new()
	_stats.text = _stats_text()
	_stats.add_theme_font_size_override("font_size", 12)
	_stats.add_theme_color_override("font_color", BoogieTheme.INK_SOFT)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_stats)

	if card.get("ability", "") != "":
		_ability = Label.new()
		_ability.text = card.ability
		_ability.add_theme_font_size_override("font_size", 11)
		_ability.add_theme_color_override("font_color", accent)
		_ability.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(_ability)

	if interactive:
		_panel.mouse_entered.connect(_on_hover_start)
		_panel.mouse_exited.connect(_on_hover_end)
		_panel.gui_input.connect(_on_panel_input)


func _stats_text() -> String:
	var ctype: String = card.get("type", "")
	if ctype == "bad":
		return "Triggers on your next shot,\nthen discards itself."
	if ctype == "putter":
		return "Green only —\nswitches to the putting green."
	return "%d-%d yds\nSweet Spot base: %s" % [
		int(card.get("min_yard", 0)), int(card.get("max_yard", 0)), _base_width_label(ctype)]


func _base_width_label(ctype: String) -> String:
	match ctype:
		"wood": return "narrow (4)"
		"iron": return "medium (6)"
		"wedge": return "wide (10)"
	return "—"


func _compact_stats_text() -> String:
	var ctype: String = card.get("type", "")
	if ctype == "bad":
		return "self-consuming"
	if ctype == "putter":
		return "green only"
	return "%d-%d yds" % [int(card.get("min_yard", 0)), int(card.get("max_yard", 0))]


# Simple procedural silhouettes so each club type reads at a glance
# without needing external art.
func _draw_icon(icon: Control) -> void:
	var ctype: String = card.get("type", "iron")
	var accent := type_color(ctype)
	var w: float = icon.size.x
	var h: float = icon.size.y
	var cx: float = w / 2.0

	match ctype:
		"wood":
			# Driver head: a rounded teardrop on a shaft.
			icon.draw_line(Vector2(cx, h * 0.15), Vector2(cx, h * 0.75), accent, 3.0)
			icon.draw_circle(Vector2(cx, h * 0.8), h * 0.22, accent)
		"iron":
			# Iron head: a flat angled blade on a shaft.
			icon.draw_line(Vector2(cx, h * 0.1), Vector2(cx, h * 0.7), accent, 3.0)
			var pts := PackedVector2Array([
				Vector2(cx - w * 0.16, h * 0.68), Vector2(cx + w * 0.2, h * 0.62),
				Vector2(cx + w * 0.22, h * 0.85), Vector2(cx - w * 0.12, h * 0.9)])
			icon.draw_colored_polygon(pts, accent)
		"wedge":
			# Wedge head: a wider, more open-faced blade.
			icon.draw_line(Vector2(cx, h * 0.1), Vector2(cx, h * 0.65), accent, 3.0)
			var pts := PackedVector2Array([
				Vector2(cx - w * 0.22, h * 0.62), Vector2(cx + w * 0.26, h * 0.55),
				Vector2(cx + w * 0.3, h * 0.88), Vector2(cx - w * 0.2, h * 0.95)])
			icon.draw_colored_polygon(pts, accent)
		"putter":
			icon.draw_line(Vector2(cx, h * 0.15), Vector2(cx, h * 0.7), accent, 3.0)
			icon.draw_rect(Rect2(cx - w * 0.18, h * 0.68, w * 0.36, h * 0.18), accent)
		"bad":
			# A cracked/warning mark for bad cards.
			icon.draw_circle(Vector2(cx, h * 0.5), h * 0.32, accent)
			icon.draw_string(ThemeDB.fallback_font, Vector2(cx - 5, h * 0.62), "!",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 22, BoogieTheme.CARD_BG)
		_:
			icon.draw_circle(Vector2(cx, h * 0.5), h * 0.25, accent)


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


# Plays a short "fly toward the hand" exit animation, then calls on_done.
func play_fly_to_hand(target_global_pos: Vector2, on_done: Callable) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position", target_global_pos, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector2(0.4, 0.4), 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(on_done)


func play_fade_out(delay: float = 0.0) -> void:
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.parallel().tween_property(self, "scale", Vector2(0.9, 0.9), 0.18)
