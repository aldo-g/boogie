extends "res://scripts/Main.gd"

# ---------------------------------------------------------
# Main.gd for the balance harness (BotSim.gd) — a dev tool, not shipped.
#
# Plays the real rules, with three changes:
#   - the screen is never redrawn, logged to or narrated (speed: the bot
#     reads state, not widgets);
#   - each hole is recorded: wind, hazards found, bad cards the Form deck
#     gained, and the bag it was played with;
#   - a few rules can be switched for controlled experiments (`variant`):
#       decay=<p>    Form decay chance after a hazard (default: the game's)
#       wind=off     no wind;  wind=<mph> caps it
#       nodraft      skip the end-of-hole draft entirely
# ---------------------------------------------------------

var decay_chance: float = -1.0   # < 0: the game's own rule, untouched
var wind_cap: float = -1.0       # < 0: the game's own wind
var no_draft: bool = false

var hole_log: Array = []


func refresh_ui() -> void:
	pass


func rebuild_log() -> void:
	pass


func log_msg(_text: String) -> void:
	pass


func caddy_says(_kind: String, _ctx: Dictionary = {}, _everyone: bool = false) -> void:
	pass


func start_hole() -> void:
	super.start_hole()
	if wind_cap >= 0.0 and hole.wind.length() > wind_cap:
		hole.wind = hole.wind.normalized() * wind_cap if wind_cap > 0.0 else Vector2.ZERO
	var bag: Array = me.hand
	hole_log.append({
		"hole": current_hole_index,
		"wind": snappedf(hole.wind.length(), 0.1),
		"bad_start": form_deck.bad_count(),
		"deck_n": form_deck.deck.size() + form_deck.discard.size(),
		"bag": bag.map(func(c): return c.name),
		"tiers": _tiers(bag),
		"hazards": 0,
		"bad_added": 0,
	})


func maybe_add_bad_card_to_form_deck(lie_result: String) -> void:
	var before := form_deck.bad_count()
	if decay_chance < 0.0:
		super.maybe_add_bad_card_to_form_deck(lie_result)
	elif ShotRules.hazard_can_decay_form(hand) and randf() < decay_chance:
		form_deck.add_bad_card_to_deck(FormCard.BAD_NAMES.pick_random())
	if not hole_log.is_empty():
		hole_log[-1].hazards += 1
		hole_log[-1].bad_added += form_deck.bad_count() - before


func begin_draft_phase() -> void:
	if no_draft:
		begin_next_draft()
		return
	super.begin_draft_phase()


static func _tiers(bag: Array) -> Dictionary:
	var out := {}
	var counts := Brands.counts(bag)
	for b in counts:
		var t := Brands.tier_reached(int(counts[b]))
		if t > 0:
			out[b] = t
	return out
