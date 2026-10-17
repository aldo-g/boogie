class_name ShotRules
extends RefCounted

# ---------------------------------------------------------
# THE RULES OF A STROKE
#
# Everything that decides what a stroke *does* — which swing tier it is,
# how many Form cards it earns, how the bag's brand bonuses bend the shot,
# and what the ground does with the ball once it stops — as pure
# functions of their inputs. Nothing here logs, plays a sound, touches the
# map, or rolls a die: Main.gd owns all of that, and owns the roll gating
# that keeps online play in step (see Main._roll()). That split is what
# lets RulesTest.gd check the rules headless, without a screen.
#
# ShotResolver.gd is the layer below: the shot's physics (distance,
# deviation, wind, carry, roll). This file is the layer that applies the
# game's rules — brands, lies, penalties — on top of it.
#
# `bag` everywhere is the player's Bag (an Array of club Dictionaries).
# ---------------------------------------------------------

const Tier := ShotResolver.Tier

# Inside this distance a putt is conceded rather than played (about 2 feet).
const GIMME_YARDS := 0.7

# Section 5 "Bad cards from hazards": the chance that a hazard lie leaves a
# bad Form card in the player's Form deck.
const FORM_DECAY_CHANCE := 1.0 / 3.0

# A range session (skipping an end-of-hole draft) purges this many bad
# cards from the Form deck.
const RANGE_SESSION_PURGE := 2


# --- Swing tier (Section 4 "Club suitability") -------------------------

# Which swing tier a shot represents: where the aimed distance falls in
# the club's own yardage band, after Ping-Well's wider Mid tier (the set
# bonus, or the club's own rider) and any tier upgrades. `armed` holds the
# abilities the player has switched on for this shot (ClubAbilities).
static func swing_tier(bag: Array, club: Dictionary, distance: float, armed: Dictionary = {}) -> int:
	# Nimbus 7: the ideal club for the shot is, by definition, a Mid swing.
	if armed.has("ideal_club"):
		return Tier.MID
	var lo: float = club.get("min_yard", 0.0)
	var hi: float = club.get("max_yard", 0.0)
	if lo <= 0.0 and hi <= 0.0:
		return Tier.MID
	var tier: int = Tier.MID
	var span := hi - lo
	if distance < lo:
		tier = Tier.EXTREME_FINESSE
	elif span > 0.0:
		var mid_span: float = ClubAbilities.mid_span(bag, club)
		var frac: float = (distance - lo) / span
		if frac >= 0.5 + mid_span / 2.0:
			tier = Tier.FULL
		elif frac < 0.5 - mid_span / 2.0:
			tier = Tier.FINESSE
	tier = upgrade_tier(bag, tier)
	# Nimbus 2: one shot per hole a tier better, on top of Ping-Well.
	if armed.has("boost_tier"):
		tier = _toward_mid(tier)
	return tier


# Ping-Well 4 plays every club one tier better than its distance implies;
# Ping-Well 7 abolishes Extreme Finesse outright. Both are applied here so
# every caller (draw count, UI text, outlook panel) sees the same tier.
static func upgrade_tier(bag: Array, tier: int) -> int:
	if tier == Tier.EXTREME_FINESSE and Brands.abolishes_extreme_finesse(bag):
		return Tier.FINESSE
	if Brands.tier_upgrade_steps(bag) <= 0:
		return tier
	return _toward_mid(tier)


# "One tier better" means toward MID, the most repeatable swing — never
# past it, since MID is already the best draw in the game.
static func _toward_mid(tier: int) -> int:
	match tier:
		Tier.EXTREME_FINESSE:
			return Tier.FINESSE
		Tier.FINESSE, Tier.FULL:
			return Tier.MID
	return tier


# --- Club and lie -------------------------------------------------------

# Woods can't be played from a bunker (Section 5) — except the clubs whose
# text says otherwise. The putter is playable from anywhere: its 0-35 band
# is what limits it, not where you stand.
static func club_playable(bag: Array, club: Dictionary, lie: String) -> bool:
	if lie == "bunker" and club.get("type", "") == "wood":
		return ClubAbilities.bunker_playable(bag, club)
	return true


# The share of the aimed distance the lie lets the ball fly (rough 80%,
# bunker 50%) — 1.0 when the bag's Callowell 4 or MacGregorian 4 removes
# terrain penalties, or the club's own rider when it has one (a MacGregorian
# Spoon ignores the rough; a Titanist Pro Driver suffers more in it).
static func lie_distance_cap(bag: Array, lie: String, club: Dictionary = {}) -> float:
	if Brands.ignores_terrain_penalty(bag) or Brands.plays_as_fairway(bag):
		return 1.0
	var own := ClubAbilities.lie_cap(club, lie)
	if own >= 0.0:
		return own
	return ShotResolver.TERRAIN_DISTANCE_CAP.get(lie, 1.0)


