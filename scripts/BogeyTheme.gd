class_name BogeyTheme
extends RefCounted

# ---------------------------------------------------------
# Shared visual palette, pulled from the course guide design doc.
# Parchment/scorecard tones with fairway, sand, and water accents —
# applied across Title.gd, Main.gd, and any future screens so the
# whole app reads as one piece of paper.
# ---------------------------------------------------------

# --- Core roles -------------------------------------------------------
const PARCHMENT := Color(0.961, 0.918, 0.847)         # F5EAD8 — page ground
const PARCHMENT_RAISED := Color(0.922, 0.867, 0.773)  # EBDDC5 — panels on parchment
const INK := Color(0.125, 0.118, 0.114)               # 201E1D — primary text
const INK_SOFT := Color(0.392, 0.365, 0.325)          # 645C50 — secondary text

const FAIRWAY := Color(0.478, 0.541, 0.369)           # 7A8A5E — secondary accent
const FAIRWAY_DEEP := Color(0.337, 0.388, 0.247)      # 56633F — deep olive
const SAND := Color(0.776, 0.443, 0.224)              # C67139 — primary accent
const SAND_DEEP := Color(0.549, 0.286, 0.102)         # 8C491A — accent, deep
const WATER := Color(0.561, 0.663, 0.722)             # 8FA9B8 — cool contrast
const WATER_DEEP := Color(0.424, 0.545, 0.608)        # 6C8B9B
const FLAG := Color(0.776, 0.443, 0.224)              # C67139 — scoring emphasis

const CARD_BG := Color(0.976, 0.957, 0.929)           # F9F4ED — raised card surface
const RULE := Color(0.125, 0.118, 0.114, 0.16)        # hairline dividers

# --- Tonal ramps ------------------------------------------------------
# Generated on one shared lightness scale, so step N of any ramp matches
# step N of the others in visual value. Used for card states, tags, and
# anything that needs a lighter/darker sibling of a role colour.
const NEUTRAL_100 := Color(0.976, 0.957, 0.929)       # F9F4ED
const NEUTRAL_200 := Color(0.933, 0.906, 0.859)       # EEE7DB
const NEUTRAL_300 := Color(0.863, 0.827, 0.769)       # DCD3C4
const NEUTRAL_400 := Color(0.753, 0.714, 0.647)       # C0B6A5
const NEUTRAL_500 := Color(0.631, 0.592, 0.525)       # A19786
const NEUTRAL_600 := Color(0.510, 0.475, 0.416)       # 82796A
const NEUTRAL_700 := Color(0.392, 0.361, 0.314)       # 645C50
const NEUTRAL_800 := Color(0.278, 0.259, 0.220)       # 474238
const NEUTRAL_900 := Color(0.180, 0.169, 0.145)       # 2E2B25

const ACCENT_100 := Color(1.000, 0.949, 0.922)        # FFF2EB
const ACCENT_200 := Color(1.000, 0.882, 0.816)        # FFE1D0
const ACCENT_300 := Color(1.000, 0.776, 0.647)        # FFC6A5
const ACCENT_400 := Color(0.965, 0.627, 0.420)        # F6A06B
const ACCENT_500 := Color(0.839, 0.498, 0.282)        # D67F48
const ACCENT_600 := Color(0.698, 0.384, 0.176)        # B2622D
const ACCENT_700 := Color(0.549, 0.286, 0.102)        # 8C491A
const ACCENT_800 := Color(0.392, 0.200, 0.071)        # 643312
const ACCENT_900 := Color(0.251, 0.137, 0.063)        # 402310

const OLIVE_100 := Color(0.941, 0.980, 0.882)         # F0FAE1
const OLIVE_200 := Color(0.882, 0.933, 0.800)         # E1EECC
const OLIVE_300 := Color(0.800, 0.859, 0.698)         # CCDBB2
const OLIVE_400 := Color(0.682, 0.749, 0.573)         # AEBF92
const OLIVE_500 := Color(0.561, 0.627, 0.451)         # 8FA073
const OLIVE_600 := Color(0.447, 0.506, 0.341)         # 728157
const OLIVE_700 := Color(0.337, 0.388, 0.247)         # 56633F
const OLIVE_800 := Color(0.239, 0.278, 0.169)         # 3D472B
const OLIVE_900 := Color(0.153, 0.180, 0.106)         # 272E1B

# --- Elevation --------------------------------------------------------
const SHADOW_SM := Color(0.180, 0.169, 0.145, 0.14)
const SHADOW_MD := Color(0.180, 0.169, 0.145, 0.16)
const SHADOW_LG := Color(0.180, 0.169, 0.145, 0.22)

# Dark-mode counterparts (used on the existing dark-green screens/panels).
const DARK_GROUND := Color(0.106, 0.129, 0.110)       # 1B211C
const DARK_PANEL := Color(0.137, 0.169, 0.141)        # 232B24
const DARK_TEXT := Color(0.914, 0.906, 0.855)         # E9E7DA
const DARK_TEXT_SOFT := Color(0.714, 0.749, 0.682)    # B6BFAE
const DARK_FAIRWAY := Color(0.561, 0.745, 0.482)      # 8FBE7B
const DARK_SAND := Color(0.847, 0.737, 0.486)         # D8BC7C
const DARK_WATER := Color(0.655, 0.761, 0.816)        # A7C2D0
const DARK_FLAG := Color(0.878, 0.408, 0.353)         # E0685A
