class_name CourseTheme
extends RefCounted

# ---------------------------------------------------------
# TERRAIN — the kind of country a course is laid out on.
#
# A course names one terrain (Course.active_theme; "theme" in a course
# file). The terrain decides two things, and only these two:
#
#   how the ground PLAYS   firmness (how far a ball runs after it lands)
#                          and the wind the course tends to get
#   how the hole LOOKS     the palette and the scenery CourseArt paints
#
# Everything else — lies, penalties, the Form deck — is the same game on
# every terrain, so a club or a brand set never needs retuning per course
# (GAME_DESIGN.md, Section 3A).
#
# Both play numbers are known before you swing: firmness is in every roll
# preview because the hole carries it (HoleData.roll_scale), and the wind
# is drawn per hole exactly as before, just from this terrain's range.
#
# To add a terrain: add an entry here and its id to ORDER. Nothing else
# needs to know — the course editor's picker, the sanitiser and the art
# all read this table.
# ---------------------------------------------------------

const DEFAULT := "parkland"
const ORDER := ["parkland", "links", "desert", "alpine"]

# Play
#   roll       run-out multiplier. 1.0 is the parkland ground every club's
#              run-out share was tuned on.
#   wind_max   strongest wind a hole can draw, mph
#   wind_skew  how hard the draw leans toward calm (higher = calmer);
#              median wind is wind_max * 0.5 ^ wind_skew
#
# Scenery: what CourseArt scatters, as [kind, chance per cell]. "inside"
# is the playable rough — kept sparse, because nothing drawn there is an
# obstacle — and "outside" is the country past the out-of-bounds line.
const THEMES := {
	"parkland": {
		"label": "Parkland",
		"blurb": "Tree-lined and sheltered. The ground plays true.",
		"roll": 1.0, "wind_max": 35.0, "wind_skew": 1.6,
		"surround": Color(0.325, 0.439, 0.290),
		"surround_alt": Color(0.275, 0.384, 0.247),
		"rough": Color(0.435, 0.557, 0.373),
		"rough_alt": Color(0.376, 0.494, 0.322),
		"collar": Color(0.522, 0.663, 0.435),
		"fairway": Color(0.596, 0.749, 0.494),
		"fairway_alt": Color(0.549, 0.706, 0.447),
		"fringe": Color(0.639, 0.780, 0.529),
		"green": Color(0.714, 0.851, 0.604),
		"green_alt": Color(0.667, 0.812, 0.557),
		"sand": Color(0.890, 0.816, 0.624),
		"sand_shade": Color(0.741, 0.647, 0.435),
		"sand_lip": Color(0.369, 0.482, 0.310),
		"water": Color(0.561, 0.675, 0.737),
		"water_deep": Color(0.443, 0.573, 0.655),
		"water_light": Color(0.741, 0.820, 0.859),
		"bank": Color(0.353, 0.451, 0.302),
		"canopy": Color(0.345, 0.471, 0.286),
		"canopy_dark": Color(0.255, 0.361, 0.212),
		"canopy_light": Color(0.447, 0.573, 0.357),
		"rock": Color(0.557, 0.553, 0.510),
		"inside": [["broadleaf", 0.20]],
		"outside": [["broadleaf", 0.82], ["conifer", 0.06]],
	},
	"links": {
		"label": "Links",
		"blurb": "Firm seaside turf and a stiff wind. The ball runs half as far again.",
		"roll": 1.5, "wind_max": 35.0, "wind_skew": 1.0,
		"surround": Color(0.616, 0.580, 0.396),
		"surround_alt": Color(0.541, 0.510, 0.345),
		"rough": Color(0.706, 0.694, 0.486),
		"rough_alt": Color(0.631, 0.635, 0.431),
		"collar": Color(0.675, 0.725, 0.498),
		"fairway": Color(0.671, 0.765, 0.529),
		"fairway_alt": Color(0.631, 0.733, 0.494),
		"fringe": Color(0.690, 0.784, 0.541),
		"green": Color(0.741, 0.847, 0.608),
		"green_alt": Color(0.698, 0.812, 0.565),
		"sand": Color(0.910, 0.855, 0.682),
		"sand_shade": Color(0.588, 0.510, 0.345),
		"sand_lip": Color(0.498, 0.522, 0.333),
		"water": Color(0.498, 0.627, 0.686),
		"water_deep": Color(0.392, 0.529, 0.612),
		"water_light": Color(0.702, 0.792, 0.820),
		"bank": Color(0.835, 0.792, 0.627),
		"canopy": Color(0.357, 0.435, 0.263),
		"canopy_dark": Color(0.275, 0.345, 0.212),
		"canopy_light": Color(0.851, 0.769, 0.310),
		"rock": Color(0.580, 0.561, 0.502),
		"inside": [["tuft", 0.34], ["heather", 0.10], ["gorse", 0.05]],
		"outside": [["dune", 0.30], ["tuft", 0.36], ["gorse", 0.16], ["heather", 0.08]],
	},
	"desert": {
		"label": "Desert",
		"blurb": "Green ribbons through hardpan. Calm air, quick ground, and sand everywhere you miss.",
		"roll": 1.3, "wind_max": 30.0, "wind_skew": 2.2,
		"surround": Color(0.800, 0.647, 0.478),
		"surround_alt": Color(0.729, 0.561, 0.404),
		"rough": Color(0.867, 0.769, 0.592),
		"rough_alt": Color(0.808, 0.698, 0.522),
		"collar": Color(0.667, 0.741, 0.486),
		"fairway": Color(0.553, 0.729, 0.459),
		"fairway_alt": Color(0.506, 0.690, 0.420),
		"fringe": Color(0.596, 0.765, 0.494),
		"green": Color(0.671, 0.831, 0.565),
		"green_alt": Color(0.624, 0.796, 0.522),
		"sand": Color(0.965, 0.933, 0.839),
		"sand_shade": Color(0.796, 0.725, 0.576),
		"sand_lip": Color(0.706, 0.588, 0.412),
		"water": Color(0.482, 0.702, 0.722),
		"water_deep": Color(0.365, 0.600, 0.651),
		"water_light": Color(0.698, 0.851, 0.847),
		"bank": Color(0.690, 0.588, 0.431),
		"canopy": Color(0.427, 0.522, 0.337),
		"canopy_dark": Color(0.318, 0.408, 0.267),
		"canopy_light": Color(0.561, 0.639, 0.427),
		"rock": Color(0.698, 0.494, 0.376),
		"inside": [["scrub", 0.30], ["rock", 0.04], ["saguaro", 0.035]],
		"outside": [["scrub", 0.34], ["rock", 0.16], ["saguaro", 0.12], ["mesa", 0.035]],
	},
	"alpine": {
		"label": "Alpine",
		"blurb": "Up and down the mountain. Soft turf that holds the ball, and gusts off the ridge.",
		"roll": 0.8, "wind_max": 35.0, "wind_skew": 1.4,
		"surround": Color(0.239, 0.353, 0.290),
		"surround_alt": Color(0.196, 0.298, 0.251),
		"rough": Color(0.373, 0.506, 0.384),
		"rough_alt": Color(0.318, 0.447, 0.341),
		"collar": Color(0.467, 0.624, 0.447),
		"fairway": Color(0.565, 0.741, 0.522),
		"fairway_alt": Color(0.518, 0.702, 0.482),
		"fringe": Color(0.608, 0.773, 0.553),
		"green": Color(0.690, 0.843, 0.624),
		"green_alt": Color(0.643, 0.808, 0.580),
		"sand": Color(0.882, 0.855, 0.757),
		"sand_shade": Color(0.686, 0.659, 0.565),
		"sand_lip": Color(0.318, 0.439, 0.337),
		"water": Color(0.431, 0.588, 0.706),
		"water_deep": Color(0.306, 0.467, 0.616),
		"water_light": Color(0.647, 0.776, 0.855),
		"bank": Color(0.459, 0.475, 0.431),
		"canopy": Color(0.263, 0.396, 0.325),
		"canopy_dark": Color(0.176, 0.286, 0.243),
		"canopy_light": Color(0.357, 0.494, 0.400),
		"rock": Color(0.616, 0.624, 0.612),
		"inside": [["conifer", 0.24], ["rock", 0.035]],
		"outside": [["conifer", 0.88], ["rock", 0.06], ["snow", 0.022]],
	},
}


