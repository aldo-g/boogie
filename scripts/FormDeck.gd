class_name FormDeck
extends RefCounted

# ---------------------------------------------------------
# Section 4 — the Form deck: the pool every shot draws from. Starts as a
# small pile for each family, about two good cards to every bad one, and
# is built by the bag: every club brings its shots (bring() / take()).
# Hazard hits add bad cards
# into this deck (not the Bag), so a rough patch degrades future draws
# for the rest of the round.
#
# FORM BY CLUB FAMILY. Every card belongs to a club family (wood, iron,
# wedge, putter — FormCard.FAMILY_MIX), and a swing is dealt only from
# the family of the club in hand. It is one deck and one discard pile,
# but a draw for a wood takes the next *wood* card down and leaves the
# others where they lie. So each family is its own form: a hazard found
# with the driver puts its bad card among the wood cards, and the wedges
# never see it.
#
# Within a family the draw is plain and unbiased — every card of it has an
# equal chance regardless of swing tier or lie. Risk instead comes from
# how many cards you get to choose from, as a bell curve centered on MID
# (a smooth, repeatable swing): both swinging all-out and easing off for
# a delicate touch shot leave you less room to dodge a bad card.
#   MID-range         -> draw 3, pick 1 (best choice)
#   FULL / FINESSE     -> draw 2, pick 1 (less room to dodge a bad one)
#   EXTREME_FINESSE     -> no draw at all: the club creates 1 fresh bad
#                          Form card on the spot and you're forced to play
#                          it, no choice. A bunker lie forces this same
#                          treatment regardless of swing tier (Section 5).
#
# `family` everywhere is one of FormCard.FAMILIES, or "" for "any card",
# which is the deck as it was before families.
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
	# See FormCard.FAMILY_MIX for the counts.
	for fam in FormCard.FAMILIES:
		var mix: Dictionary = FormCard.FAMILY_MIX[fam]
		for card_name in mix:
			for i in range(int(mix[card_name])):
				cards.append(FormCard.make(card_name).of_family(fam))
	return cards


# DEALT TO THE CLUB (2026-11-19). A card a club brought (FormCard.owner)
# is dealt only to that club. So a swing draws from its family's own pile
# — the cards the round started with and the ones trouble left there —
# plus the shots of the club in hand. `owner` everywhere is that club's
# name, or "" for "any club's" (purges, counts, the tests).

# Whether `card` can be dealt to a swing of `family` with the club `owner`.
static func _in_family(card: FormCard, family: String, owner: String = "") -> bool:
	if not (family == "" or card.family == family or card.family == ""):
		return false
	return owner == "" or card.owner == "" or card.owner == owner


# Index of the next card for `family` and `owner` from the top of the
# deck, or -1.
func _top_of(family: String, owner: String = "") -> int:
	for i in range(deck.size() - 1, -1, -1):
		if _in_family(deck[i], family, owner):
			return i
	return -1


# The family's played cards go back into the deck. Only that family's:
# the others are still working through their own.
func _reshuffle(family: String) -> void:
	var stay: Array = []
	for c in discard:
		if _in_family(c, family):
			deck.append(c)
		else:
			stay.append(c)
	discard = stay
	deck.shuffle()


func _draw_one(family: String = "", owner: String = "") -> FormCard:
	var i := _top_of(family, owner)
	if i < 0:
		_reshuffle(family)
		i = _top_of(family, owner)
	if i < 0 and family != "":
		# Every card of the family is already in the hand being dealt (a big
		# draw from a small family). Borrow the next card of any family
		# rather than deal nothing.
		return _draw_one("")
	if i < 0:
		# No cards anywhere (degenerate/empty-pool edge case) — hand back a
		# neutral Pure Strike rather than crashing the draw.
		return FormCard.make("Pure Strike")
	var card: FormCard = deck[i]
	deck.remove_at(i)
	return card


# Creates a fresh bad Form card directly (not drawn from the deck at all)
# for Extreme Finesse and bunker lies — the same Created-card mechanism as
# Section 4's Pure Strike/Big Strike, just bad instead of good, and one of
# the misses the club's family is prone to. The deck's own contents are
# untouched by this — it exhausts like any created card, so it never
# reaches the discard pile.
func create_forced_bad_card(card_name: String = "", family: String = "") -> FormCard:
	var name: String = card_name
	if name == "":
		var pool: Array = FormCard.bad_names_for(family)
		name = pool[randi_range(0, pool.size() - 1)]
	return FormCard.make(name).of_family(family).as_created()