# --- The Form draw ------------------------------------------------------

# A bunker forces the Extreme Finesse treatment (Section 5) — unless
# MacGregorian 4 plays you out of it as though from the fairway.
static func lie_forces_card(bag: Array, lie: String) -> bool:
	return lie == "bunker" and not Brands.plays_as_fairway(bag)


# True when this shot gets no draw at all: one created bad card, forced.
static func is_forced(bag: Array, tier: int, lie: String) -> bool:
	return tier == Tier.EXTREME_FINESSE or lie_forces_card(bag, lie)


# How many Form cards the player will choose from — 1 for a forced card.
# Titanist 2 draws one extra and bins the worst, so it leaves this
# unchanged. `created` is how many created cards join the draw. Used to
# preview the draw before it happens.
static func form_choice_count(bag: Array, tier: int, lie: String, created: int = 0) -> int:
	if is_forced(bag, tier, lie):
		return 1 + created
	return FormDeck.TIER_DRAW_COUNT.get(tier, 3) + maxi(Brands.bonus_draw_cards(bag), 0) + created


# Draws this shot's Form hand from `deck` with the bag's brand bonuses,
# then adds `created` (card names) as created cards. A created card is
# always a real choice: a forced bad card with a created card beside it is
# no longer forced — exactly the bail-out Section 4 describes.
# Returns FormDeck.draw_for_shot()'s {cards, forced}, plus:
#   tier     — the swing tier the draw was made at
#   from_lie — true when the lie (not the tier) forced the bad card
#   had_forced_card — true when a bad card was created for the shot
static func draw_form(deck: FormDeck, bag: Array, club: Dictionary,
		distance: float, lie: String, armed: Dictionary = {}, created: Array = []) -> Dictionary:
	var tier := swing_tier(bag, club, distance, armed)
	var lie_forced := lie_forces_card(bag, lie)
	var result := deck.draw_for_shot(tier, lie_forced,
		Brands.bonus_draw_cards(bag), Brands.drops_worst_draw(bag))
	result["tier"] = tier
	result["from_lie"] = lie_forced and tier != Tier.EXTREME_FINESSE
	result["had_forced_card"] = result.forced
	for card_name in created:
		result.cards.append(FormCard.make(str(card_name)).as_created())
	if not created.is_empty():
		result.forced = false
	return result


# --- Playing the card ---------------------------------------------------

enum Yips { NONE, BLOCKED, TAINTS_PUTT }

# Section 4 "Putting cross-trigger": playing the Yips taints the next putt,
# unless Callowell 7 shrugs it off.
static func yips_effect(bag: Array, card: FormCard) -> int:
	if not card.is_yips:
		return Yips.NONE
	return Yips.BLOCKED if Brands.blocks_yips(bag) else Yips.TAINTS_PUTT


# Nimbus 7's "ideal club" buffers like a wedge.
const IDEAL_BUFFER := 0.5


# The flight of the shot with every brand and club modifier applied — see
# ShotResolver.resolve_shot() for the fields of the result.
static func resolve(bag: Array, club: Dictionary, aimed_distance: float,
		lie: String, card: FormCard, armed: Dictionary = {}) -> Dictionary:
	var distance := aimed_distance
	# Big Strike flies the club's whole carry, whatever was aimed.
	if card.to_max_band:
		distance = float(club.get("max_yard", aimed_distance)) + ClubAbilities.big_strike_bonus(club)
	# The lie's cut is applied here, so a club's own rough/bunker rider can
	# replace the terrain table's. A card that ignores the penalty (Flop,
	# Big Strike) skips it, as ShotResolver would.
	if not card.ignores_hazard_penalty:
		distance *= lie_distance_cap(bag, lie, club)

	# Buffering: the club type's share of the deviation, scaled by the
	# club's own rider, and capped at a wedge's for Nimbus 7.
	var type_buffer := ShotResolver.buffer_for_club(club)
	var club_buffer := ClubAbilities.buffer(club)
	if armed.has("ideal_club"):
		club_buffer = minf(club_buffer, IDEAL_BUFFER)
	var buffer_scale := club_buffer / type_buffer if type_buffer > 0.0 else 1.0

	var severity := Brands.severity_mult(bag)
	# Callowell 7 and the Callowell Big Deal Driver: mishits (Top, Thin,
	# Chunk, Skied) hit at half severity — they cost half as much distance.
	if card.mishit:
		if Brands.softens_mishits(bag):
			severity *= 0.5
		if ClubAbilities.softens_mishit(club, card):
			severity *= 0.5

	var result := ShotResolver.resolve_shot(club, distance, lie, card, true,
		Brands.deviation_mult(bag, lie, card) * buffer_scale, severity)
	var run := ClubAbilities.bump_run_share(club)
	if card.run_share > 0.0 and run > 0.0:
		result.run_share = run
	return result


