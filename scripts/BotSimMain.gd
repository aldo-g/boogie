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
#       rough=<p>    ...and after finishing in the rough
#       pins=off     every pin in the middle of its green
#       build=off    the wind and the pins don't build through the round
#       wind=off     no wind;  wind=<mph> caps it
#       nodraft      skip the end-of-hole draft entirely
# ---------------------------------------------------------

var decay_chance: float = -1.0   # < 0: the game's own rule, untouched
var rough_chance: float = -1.0   # < 0: the game's own rule, untouched
var pins_off: bool = false
var build_off: bool = false
var wind_cap: float = -1.0       # < 0: the game's own wind
var no_draft: bool = false

var hole_log: Array = []


func refresh_ui() -> void:
	pass


func rebuild_log() -> void:
	pass


func log_msg(_text: String) -> void:
	pass


func caddy_says(_kind: String, _ctx: Dictionary = {}, _everyone: bool = false, _wait: bool = false) -> void:
	pass


func start_hole() -> void:
	super.start_hole()
	if build_off:
		hole.wind = Wind.for_hole(wind_seed, current_hole_index, "", 0.0)
		hole.cut_pin(Pins.for_hole(wind_seed, current_hole_index, hole, 0.0))
	if pins_off:
		hole.cut_pin(hole.green_pos)
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
		"counts": Brands.counts(bag),
		"pin": hole.pin_name,
		"pin_off": snappedf(hole.pin_pos.distance_to(hole.green_pos), 0.1),
		"hazards": 0,
		"roughs": 0,
		"bad_added": 0,
	})


# `chance` tells a hazard from the rough: only the rough's is lower.
func maybe_add_bad_card_to_form_deck(lie_result: String, chance: float, family: String = "") -> void:
	var from_rough: bool = chance < ShotRules.FORM_DECAY_CHANCE - 0.0001
	var before := form_deck.bad_count()
	var swapped: float = rough_chance if from_rough else decay_chance
	if swapped < 0.0:
		super.maybe_add_bad_card_to_form_deck(lie_result, chance, family)
	elif ShotRules.hazard_can_decay_form(hand) and randf() < swapped:
		form_deck.add_bad_card_to_deck("", family)
	if not hole_log.is_empty():
		if from_rough:
			hole_log[-1].roughs += 1
		else:
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
