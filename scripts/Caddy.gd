extends Control

# ---------------------------------------------------------
# THE CADDY
# An arctic char who swims in from the left edge now and then, says one
# line, and swims off again. Main.gd tells him what just happened
# (react()) and he decides whether it's worth a word: big moments always
# get one, routine ones only sometimes, and never two in quick succession.
#
# Purely cosmetic. He reads the context Main hands him and touches no game
# state, and he draws from his own RandomNumberGenerator — never the
# global one — because Main's _roll() generates online and replay results
# from the global RNG, and an extra randf() here would shift them.
# ---------------------------------------------------------

const CADDY_NAME := "Charlie"
const FISH_TEXTURE := preload("res://assets/art/caddy/char.png")

const FISH_SIZE := Vector2(220, 80)
const BUBBLE_WIDTH := 280.0
const EDGE_GAP := 16.0      # from the left edge of the screen
const ABOVE_GAP := 10.0     # between the fish and the panel he sits above
# Optional lines wait at least this long after the last one, so he
# chimes in rather than narrates.
const COOLDOWN_SEC := 25.0
# Nothing interrupts a line until it's been up this long.
const MIN_ON_SCREEN_SEC := 3.0

# Chance an optional line is spoken when it isn't on cooldown, by the
# event Main reported. Lines listed under _forced in the data file skip it.
const CHANCE := {
	"tee": 0.55,
	"landing": 0.35,
	"form_draw": 0.2,
	"yips": 0.7,
	"bad_card": 0.5,
	"putt": 0.35,
	"putt_result": 0.3,
	"holed": 0.5,
}

# Everything he says lives here, grouped by situation — see the file's
# _comment for the placeholders.
const LINES_PATH := "res://assets/data/caddy_lines.json"
# A fairway shot that carried at least this far gets the big-drive lines.
const BOMB_CARRY := 230.0
# Form cards he has something to say about, and the lines for each.
const CARD_KEYS := {
	"Hook": "card_hook", "Slice": "card_slice", "Top": "card_top",
	"Chunk": "card_chunk", "Shank": "card_shank",
	"Pure Strike": "card_pure_strike", "Stinger": "card_stinger",
	"Flop Shot": "card_flop", "Bump and Run": "card_bump",
	"Controlled Draw": "card_draw", "Controlled Fade": "card_fade",
	"Big Strike": "card_big_strike", "In the Zone": "card_in_the_zone",
}

static var _lines: Dictionary = {}

# The panel he sits on top of (the bag strip). Set by Main.
var anchor_above: Control

var _rng := RandomNumberGenerator.new()
var _rig: Control
var _fish: TextureRect
var _bubble: PanelContainer
var _text: Label
var _tween: Tween
var _showing: bool = false
var _hide_at: float = 0.0
var _last_spoke: float = -1000.0
var _current_forced: bool = false
var _introduced: bool = false
var _clock: float = 0.0


# Built in _init rather than _ready: the test harnesses play a hole before
# the scene's _ready() has run, and he has to be able to talk by then.
func _init() -> void:
	_rng.randomize()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_rig = Control.new()
	_rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rig.visible = false
	add_child(_rig)

	_bubble = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = BogeyTheme.CARD_BG
	s.set_corner_radius_all(10)
	s.border_color = Color(BogeyTheme.INK, 0.22)
	s.set_border_width_all(1)
	s.shadow_color = BogeyTheme.SHADOW_MD
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	_bubble.add_theme_stylebox_override("panel", s)
	_bubble.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)
	_bubble.tooltip_text = "Click to send %s away" % CADDY_NAME
	_bubble.gui_input.connect(_on_click)
	_bubble.resized.connect(_place_bubble)
	_rig.add_child(_bubble)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(col)
	var who := BogeyUI.kicker("%s · your caddy" % CADDY_NAME, BogeyTheme.ACCENT_700)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(who)
	_text = BogeyUI.body("", 15, BogeyTheme.INK)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_text)

	_fish = TextureRect.new()
	_fish.texture = FISH_TEXTURE
	_fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fish.size = FISH_SIZE
	_fish.pivot_offset = FISH_SIZE / 2.0
	_fish.tooltip_text = _bubble.tooltip_text
	_fish.gui_input.connect(_on_click)
	_rig.add_child(_fish)


func _process(delta: float) -> void:
	_clock += delta
	if not _rig.visible:
		return
	# A lazy fin-paddle bob while he's on screen.
	_fish.position.y = _fish_rest_y() + sin(_clock * 3.0) * 3.0
	_fish.rotation = sin(_clock * 2.2) * 0.035
	if _showing and _clock >= _hide_at:
		dismiss()


