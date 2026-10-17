extends SceneTree
# Checks the caddy's line file (assets/data/caddy_lines.json) after editing:
#   1. it parses
#   2. every situation the game can produce has at least one line
#   3. every _forced key is a real situation
#   4. no line uses a placeholder fill() doesn't know
# Run: godot --headless --script res://scripts/CaddyTest.gd

const Caddy := preload("res://scripts/Caddy.gd")

# Every key Caddy.situation() can return.
const SITUATIONS := [
	"intro", "tips",
	"tee_calm", "tee_into", "tee_helping", "tee_from_left", "tee_from_right",
	"tee_gale", "tee_water", "tee_par3", "tee_par4", "tee_par5", "tee_last_hole",
	"forced_card", "yips", "bad_card_added",
	"land_water", "land_out", "land_bunker", "land_rough", "land_rough_free",
	"land_fairway", "land_fairway_bomb", "land_green",
	"rim_out", "hole_out", "hole_in_one",
	"putt_long", "putt_mid", "putt_short", "putt_close", "putt_miss",
	"holed_eagle", "holed_birdie", "holed_par", "holed_bogey", "holed_double",
	"round_under", "round_level", "round_over",
]


func _initialize() -> void:
	var failures: Array = []
	var data: Dictionary = Caddy._data()
	if data.has("_unreadable"):
		print("CADDY: FAIL — %s doesn't parse" % Caddy.LINES_PATH)
		quit(1)
		return

	var known := SITUATIONS.duplicate()
	for card_key in Caddy.CARD_KEYS.values():
		known.append(card_key)

	var total := 0
	for key in known:
		var lines := Caddy.lines_for(key)
		total += lines.size()
		if lines.is_empty():
			failures.append("no lines for '%s'" % key)

	for key in data:
		if not key.begins_with("_") and not key in known:
			failures.append("'%s' is never used by the game (typo?)" % key)
	for key in data.get("_forced", []):
		if not key in known:
			failures.append("_forced names unknown situation '%s'" % key)

	# A filled line with a brace left in it used a placeholder fill() lacks.
	var ctx := {"wind": Vector2(10, 0), "yards": 400, "par": 4, "distance_cap": 0.8,
		"dist_text": "9 ft", "carry": 240.0, "diff": 2, "holes": 18}
	for key in known:
		for line in Caddy.lines_for(key):
			var out := Caddy.fill(str(line), ctx)
			if out.contains("{") or out.contains("}"):
				failures.append("unknown placeholder in %s: %s" % [key, line])

	print("caddy lines: %d across %d situations" % [total, known.size()])
	for f in failures:
		print("  FAIL: " + f)
	print("\nCADDY: %s" % ("OK" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