# The direction a shot is struck along. An aim on top of the ball falls
# back to the pin, and a ball on the pin falls back to straight up the map.
static func aim_direction(from_pos: Vector2, aim: Vector2, pin: Vector2) -> Vector2:
	var dir: Vector2 = (aim - from_pos).normalized()
	if dir.length_squared() < 0.0001:
		dir = (pin - from_pos).normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector2.UP
	return dir


# --- Where the ball ends up --------------------------------------------

# A hole-out d20 that falls short rattles the cup and stays out. Left
# deliberately OUTSIDE gimme range: a rim-out conceded as a tap-in ends the
# hole the same instant a made one does, which makes the die invisible.
# A 19 lips out to ~1 yard, a 1 pulls up ~3, so the number on the die is
# visible in where the ball ends up.
static func rim_out_position(pin: Vector2, landing_pos: Vector2, roll: int) -> Vector2:
	var rim_dir: Vector2 = landing_pos - pin
	if rim_dir.length_squared() < 0.0001:
		rim_dir = Vector2(0, 1)
	var leave: float = lerpf(3.0, 1.0,
		float(roll - 1) / float(ShotResolver.HOLE_OUT_DIE - 1))
	return pin + rim_dir.normalized() * leave


# What the ground does with a ball that came to rest at `landing_pos`,
# struck from `before_pos`. Returns:
#   terrain        — what it finished on ("out", "water", "bunker", ...)
#   ball_pos, lie  — where the next shot is played from, and its lie
#   penalty        — penalty strokes (out of bounds and water: 1)
#   hazard         — true when this counts as a hazard for Form decay
#   lie_downgraded — true when the card's Shank downgraded the lie
static func settle(hole: HoleData, before_pos: Vector2, landing_pos: Vector2,
		downgrades_lie: bool, bag: Array, club: Dictionary = {}) -> Dictionary:
	var terrain := hole.terrain_at(landing_pos)
	var out := {
		"terrain": terrain, "ball_pos": landing_pos, "lie": terrain,
		"penalty": 0, "hazard": false, "lie_downgraded": false,
	}
	match terrain:
		"out":
			# Rule 18 — stroke and distance: a penalty stroke, and the ball
			# is replayed from where the shot was struck.
			out.penalty = 1
			out.ball_pos = before_pos
			out.lie = hole.terrain_at(before_pos)
			if out.lie == "out":
				# The previous spot can itself be off the course only if the
				# ball was already OB, which cannot happen — but never leave
				# the lie in a state no club can be played from.
				out.lie = "rough"
			out.hazard = true
		"water":
			out.penalty = 1
			out.ball_pos = before_pos
			out.lie = "rough" if hole.terrain_at(before_pos) != "fairway" else "fairway"
			out.hazard = true
		"bunker":
			out.hazard = true
		"rough":
			# The MacGregorian Jigger putts from the fringe collar.
			if ClubAbilities.fringe_putts(bag) and not hole.green_fringe_polygon.is_empty() \
					and Geometry2D.is_point_in_polygon(landing_pos, hole.green_fringe_polygon):
				out.lie = "green"
		"green":
			pass
		_:
			out.lie = "fairway"

	# Callowell 7 and the Callowell Gap Wedge: no downgraded lie.
	if downgrades_lie and out.lie != "green" and not Brands.blocks_lie_downgrade(bag) \
			and not ClubAbilities.blocks_lie_downgrade(club):
		out.lie = ShotResolver.lie_downgrade(out.lie)
		out.lie_downgraded = true
		out.hazard = true
	return out


# MacGregorian 2 or a MacGregorian Niblick: hazards stop feeding bad cards
# into the Form deck, so a rough patch no longer compounds for the rest of
# the round. When this is false no decay roll is made at all.
static func hazard_can_decay_form(bag: Array) -> bool:
	return not ClubAbilities.blocks_form_decay(bag)


# --- Putting (Section 6) ------------------------------------------------

static func is_gimme(putt_dist: float) -> bool:
	return putt_dist <= GIMME_YARDS


# How much wider than the green alone the putt meter's bands are: putter
# riders in the bag, and Steady Hands when it's switched on.
static func putt_band_mult(bag: Array, putt_dist: float, armed: Dictionary = {}) -> float:
	return ClubAbilities.putt_band_mult(bag, putt_dist, armed.has("old_reliable"))