# Main reports an event; he may or may not have something to say about it.
func react(kind: String, ctx: Dictionary) -> void:
	var key := situation(kind, ctx, _rng)
	var options := lines_for(key)
	if options.is_empty():
		return
	var forced := is_forced(key)
	# Let a line he's only just started finish, unless something bigger
	# has just happened: a ball in the water outranks a remark about the
	# card that put it there.
	if _showing and _clock - _last_spoke < MIN_ON_SCREEN_SEC and (_current_forced or not forced):
		return
	var text := fill(_any(_rng, options), ctx)
	if kind == "tee" and not _introduced:
		# His first appearance always happens, and opens with who he is.
		_introduced = true
		var intro := lines_for("intro")
		if not intro.is_empty():
			text = fill(_any(_rng, intro), ctx) + " " + text
		forced = true
	if not forced:
		if _clock - _last_spoke < COOLDOWN_SEC:
			return
		if _rng.randf() > float(CHANCE.get(kind, 0.3)):
			return
	_current_forced = forced
	say(text)


func say(text: String) -> void:
	_last_spoke = _clock
	_text.text = text
	# Long lines stay up longer; nothing lingers past ten seconds.
	_hide_at = _clock + clampf(2.5 + text.split(" ").size() * 0.3, 4.5, 10.0)
	if _showing:
		_pop_bubble()
		return
	_showing = true
	# Looked up rather than named: a bare --script run (CaddyTest) has no
	# autoloads, and naming one would stop this file compiling there.
	var sound := get_node_or_null("/root/Sound")
	if sound != null:
		sound.play("ui_click", 0.1, -6.0)
	_layout()
	_fish.flip_h = false
	_bubble.modulate.a = 0.0
	_rig.visible = true
	_rig.position.x = -(FISH_SIZE.x * 0.55 + BUBBLE_WIDTH + 40.0)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_rig, "position:x", EDGE_GAP, 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_pop_bubble)


func dismiss() -> void:
	if not _showing:
		return
	_showing = false
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_bubble, "modulate:a", 0.0, 0.15)
	# He turns tail and swims off the way he came.
	_tween.tween_callback(func(): _fish.flip_h = true)
	_tween.tween_property(_rig, "position:x", -(FISH_SIZE.x * 0.55 + BUBBLE_WIDTH + 40.0), 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): _rig.visible = false)


func is_showing() -> bool:
	return _showing


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
		accept_event()


