extends RefCounted

# ---------------------------------------------------------
# THE GUIDED ROUND
#
# A new player's first solo round brings the game in a piece at a time
# rather than all at once: the first hole is club, aim, card and putt, and
# the rest arrives over the next five holes, each piece said once by the
# caddy as it turns up. Nothing is cut; it is only held back.
#
#   hole 1        club, aim, Form card, putt; then straight to the pro shop
#   hole 2        what the dots on a club mean; makers and sets at the shop
#   after hole 3  the fork: a choice of stops
#   after hole 4  Staff, limited and second-hand clubs can be on the rack
#   hole 4        trouble can leave a fault on a club
#   hole 5        calling the hole
#   after hole 6  dig and trade in
#
# A guided round is not played for strokes in hand (Main.plays_for_keeps),
# so a first round can't be cut short.
#
# Main asks opens() before each held-back rule and says a line through
# teach(). Only the title's solo Play starts one (GameSetup.guided), so
# harnesses, hot-seat, rivals, the tour and online rounds are untouched.
# Loaded by preload:
#   const Lessons := preload("res://scripts/Lessons.gd")
# ---------------------------------------------------------

# The hole from which each held-back piece is in play. For the pieces that
# live between holes (fork, rare, hunt) it is the hole just finished.
const OPENS := {
	"makers": 3,   # the maker rack over the bag
	"fork": 3,     # a choice of stops; before it, straight to the pro shop
	"rare": 4,     # Staff, limited and second-hand clubs on the rack
	"curse": 4,    # trouble can leave a fault on the club that found it
	"call": 5,     # calling the hole
	"hunt": 6,     # dig and trade in
}

# Every piece is in play once this hole is done: the setting that starts
# rounds guided switches itself off there.
const LAST := 6

# What the caddy says, once each. Short enough to read in one look.
const LINES := {
	# On the hole, in his bubble.
	"start": "I'm Charlie, your caddy. Every shot is three steps: club, aim, card. Pick a club from your bag, below. Hover one to see how far it goes.",
	"aim": "Now click the map where you want it to land. The arcs are this club's range. Aim inside the hatched band and you choose from three cards, not two.",
	"form": "Form cards: how you actually strike it. Green is a good swing, claret a miss. Keep one. It decides where the ball really goes.",
	"result": "Top right is what that shot did: the card first, then wind and ground. Same three steps from here: club, aim, card.",
	"dots": "The dots under each club are the cards it can deal you: green shots, claret misses. Fewer claret dots, safer club. That is the choice every time you pick one.",
	"gust": "The wind is gusting on this hole. Watch the dial rise and fall. Your shot gets the wind of the moment you pick your card: wait for a lull, or for a gust at your back.",
	"bad_card": "Trouble costs more than a stroke. A miss just joined your deck, so those clubs carry one more claret dot. The range, later, works them out.",
	"curse": "That club picked up a fault in there. Its tile says what is wrong with it. The right boost at a fitting bay mends it.",
	"call": "New: the call, on the right. Before your tee shot, call birdie. Make it and the pro shop shows five clubs and you keep two. Miss and it shows two.",
	# Between holes, as a note on the page.
	"shop": "Every hole ends with a club. Three on the rack: keep one, and it is yours for the round. The claret band on the chart is a distance you can't hit yet. Hover a club to see what it fills.",
	"sets": "Every club has a maker, named above it. Carry two from the same maker and the set pays a bonus, and a bigger one at four. Each card says how close you are.",
	"fork": "From here you choose one stop between holes. The pro shop always has clubs. The other stop changes: a fitting bay improves a club you hold, the range takes misses out of your deck, the hut is a gamble.",
	"wear": "Use a club well and it wears in. This one has earned an upgrade: pick one. A club can wear in twice.",
	"staff": "There is a Staff club on the rack. Poor by itself, excellent once you carry four from its maker. It is a bet on the set.",
	"second_hand": "One of these is second-hand: already worn in, but with a fault. Its card says what is wrong. The right boost at a fitting bay mends it.",
	"hunt": "Two more moves under the rack. Dig sends all three back for fresh ones, at the price of a miss in your deck. Trade in gives up a club for one more offer.",
	"end": "That was your guided round. From the next one you play for strokes in hand: every stroke over par spends one, and the round ends if they run out.",
}


static func opens(feature: String, hole: int) -> bool:
	return hole >= int(OPENS.get(feature, 0))