# Draws the Form card options for this shot from `family`. force_extreme (a
# bunker lie) makes this resolve exactly like EXTREME_FINESSE regardless of
# tier: {"forced": true, "cards": [<the one forced bad card>]} — no choice,
# no draw from the deck. Otherwise draws TIER_DRAW_COUNT[tier] cards,
# plainly and without bias, for the caller to pick 1 from:
# {"forced": false, "cards": [...]}.
# bonus_cards: Section 3A brand set bonuses (Titanist 4, Slazinger 2/4)
# add cards to every draw. drop_worst (Titanist 2) then discards the worst
# card of the draw before the player picks — they still choose from the
# same number of cards, but never from the very worst option available.
func draw_for_shot(tier: int, force_extreme: bool = false,
		bonus_cards: int = 0, drop_worst: bool = false, family: String = "",
		owner: String = "") -> Dictionary:
	if force_extreme or tier == Tier.EXTREME_FINESSE:
		return {"forced": true, "cards": [create_forced_bad_card("", family)]}

	# A bonus can be negative (a Titanist Staff club out of its set draws
	# one fewer), but a swing is always dealt at least one card.
	var count: int = maxi(1, TIER_DRAW_COUNT.get(tier, 3) + bonus_cards)
	# Titanist 2 draws one extra and bins the worst, so the player still
	# picks from the tier's normal count.
	if drop_worst:
		count += 1

	var drawn: Array = []
	for i in range(count):
		drawn.append(_draw_one(family, owner))
	# A grooved shot comes with a spare (FormCard.grooved).
	for i in range(count):
		if drawn[i].grooved:
			drawn.append(_draw_one(family, owner))

	if drop_worst and drawn.size() > 1:
		var worst_index := 0
		for i in range(1, drawn.size()):
			if _card_rank(drawn[i]) < _card_rank(drawn[worst_index]):
				worst_index = i
		discard.append(drawn[worst_index])
		drawn.remove_at(worst_index)

	return {"forced": false, "cards": drawn}


# Rough desirability score, only ever used to decide which card Titanist's
# 2-set bins and which bad card a purge takes. Good cards always outrank
# bad ones; within each group, less deviation and less distance loss rank
# higher. Deliberately simple — it picks the card to throw away, not the
# card to play.
func _card_rank(card: FormCard) -> float:
	var score: float = 100.0 if card.good else 0.0
	score -= card.degrees
	score += card.distance_mult * 20.0
	if card.downgrades_lie:
		score -= 30.0
	if card.is_yips:
		score -= 25.0
	return score


# Created cards exhaust — they never join the discard pile.
func return_unpicked(cards: Array, picked_index: int) -> void:
	for i in range(cards.size()):
		if i != picked_index and not cards[i].created:
			discard.append(cards[i])


# The card that was played joins the ones passed over in the discard
# pile, to come round again when its family is reshuffled. Without this
# every shot would take a card out of the game, and a round has more shots
# in it than the deck has cards. A created card exhausts instead.
func discard_played(card: FormCard) -> void:
	if card != null and not card.created:
		discard.append(card)


# `n` plain draws from `family`, for a re-draw (Titanist 8).
func draw_cards(n: int, family: String = "", owner: String = "") -> Array:
	var drawn: Array = []
	for i in range(n):
		drawn.append(_draw_one(family, owner))
	return drawn


# Bad cards in the deck and discard — of one family, or of all.
func bad_count(family: String = "") -> int:
	var n := 0
	for c in deck + discard:
		if not c.good and (family == "" or c.family == family):
			n += 1
	return n


# Your form with each kind of club: {family: {"good": n, "bad": n}}, over
# the deck and the discard pile together — every card that can still be
# dealt to that family this round.
func family_form() -> Dictionary:
	var out := {}
	for fam in FormCard.FAMILIES:
		out[fam] = {"good": 0, "bad": 0}
	for c in deck + discard:
		# A club's own shots are that club's form, not the family's.
		if c.owner != "":
			continue
		if out.has(c.family):
			out[c.family]["good" if c.good else "bad"] += 1
		elif c.family == "":
			# A card of no family (a Nimbus Utility Swing) can be dealt to
			# any swing, so it is part of every family's form.
			for fam in FormCard.FAMILIES:
				out[fam]["good" if c.good else "bad"] += 1
	return out


# What `club` is dealt from: {"good": n, "bad": n} over its family's pile
# and its own shots.
func club_form(club: Dictionary) -> Dictionary:
	var out := {"good": 0, "bad": 0}
	for c in club_cards(club):
		out["good" if c.good else "bad"] += 1
	return out


# The cards themselves: every card `club` can be dealt, drawn or discarded.
func club_cards(club: Dictionary) -> Array:
	return (deck + discard).filter(func(c):
		return _in_family(c, FormCard.family_of(club), str(club.get("name", ""))))


