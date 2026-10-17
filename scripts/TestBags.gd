extends RefCounted

# ---------------------------------------------------------
# Fixed bags for the headless harnesses. Dev tool, not shipped.
#
# A randomly drafted bag almost never holds a limited edition or a 7-set,
# so the flow harnesses would barely touch club abilities. These loadouts
# put every ability in someone's bag — one per seat — so a 2-4 player
# round exercises them end to end, online included.
#
#   const TestBags := preload("res://scripts/TestBags.gd")
#   player.hand = TestBags.loadout(seat)
# ---------------------------------------------------------

const LOADOUTS := [
	# Titanist 7 (re-draw) + the Gold Cleek with its Titanist Wood rider,
	# the Blade Putter's retry, and the Bulger with a wedge.
	["Titanist Pro Driver", "Titanist Fairway 5", "Titanist 4-Iron", "Titanist 6-Iron",
		"Titanist 8-Iron", "Titanist Tour Wedge", "Titanist Blade Putter", "Gold Cleek",
		"The Bulger", "Sand Wedge"],
	# MacGregorian 7 (improve lie), Old Tom's Niblick with a MacGregorian
	# Wood, the Persimmon Spoon, the Jigger, and the Rutter with a
	# Callowell Iron.
	["MacGregorian Persimmon Driver", "MacGregorian Brassie", "MacGregorian Spoon",
		"MacGregorian Mashie", "MacGregorian Mid-Mashie", "MacGregorian Niblick",
		"MacGregorian Jigger", "Old Tom's Niblick", "Persimmon Spoon", "The Rutter",
		"Callowell Rescue"],
	# Nimbus 7 (tier boost, ideal club, every type), the Utility Wedge,
	# and the Equaliser beside two other brands.
	["Nimbus Driver", "Nimbus Hybrid 3", "Nimbus Hybrid 5", "Nimbus Hybrid 7",
		"Nimbus All-Rounder", "Nimbus Utility Wedge", "Nimbus Putter", "The Equaliser",
		"Ping-Well Lob Wedge", "Callowell Gap Wedge"],
	# Slazinger 7 (once-per-round abilities every hole), Old Reliable's
	# Steady Hands with another Ping-Well club, and the Callowell Mallet.
	["Slazinger Cannon Driver", "Slazinger Launch Wood", "Slazinger Long Iron",
		"Slazinger Power Iron", "Slazinger Deep Iron", "Slazinger Blast Wedge",
		"Slazinger Heavy Putter", "Old Reliable Putter", "Ping-Well Mallet Putter",
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


static func wants_range(main, chance: float) -> bool:
	return main.state == main.State.DRAFT and main.form_deck.bad_count() > 0 and randf() < chance
