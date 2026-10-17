class_name Credits
extends RefCounted

# ---------------------------------------------------------
# CREDITS — the attributions the game is obliged to show.
#
# This exists because of a licence condition, not as decoration. The Form
# card icons are game-icons.net under CC BY 3.0, which REQUIRES crediting
# the authors wherever the work is used. A table in a repo file is not a
# credit to a player, so it has to reach the screen.
#
# Everything else here is CC0 or public domain and needs no credit at
# all; those creators are named anyway, because they gave the work away
# and saying so costs nothing.
#
# Keep this in step with assets/art/CREDITS.md and
# assets/audio/CREDITS.md, which carry the per-file detail. This file is
# the player-facing summary: who made what, and under which licence.
# ---------------------------------------------------------

# A section is {heading, note, lines}. `note` carries the licence
# statement; `lines` are the individual credits.
const SECTIONS := [
	{
		"heading": "Form card icons",
		"note": "game-icons.net — CC BY 3.0",
		"lines": [
			"Lorc — return arrow, slicing arrow, earth crack, vibrating ball,",
			"    on target, wasp sting, arrow dunk, lob arrow,",
			"    bowling propulsion, hand, meditation",
			"Caro Asercion — ricochet",
			"Catsu — broken arrow",
		],
	},
	{
		"heading": "Club card illustrations",
		"note": "American Type Founders Company, 1920s — public domain",
		"lines": [
			"Golf printer's cuts, via Wikimedia Commons",
		],
	},
	{
		"heading": "Caddy",
		"note": "Iduns kokbok — public domain",
		"lines": [
			"Arctic char illustration, via Wikimedia Commons",
		],
	},
	{
		"heading": "Sound effects",
		"note": "CC0, except where noted",
		"lines": [
			"Kenney — cards, interface, impacts, jingles  (kenney.nl)",
			"rubberduck — water and splash  (OpenGameArt)",
			"Swishes Sound Pack  (OpenGameArt)",
			"Joseph SARDIN — wooden club swing  (BigSoundBank)",
			"Mixkit — golf strikes  (Mixkit Sound Effects Free License)",
		],
	},
	{
		"heading": "Music",
		"note": "CC0",
		"lines": [
			"Short Loops Background Music Pack  (OpenGameArt)",
			"Jazz Improvisation Looped  (OpenGameArt)",
			"Just You and Me  (OpenGameArt)",
			"memoraphile — Gone Fishin'  (OpenGameArt)",
			"isaiah658 — Ambient Relaxing Loop  (OpenGameArt)",
		],
	},
	{
		"heading": "Font",
		"note": "",
		"lines": [
			"Alex Brush — Robert Leuschke",
		],
	},
]

# Shown under the sections, since CC BY is the one licence here that
# actually obliges us.
const LICENCE_NOTE := "Full per-file credits are in assets/art/CREDITS.md and assets/audio/CREDITS.md."