# --- Cards a club brings (Section 4 "Clubs bring their shots") -----------

# Puts a card into the deck in `family` ("" for a card any swing can be
# dealt). Straight into the live deck, shuffled, so it can turn up on the
# next draw.
func add_card(card_name: String, family: String = "", owner: String = "") -> FormCard:
	var card := FormCard.make(card_name).of_family(family).owned_by(owner)
	deck.append(card)
	deck.shuffle()
	return card


# Takes one copy of a card of `family` out of the deck for good — from the
# discard pile first, so the cards about to be drawn are the last touched.
# False if there was none to take.
func remove_card(card_name: String, family: String = "", owner: String = "") -> bool:
	for pile in [discard, deck]:
		for i in range(pile.size()):
			var c: FormCard = pile[i]
			if c.key() == card_name and c.family == family and c.owner == owner and not c.created:
				pile.remove_at(i)
				return true
	return false


# --- The shots a club brings (Section 4 "Every club brings its shots") ---

# Puts every shot `club` brings into the deck, each in its family. Returns
# their names.
func bring(club: Dictionary) -> Array:
	var shots: Array = club.get("shots", [])
	for s in shots:
		var fam := Brands.shot_family(club, str(s))
		add_card(str(s), fam, shot_owner(club, fam))
	# A club that arrives with a hosel rocket (a second-hand one) brings it.
	if ClubAbilities.curse(club) == "hosel_rocket":
		add_card("Shank", FormCard.family_of(club), str(club.name))
	return shots


# Who a club's shot of `family` is dealt to: the club alone — except a
# card of no family (a Nimbus Utility Swing), which is anyone's.
static func shot_owner(club: Dictionary, family: String) -> String:
	return "" if family == "" else str(club.get("name", ""))


# Takes a club's shots out again when it leaves the bag, and the Shank a
# hosel rocket put there. Returns the names that were still in the deck (a
# range session may have had its miss already).
func take(club: Dictionary) -> Array:
	var out: Array = []
	for s in club.get("shots", []):
		var fam := Brands.shot_family(club, str(s))
		if remove_card(str(s), fam, shot_owner(club, fam)):
			out.append(str(s))
	if ClubAbilities.curse(club) == "hosel_rocket":
		remove_card("Shank", FormCard.family_of(club), str(club.get("name", "")))
	return out


# How many copies of a card the deck and discard hold, in any family.
func count_of(card_name: String) -> int:
	var n := 0
	for c in deck + discard:
		if c.name == card_name:
			n += 1
	return n


# A played bad card that goes straight back on top of the deck, to be the
# next card its family is dealt (a Callowell Staff club out of its set).
func return_to_top(card: FormCard) -> void:
	if card != null and not card.created:
		deck.append(card)


# Removes up to `n` bad cards from the deck and discard — the worst first
# (by _card_rank), discard before deck on a tie so the next draws are the
# last thing touched. With a `family`, that family's bad cards go first
# and the others only once it has none left. Returns the removed cards'
# names.
func purge_bad(n: int, family: String = "") -> Array:
	var removed: Array = []
	for k in range(n):
		var hit := _worst_bad(family)
		if hit.is_empty() and family != "":
			hit = _worst_bad("")
		if hit.is_empty():
			break
		var pile: Array = hit.pile
		removed.append(pile[hit.index].name)
		pile.remove_at(hit.index)
	return removed


# The worst bad card of `family` ("" for any): {pile, index}, or {} if
# there is none.
func _worst_bad(family: String) -> Dictionary:
	var best := {}
	var best_rank := INF
	for pile in [discard, deck]:
		for i in range(pile.size()):
			var c: FormCard = pile[i]
			if c.good or (family != "" and c.family != family):
				continue
			if _card_rank(c) < best_rank:
				best_rank = _card_rank(c)
				best = {"pile": pile, "index": i}
	return best


# A hazard's bad card joins the family of the club that found it. With no
# name, it is one of that family's misses; with no family, the card goes
# to the first family whose misses include it.
func add_bad_card_to_deck(card_name: String = "", family: String = "") -> FormCard:
	var name: String = card_name
	if name == "":
		var pool: Array = FormCard.bad_names_for(family)
		name = pool[randi_range(0, pool.size() - 1)]
	var fam := family if family != "" else FormCard.home_family(name)
	var card := FormCard.make(name).of_family(fam)
	# Straight into the live deck (not discard) so it can surface on the very
	# next draw rather than waiting for a reshuffle.
	deck.append(card)
	deck.shuffle()
	return card