# Anything unknown — an old file, a newer build's terrain, garbage off the
# wire — plays as the default rather than failing.
static func sanitise(id) -> String:
	return id if (id is String and THEMES.has(id)) else DEFAULT


static func get_theme(id: String) -> Dictionary:
	return THEMES.get(id, THEMES[DEFAULT])


static func label(id: String) -> String:
	return str(get_theme(id).label)


static func blurb(id: String) -> String:
	return str(get_theme(id).blurb)


static func roll_scale(id: String) -> float:
	return float(get_theme(id).roll)


static func color(id: String, role: String) -> Color:
	return get_theme(id).get(role, Color.MAGENTA)


# "Firm · windy" — the two things the terrain does to a shot, in the
# fewest words, for the course picker.
static func play_summary(id: String) -> String:
	var t := get_theme(id)
	var roll: float = t.roll
	var ground := "true ground"
	if roll >= 1.4:
		ground = "firm, fast ground"
	elif roll > 1.05:
		ground = "quick ground"
	elif roll < 0.95:
		ground = "soft ground"
	var median: float = float(t.wind_max) * pow(0.5, float(t.wind_skew))
	var air := "a steady breeze"
	if median >= 15.0:
		air = "a stiff wind"
	elif median >= 12.0:
		air = "gusty"
	elif median < 8.0:
		air = "still air"
	return "%s, %s" % [ground, air]