func _pop_bubble() -> void:
	_layout()
	_bubble.scale = Vector2(0.85, 0.85)
	var t := create_tween().set_parallel(true)
	t.tween_property(_bubble, "modulate:a", 1.0, 0.15)
	t.tween_property(_bubble, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# The rig is the fish, sitting just on top of the anchor panel. The bubble
# hangs above his head (he faces right) and grows upward, so a line that
# wraps differently never moves the fish.
func _layout() -> void:
	var floor_y := size.y
	if anchor_above != null and anchor_above.is_inside_tree():
		floor_y = anchor_above.global_position.y - global_position.y
	_rig.size = FISH_SIZE
	_rig.position.y = floor_y - FISH_SIZE.y - ABOVE_GAP
	_fish.position = Vector2(0, _fish_rest_y())
	_bubble.reset_size()
	_place_bubble()


# Also runs on the bubble's own resized signal: an autowrapped label only
# knows its height after a layout pass.
func _place_bubble() -> void:
	_bubble.position = Vector2(FISH_SIZE.x * 0.55, -_bubble.size.y - 2.0)
	_bubble.pivot_offset = Vector2(24, _bubble.size.y)


func _fish_rest_y() -> float:
	return 0.0


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


# --- What he says -------------------------------------------------------
# situation() turns an event into a key in caddy_lines.json; the lines
# themselves are all data. Static and RNG-injected so it can be tested
# without a scene.
#
# ctx keys by kind:
#   tee          par, yards, wind (Vector2), dir (tee to pin), water, last_hole
#   landing      terrain, distance_cap (share of distance the new lie allows),
#                card (Form card name), carry (yards)
#   form_draw    forced (a bad card was forced, no choice)
#   yips, bad_card, rim_out  —
#   hole_out     strokes
#   putt         dist (yards), dist_text
#   putt_result  result ("close" / "miss")
#   holed        diff (strokes against par)
#   round        diff, holes
static func situation(kind: String, ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	match kind:
		"tee":
			return _tee_key(ctx, rng)
		"landing":
			return _landing_key(ctx, rng)
		"form_draw":
			if ctx.get("forced", false):
				return "forced_card"
			return "tips"
		"yips":
			return "yips"
		"bad_card":
			return "bad_card_added"
		"rim_out":
			return "rim_out"
		"hole_out":
			return "hole_in_one" if int(ctx.get("strokes", 0)) == 1 else "hole_out"
		"putt":
			var dist := float(ctx.get("dist", 0.0))
			if dist >= 12.0:
				return "putt_long"
			if dist <= 4.0:
				return "putt_short"
			return "putt_mid"
		"putt_result":
			return "putt_close" if ctx.get("result", "") == "close" else "putt_miss"
		"holed":
			var diff := int(ctx.get("diff", 0))
			if diff <= -2:
				return "holed_eagle"
			if diff == -1:
				return "holed_birdie"
			if diff == 0:
				return "holed_par"
			return "holed_bogey" if diff == 1 else "holed_double"
		"round":
			var diff := int(ctx.get("diff", 0))
			if diff < 0:
				return "round_under"
			return "round_level" if diff == 0 else "round_over"
	return ""


static func _tee_key(ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	if ctx.get("last_hole", false) and rng.randf() < 0.5:
		return "tee_last_hole"
	var keys: Array = []
	var wind: Vector2 = ctx.get("wind", Vector2.ZERO)
	var dir: Vector2 = ctx.get("dir", Vector2(0, -1))
	var mph := Wind.mph(wind)
	if mph < Wind.CALM_MPH:
		keys.append("tee_calm")
	elif mph >= 26:
		# In a gale nothing else about the wind matters.
		keys.append("tee_gale")
	elif dir.length_squared() > 0.0001:
		# Same reading of the wind as Wind.describe().
		var d := dir.normalized()
		var w := wind.normalized()
		var along := w.dot(d)
		var across := w.dot(Vector2(d.y, -d.x))  # > 0: blowing to the right
		if along <= -0.4:
			keys.append("tee_into")
		elif along >= 0.4:
			keys.append("tee_helping")
		if absf(across) >= 0.4:
			keys.append("tee_from_left" if across > 0.0 else "tee_from_right")
	if ctx.get("water", false):
		keys.append("tee_water")
	keys.append({3: "tee_par3", 5: "tee_par5"}.get(int(ctx.get("par", 4)), "tee_par4"))
	if rng.randf() < 0.35:
		keys.append("tips")
	return str(keys[rng.randi_range(0, keys.size() - 1)])


static func _landing_key(ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	var terrain := str(ctx.get("terrain", ""))
	if terrain in ["water", "out", "bunker"]:
		return "land_" + terrain
	# Half the time, talk about the card that got it here instead.
	var card_key: String = CARD_KEYS.get(str(ctx.get("card", "")), "")
	if card_key != "" and rng.randf() < 0.5:
		return card_key
	match terrain:
		"rough":
			return "land_rough_free" if float(ctx.get("distance_cap", 0.8)) >= 1.0 else "land_rough"
		"fairway":
			return "land_fairway_bomb" if float(ctx.get("carry", 0.0)) >= BOMB_CARRY else "land_fairway"
		"green":
			return "land_green"
	return ""


# Swaps {placeholders} for numbers from the moment he's talking about.
static func fill(text: String, ctx: Dictionary) -> String:
	var diff := int(ctx.get("diff", 0))
	var score := "level par"
	if diff < 0:
		score = "%d under" % -diff
	elif diff > 0:
		score = "%d over" % diff
	return text.format({
		"name": CADDY_NAME,
		"mph": Wind.mph(ctx.get("wind", Vector2.ZERO)),
		"yards": int(ctx.get("yards", 0)),
		"par": int(ctx.get("par", 0)),
		"pct": int(round((1.0 - float(ctx.get("distance_cap", 1.0))) * 100.0)),
		"dist": str(ctx.get("dist_text", "")),
		"carry": int(round(float(ctx.get("carry", 0.0)))),
		"score": score,
		"holes": int(ctx.get("holes", 0)),
	})


static func lines_for(key: String) -> Array:
	if key == "":
		return []
	var v: Variant = _data().get(key, [])
	return v if v is Array else []


static func is_forced(key: String) -> bool:
	var v: Variant = _data().get("_forced", [])
	return v is Array and key in v


static func _data() -> Dictionary:
	if _lines.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		if parsed is Dictionary:
			_lines = parsed
		else:
			push_error("Caddy: couldn't read %s — he'll stay quiet." % LINES_PATH)
			_lines = {"_unreadable": true}
	return _lines


static func _any(rng: RandomNumberGenerator, lines: Array) -> String:
	return str(lines[rng.randi_range(0, lines.size() - 1)])
