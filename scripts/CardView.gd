class_name CardView
extends Control

# ---------------------------------------------------------
# Reusable visual card for a club/bad-card dictionary (see Main.gd's
# make_club()). Draws a card-shaped panel with a type-colored header,
# a procedural club icon, and stat text — plus hover lift and a pick
# "pop" animation. No external art: everything is StyleBoxFlat/draw calls.
# ---------------------------------------------------------

signal picked(card_view: CardView)
# Emitted as the cursor enters/leaves the card, so the hole map can preview
# this club's reach without CardView needing to know the map exists.
signal hover_started(card_view: CardView)
signal hover_ended(card_view: CardView)

const CARD_SIZE := Vector2(150, 190)
const COMPACT_SIZE := Vector2(132, 168)

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
var _detail: PanelContainer   # compact cards only: the hover detail popup
var _detail_timer: Timer      # dwell before the popup appears
var _layout_y: float = INF    # resting y from the container, captured on first hover
var _shadow: PanelContainer    # drop shadow, deepened on hover
var _shadow_style: StyleBoxFlat
var _panel_style: StyleBoxFlat # the card face, glowed on hover
var _accent: Color


static func type_color(ctype: String) -> Color:
	match ctype:
		"wood": return BogeyTheme.FAIRWAY_DEEP
		"iron": return BogeyTheme.WATER_DEEP
		"wedge": return BogeyTheme.SAND_DEEP
		"putter": return BogeyTheme.INK_SOFT
	return BogeyTheme.INK_SOFT


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
	_shadow = shadow
	_shadow_style = shadow_style

	_panel = PanelContainer.new()
	_panel.position = Vector2.ZERO
	_panel.size = card_size
	var style := StyleBoxFlat.new()
	style.bg_color = BogeyTheme.CARD_BG
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
	_panel_style = style
	_accent = accent
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2 if compact else 4)
	_panel.add_child(vbox)

	_header = Label.new()
	_header.text = card.get("name", "?")
	_header.add_theme_font_size_override("font_size", 11 if compact else 15)
	_header.add_theme_color_override("font_color", BogeyTheme.INK)
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_header)

	if compact:
		# Bag card, redesigned: brand line, then the club name, then a
		# category tag and the yardage band. Brand is the read the draft
		# turns on (Section 3A), so it leads rather than hiding in the
		# stats line.
		_header.add_theme_font_size_override("font_size", 17)

		var brand_id: String = card.get("brand", "")
		if brand_id != "":
			var brand_label := Label.new()
			brand_label.text = Brands.display_name(brand_id).to_upper()
			brand_label.add_theme_font_size_override("font_size", 10)
			brand_label.add_theme_color_override("font_color", BogeyTheme.NEUTRAL_600)
			vbox.add_child(brand_label)
			vbox.move_child(brand_label, 0)

		_icon = Control.new()
		_icon.custom_minimum_size = Vector2(0, 34)
		_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_icon.draw.connect(_draw_icon.bind(_icon))
		vbox.add_child(_icon)

		var cat_text: String = card.get("type", "").capitalize()
		if card.get("limited", false):
			cat_text = "Limited · " + cat_text
		vbox.add_child(BogeyUI.tag(
			cat_text,
			BogeyTheme.ACCENT_200 if card.get("limited", false) else BogeyTheme.OLIVE_200,
			BogeyTheme.ACCENT_800 if card.get("limited", false) else BogeyTheme.OLIVE_800))

		_stats = Label.new()
		_stats.text = _compact_stats_text()
		_stats.add_theme_font_size_override("font_size", 13)
		_stats.add_theme_color_override("font_color", BogeyTheme.NEUTRAL_700)
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
		_ribbon.add_theme_color_override("font_color", BogeyTheme.SAND_DEEP)
		vbox.add_child(_ribbon)

	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(0, 46)
	_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon.draw.connect(_draw_icon.bind(_icon))
	vbox.add_child(_icon)

	var rule := ColorRect.new()
	rule.color = BogeyTheme.RULE
	rule.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(rule)

	_stats = Label.new()
	_stats.text = _stats_text()
	_stats.add_theme_font_size_override("font_size", 12)
	_stats.add_theme_color_override("font_color", BogeyTheme.INK_SOFT)
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
	return "%d-%d yds\nSweet Spot base: %s" % [
		int(card.get("min_yard", 0)), int(card.get("max_yard", 0)), _base_width_label(ctype)]


func _base_width_label(ctype: String) -> String:
	match ctype:
		"wood": return "narrow (4)"
		"iron": return "medium (6)"
		"wedge": return "wide (10)"
		# The putter buffers deviation to zero (ShotResolver.BUFFER_BY_TYPE),
		# so it never pushes the ball offline — its limit is pure distance.
		"putter": return "no deviation"
	return "—"


