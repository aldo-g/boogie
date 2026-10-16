class_name GameSetup
extends RefCounted

# ---------------------------------------------------------
# Round setup carried from the title/lobby screens into the game scene.
#
# Class-level static vars rather than an autoload: these are plain values
# that need no node in the tree, and they survive change_scene_to_file()
# where an instance would not. (The multiplayer connection itself DOES
# need a node, because it holds signals — that's the Net autoload.)
#
# Defaults describe a solo round, so running scenes/Main.tscn directly —
# which the prototype does constantly — still works with nothing set.
# ---------------------------------------------------------

static var player_count: int = 1

# --- Online rounds -----------------------------------------------------
# False for solo and hot-seat, where every seat is played from this
# machine and any input is legitimate.
static var online: bool = false

# Which seat this machine controls in an online round. Ignored when
# `online` is false (hot-seat deliberately lets one screen play them all).
static var my_seat: int = 0

# Display names by seat index, as agreed in the lobby. Empty means "fall
# back to the default naming" (see Main.default_player_name).
static var seat_names: Dictionary = {}

# The host's authoritative starting state for an online round: every
# player's bag, draft pool, live brands and Form deck, already shuffled.
# Clients rebuild from this instead of rolling their own, so no two
# machines start from different decks. Empty for local rounds.
static var round_payload: Dictionary = {}

# Set when the course editor launches a test round, so the round's Menu
# button goes back to the editor instead of the title.
static var return_to_editor: bool = false


# Back to a plain solo round. Called when entering a local game so a
# previous online session can't leak settings into it.
static func reset_to_local(count: int) -> void:
	player_count = count
	online = false
	my_seat = 0
	seat_names = {}
	round_payload = {}
