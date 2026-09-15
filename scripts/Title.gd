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
	prompt.text = "Click to tee off"
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", COLOR_DARK_GREEN)
	prompt.add_theme_color_override("font_outline_color", COLOR_FADED_WHITE)
	prompt.add_theme_constant_override("outline_size", 4)
	vbox.add_child(prompt)


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventKey) and event.pressed:
		get_tree().change_scene_to_file(MAIN_SCENE)
