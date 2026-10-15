extends Control

# ---------------------------------------------------------
# BOGEY TITLE SCREEN
# Course map fills the entire background. Title wordmark sits on
# top of it in the open space.
# Click/press to continue into the single-hole prototype (scenes/Main.tscn).
# ---------------------------------------------------------

const COURSE_MAP := preload("res://assets/maps/llanfair-course.jpeg")
const TITLE_FONT := preload("res://assets/fonts/AlexBrush-Regular.ttf")
const Palette := preload("res://scripts/BogeyTheme.gd")
const MAIN_SCENE := "res://scenes/Main.tscn"

# How many players the round starts with. Read by Main.gd on load.
# Hot-seat: everyone plays on this one screen, taking turns.
const MAX_PLAYERS := 4

const COLOR_DARK_GREEN := Palette.FAIRWAY_DEEP
const COLOR_FADED_WHITE := Palette.PARCHMENT


func _ready() -> void:
	build_ui()


func build_ui() -> void:
	# Course map, filling the entire window edge-to-edge.
	var bg := TextureRect.new()
	bg.texture = COURSE_MAP
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vbox.offset_left = 40
	vbox.offset_top = 24
	add_child(vbox)

	var title := Label.new()
	title.text = "Bogey!"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", COLOR_DARK_GREEN)
	title.add_theme_color_override("font_outline_color", COLOR_FADED_WHITE)
	title.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title)

	var prompt := Label.new()
	prompt.text = "Choose your players, then tee off"
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", COLOR_DARK_GREEN)
	prompt.add_theme_color_override("font_outline_color", COLOR_FADED_WHITE)
	prompt.add_theme_constant_override("outline_size", 4)
	vbox.add_child(prompt)

	# --- Player count (hot-seat, one screen, taking turns) ---
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	for n in range(1, MAX_PLAYERS + 1):
		var b := Button.new()
		b.text = "1 Player" if n == 1 else "%d Players" % n
		b.custom_minimum_size = Vector2(118, 40)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_player_count_pressed.bind(n))
		row.add_child(b)

	var note := Label.new()
	note.text = "Hot-seat — everyone plays on this screen, furthest from the pin plays first."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", COLOR_DARK_GREEN)
	note.add_theme_color_override("font_outline_color", COLOR_FADED_WHITE)
	note.add_theme_constant_override("outline_size", 3)
	vbox.add_child(note)


func _on_player_count_pressed(count: int) -> void:
	start_round(count)


func start_round(count: int) -> void:
	Sound.play("ui_confirm")
	GameSetup.player_count = count
	get_tree().change_scene_to_file(MAIN_SCENE)


# Clicking anywhere off the buttons still tees off solo, so the old
# one-click path into the game is unchanged.
func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventKey) and event.pressed:
		start_round(1)
