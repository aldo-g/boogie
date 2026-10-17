class_name SettingsPanel
extends VBoxContainer

# ---------------------------------------------------------
# The settings controls, built in code like the rest of the UI. Used by
# the title screen's Settings page and by the in-game popup, so the two
# can never disagree. Every change is applied and saved at once
# (Settings.set_value), so there's no Save button to forget.
# ---------------------------------------------------------

signal closed

var _show_back: bool
var _key_button: Button
var _capturing := false
var _speed_buttons: Array = []
var _sliders: Dictionary = {}  # setting key -> [HSlider, value Label]


func _init(show_back: bool = true) -> void:
	_show_back = show_back


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_sliders = {}
	_speed_buttons = []

	add_child(BogeyUI.kicker("Sound"))
	_add_slider("master", "Master")
	_add_slider("music", "Music")
	_add_slider("sfx", "Effects")

	add_child(BogeyUI.hairline(0.12))
	add_child(BogeyUI.kicker("Shots"))
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	add_child(speed_row)
	for i in Settings.SHOT_SPEED_NAMES.size():
		var b := Button.new()
		b.text = Settings.SHOT_SPEED_NAMES[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_speed_pressed.bind(i))
		speed_row.add_child(b)
		_speed_buttons.append(b)
	_style_speed_buttons()
	add_child(BogeyUI.body("How the ball's flight plays out. Instant skips straight to where it stops.", 12, BogeyTheme.NEUTRAL_600))

	add_child(BogeyUI.hairline(0.12))
	add_child(BogeyUI.kicker("Putting"))
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 10)
	add_child(key_row)
	var key_label := BogeyUI.body("Strike key", 14, BogeyTheme.INK)
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key_row.add_child(key_label)
	_key_button = Button.new()
	_key_button.custom_minimum_size = Vector2(200, 40)
	_key_button.focus_mode = Control.FOCUS_NONE
	_key_button.pressed.connect(_on_key_pressed)
	key_row.add_child(_key_button)
	_refresh_key_button()

	add_child(BogeyUI.hairline(0.12))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	add_child(footer)
	if _show_back:
		var back := Button.new()
		back.text = "Back"
		back.custom_minimum_size = Vector2(140, 0)
		BogeyUI.style_button(back)
		back.pressed.connect(_on_back_pressed)
		footer.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var reset := BogeyUI.style_link_button(Button.new())
	reset.text = "Reset to defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_on_reset_pressed)
	footer.add_child(reset)


func _add_slider(key: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var label := BogeyUI.body(label_text, 14, BogeyTheme.INK)
	label.custom_minimum_size = Vector2(80, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = round(float(Settings.get_value(key)) * 100.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	var value := BogeyUI.body("", 13, BogeyTheme.NEUTRAL_700)
	value.custom_minimum_size = Vector2(44, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	_sliders[key] = [slider, value]
	_set_value_label(key)
	slider.value_changed.connect(_on_slider_changed.bind(key))
	# A click of the effects slider lets you hear the new level.
	if key == "sfx" or key == "master":
		slider.drag_ended.connect(func(_changed): Sound.play("ui_click"))


func _set_value_label(key: String) -> void:
	var pair: Array = _sliders[key]
	var v := int((pair[0] as HSlider).value)
	(pair[1] as Label).text = "Off" if v == 0 else "%d%%" % v


func _on_slider_changed(v: float, key: String) -> void:
	Settings.set_value(key, v / 100.0)
	_set_value_label(key)


func _style_speed_buttons() -> void:
	for i in _speed_buttons.size():
		BogeyUI.style_button(_speed_buttons[i], i == Settings.shot_speed(), 14)


func _on_speed_pressed(i: int) -> void:
	Settings.set_value("shot_speed", i)
	Sound.play("ui_click")
	_style_speed_buttons()


# --- Putt key capture ------------------------------------------------

func _refresh_key_button() -> void:
	if _capturing:
		_key_button.text = "Press a key…  (Esc cancels)"
		BogeyUI.style_button(_key_button, true, 14)
	else:
		_key_button.text = Settings.putt_key_name()
		BogeyUI.style_button(_key_button, false, 14)


func _on_key_pressed() -> void:
	_capturing = not _capturing
	Sound.play("ui_click")
	_refresh_key_button()


func is_capturing() -> bool:
	return _capturing


func _input(event: InputEvent) -> void:
	if not _capturing or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var code: int = event.keycode
	if code == KEY_ESCAPE:
		_capturing = false
		Sound.play("ui_back")
	elif Settings.key_allowed(code):
		Settings.set_value("putt_key", code)
		_capturing = false
		Sound.play("ui_confirm")
	else:
		Sound.play("ui_error")
		return
	_refresh_key_button()


# --- Footer --------------------------------------------------------

func _on_reset_pressed() -> void:
	Settings.reset_to_defaults()
	_capturing = false
	Sound.play("ui_back")
	_build()


func _on_back_pressed() -> void:
	_capturing = false
	Sound.play("ui_back")
	closed.emit()
