class_name BogeyTheme
extends RefCounted

# ---------------------------------------------------------
# Shared visual palette.
#
# The page is white stock and black ink. Colour is rationed to three jobs
# and never used for decoration:
#   green — good news: good Form, under par, the sunk band
#   claret — bad news: bad Form, over par, warnings, the flag
#   gilt  — Limited editions, and nothing else
# Everything else — labels, rules, cards, buttons — is ink at some
# strength on paper, so the hole map is the one saturated thing on screen.
# ---------------------------------------------------------

# --- Core roles -------------------------------------------------------
const PARCHMENT := Color("F7F6F2")          # page ground
const PARCHMENT_RAISED := Color("EFEDE7")   # a quiet tonal block on the page
const INK := Color("151514")                # primary text
const INK_SOFT := Color("6F6D67")           # secondary text

const FAIRWAY := Color("3D7052")            # good — mid
const FAIRWAY_DEEP := Color("1F4A36")       # good — text weight
const SAND := Color("CDBE9F")               # the "close" band; a warm neutral
const SAND_DEEP := Color("7D6B4A")          # bronze — sand lies, in words
const WATER := Color("8FA4AE")
const WATER_DEEP := Color("4F6A78")         # water hazards, in words
const FLAG := Color("A3202F")               # claret — bad news and the flag

const CARD_BG := Color("FFFFFF")            # raised card surface
const RULE := Color(0.082, 0.082, 0.078, 0.12)   # hairline dividers

# --- Tonal ramps ------------------------------------------------------
# One shared lightness scale, so step N of any ramp matches step N of the
# others in visual value.
const NEUTRAL_100 := Color("FCFBF9")
const NEUTRAL_200 := Color("F1EFEA")
const NEUTRAL_300 := Color("E3E0D9")
const NEUTRAL_400 := Color("CBC7BE")
const NEUTRAL_500 := Color("A5A198")
const NEUTRAL_600 := Color("827E76")
const NEUTRAL_700 := Color("5F5C55")
const NEUTRAL_800 := Color("3F3D38")
const NEUTRAL_900 := Color("262522")

# Claret. (Named ACCENT for the role it has always had: the warning ramp.)
const ACCENT_100 := Color("FBF2F2")
const ACCENT_200 := Color("F3DEDF")
const ACCENT_300 := Color("E4B7BB")
const ACCENT_400 := Color("CE858C")
const ACCENT_500 := Color("B8525D")
const ACCENT_600 := Color("A3202F")
const ACCENT_700 := Color("871A27")
const ACCENT_800 := Color("66141E")
const ACCENT_900 := Color("450D14")

# Green. (Named OLIVE for the same reason: the good-news ramp.)
const OLIVE_100 := Color("EFF4F0")
const OLIVE_200 := Color("DCE8DF")
const OLIVE_300 := Color("BCD2C2")
const OLIVE_400 := Color("8FB29A")
const OLIVE_500 := Color("5F8F70")
const OLIVE_600 := Color("3D7052")
const OLIVE_700 := Color("2A5740")
const OLIVE_800 := Color("1F4A36")
const OLIVE_900 := Color("143021")

# Limited-edition gilt: the frame, face and tag of a Limited club. Gold is
# reserved for these, so nothing else should borrow it.
const GOLD := Color("B08D3C")                          # frame
const GOLD_100 := Color("FCF9EE")                      # warm card face
const GOLD_200 := Color("EFE3BC")                      # tag fill
const GOLD_800 := Color("5E4612")                      # tag ink

# --- Elevation --------------------------------------------------------
const SHADOW_SM := Color(0.082, 0.082, 0.078, 0.06)
const SHADOW_MD := Color(0.082, 0.082, 0.078, 0.10)
const SHADOW_LG := Color(0.082, 0.082, 0.078, 0.18)

# Dark-mode counterparts (kept for any dark panel that wants them).
const DARK_GROUND := Color("151514")
const DARK_PANEL := Color("201F1D")
const DARK_TEXT := Color("F1EFEA")
const DARK_TEXT_SOFT := Color("A5A198")
const DARK_FAIRWAY := Color("8FB29A")
const DARK_SAND := Color("CDBE9F")
const DARK_WATER := Color("8FA4AE")
const DARK_FLAG := Color("CE858C")
