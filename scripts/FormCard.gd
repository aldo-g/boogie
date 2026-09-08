class_name FormCard
extends RefCounted

# ---------------------------------------------------------
# Section 4 — Form Card System
# A single, fully-known Form card: its identity (good/bad) and its
# deterministic effect on the shot it's played into. No hidden state —
# everything here is exactly what the player sees before they aim.
#
# side: -1 = pulls left (Hook/Draw-shape), +1 = pulls right (Slice/Fade-shape), 0 = straight
# degrees: known deviation magnitude, in degrees, before club buffering
# distance_mult: known distance multiplier, before terrain/tier caps
# ---------------------------------------------------------

var name: String
var good: bool
var side: int
var degrees: float
var distance_mult: float
var ignores_hazard_penalty: bool  # Flop Shot: ignores rough/bunker distance cap
var extra_roll: float             # Bump and Run: added roll distance
var downgrades_lie: bool          # Shank: worsens the resulting lie by one step
var is_yips: bool                 # Only meaningful on the green — see Section 4 cross-trigger


func _init(p_name: String, p_good: bool, p_side: int = 0, p_degrees: float = 0.0,
		p_distance_mult: float = 1.0, p_ignores_hazard_penalty: bool = false,
		p_extra_roll: float = 0.0, p_downgrades_lie: bool = false, p_is_yips: bool = false) -> void:
	name = p_name
	good = p_good
	side = p_side
	degrees = p_degrees
	distance_mult = p_distance_mult
	ignores_hazard_penalty = p_ignores_hazard_penalty
	extra_roll = p_extra_roll
	downgrades_lie = p_downgrades_lie
	is_yips = p_is_yips


func side_label() -> String:
	if side < 0:
		return "Left"
	elif side > 0:
		return "Right"
	return "Straight"


# One-line, fully-known effect text — exactly what Section 4 says the
# player should be able to read before aiming. No hidden numbers.
func effect_text() -> String:
	var bits: Array = []
	if degrees > 0.0:
		bits.append("Pulls %s %d°" % [side_label().to_lower(), int(degrees)])
	if distance_mult < 0.999:
		bits.append("%d%% distance" % int(round(distance_mult * 100.0)))
	elif distance_mult > 1.001:
		bits.append("+%d%% distance" % int(round((distance_mult - 1.0) * 100.0)))
	if ignores_hazard_penalty:
		bits.append("ignores rough/bunker penalty")
	if extra_roll > 0.0:
		bits.append("+%d yds roll" % int(extra_roll))
	if downgrades_lie:
		bits.append("downgrades your lie")
	if is_yips:
		bits.append("taints your next putt if played")
	if bits.is_empty():
		bits.append("No deviation, standard distance")
	return "; ".join(bits)


# --- Card definitions (Section 4 — first-draft list, 6 bad / 8 good) ---
static func make(card_name: String) -> FormCard:
	match card_name:
		# --- Bad ---
		"Hook":
			return FormCard.new("Hook", false, -1, 15.0, 0.9)
		"Slice":
			return FormCard.new("Slice", false, 1, 15.0, 0.9)
		"Top":
			return FormCard.new("Top", false, 0, 0.0, 0.45)
		"Chunk":
			return FormCard.new("Chunk", false, 0, 0.0, 0.3)
		"Shank":
			return FormCard.new("Shank", false, 1, 35.0, 0.6, false, 0.0, true)
		"Yips":
			return FormCard.new("Yips", false, 0, 0.0, 1.0, false, 0.0, false, true)
		# --- Good ---
		"Pure Strike":
			return FormCard.new("Pure Strike", true, 0, 0.0, 1.0)
		"Stinger":
			return FormCard.new("Stinger", true, 0, 0.0, 0.92)
		"Controlled Draw":
			return FormCard.new("Controlled Draw", true, -1, 10.0, 1.0)
		"Controlled Fade":
			return FormCard.new("Controlled Fade", true, 1, 10.0, 1.0)
		"Flop Shot":
			return FormCard.new("Flop Shot", true, 0, 0.0, 0.85, true)
		"Bump and Run":
			return FormCard.new("Bump and Run", true, 0, 0.0, 1.0, false, 15.0)
		"Steady Hands":
			return FormCard.new("Steady Hands", true)
		"In the Zone":
			return FormCard.new("In the Zone", true)
	push_error("FormCard.make(): unknown card '%s'" % card_name)
	return FormCard.new(card_name, true)


const BAD_NAMES := ["Hook", "Slice", "Top", "Chunk", "Shank", "Yips"]
const GOOD_NAMES := ["Pure Strike", "Stinger", "Controlled Draw", "Controlled Fade",
	"Flop Shot", "Bump and Run", "Steady Hands", "In the Zone"]
