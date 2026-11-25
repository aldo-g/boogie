extends RefCounted

# ---------------------------------------------------------
# The round in progress, kept between sessions in user://round.save — so
# a round of an hour or more, and a tour of four, can be left and come
# back to.
#
# One save, written by Main at the stop after each hole (and before the
# first tee): the state as the hole was scored, before anything is dealt
# at the stop. Coming back picks the round up at that stop, so leaving in
# the middle of a hole means playing the hole again from its tee, and a
# finished hole is never lost. A tour course that is finished with another
# to come is saved as done, with the bag still to pack.
#
# Only local rounds a player started from the title are saved: Main asks
# Records.enabled, the same gate the records use, so no harness or capture
# writes one. Online rounds are the host's to run and are not saved.
#
# Stored with store_var(), not as JSON: a save is full of ints (hole
# numbers, marks, levels) that JSON would hand back as floats. Objects are
# never decoded from it.
#
# Loaded by preload:
#   const RoundSave := preload("res://scripts/RoundSave.gd")
# ---------------------------------------------------------

const PATH := "user://round.save"
const VERSION := 1

static var path: String = PATH  # a harness points this at a scratch file


static func exists() -> bool:
	return not read().is_empty()


# The saved round, or {} when there is none (or it is from another
# version of the game, or unreadable).
static func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() == 0:
		return {}
	var data: Variant = f.get_var(false)
	if not (data is Dictionary) or int(data.get("version", 0)) != VERSION \
			or not (data.get("players") is Array) or (data.players as Array).is_empty():
		return {}
	return data


static func write(data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Pars and Chars: could not save the round to %s" % path)
		return
	f.store_var(data, false)


static func clear() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# Puts the title's choices back as they were when the saved round was
# started — who is playing, the tour so far, the course — ready for the
# game scene, which picks the rest up from GameSetup.resume.
static func restore_setup(data: Dictionary) -> void:
	var players: Array = data.get("players", [])
	GameSetup.reset_to_local(clampi(players.size(), 1, 4))
	for i in range(players.size()):
		var skill := str(players[i].get("cpu_skill", ""))
		if skill != "":
			GameSetup.cpu_seats[i] = skill
	GameSetup.guided = bool(data.get("guided", false))
	var tour: Dictionary = data.get("tour", {})
	GameSetup.tour = bool(tour.get("on", false))
	GameSetup.tour_leg = int(tour.get("leg", 0))
	GameSetup.tour_bag = (tour.get("bag", []) as Array).duplicate(true)
	GameSetup.tour_brands = (tour.get("brands", []) as Array).duplicate()
	GameSetup.tour_results = (tour.get("results", []) as Array).duplicate(true)
	# One of the game's own courses by which course it is; a saved one by
	# its holes as they were, since its file may have changed since.
	if not Course.use_shipped(str(data.get("course_id", ""))):
		var course := Course.from_wire(data.get("course", {}))
		if course.is_empty():
			Course.use_builtin()
		else:
			Course.use(course)
			Course.active_path = str(data.get("course_path", ""))
	GameSetup.resume = data


# "Bogey Links · 6 holes played · 3 over", for the title screen.
static func summary(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	var bits := PackedStringArray()
	var tour: Dictionary = data.get("tour", {})
	if bool(tour.get("on", false)):
		bits.append("The Tour, course %d" % (int(tour.get("leg", 0)) + 1))
	bits.append(str(data.get("course_name", "")))
	var played := int(data.get("hole", 0))
	if bool(data.get("done", false)):
		bits.append("packing for the next course")
	elif played <= 0:
		bits.append("before the first tee")
	else:
		bits.append("%d hole%s played" % [played, "" if played == 1 else "s"])
		var diff := 0
		for entry in (data.players[0].get("round_scores", []) as Array):
			diff += int(entry.strokes) - int(entry.par)
		bits.append(Records.diff_text(diff))
	var others := PackedStringArray()
	for i in range(1, (data.players as Array).size()):
		others.append(str(data.players[i].get("name", "")))
	if not others.is_empty():
		bits.append("with %s" % ", ".join(others))
	return " · ".join(bits)
