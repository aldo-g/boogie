class_name BoogieTheme
extends RefCounted

# ---------------------------------------------------------
# Shared visual palette, pulled from the course guide design doc.
# Parchment/scorecard tones with fairway, sand, and water accents —
# applied across Title.gd, Main.gd, and any future screens so the
# whole app reads as one piece of paper.
# ---------------------------------------------------------

const PARCHMENT := Color(0.965, 0.953, 0.918)        # F6F3EA — page ground
const PARCHMENT_RAISED := Color(0.937, 0.918, 0.863) # EFEADB — panels on parchment
const INK := Color(0.169, 0.227, 0.184)               # 2B3A2F — primary text
const INK_SOFT := Color(0.294, 0.353, 0.310)          # 4B5A4F — secondary text

const FAIRWAY := Color(0.420, 0.561, 0.353)           # 6B8F5A — primary accent
const FAIRWAY_DEEP := Color(0.306, 0.431, 0.251)      # 4E6E40 — headings/emphasis
const SAND := Color(0.788, 0.663, 0.380)              # C9A961 — hazards/highlights
const SAND_DEEP := Color(0.663, 0.525, 0.247)         # A9863F
const WATER := Color(0.561, 0.663, 0.722)             # 8FA9B8 — cool contrast
const WATER_DEEP := Color(0.424, 0.545, 0.608)        # 6C8B9B
const FLAG := Color(0.753, 0.278, 0.227)              # C0473A — scoring emphasis, warnings

const CARD_BG := Color(1.0, 0.992, 0.969)             # FFFDF7 — raised card surface
const RULE := Color(0.169, 0.227, 0.184, 0.14)        # hairline dividers on parchment

# Dark-mode counterparts (used on the existing dark-green screens/panels).
const DARK_GROUND := Color(0.106, 0.129, 0.110)       # 1B211C
const DARK_PANEL := Color(0.137, 0.169, 0.141)        # 232B24
const DARK_TEXT := Color(0.914, 0.906, 0.855)         # E9E7DA
const DARK_TEXT_SOFT := Color(0.714, 0.749, 0.682)    # B6BFAE
const DARK_FAIRWAY := Color(0.561, 0.745, 0.482)      # 8FBE7B
const DARK_SAND := Color(0.847, 0.737, 0.486)         # D8BC7C
const DARK_WATER := Color(0.655, 0.761, 0.816)        # A7C2D0
const DARK_FLAG := Color(0.878, 0.408, 0.353)         # E0685A