# How far a putt the Yips has tainted leaves the ball, regardless of the
# strike.
static func yips_putt_leave(putt_dist: float) -> float:
	return maxf(1.0, putt_dist * 0.35)


# How far a putt that stayed out leaves the ball. `result` is the meter's
# "close" or "miss"; `accuracy` is 0..1. A miss never finishes further out
# than it started, so a putting sequence always walks toward the hole.
static func putt_leave(result: String, accuracy: float, putt_dist: float) -> float:
	if result == "close":
		# The better the timing, the closer it finishes.
		return minf(lerpf(2.2, 0.6, accuracy), maxf(putt_dist * 0.5, GIMME_YARDS))
	# A miss scales with how wild the timing was, and with how long the
	# putt was to begin with: badly struck lag putts can race well past,
	# short ones only ever dribble off line.
	var leave: float = lerpf(0.25, 0.06, accuracy) * maxf(putt_dist, 3.0)
	return clampf(leave, GIMME_YARDS, minf(putt_dist, 12.0))


# --- What the ball actually did ------------------------------------------

# A played shot taken apart: how far it carried and rolled, and how much
# of that was the wind and the ground — so a player can learn from the
# shot they just hit. The wind's share is the difference from the same
# shot in still air; the slope's is the difference between the flat carry
# and the elevated one. Returns:
#   carry, roll                — yards
#   wind_along, wind_across    — wind's effect on the carry: + longer / + right
#   elevation                  — yards the landing height added (+) or cost (-)
#   rise_ft                    — landing height above (+) or below the strike
#   degree, side               — the card's deviation (ShotResolver.Side)
static func shot_breakdown(hole: HoleData, from_pos: Vector2, aim_dir: Vector2,
		result: Dictionary, club: Dictionary, outcome: Dictionary) -> Dictionary:
	var dir := ShotResolver.shot_direction(aim_dir, result)
	var calm := ShotResolver.shot_outcome(hole, from_pos, aim_dir, result, club, false)
	var blown: Vector2 = outcome.carry_pos - calm.carry_pos
	var right := Vector2(dir.y, -dir.x)  # the golfer's right, facing `dir`
	var roll := 0.0
	var path: Array = outcome.roll_path
	for i in range(1, path.size()):
		roll += (path[i] as Vector2).distance_to(path[i - 1])
	var elevation := 0.0
	# A Bump and Run lands short by design, so its carry isn't a flat-vs-hill
	# comparison; leave the slope out of it.
	if float(result.get("run_share", 0.0)) <= 0.0:
		var flat := float(result.distance)
		elevation = ShotResolver.elevated_carry(hole, from_pos, dir, flat) - flat
	return {
		"carry": float(outcome.carry), "roll": roll,
		"wind_along": blown.dot(dir), "wind_across": blown.dot(right),
		"elevation": elevation,
		"rise_ft": (hole.height_at(outcome.carry_pos) - hole.height_at(from_pos)) * HoleData.FEET_PER_YARD,
		"degree": int(result.degree), "side": int(result.side),
	}


# The breakdown as one line: "Carried 182 · rolled 14 · wind cost 6 and
# pushed it 4 right · landing 12 ft up cost 4". Effects under a yard are
# left out — they're noise, not lessons.
static func breakdown_text(b: Dictionary) -> String:
	var bits: Array = ["Carried %d" % int(round(b.carry))]
	if b.roll >= 1.0:
		bits.append("rolled %d" % int(round(b.roll)))
	var along: float = b.wind_along
	var across: float = b.wind_across
	var wind: Array = []
	if absf(along) >= 1.0:
		wind.append(("added %d" if along > 0.0 else "cost %d") % int(round(absf(along))))
	if absf(across) >= 1.0:
		wind.append("pushed it %d %s" % [int(round(absf(across))), "right" if across > 0.0 else "left"])
	if not wind.is_empty():
		bits.append("wind " + " and ".join(PackedStringArray(wind)))
	if absf(b.elevation) >= 1.0:
		bits.append("landing %d ft %s %s %d" % [int(round(absf(b.rise_ft))),
			"up" if b.rise_ft > 0.0 else "down",
			"cost" if b.elevation < 0.0 else "added", int(round(absf(b.elevation)))])
	if int(b.degree) > 0:
		bits.append("the card bent it %d° %s" % [int(b.degree),
			"left" if int(b.side) == ShotResolver.Side.DRAW else "right"])
	return " · ".join(PackedStringArray(bits)) + " (yds)"
