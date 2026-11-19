extends RefCounted

# ---------------------------------------------------------
# Fixed bags for the headless harnesses. Dev tool, not shipped.
#
# A randomly drafted bag almost never holds a limited edition or a top set,
# so the flow harnesses would barely touch club abilities. These loadouts
# put every ability in someone's bag — one per seat — so a 2-4 player
# round exercises them end to end, online included.
#
#   const TestBags := preload("res://scripts/TestBags.gd")
#   player.hand = TestBags.loadout(seat)
# ---------------------------------------------------------

const LOADOUTS := [
	# Titanist 8 (re-draw) + the Gold Cleek with its Titanist Wood rider,
	# the Blade Putter's retry, and the Bulger with a wedge.
	["Titanist Pro Driver", "Titanist Fairway 5", "Titanist 4-Iron", "Titanist 6-Iron",
		"Titanist 8-Iron", "Titanist Tour Wedge", "Titanist Blade Putter", "Gold Cleek",
		"The Bulger", "Sand Wedge"],
	# MacGregorian 8 (improve lie), Old Tom's Niblick with a MacGregorian
	# Wood, the Persimmon Spoon, the Jigger, and the Rutter with a
	# Callowell Iron.
	["MacGregorian Persimmon Driver", "MacGregorian Brassie", "MacGregorian Spoon",
		"MacGregorian Mashie", "MacGregorian Mid-Mashie", "MacGregorian Niblick",
		"MacGregorian Jigger", "Old Tom's Niblick", "Persimmon Spoon", "The Rutter",
		"Callowell Rescue"],
	# Nimbus 8 (tier boost, ideal club, every type), the Utility Wedge,
	# and the Equaliser beside two other brands.
	["Nimbus Driver", "Nimbus Hybrid 3", "Nimbus Hybrid 5", "Nimbus Hybrid 7",
		"Nimbus All-Rounder", "Nimbus Utility Wedge", "Nimbus Putter", "The Equaliser",
		"Ping-Well Lob Wedge", "Callowell Gap Wedge"],
	# Slazinger 8 (once-per-round abilities every hole), Old Reliable's
	# Steady Hands with another Ping-Well club, and the Callowell Mallet.
	["Slazinger Cannon Driver", "Slazinger Launch Wood", "Slazinger Long Iron",
		"Slazinger Power Iron", "Slazinger Deep Iron", "Slazinger Blast Wedge",
		"Slazinger Heavy Putter", "Slazinger Short Iron", "Old Reliable Putter", "Ping-Well Mallet Putter",
		"Callowell Mallet Putter"],
]


static func loadout(seat: int) -> Array:
	var wanted: Array = LOADOUTS[seat % LOADOUTS.size()]
	var all: Array = ClubRoster.standard_clubs() + ClubRoster.limited_clubs()
	for b in Brands.DRAFTABLE:
		all.append_array(ClubRoster.branded_clubs(b))
	var bag: Array = []
	for n in wanted:
		for c in all:
			if c.name == n:
				bag.append(c.duplicate(true))
				break
	ClubRoster.sort_bag(bag)
	return bag


# One action a bot might take with an ability, or "" — the id of an
# available ability, pressed `chance` of the time.
static func pick_ability(main, chance: float) -> String:
	if randf() >= chance:
		return ""
	var list: Array = main.available_abilities()
	if list.is_empty():
		return ""
	return str(list.pick_random().id)


# The move a random player makes at the fork after a hole, and at the
# stops that are not the pro shop (Route.gd): {kind, payload}, or {} at the
# pro shop, where the caller drafts as it always did.
static func stop_move(main) -> Dictionary:
	if main.state != main.State.DRAFT:
		return {}
	var p = main.me
	match str(p.draft_stop):
		"":
			return {"kind": "stop", "payload": {"index": randi() % 2}}
		"fit":
			for boost in p.draft_boosts:
				for i in range(main.hand.size()):
					if randf() < 0.5 and ClubAbilities.can_boost(main.hand[i], boost):
						return {"kind": "boost", "payload": {"boost": boost, "index": i, "shot": 0}}
			return {"kind": "leave", "payload": {}}
		"hut":
			return {"kind": "event" if randf() < 0.6 else "leave", "payload": {}}
	return {}


const _DraftRules := preload("res://scripts/DraftRules.gd")


# One of the hunting moves a bot might make (DraftRules.gd), `chance` of
# the time: a call on the tee, or in the draft a dig, a trade-in, or
# stopping a draft that keeps two. {kind, payload}, or {} for none.
static func pick_hunt(main, chance: float) -> Dictionary:
	if randf() >= chance:
		return {}
	if main.can_call_hole():
		return {"kind": "call", "payload": {}}
	if main.state != main.State.DRAFT:
		return {}
	var p = main.me
	# A worn-in club's choice can be made anywhere in the draft; the rest
	# are the pro shop's.
	var worn: int = main.wear_due()
	if worn >= 0 and randf() < 0.5:
		return {"kind": "wear", "payload": {"index": worn, "choice": randi() % ClubAbilities.wear_choices(main.hand[worn]).size()}}
	if p.draft_stop != "shop":
		return {}
	var shown: int = main.current_draft_options.size()
	var moves: Array = []
	if _DraftRules.can_dig(main.hand, p.draft_taken, p.draft_digs, shown):
		moves.append({"kind": "dig", "payload": {}})
	# Not from a small bag: the harnesses expect a bag to stay playable.
	if main.hand.size() > 3 and _DraftRules.can_trade(main.hand, p.draft_taken, p.draft_traded, shown):
		moves.append({"kind": "trade", "payload": {"index": randi() % main.hand.size()}})
	if p.draft_taken > 0:
		moves.append({"kind": "done", "payload": {}})
	if moves.is_empty():
		return {}
	return moves.pick_random()
