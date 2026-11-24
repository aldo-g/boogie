extends RefCounted

# ---------------------------------------------------------
# RIVALS — the computer golfers you can play a round against.
#
# A rival is GreedyBot (the same player the balance harness uses) with a
# human's two weaknesses dialled in: how badly it misjudges a line, and
# how far out its read of a putt is. It plays the real rules through
# the same entry points as a person — its own bag, its own draft, its own
# Form deck — so it can be beaten the same way a person can, and it never
# sees anything the screen doesn't show.
#
# `typical` is what each one shoots on the built-in course (par 71),
# measured with BotSim: BOTSIM_VARIANT="aim=<aim>,putt=<putt x 1000>". Re-run
# that after changing a number here, or the title screen will be lying.
# As measured late on 2026-11-16 (48 rounds each, seeds 101-148): 85.8,
# 74.5 and 66.6 — after the holes were reshaped, the course began to push
# back (rough's bad card, moving pins, wind and pins building late) and
# the Form deck stopped draining. Before all that they were 80.2, 72.9
# and 65.1. With no misjudgement at all the same bot shot about 58 then;
# that figure has not been re-measured.
# Re-measured 2026-11-17 with the deeper draft (Staff clubs, signature
# shots, calling, digging and trading in): 85.8 over 48 rounds, 74.5 and
# 66.9 over 72 each — unchanged, so `typical` stood.
# Re-measured 2026-11-20 (48 rounds each, seeds 201-248) after clubs
# began to bring their shots, wear in and be boosted, the route, and the
# Tempo and Pocket cards: 83.6, 72.7 and 64.4, so +13, +2 and -7.
# Re-measured 2026-11-22 (same 48 seeds) after the holes were bent into
# doglegs and curves: 87.9, 74.2 and 66.2, so +17, +3 and -5. A bend's
# inside corner is out of bounds, and the wilder the golfer the more it
# costs: 4.2 strokes (se 1.2), 1.6 (0.7) and 1.9 (0.7).
# ---------------------------------------------------------

const ORDER := ["easy", "medium", "hard"]

const SKILLS := {
	"easy": {
		"name": "Dory Mulligan",
		"blurb": "Weekend hacker",
		"aim": 19.0,     # yards of misjudgement per 100 yards of shot (sd)
		"putt": 0.225,   # how far out its read of a putt is (GreedyBot.putt_error)
		"typical": 17,   # strokes against par on the built-in course
	},
	"medium": {
		"name": "Coley Niblick",
		"blurb": "Club regular",
		"aim": 13.0,
		"putt": 0.185,
		"typical": 3,
	},
	"hard": {
		"name": "Ace Marlin",
		"blurb": "Scratch golfer",
		"aim": 8.0,
		"putt": 0.150,
		"typical": -5,
	},
}


static func has(skill: String) -> bool:
	return SKILLS.has(skill)


static func name_of(skill: String) -> String:
	return str(SKILLS.get(skill, {}).get("name", "Computer"))


static func blurb_of(skill: String) -> String:
	return str(SKILLS.get(skill, {}).get("blurb", ""))


# "about 9 over par", for the title screen.
static func typical_text(skill: String) -> String:
	var diff := int(SKILLS.get(skill, {}).get("typical", 0))
	if diff == 0:
		return "shoots about par"
	return "shoots about %d %s" % [absi(diff), "over" if diff > 0 else "under"]


# The bot that plays a seat at this skill.
static func make_bot(skill: String, seed_value: int) -> GreedyBot:
	var bot := GreedyBot.new(seed_value)
	var s: Dictionary = SKILLS.get(skill, SKILLS["medium"])
	# Set the same way BotSim sets them, so the measured scores above are
	# the scores this bot shoots.
	bot.aim_error = float(s.aim)
	bot.putt_error = float(s.putt)
	return bot
