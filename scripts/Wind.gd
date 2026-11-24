class_name Wind
extends RefCounted

# ---------------------------------------------------------
# One wind a round, blowing over the whole course. Its strength and where
# it comes from are drawn once from the round's seed; what changes from
# hole to hole is which way the hole points (Course.to_hole, the routing
# the title screen draws), so the same wind is into you on one hole and
# behind you on the next, as on a real course. It sways a little from
# hole to hole (SWAY_MPH, SWAY_DEG) and freshens as the round goes on.
# Until 2026-11-24 every hole drew a wind of its own, 4 mph one hole and
# 30 the next.
#
# All of it is a pure function of the seed, the hole number and the
# course, which every machine in an online round already has, so there is
# still no roll per hole to sync.
#
# Wind is fully known before you play: it's set when the hole starts and
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
# How far a hole's wind strays from the day's: mph either way, and degrees.
const SWAY_MPH := 1.0
const SWAY_DEG := 12.0
# Gusts (2026-11-25). On a hole blowing GUST_FROM mph or more the wind
# gusts in real time: a lull of GUST_LULL seconds, then a gust that builds
# over GUST_RISE, blows for GUST_LAST seconds in all and dies over
# GUST_FALL, at up to GUST_TIMES the wind's strength. The map shows it
# coming (the dial's needle and number, streaks across the hole), and the
# wind a shot flies in is the wind at the moment its Form card is played —
# so a shot can be held for a lull, or for a gust at your back. This is
# the one place in the long game where when you act matters. (For a day
# before this, one shot in five was simply rolled a gust.)
const GUST_FROM := 8.0
const GUST_TIMES := 1.6
const GUST_LULL := Vector2(4.0, 11.0)
const GUST_LAST := Vector2(2.5, 4.5)
const GUST_RISE := 0.8
const GUST_FALL := 1.0


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
	if late < 0.0:
		late = Course.late(hole_n)
	# The day's wind: how hard, and where to over the course.
	var day := RandomNumberGenerator.new()
	day.seed = hash([seed, "wind"])
	var top: float = float(t.get("wind_max", MAX_MPH))
	var mph: float = top * pow(day.randf(), float(t.get("wind_skew", CALM_SKEW)))
	var angle: float = day.randf() * TAU
	var room: float = 1.0 - mph / maxf(top, 0.001)
	mph += clampf(late, 0.0, 1.0) * LATE_LIFT * top * room * room
	# This hole's sway on it, then the wind as this hole lies to it.
	var sway := RandomNumberGenerator.new()
	sway.seed = hash([seed, hole_n, "wind"])
	mph = clampf(mph + sway.randf_range(-SWAY_MPH, SWAY_MPH), 0.0, top)
	angle += deg_to_rad(sway.randf_range(-SWAY_DEG, SWAY_DEG))
	var w := Course.to_hole(hole_n, Vector2.from_angle(angle)) * mph
	# Whole mph — it's what the player is shown, so it's what the shot uses.
	return w.normalized() * round(mph) if round(mph) >= 1.0 else Vector2.ZERO


static func mph(wind: Vector2) -> int:
	return int(round(wind.length()))


# How hard a gust blows in this wind, in mph, or 0 where it doesn't gust.
static func gust_mph(wind: Vector2) -> int:
	return int(round(wind.length() * GUST_TIMES)) if wind.length() >= GUST_FROM else 0


# The wind with `level` of a gust in it: 0 the hole's own wind, 1 a gust
# at its height. Unchanged where it doesn't gust.
static func gusted(wind: Vector2, level: float) -> Vector2:
	return wind * (1.0 + (GUST_TIMES - 1.0) * clampf(level, 0.0, 1.0)) if gust_mph(wind) > 0 else wind


# How much of a gust is blowing `t` seconds into a cycle of `lull` seconds
# of quiet and then a gust `last` seconds long: 0 to 1.
static func gust_level(t: float, lull: float, last: float) -> float:
	var into := t - lull
	if into <= 0.0 or into >= last:
		return 0.0
	return clampf(minf(into / GUST_RISE, (last - into) / GUST_FALL), 0.0, 1.0)


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