func _compact_stats_text() -> String:
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
		_:
			icon.draw_circle(Vector2(cx, h * 0.5), h * 0.25, accent)


# The compact bag card has room for brand, name, category and yardage —
# but not for the Sweet Spot width or the ability line, and 42 of the
# pool's clubs carry an ability. That detail is exactly what you need in
# order to choose between two clubs that reach the same distance, so it
# appears on hover rather than only after you've drafted the thing.
#
# Built lazily on first hover and kept for the life of the card: these
# are short-lived nodes (rebuilt every refresh_ui) and the text never
# changes once set.
func _build_detail() -> void:
	if _detail:
		return

	var style := StyleBoxFlat.new()
	style.bg_color = BogeyTheme.CARD_BG
	style.set_corner_radius_all(8)
	style.border_color = type_color(card.get("type", "iron"))
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8

	_detail = PanelContainer.new()
	_detail.add_theme_stylebox_override("panel", style)
	# The popup is a read-out, not a target: it must never eat the hover
	# that is keeping it open, or it would flicker as the cursor crossed it.
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.custom_minimum_size = Vector2(212, 0)
	_detail.z_index = 100
	_detail.visible = false

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(box)

	var ctype: String = card.get("type", "")

	# Yardage band, spelled out rather than abbreviated as on the face.
	box.add_child(_detail_line("%d-%d yds carry" % [
		int(card.get("min_yard", 0)), int(card.get("max_yard", 0))],
		13, BogeyTheme.INK))
	# The Sweet Spot width is the club's real character — it decides how
	# forgiving the swing is — and the compact face has no room for it.
	box.add_child(_detail_line("Sweet Spot: %s" % _base_width_label(ctype),
		12, BogeyTheme.NEUTRAL_700))
	if ctype == "putter":
		box.add_child(_detail_line(
			"Playable anywhere. On the green, switches to the putt meter.",
			11, BogeyTheme.NEUTRAL_700))

	var ability: String = card.get("ability", "")
	if ability != "":
		var rule := ColorRect.new()
		rule.color = BogeyTheme.RULE
		rule.custom_minimum_size = Vector2(0, 1)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rule)
		box.add_child(_detail_line(ability, 11, type_color(ctype)))

	if card.get("limited", false):
		box.add_child(_detail_line("LIMITED EDITION", 9, BogeyTheme.SAND_DEEP))

	# Parented to the viewport rather than to this card on purpose: the bag
	# row sits inside a ScrollContainer, whose clip_contents would cut off
	# anything drawn above the card. A viewport child is positioned in
	# global coordinates (see _place_detail) and clipped by nothing.
	var host := get_viewport()
	if host == null:
		# Not in the tree yet — nothing can be hovering us, so drop the
		# half-built popup and let the next hover rebuild it.
		_detail.queue_free()
		_detail = null
		return
	host.add_child(_detail)
	if not tree_exiting.is_connected(_free_detail):
		tree_exiting.connect(_free_detail)


