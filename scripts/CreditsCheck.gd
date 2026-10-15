extends SceneTree
# Checks the credits content carries the attributions CC BY 3.0 requires.
# Builds the labels the same way _build_credits() does, without needing
# the title scene (whose _ready() touches the Net autoload, unavailable
# to --script runs).
func _initialize() -> void:
	var lines: Array = []
	for section in Credits.SECTIONS:
		lines.append(str(section.heading))
		if str(section.note) != "":
			lines.append(str(section.note))
		for l in section.lines:
			lines.append(str(l))
	lines.append(Credits.LICENCE_NOTE)
	var blob := "\n".join(lines)

	print("credit lines: %d" % lines.size())

	# These are the obligation.
	var required := ["Lorc", "Caro Asercion", "Catsu", "CC BY 3.0", "game-icons.net"]
	var missing: Array = []
	for r in required:
		if not blob.contains(r):
			missing.append(r)
	print("REQUIRED missing: %s" % str(missing))

	# These are courtesy, but check they survived editing.
	var courtesy := ["Kenney", "memoraphile", "isaiah658", "Alex Brush",
		"Mixkit", "OpenGameArt", "public domain"]
	var absent: Array = []
	for c in courtesy:
		if not blob.contains(c):
			absent.append(c)
	print("courtesy absent: %s" % str(absent))

	# Every icon author in the art CREDITS.md must appear on screen.
	var f := FileAccess.open("res://assets/art/CREDITS.md", FileAccess.READ)
	var doc := f.get_as_text()
	f.close()
	var doc_authors := ["Lorc", "Caro Asercion", "Catsu"]
	var unshown: Array = []
	for a in doc_authors:
		if doc.contains(a) and not blob.contains(a):
			unshown.append(a)
	print("in CREDITS.md but not on screen: %s" % str(unshown))

	var ok: bool = missing.is_empty() and unshown.is_empty()
	print("CREDITS: %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)
