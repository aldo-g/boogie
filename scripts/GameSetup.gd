class_name GameSetup
extends RefCounted

# ---------------------------------------------------------
# Round setup carried from the title screen into the game scene.
#
# A class-level static var rather than an autoload: it's one value, it
# needs no node in the tree, and changing scenes would otherwise lose it.
# Defaults to 1 so running scenes/Main.tscn directly (which the prototype
# does constantly) still gives a solo round.
# ---------------------------------------------------------

static var player_count: int = 1