# One wrapped line inside the detail popup.
func _detail_line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(192, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Places the popup above the card, nudged horizontally so it can never
# hang off the edge of the window — the bag row runs to both margins, so
# the first and last cards would otherwise push it out of view.
func _place_detail() -> void:
	_detail.reset_size()
	var card_size := COMPACT_SIZE if compact else CARD_SIZE
	var size_now := _detail.size
	# Centred over the card and sitting just above it, in global space.
	# Anchored to the card's resting y, not its live one: the hover lift is
	# still animating when the popup appears, and tracking it would make
	# the panel drift those few pixels as it fades in.
	var anchor := global_position
	if _layout_y != INF:
		anchor.y += _layout_y - position.y
	var pos := anchor + Vector2(
		(card_size.x - size_now.x) * 0.5, -size_now.y - 10.0)

	# Clear the whole bag panel, not just the card. Sitting "just above the
	# card" puts the popup on top of the bag's own header and brand rack,
	# which is what made it look clipped — the panel it overlapped simply
	# painted a hard edge across it. Lifting it clear of the panel's top
	# edge means it always opens into the empty board area above.
	var panel_top := _bag_panel_top()
	if panel_top != INF:
		pos.y = min(pos.y, panel_top - size_now.y - 8.0)

	# Keep it on screen: the bag row runs to both margins, so the first and
	# last cards would otherwise push the popup off the edge.
	var margin := 8.0
	var view := get_viewport_rect().size
	pos.x = clampf(pos.x, margin, view.x - size_now.x - margin)
	# If there is genuinely no room above, flip below the card instead.
	if pos.y < margin:
		pos.y = global_position.y + card_size.y + 10.0
	_detail.position = pos


# Global y of the top edge of the panel this card sits in, or INF if it
# can't be determined. Walks up to the nearest PanelContainer ancestor —
# the bag/draft strip — rather than hard-coding a height, so the popup
# keeps clearing it if that layout ever changes.
func _bag_panel_top() -> float:
	var n := get_parent()
	while n != null:
		if n is PanelContainer:
			return (n as PanelContainer).global_position.y
		n = n.get_parent()
	return INF


func _on_hover_start() -> void:
	if not interactive:
		return
	# No scale-up: the card holding its size keeps the bag row stable, and
	# the detail popup is the hover feedback now. A small rise is enough to
	# say "this one" without the text resampling as it grows.
	_animate_lift(-8.0, 0.14)
	z_index = 5
	_show_detail()
	_set_hover_emphasis(true)
	hover_started.emit(self)


func _on_hover_end() -> void:
	if not interactive:
		return
	_animate_lift(0.0, 0.14)
	z_index = 0
	_hide_detail()
	_set_hover_emphasis(false)
	hover_ended.emit(self)


# The rest of the hover feedback: a brighter, thicker accent border plus a
# deeper, further-offset shadow, so the hovered club reads as lifted off
# the row. Applied to the existing StyleBoxFlats rather than swapped in as
# new ones, so nothing re-lays-out and the card cannot change size.
func _set_hover_emphasis(on: bool) -> void:
	if _panel_style:
		var base_w: int = 2
		var base_top: int = 6 if not compact else 4
		_panel_style.set_border_width_all(3 if on else base_w)
		_panel_style.border_width_top = (base_top + 2) if on else base_top
		# Lighten toward white rather than saturating: the accent is already
		# a deep tone, and brightening it keeps the card face readable.
		_panel_style.border_color = _accent.lerp(Color.WHITE, 0.28) if on else _accent
	if _shadow_style:
		_shadow_style.bg_color = Color(0, 0, 0, 0.28 if on else 0.16)
	if _shadow:
		_shadow.position = Vector2(4, 9) if on else Vector2(3, 5)


# Shown after a short dwell, not instantly: sweeping the cursor across the
# bag to reach the club you already want shouldn't strobe a panel over
# every card on the way.
func _show_detail() -> void:
	_build_detail()
	if not is_instance_valid(_detail):
		return
	if _detail_timer:
		_detail_timer.stop()
	else:
		_detail_timer = Timer.new()
		_detail_timer.one_shot = true
		_detail_timer.timeout.connect(_on_detail_timeout)
		add_child(_detail_timer)
	_detail_timer.start(0.35)


func _on_detail_timeout() -> void:
	# The cursor may have left during the dwell, or the card been taken out
	# of play by a pick, between the timer starting and firing.
	if not interactive or not is_visible_in_tree() or not is_instance_valid(_detail):
		return
	_detail.modulate.a = 0.0
	_detail.visible = true
	_place_detail()
	var tw := create_tween()
	tw.tween_property(_detail, "modulate:a", 1.0, 0.10)


func _hide_detail() -> void:
	if _detail_timer:
		_detail_timer.stop()
	if is_instance_valid(_detail):
		_detail.visible = false


# The popup is parented to the viewport, so it does NOT die with this card.
# Bag rows are rebuilt (and freed) on every refresh_ui, so without this the
# popups would pile up in the viewport, one per card per refresh.
func _free_detail() -> void:
	if is_instance_valid(_detail):
		_detail.queue_free()
	_detail = null


func _on_panel_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_pick_pop()


# Hover feedback: a few pixels of rise rather than a zoom. Animates
# position_offset_y through `position`, which the HBoxContainer sets on
# layout — so it is re-applied relative to the laid-out spot each time
# rather than accumulating.
func _animate_lift(offset_y: float, duration: float) -> void:
	if _hover_tween:
		_hover_tween.kill()
	if _layout_y == INF:
		_layout_y = position.y
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "position:y", _layout_y + offset_y, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_pick_pop() -> void:
	# Before clearing `interactive`: _on_hover_end() bails on a
	# non-interactive card, so the popup has to come down here or it would
	# be stranded on screen after the pick.
	_hide_detail()
	interactive = false
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.14, 1.14), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): picked.emit(self))


# Plays a short "fly toward the hand" exit animation, then calls on_done.
func play_fly_to_hand(target_global_pos: Vector2, on_done: Callable) -> void:
	_hide_detail()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position", target_global_pos, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector2(0.4, 0.4), 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(on_done)


func play_fade_out(delay: float = 0.0) -> void:
	_hide_detail()
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.parallel().tween_property(self, "scale", Vector2(0.9, 0.9), 0.18)
