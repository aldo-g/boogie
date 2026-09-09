extends Node

# Dev-only screenshot harness: boots Main.tscn at a fixed size, lets the UI
# settle, then writes a PNG. Not shipped with the game.

func _ready() -> void:
	var w := int(OS.get_environment("CAP_W")) if OS.get_environment("CAP_W") != "" else 1200
	var h := int(OS.get_environment("CAP_H")) if OS.get_environment("CAP_H") != "" else 900
	var out := OS.get_environment("CAP_OUT")
	if out == "":
		out = "user://capture.png"
	get_window().size = Vector2i(w, h)
	get_window().content_scale_size = Vector2i(w, h)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var scene := load("res://scenes/Main.tscn")
	add_child(scene.instantiate())
	# Let _ready, layout, and any deferred UI build finish.
	for i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("CAPTURED ", out, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()
