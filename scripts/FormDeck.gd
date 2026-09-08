class_name FormDeck
extends RefCounted

# ---------------------------------------------------------
# Section 4 — Form deck: the shared pool every shot draws from. Starts
# ~65% good / 35% bad (Section 4). Hazard hits add bad cards into this
# deck (not the Bag) so a rough patch degrades future draws for the rest
# of the round.
#
# The draw itself is always plain and unbiased — every card in the deck
# has an equal chance regardless of swing tier or lie. Risk instead comes
# from how many cards you get to choose from, as a bell curve centered on
# MID (a smooth, repeatable swing): both swinging all-out and easing off
# for a delicate touch shot leave you less room to dodge a bad card.
#   MID-range         -> draw 3, pick 1 (best choice)
#   FULL / FINESSE     -> draw 2, pick 1 (less room to dodge a bad one)
#   EXTREME_FINESSE     -> no draw at all: the club creates 1 fresh bad
#                          Form card on the spot and you're forced to play
#                          it, no choice. A bunker lie forces this same
#                          treatment regardless of swing tier (Section 5).
# ---------------------------------------------------------

const Tier := ShotResolver.Tier

const TIER_DRAW_COUNT := {
	ShotResolver.Tier.FULL: 2,
	ShotResolver.Tier.MID: 3,
	ShotResolver.Tier.FINESSE: 2,
	ShotResolver.Tier.EXTREME_FINESSE: 0,  # 0 means "forced card, no draw" — see draw_for_shot()
}

var deck: Array = []     # Array[FormCard]
var discard: Array = []  # Array[FormCard]


func _init() -> void:
	deck = build_starting_deck()
	deck.shuffle()


static func build_starting_deck() -> Array:
	var cards: Array = []
	# ~65% good / 35% bad. 8 good names x2 = 16, 6 bad names x~2 = 12 -> 16/28 = 57%;
	# bump good copies to 3 each to land closer to 65/35 (21 good / 12 bad = 64%).
	for good_name in FormCard.GOOD_NAMES:
		for i in range(3):
			cards.append(FormCard.make(good_name))
	for bad_name in FormCard.BAD_NAMES:
		for i in range(2):
			cards.append(FormCard.make(bad_name))
	return cards


func _reshuffle_if_empty() -> void:
	if deck.is_empty():
		deck.append_array(discard)
		discard.clear()
		deck.shuffle()


func _draw_one() -> FormCard:
	_reshuffle_if_empty()
	if deck.is_empty():
		# Discard was also empty (degenerate/empty-pool edge case) — hand back
		# a neutral Pure Strike rather than crashing the draw.
		return FormCard.make("Pure Strike")
	return deck.pop_back()


# Creates a fresh bad Form card directly (not drawn from the shared deck at
# all) for Extreme Finesse and bunker lies — the same Created-card
# mechanism as Section 4's Pure Strike/Big Strike, just bad instead of
# good. The shared Form deck's own contents/odds are untouched by this.
func create_forced_bad_card(card_name: String = "") -> FormCard:
	var name: String = card_name
	if name == "":
		name = FormCard.BAD_NAMES[randi_range(0, FormCard.BAD_NAMES.size() - 1)]
	return FormCard.make(name)


# Draws the Form card options for this shot. force_extreme (a bunker lie)
# makes this resolve exactly like EXTREME_FINESSE regardless of tier:
# {"forced": true, "cards": [<the one forced bad card>]} — no choice, no
# draw from the shared deck. Otherwise draws TIER_DRAW_COUNT[tier] cards,
# plainly and without bias, for the caller to pick 1 from:
# {"forced": false, "cards": [...]}.
func draw_for_shot(tier: int, force_extreme: bool = false) -> Dictionary:
	if force_extreme or tier == Tier.EXTREME_FINESSE:
		return {"forced": true, "cards": [create_forced_bad_card()]}

	var count: int = TIER_DRAW_COUNT.get(tier, 3)
	var drawn: Array = []
	for i in range(count):
		drawn.append(_draw_one())
	return {"forced": false, "cards": drawn}


func return_unpicked(cards: Array, picked_index: int) -> void:
	for i in range(cards.size()):
		if i != picked_index:
			discard.append(cards[i])


func add_bad_card_to_deck(card_name: String = "") -> FormCard:
	var name: String = card_name
	if name == "":
		name = FormCard.BAD_NAMES[randi_range(0, FormCard.BAD_NAMES.size() - 1)]
	var card := FormCard.make(name)
	# Straight into the live deck (not discard) so it can surface on the very
	# next draw rather than waiting for a reshuffle.
	deck.append(card)
	deck.shuffle()
	return card
