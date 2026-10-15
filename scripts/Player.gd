class_name Player
extends RefCounted

# ---------------------------------------------------------
# One player in a round (Section 7 — Modes).
#
# Everything that used to be a bare top-level var in Main.gd and belonged
# to "the player" lives here instead, so a round can hold 1..4 of these
# and Main.gd just points at whichever one is active. Nothing in this
# class knows about UI or about the other players.
#
# What is deliberately PER-PLAYER rather than shared:
#   - the Bag (hand), and so every brand set bonus derived from it
#   - the Form deck: hazard decay must punish the player who hit the
#     hazard, not the table. A shared Form deck would make one player's
#     bad hole everyone's problem, which is not what Section 4 describes.
#   - the club deck/discard: with independent draw-3 drafts (no sniping),
#     each player draws from their own shuffled pool, so two players can
#     own the same club and neither can take a card out of the other's
#     draft.
#   - live_brands: each player's pool is shaped independently, so the
#     4-of-6 reveal is per player.
# ---------------------------------------------------------

var name: String = "Player"

# --- The Bag and its draft pool (Sections 3, 3B, 3C) ---
var hand: Array = []
var club_deck: Array = []
var club_discard: Array = []
var live_brands: Array = []

# --- Form deck (Section 4) — per player, so hazard decay is personal ---
var form_deck: FormDeck

# --- Position on the current hole ---
var ball_pos: Vector2 = Vector2.ZERO   # yard-space, (0,0) at tee, +y toward pin
var shot_path: Array = []              # ball_pos history this hole, for the trail
var strokes: int = 0
var current_lie: String = "tee"
var aim_target: Vector2 = Vector2.ZERO
var holed_out: bool = false            # finished this hole; skipped in the turn order

# --- Putting ---
var putt_dist: float = 0.0
var putt_dir: Vector2 = Vector2(0, 1)
var yips_pending: bool = false         # Section 4 putting cross-trigger

# --- Mid-turn selections (never outlive this player's own turn) ---
var pending_club: Dictionary = {}
var pending_new_card = null
var current_draft_options: Array = []
var current_form_options: Array = []   # Array[FormCard]
var current_form_forced: bool = false

# --- Scoring ---
var round_scores: Array = []  # [{"hole": int, "par": int, "strokes": int}, ...]


func _init(player_name: String = "Player") -> void:
	name = player_name


# Distance to the pin — the turn-order key ("furthest from pin plays
# first", Section 7).
func distance_to(pin_pos: Vector2) -> float:
	return ball_pos.distance_to(pin_pos)


func total_strokes() -> int:
	var total := 0
	for entry in round_scores:
		total += int(entry.strokes)
	return total


func total_par() -> int:
	var total := 0
	for entry in round_scores:
		total += int(entry.par)
	return total


# Strokes relative to par across the holes played so far.
func score_diff() -> int:
	return total_strokes() - total_par()


# Resets position/lie state for a new hole. The Bag, the Form deck and the
# club pool deliberately persist — they are the run, not the hole.
func start_hole(tee_pos: Vector2) -> void:
	ball_pos = tee_pos
	shot_path = [tee_pos]
	strokes = 0
	current_lie = "tee"
	aim_target = tee_pos
	holed_out = false
	yips_pending = false
	putt_dist = 0.0
	putt_dir = Vector2(0, 1)
	pending_club = {}
	pending_new_card = null
	current_draft_options = []
	current_form_options = []
	current_form_forced = false
