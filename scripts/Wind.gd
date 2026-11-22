class_name Wind
extends RefCounted

# ---------------------------------------------------------
# Per-hole wind. One seed per round (rolled by whoever sets up the round
# and sent with the opening decks), and each hole's wind is a pure function
# of that seed and the hole number — so every machine in an online round
# gets the same wind on every hole without a roll per hole to sync.
#
# Wind is fully known before you play: it's drawn when the hole starts and
# held for the whole hole. Its effect on a shot lives in
# ShotResolver.apply_wind(); this file only decides what the wind is and
# how to say it.
# ---------------------------------------------------------

const MAX_MPH := 35.0
# Skews the draw toward calm: the median hole is ~10 mph, about one hole
# in six blows 25+, and a full 35 mph gale is rare.
const CALM_SKEW := 1.6
const CALM_MPH := 3.0
# The wind gets up as the round goes on (Course.late()), and it is the
# quiet holes that go: a hole's draw is lifted by up to this share of the
# terrain's ceiling, the lift fading to nothing as the draw nears the
# ceiling. By the last hole on parkland a dead calm has become a 9 mph
# breeze and the median has gone from ~11 mph to ~16 — but a gale is no
# stronger, and hardly more common, than on the first tee. So the back
# nine asks more of the low cards without handing out more disasters: a
# 30 mph hole decides a round more than it tests it, and there were
# enough of those.
# (0.26 until 2026-11-20, when the back nine was still playing three
# strokes easier than the front: Section 5, "The course pushes back".)
const LATE_LIFT := 0.45


# The two constants above are the parkland numbers. The terrain a course
# sits on (CourseTheme) can swap them: a links blows harder, a desert
# barely at all. `theme` defaults to the course being played, which every
# machine in an online round already agrees on — it travels with the
# course — so the wind stays a pure function of things everyone has.
#
# `late` is how far through the round the hole is, 0 to 1; left at -1 it
# is worked out from the course being played (Course.late()).
static func for_hole(seed: int, hole_n: int, theme: String = "", late: float = -1.0) -> Vector2:
	var t := CourseTheme.get_theme(Course.active_theme if theme == "" else theme)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, hole_n, "wind"])
	if late < 0.0:
		late = Course.late(hole_n)
	var top: float = float(t.get("wind_max", MAX_MPH))
	var mph: float = top * pow(rng.randf(), float(t.get("wind_skew", CALM_SKEW)))
	var room: float = 1.0 - mph / maxf(top, 0.001)
	mph += clampf(late, 0.0, 1.0) * LATE_LIFT * top * room * room
	var angle: float = rng.randf() * TAU
	var w := Vector2.from_angle(angle) * mph
	# Whole mph — it's what the player is shown, so it's what the shot uses.
	return w.normalized() * round(mph) if round(mph) >= 1.0 else Vector2.ZERO


static func mph(wind: Vector2) -> int:
	return int(round(wind.length()))


# "18 mph · into you, from the left" — relative to the shot in front of
# you (`dir`, ball toward target), since that's how a golfer reads wind.
static func describe(wind: Vector2, dir: Vector2) -> String:
	var speed := mph(wind)
	if speed < CALM_MPH:
		return "Calm"
	if dir.length_squared() < 0.0001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var along: float = wind.normalized().dot(dir)
	var right := Vector2(dir.y, -dir.x)
	var across: float = wind.normalized().dot(right)
	var parts: Array = []
	if along <= -0.4:
		parts.append("into you")
	elif along >= 0.4:
		parts.append("helping")
	if absf(across) >= 0.4:
		# Blowing toward the right means it comes from the left.
		parts.append("from the left" if across > 0.0 else "from the right")
	return "%d mph · %s" % [speed, ", ".join(parts)]


static func strength_word(wind: Vector2) -> String:
	var speed := mph(wind)
	if speed < CALM_MPH:
		return "Calm"
	if speed < 10:
		return "Light"
	if speed < 18:
		return "Breezy"
	if speed < 26:
		return "Strong"
	return "Gale"
