class_name CourseArt
extends Control

# ---------------------------------------------------------
# The painted hole: everything on the map that stays put while a hole is
# played — the country around it, rough, fairway, sand, water, green,
# slope shading and contour lines, scenery, tee and flag.
#
# It is a child of CourseMapView drawn BEHIND it, and that split is the
# point. The map redraws on every mouse move while you aim and every frame
# of a ball's flight; none of that touches the ground. Godot keeps a
# node's draw commands until the node asks to redraw, so the painting here
# is built once per hole (or per resize) and the map's own _draw() is left
# with only the things that move.
#
# What it paints is decided by the hole's terrain (CourseTheme): the
# palette, and what grows or lies around. The shapes are the hole's own —
# nothing here invents ground the rules don't know about. Scenery is
# decoration, never an obstacle, so inside the playable rough it's kept
# sparse and well clear of fairway, sand, water and green; the thick of it
# sits beyond the out-of-bounds stakes.
#
# Screen-up is toward the pin and the light comes from the upper left,
# for the slope shading, the sand, the trees and every shadow alike.
# ---------------------------------------------------------

var view: CourseMapView

const HILLSHADE_STEP := 2.0   # yards per texel, at the finest
const HILLSHADE_TEXELS := 20000.0   # ...but never more texels than this
const SHADE_NEAR := 60.0      # yards from the line of play: full shading inside...
const SHADE_FAR := 150.0      # ...none beyond
const HILLSHADE_GAIN := 7.0   # slopes are gentle; exaggerate so 3% reads
const CONTOUR_FT := 5.0       # height between contour lines
const CONTOUR_CELL := 4.0     # yards: the grid the lines are traced on
const SHADOW_DIR := Vector2(0.62, 0.78)   # the way shadows fall, in pixels
const COLOR_SHADOW := Color(0.08, 0.10, 0.07)

const SCENERY_CELL := 13.0    # yards: one piece of scenery per cell at most
const SCENERY_REACH := 600.0  # yards beyond the hole's box that scenery is ever planted
const MIN_SCALE := 0.05       # pixels per yard: below this there's no picture to paint
const MOW_TILE := 34.0        # yards across one repeat of the fairway's cross-cut
const GREEN_TILE := 11.0      # ...and of the green's stripes
const MOTTLE_TILE := 96.0     # ...and of the rough's blotches

# Slope shading, baked once per hole (see _bake_hillshade()).
var _hillshade: ImageTexture = null
var _hillshade_bounds: Rect2 = Rect2()

# Contour lines, traced once per hole (see _trace_contours()): pairs of
# yard-space points, one pair per short segment. The second list is every
# fifth line, drawn heavier, as on a survey map.
var _contours: PackedVector2Array = PackedVector2Array()
var _contours_index: PackedVector2Array = PackedVector2Array()

var _label_spots: Array = []   # yard-space: where each yardage number starts

# Tiling alpha masks, shared by every map: a colour drawn through one
# lands only where the mask is solid, which is how a flat fill gets its
# mow pattern or its mottle without clipping polygons against each other.
static var _tex_mottle: ImageTexture
static var _tex_cross: ImageTexture
static var _tex_stripe: ImageTexture


func _init() -> void:
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	set_anchors_preset(Control.PRESET_FULL_RECT)


# The hole changed. `bake` = false skips the slope shading and contours —
# the course editor rebuilds the hole on every drag step and bakes when the
# drag ends.
func refresh(bake: bool) -> void:
	var hole: HoleData = view.hole if view else null
	_hillshade = _bake_hillshade(hole) if (hole and bake) else null
	_contours = PackedVector2Array()
	_contours_index = PackedVector2Array()
	if hole and bake:
		_trace_contours(hole)
	queue_redraw()


# --- Slope shading -----------------------------------------------------
# Slopes facing the light brighten, slopes facing away darken. Baked into
# a small texture so _draw() just stretches one image over the plate.
#
# It runs on past the out-of-bounds stakes — a hillside doesn't stop at
# them, and shading that did would draw a box round every hole — and
# fades away with distance from the line of play. The bake is as wide as
# the hole is long, coarser the bigger that is.
# Water is left out: it lies flat whatever the ground under it does.
func _bake_hillshade(hole: HoleData) -> ImageTexture:
	var b := hole.bounds
	var tall: float = b.size.y + 60.0
	var wide: float = maxf(b.size.x + 60.0, tall)
	var area := Rect2(b.get_center() - Vector2(wide, tall) * 0.5, Vector2(wide, tall))
	_hillshade_bounds = area
	var step: float = maxf(HILLSHADE_STEP, sqrt(wide * tall / HILLSHADE_TEXELS))
	var w: int = maxi(2, int(ceil(wide / step)))
	var h: int = maxi(2, int(ceil(tall / step)))

	# One height per texel; the slope comes from its neighbours.
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	for j in h:
		# Row 0 is the top of the picture, which is the far (pin) end.
		var y: float = area.end.y - (float(j) + 0.5) * step
		for i in w:
			heights[j * w + i] = hole.height_at(Vector2(area.position.x + (float(i) + 0.5) * step, y))

	var waters: Array = []
	for hazard in hole.hazards:
		if hazard.type == "water":
			waters.append([_rect_of(hazard.polygon), hazard.polygon])
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var light := Vector2(-1.0, 1.0).normalized()
	for j in h:
		var y: float = area.end.y - (float(j) + 0.5) * step
		for i in w:
			var p := Vector2(area.position.x + (float(i) + 0.5) * step, y)
			var wet := false
			for entry in waters:
				if (entry[0] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, entry[1]):
					wet = true
					break
			if wet:
				img.set_pixel(i, j, Color(1, 1, 1, 0))
				continue
			var i0: int = maxi(i - 1, 0)
			var i1: int = mini(i + 1, w - 1)
			var j0: int = maxi(j - 1, 0)
			var j1: int = mini(j + 1, h - 1)
			# Rows run down the picture, so +y in yards is the row above.
			var g := Vector2(
				(heights[j * w + i1] - heights[j * w + i0]) / (float(i1 - i0) * step),
				(heights[j0 * w + i] - heights[j1 * w + i]) / (float(j1 - j0) * step))
			# Ground facing the light has its downhill direction pointing
			# away from it, i.e. gradient along the light vector.
			var lit: float = clampf(g.dot(light) * HILLSHADE_GAIN, -1.0, 1.0)
			var fade: float = clampf(float(mini(mini(i, w - 1 - i), mini(j, h - 1 - j))) / 4.0, 0.0, 1.0)
			# The ground is only known along the hole — its height off to
			# the side is the same slope carried on for ever — so the
			# shading thins out with distance from the line of play rather
			# than striping the whole countryside.
			fade *= 1.0 - smoothstep(SHADE_NEAR, SHADE_FAR, absf(p.x - hole.centre_x_at(p.y)))
			fade *= 1.0 - smoothstep(SHADE_NEAR * 0.5, SHADE_FAR * 0.5, maxf(hole.tee_pos.y - p.y, p.y - hole.green_pos.y))
			if lit >= 0.0:
				img.set_pixel(i, j, Color(1.0, 0.98, 0.9, lit * 0.32 * fade))
			else:
				img.set_pixel(i, j, Color(0.08, 0.12, 0.06, -lit * 0.32 * fade))
	return ImageTexture.create_from_image(img)


# --- Contours ----------------------------------------------------------
# Lines of equal height every CONTOUR_FT feet, so a climb, a drop or a
# side-hill can be read off the map the way it can off a survey sheet:
# close together is steep. Traced cell by cell (marching squares) over a
# grid of the hole's heights; the segments aren't joined up, they're just
# drawn, which is all a picture needs. Flat holes get none. Nor does
# water, or anything past the stakes.
#
# They are traced from the ground the ball plays on (HoleData.height_at)
# and never bent for looks: where a line curves, the ground does (see
# "the lie of the land" in HoleData).
func _trace_contours(hole: HoleData) -> void:
	var b := hole.bounds
	var nx: int = maxi(1, int(ceil(b.size.x / CONTOUR_CELL)))
	var ny: int = maxi(1, int(ceil(b.size.y / CONTOUR_CELL)))
	var step := Vector2(b.size.x / float(nx), b.size.y / float(ny))
	var feet := PackedFloat32Array()
	feet.resize((nx + 1) * (ny + 1))
	var lo := INF
	var hi := -INF
	for j in ny + 1:
		for i in nx + 1:
			var v: float = hole.height_at(b.position + Vector2(float(i), float(j)) * step) * HoleData.FEET_PER_YARD
			feet[j * (nx + 1) + i] = v
			lo = minf(lo, v)
			hi = maxf(hi, v)
	if hi - lo < CONTOUR_FT * 0.5:
		return
	var waters: Array = []
	for hazard in hole.hazards:
		if hazard.type == "water":
			waters.append([_rect_of(hazard.polygon), hazard.polygon])
	for j in ny:
		for i in nx:
			var p00 := b.position + Vector2(float(i), float(j)) * step
			var corners := [p00, p00 + Vector2(step.x, 0), p00 + step, p00 + Vector2(0, step.y)]
			var h := [feet[j * (nx + 1) + i], feet[j * (nx + 1) + i + 1],
				feet[(j + 1) * (nx + 1) + i + 1], feet[(j + 1) * (nx + 1) + i]]
			var cell_lo: float = minf(minf(h[0], h[1]), minf(h[2], h[3]))
			var cell_hi: float = maxf(maxf(h[0], h[1]), maxf(h[2], h[3]))
			# Levels sit half a step off the round numbers, so dead-flat
			# ground at 0 ft never lies exactly on one.
			var first: int = int(ceil(cell_lo / CONTOUR_FT - 0.5))
			var last: int = int(floor(cell_hi / CONTOUR_FT - 0.5))
			for level in range(first, last + 1):
				var at: float = (float(level) + 0.5) * CONTOUR_FT
				var cuts := PackedVector2Array()
				for e in 4:
					var a: float = h[e]
					var c: float = h[(e + 1) % 4]
					if (a < at) != (c < at):
						cuts.append((corners[e] as Vector2).lerp(corners[(e + 1) % 4], (at - a) / (c - a)))
				for k in range(0, cuts.size() - 1, 2):
					var mid := (cuts[k] + cuts[k + 1]) * 0.5
					var wet := false
					for entry in waters:
						if (entry[0] as Rect2).has_point(mid) and Geometry2D.is_point_in_polygon(mid, entry[1]):
							wet = true
							break
					# Only over the ground in play: lines ruled across the trees
					# say nothing a golfer can use.
					if wet or hole.is_out_of_bounds(mid):
						continue
					var into: PackedVector2Array = _contours_index if posmod(level, 5) == 0 else _contours
					into.append(cuts[k])
					into.append(cuts[k + 1])
					if posmod(level, 5) == 0:
						_contours_index = into
					else:
						_contours = into


# --- The painting ------------------------------------------------------

func _draw() -> void:
	if view == null or view.hole == null or size.x < 4.0 or size.y < 4.0:
		return
	var hole: HoleData = view.hole
	var t: Dictionary = CourseTheme.get_theme(hole.theme)

	# The country the hole is cut through fills the whole plate; the
	# ground in play is the lighter clearing in it, the shape the hole
	# makes rather than a box round it.
	var frame := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	draw_colored_polygon(frame, t.surround)
	# No room for a picture: a layout pass that hasn't given the map its
	# height yet (the editor's first frame is 13 pixels tall), or a window
	# dragged down to nothing. The scale is then next to nothing, or less
	# than nothing, and what follows works in yards-on-the-plate — which
	# would be the whole county. Leave the plate plain until there's room.
	var s: float = view._px_scale()
	if s < MIN_SCALE:
		return
	_fill_through(frame, Color(t.surround_alt, 0.85), _mottle(), MOTTLE_TILE * 1.4 * s, Vector2(37, 91))

	var clearings: Array = []
	for poly in _play_outlines(hole):
		clearings.append(_px_poly(poly))
	# Two soft passes outside the edge first, so the rough thins out into
	# the country instead of stopping at a line.
	for ground in clearings:
		_outline(ground, Color(t.rough, 0.28), maxf(11.0 * s, 7.0))
		_outline(ground, Color(t.rough, 0.45), maxf(5.0 * s, 3.5))
	for ground in clearings:
		draw_colored_polygon(ground, t.rough)
		_fill_through(ground, Color(t.rough_alt, 0.8), _mottle(), MOTTLE_TILE * s)

	_draw_fairway(hole, t, s)

	# Same order the rules resolve in — green over hazards over fairway —
	# so where two shapes overlap, the one you'd be lying on is on top.
	for hazard in hole.hazards:
		if hazard.type == "water":
			_draw_water(hazard.polygon, t, s)
		else:
			_draw_bunker(hazard.polygon, t, s)
	_draw_green(hole, t, s)

	if _hillshade:
		var hb := _hillshade_bounds
		var top_left := _to_px(Vector2(hb.position.x, hb.end.y))
		var bottom_right := _to_px(Vector2(hb.end.x, hb.position.y))
		# Half a texel in from each edge: this node tiles its textures, and
		# a stretched image must not blend its edges into each other.
		var src := Rect2(Vector2(0.5, 0.5), Vector2(_hillshade.get_size()) - Vector2.ONE)
		draw_texture_rect_region(_hillshade, Rect2(top_left, bottom_right - top_left), src)
	# Contours over the turf but under everything standing on it.
	# A darker shade of the turf they cross, not ink: they're there to be
	# read when looked for, and not seen otherwise.
	var line_col := Color((t.rough as Color).darkened(0.4), 0.26)
	if _contours.size() >= 2:
		draw_multiline(_px_poly(_contours), line_col, 1.0, true)
	if _contours_index.size() >= 2:
		draw_multiline(_px_poly(_contours_index), Color(line_col, 0.44), 1.3, true)
	_draw_green_slope(hole)

	_draw_tee(hole, t, s)
	_draw_scenery(hole, t, s)
	_draw_stakes(hole, s)
	_draw_yardage_markers(hole, s)
	_draw_pin(hole)

	# A hairline of ink round the plate, so the painting sits in its mat.
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Color(BogeyTheme.INK, 0.22), false, 1.0)
	draw_rect(Rect2(Vector2(1.5, 1.5), size - Vector2(3, 3)), Color(BogeyTheme.INK, 0.07), false, 1.0)


func _draw_fairway(hole: HoleData, t: Dictionary, s: float) -> void:
	var fw := _px_poly(hole.fairway_polygon)
	if fw.size() < 3:
		return
	# The first cut: a collar of longer grass between fairway and rough.
	for piece in _grown(fw, maxf(2.6 * s, 1.6)):
		draw_colored_polygon(piece, t.collar)
		_outline(piece, Color(t.collar, 0.7))
	draw_colored_polygon(fw, t.fairway)
	_fill_through(fw, Color(t.fairway_alt, 0.9), _cross(), MOW_TILE * s)
	_outline(fw, (t.fairway as Color).lerp(t.collar, 0.55), 1.0)


# Water in bands, pale at the margin and darker toward the middle, the
# way a chart draws depth.
func _draw_water(poly: PackedVector2Array, t: Dictionary, s: float) -> void:
	var w := _px_poly(poly)
	if w.size() < 3:
		return
	for piece in _grown(w, maxf(1.7 * s, 1.3)):
		draw_colored_polygon(piece, t.bank)
		_outline(piece, Color(t.bank, 0.8))
	var water: Color = t.water
	draw_colored_polygon(w, water.lerp(t.water_light, 0.5))
	_outline(w, (t.bank as Color).darkened(0.2), 1.0)
	for band in [[3.2, water], [8.5, water.lerp(t.water_deep, 0.55)], [15.0, t.water_deep]]:
		for piece in _grown(w, -float(band[0]) * s):
			draw_colored_polygon(piece, band[1])

	# A few wavelets, set in from the bank.
	var r := _rect_of(poly)
	var k: float = clampf(1.5 * s, 1.2, 2.6)
	var ripple := Color(t.water_light, 0.85)
	var step := 12.0
	var row := 0
	var y: float = r.position.y + step * 0.5
	while y < r.end.y:
		var x: float = r.position.x + (step * 0.5 if row % 2 == 0 else step)
		while x < r.end.x:
			var p := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(p, poly) \
					and Geometry2D.is_point_in_polygon(p + Vector2(4.5, 0), poly) \
					and Geometry2D.is_point_in_polygon(p - Vector2(4.5, 0), poly):
				var c := _to_px(p)
				draw_polyline(PackedVector2Array([c + Vector2(-2.4, 0.2) * k, c + Vector2(-1.2, -0.6) * k,
					c + Vector2(0, 0.1) * k, c + Vector2(1.2, 0.7) * k, c + Vector2(2.4, 0.0) * k]),
					ripple, 1.0, true)
			x += step
		y += step
		row += 1


# Sand sits below the turf: a lip of grass round it, the near face in
# shadow, the floor in the light.
func _draw_bunker(poly: PackedVector2Array, t: Dictionary, s: float) -> void:
	var b := _px_poly(poly)
	if b.size() < 3:
		return
	for piece in _grown(b, maxf(1.0 * s, 1.0)):
		draw_colored_polygon(piece, t.sand_lip)
		_outline(piece, Color(t.sand_lip, 0.8))
	draw_colored_polygon(b, t.sand_shade)
	var floor_poly := _shifted(b, SHADOW_DIR * clampf(1.7 * s, 1.3, 4.5))
	for piece in Geometry2D.intersect_polygons(b, floor_poly):
		if _drawable(piece):
			draw_colored_polygon(piece, t.sand)
			_fill_through(piece, Color(t.sand_shade, 0.3), _mottle(), 30.0 * s, Vector2(11, 5))


func _draw_green(hole: HoleData, t: Dictionary, s: float) -> void:
	var g := _px_poly(hole.green_polygon)
	if g.size() < 3:
		return
	var fringe := _px_poly(hole.green_fringe_polygon)
	if fringe.size() >= 3:
		draw_colored_polygon(_shifted(fringe, SHADOW_DIR * clampf(1.6 * s, 1.0, 4.0)), Color(COLOR_SHADOW, 0.13))
		draw_colored_polygon(fringe, t.fringe)
		_outline(fringe, Color(t.fringe, 0.8))
	draw_colored_polygon(g, t.green)
	_fill_through(g, Color(t.green_alt, 0.9), _stripe(), GREEN_TILE * s)
	_outline(g, (t.green_alt as Color).darkened(0.1), 1.0)


# Fall-line chevrons on the green: point downhill, and only where it's
# steep enough to matter. Closer together when the map has closed in on a
# putt, so there are always some round the ball and the hole to read.
func _draw_green_slope(hole: HoleData) -> void:
	if hole.green_tilt == Vector2.ZERO:
		return
	var r: float = hole.green_radius
	var s: float = maxf(view._px_scale(), MIN_SCALE)
	var step: float = minf(max(6.0, r / 2.5), 70.0 / s)
	var clear: float = minf(3.0, 30.0 / s)   # kept off the hole itself
	var col := Color(BogeyTheme.FAIRWAY_DEEP, 0.55)
	var y := -r
	while y <= r:
		var x := -r
		while x <= r:
			var p: Vector2 = hole.green_pos + Vector2(x, y)
			if Rect2(Vector2.ZERO, size).has_point(_to_px(p)) and Geometry2D.is_point_in_polygon(p, hole.green_polygon) and p.distance_to(hole.pin_pos) > clear:
				var g := hole.gradient_at(p)
				if g.length() > 0.008:
					var down := -g.normalized()
					var c := _to_px(p)
					var tip := _to_px(p + down * 2.0)
					var dir_px := (tip - c).normalized()
					var side := Vector2(-dir_px.y, dir_px.x)
					var len := 3.0 + clampf(g.length() * 80.0, 0.0, 3.0)
					draw_line(c + dir_px * len, c - dir_px * len * 0.2 + side * len, col, 1.5, true)
					draw_line(c + dir_px * len, c - dir_px * len * 0.2 - side * len, col, 1.5, true)
			x += step
		y += step


# The tee box: a mown pad behind the ball, set along the line of play and
# round at the corners, and the two markers you tee between.
func _draw_tee(hole: HoleData, t: Dictionary, s: float) -> void:
	var c: Vector2 = hole.tee_pos
	var ahead := Vector2(0, 1)
	if hole.spine_centres.size() >= 2:
		ahead = ((hole.spine_centres[1] as Vector2) - (hole.spine_centres[0] as Vector2)).normalized()
	var across := Vector2(ahead.y, -ahead.x)
	var shape := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		# A squared-off oval: |cos| and |sin| to a power under one.
		var u: float = signf(cos(a)) * pow(absf(cos(a)), 0.45)
		var v: float = signf(sin(a)) * pow(absf(sin(a)), 0.45)
		shape.append(c - ahead * 2.8 + across * u * 6.5 + ahead * v * 7.5)
	var pad := _px_poly(shape)
	draw_colored_polygon(_shifted(pad, SHADOW_DIR * clampf(1.2 * s, 0.8, 3.0)), Color(COLOR_SHADOW, 0.12))
	draw_colored_polygon(pad, t.fringe)
	_fill_through(pad, Color(t.green_alt, 0.7), _stripe(), 7.0 * s)
	_outline(pad, (t.collar as Color).darkened(0.12), 1.0)
	var tee_px := _to_px(c)
	var side := (_to_px(c + across) - tee_px).normalized()
	var gap: float = clampf(3.6 * s, 3.0, 9.0)
	for k in [-1.0, 1.0]:
		draw_circle(tee_px + side * k * gap, 2.2, BogeyTheme.INK_SOFT)
		draw_circle(tee_px + side * k * gap - Vector2(0.5, 0.5), 0.9, BogeyTheme.CARD_BG)


# The edge of the ground in play, as outlines in yards. The rule is tested
# against a few points a dozen yards apart; drawn like that it would show
# its corners, so the painting runs a curve through them. (The curve
# strays from the straight edges by well under a yard.)
func _play_outlines(hole: HoleData) -> Array:
	var out: Array = []
	for poly in hole.play_polygons:
		out.append(CourseShape.smooth(poly, 4))
	if out.is_empty():
		var b := hole.bounds
		out.append(PackedVector2Array([b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]))
	return out


# Out-of-bounds stakes: white posts along the edge of the ground in play.
# None in water — a burn that runs on past the line needs no fence.
func _draw_stakes(hole: HoleData, s: float) -> void:
	var gap: float = maxf(20.0, 12.0 / s)   # yards between posts
	for poly in _play_outlines(hole):
		for p in CourseShape.resample(poly, gap):
			var wet := false
			for hazard in hole.hazards:
				if hazard.type == "water" and Geometry2D.is_point_in_polygon(p, hazard.polygon):
					wet = true
					break
			if wet:
				continue
			var px := _to_px(p)
			draw_circle(px + Vector2(0.7, 0.9), 1.3, Color(COLOR_SHADOW, 0.3))
			draw_circle(px, 1.3, Color(0.97, 0.96, 0.93, 0.9))


# The x where the ground in play begins at `y`, coming in from the left.
func _left_edge(hole: HoleData, y: float) -> float:
	var x: float = hole.bounds.position.x
	while x < hole.bounds.end.x and hole.is_out_of_bounds(Vector2(x, y)):
		x += 3.0
	return x


# 100 / 150 / 200 to the middle of the green (not to the pin, which moves
# from round to round): a disc in the fairway, as on a real course,
# and the number just inside the left edge of the ground in play.
func _draw_yardage_markers(hole: HoleData, s: float) -> void:
	var font := ThemeDB.fallback_font
	var discs := {100: Color(0.78, 0.31, 0.26), 150: Color(0.97, 0.96, 0.93), 200: Color(0.33, 0.47, 0.70)}
	var ink := Color(BogeyTheme.INK, 0.55)
	for dist_to_pin in [100, 150, 200]:
		var y: float = hole.green_pos.y - dist_to_pin
		if y <= hole.tee_pos.y + 5.0 or y >= hole.green_pos.y - 5.0:
			continue
		var p := _to_px(Vector2(_left_edge(hole, y) + 6.0, y))
		draw_line(p + Vector2(0, -5), p + Vector2(0, 5), ink, 1.5)
		draw_string(font, p + Vector2(6, 4), "%d" % dist_to_pin, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)
		var mid := Vector2(hole.centre_x_at(y), y)
		if hole.terrain_at(mid) == "fairway":
			var c := _to_px(mid)
			var r: float = clampf(1.3 * s, 1.8, 3.2)
			draw_circle(c, r + 0.8, Color(BogeyTheme.INK, 0.5))
			draw_circle(c, r, discs[dist_to_pin])


func _draw_pin(hole: HoleData) -> void:
	var pin_px := _to_px(hole.pin_pos)
	# The stick's shadow lies across the green, away from the light.
	draw_line(pin_px, pin_px + SHADOW_DIR * 11.0, Color(COLOR_SHADOW, 0.22), 2.0, true)
	draw_circle(pin_px, 2.6, BogeyTheme.INK)
	draw_line(pin_px, pin_px + Vector2(0, -19), Color(0.96, 0.95, 0.91), 2.4)
	draw_line(pin_px, pin_px + Vector2(0, -19), BogeyTheme.INK_SOFT, 1.0)
	var flag := PackedVector2Array([
		pin_px + Vector2(0.5, -19), pin_px + Vector2(11, -15.5), pin_px + Vector2(0.5, -11)])
	draw_colored_polygon(flag, CourseMapView.COLOR_PIN)
	_outline(flag, CourseMapView.COLOR_PIN.darkened(0.25), 1.0)


# --- Scenery -----------------------------------------------------------
# One candidate spot per cell of a grid laid over the plate, decided by a
# hash of the cell — so the same tree stands in the same place on every
# redraw, at every window size, and while the editor drags the hole about
# underneath it.
func _draw_scenery(hole: HoleData, t: Dictionary, s: float) -> void:
	var lo := view._px_to_yard(Vector2(0, size.y))
	var hi := view._px_to_yard(Vector2(size.x, 0))
	var i0 := int(floor(lo.x / SCENERY_CELL)) - 1
	var i1 := int(ceil(hi.x / SCENERY_CELL)) + 1
	var j0 := int(floor(lo.y / SCENERY_CELL)) - 1
	var j1 := int(ceil(hi.y / SCENERY_CELL)) + 1
	# Never further than this from the hole, however much of the country
	# the plate claims to show — so the planting is bounded by the hole,
	# not by the window (see MIN_SCALE in _draw()).
	var reach := hole.bounds.grow(SCENERY_REACH)
	i0 = maxi(i0, int(floor(reach.position.x / SCENERY_CELL)))
	i1 = mini(i1, int(ceil(reach.end.x / SCENERY_CELL)))
	j0 = maxi(j0, int(floor(reach.position.y / SCENERY_CELL)))
	j1 = mini(j1, int(ceil(reach.end.y / SCENERY_CELL)))
	var salt := hole.number * 7919
	var near := hole.bounds.grow(16.0)
	# Where the yardage numbers go, so nothing is planted on top of them.
	_label_spots = []
	for dist_to_pin in [100.0, 150.0, 200.0]:
		var y: float = hole.green_pos.y - dist_to_pin
		if y > hole.tee_pos.y + 5.0 and y < hole.green_pos.y - 5.0:
			_label_spots.append(Vector2(_left_edge(hole, y), y))
	var standing: Array = []
	# Far rows first, so what's nearer the bottom of the plate overlaps
	# what's behind it.
	for j in range(j1, j0 - 1, -1):
		for i in range(i0, i1 + 1):
			var p := Vector2(float(i) + 0.15 + 0.7 * _rand(i, j, salt),
				float(j) + 0.15 + 0.7 * _rand(i, j, salt + 1)) * SCENERY_CELL
			var inside: bool = not hole.is_out_of_bounds(p)
			# Scenery comes in stands and clearings, not an even sprinkle:
			# each block of cells is thick, thin or bare as a whole.
			var stand: float = _rand(floori(float(i) / 3.0), floori(float(j) / 3.0), salt + 9)
			var density: float = lerpf(0.15, 1.9, stand) if inside else lerpf(0.75, 1.15, stand)
			var kind := _pick(t.inside if inside else t.outside, _rand(i, j, salt + 2) / density)
			if kind == "":
				continue
			var big: bool = kind in ["broadleaf", "conifer", "mesa", "dune", "snow"]
			# Only spots near the playable ground need checking against it.
			if near.has_point(p) and not _is_clear(hole, p, 9.0 if big else 4.0):
				continue
			var scale: float = lerpf(0.7, 1.3, _rand(i, j, salt + 3)) * (1.0 if inside else 1.18)
			var item := [kind, _to_px(p), scale, hash(Vector3i(i, j, salt + 4))]
			# What lies on the ground goes down now; what stands on it waits,
			# so a tree is never under a snow patch or a dune.
			if kind in _FLAT:
				_draw_item(kind, item[1], s, scale, item[3], t)
			else:
				standing.append(item)
	for item in standing:
		_draw_item(item[0], item[1], s, item[2], item[3], t)


const _FLAT := ["heather", "dune", "snow", "tuft"]


static func _pick(list: Array, roll: float) -> String:
	var acc := 0.0
	for entry in list:
		acc += float(entry[1])
		if roll < acc:
			return str(entry[0])
	return ""


const _RING := [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7)]

# True if nothing within `clearance` yards of `p` is fairway, sand, water,
# green, collar or tee — i.e. scenery here can't be mistaken for, or drawn
# over, ground that matters.
func _is_clear(hole: HoleData, p: Vector2, clearance: float) -> bool:
	if p.distance_to(hole.tee_pos) < clearance + 12.0:
		return false
	# The yardage numbers sit just inside the left edge; leave them readable.
	for spot in _label_spots:
		if absf(p.y - spot.y) < clearance + 5.0 and p.x > spot.x - clearance and p.x < spot.x + 36.0:
			return false
	for off in _RING:
		var q: Vector2 = p + off * clearance
		var terrain := hole.terrain_at(q)
		if terrain != "rough" and terrain != "out":
			return false
		if not hole.green_fringe_polygon.is_empty() \
				and Geometry2D.is_point_in_polygon(q, hole.green_fringe_polygon):
			return false
	# terrain_at() calls everything past the stakes "out", whatever shape
	# reaches there — but water can run on beyond them, and is painted.
	for hazard in hole.hazards:
		if hazard.type == "water":
			for off in _RING:
				if Geometry2D.is_point_in_polygon(p + off * clearance, hazard.polygon):
					return false
	return true


func _draw_item(kind: String, px: Vector2, s: float, scale: float, h: int, t: Dictionary) -> void:
	match kind:
		"broadleaf":
			var r: float = clampf(3.7 * s * scale, 2.4, 13.0)
			draw_circle(px + SHADOW_DIR * r * 0.7, r * 0.95, Color(COLOR_SHADOW, 0.2))
			draw_circle(px, r, t.canopy_dark)
			draw_circle(px - Vector2(0.2, 0.22) * r, r * 0.74, t.canopy)
			draw_circle(px - Vector2(0.34, 0.38) * r, r * 0.36, t.canopy_light)
		"conifer":
			var r: float = clampf(3.3 * s * scale, 2.4, 12.0)
			var turn: float = float(h & 0xFF) / 255.0 * TAU
			draw_circle(px + SHADOW_DIR * r * 0.8, r * 0.8, Color(COLOR_SHADOW, 0.24))
			draw_colored_polygon(_star(px, r, r * 0.56, 8, turn), t.canopy_dark)
			draw_colored_polygon(_star(px - Vector2(0.1, 0.12) * r, r * 0.62, r * 0.34, 8, turn + 0.39), t.canopy)
			draw_circle(px - Vector2(0.14, 0.16) * r, maxf(r * 0.17, 0.7), t.canopy_light)
		"gorse":
			var r: float = clampf(2.2 * s * scale, 1.8, 7.0)
			draw_circle(px + SHADOW_DIR * r * 0.5, r, Color(COLOR_SHADOW, 0.16))
			for k in 3:
				var a: float = float(k) * 2.1 + float(h & 0x3F) * 0.1
				draw_circle(px + Vector2.from_angle(a) * r * 0.55, r * 0.72, t.canopy_dark if k == 0 else t.canopy)
			for k in 4:
				var a: float = float(k) * 1.7 + float((h >> 6) & 0x3F) * 0.1
				draw_circle(px + Vector2.from_angle(a) * r * 0.6, maxf(r * 0.2, 0.7), t.canopy_light)
		"tuft":
			var len: float = clampf(2.6 * s * scale, 2.6, 8.0)
			var col: Color = (t.rough_alt as Color).darkened(0.28)
			for k in [-1.0, 0.0, 1.0]:
				draw_line(px, px + Vector2(k * len * 0.45, -len * (1.0 - absf(k) * 0.2)), col, 1.0, true)
		"heather":
			var r: float = clampf(3.4 * s * scale, 2.4, 10.0)
			draw_colored_polygon(_blob(px, r, r * 0.6, h, 8), Color(0.573, 0.435, 0.541, 0.5))
		"dune":
			# A hummock: lit on the side facing the light, shaded on the lee.
			var r: float = clampf(8.0 * s * scale, 5.0, 26.0)
			var base: Color = t.surround
			draw_colored_polygon(_blob(px, r, r * 0.62, h, 10), Color(base.lightened(0.16), 0.85))
			draw_arc(px, r * 0.8, deg_to_rad(20), deg_to_rad(120), 10, Color(base.darkened(0.22), 0.7), maxf(r * 0.16, 1.0), true)
			draw_arc(px, r * 0.8, deg_to_rad(200), deg_to_rad(290), 10, Color(base.lightened(0.34), 0.8), maxf(r * 0.1, 1.0), true)
		"scrub":
			var r: float = clampf(1.5 * s * scale, 1.3, 4.5)
			draw_circle(px + SHADOW_DIR * r * 0.5, r, Color(COLOR_SHADOW, 0.14))
			draw_circle(px, r, t.canopy)
			draw_circle(px + Vector2(0.25, 0.25) * r, r * 0.5, t.canopy_dark)
		"rock":
			_draw_rock(px, clampf(2.3 * s * scale, 2.0, 8.0), h, t.rock, false)
		"mesa":
			_draw_rock(px, clampf(9.5 * s * scale, 7.0, 30.0), h, t.rock, true)
		"snow":
			var r: float = clampf(7.5 * s * scale, 5.0, 24.0)
			draw_colored_polygon(_blob(px + SHADOW_DIR * r * 0.14, r, r * 0.66, h, 9), Color(0.55, 0.64, 0.70, 0.4))
			draw_colored_polygon(_blob(px, r, r * 0.66, h, 9), Color(0.89, 0.92, 0.93, 0.8))
		"saguaro":
			# Drawn standing, the way an illustrated map draws a landmark.
			var tall: float = clampf(8.0 * s * scale, 6.5, 20.0)
			var wide: float = maxf(tall * 0.17, 1.4)
			var col: Color = t.canopy_dark
			draw_line(px, px + Vector2(tall * 0.6, tall * 0.3), Color(COLOR_SHADOW, 0.18), wide)
			draw_line(px, px + Vector2(0, -tall), col, wide)
			draw_circle(px + Vector2(0, -tall), wide * 0.5, col)
			var arm := wide * 0.8
			var la := px + Vector2(0, -tall * 0.42)
			draw_polyline(PackedVector2Array([la, la + Vector2(-tall * 0.26, 0), la + Vector2(-tall * 0.26, -tall * 0.3)]), col, arm)
			var ra := px + Vector2(0, -tall * 0.6)
			draw_polyline(PackedVector2Array([ra, ra + Vector2(tall * 0.22, 0), ra + Vector2(tall * 0.22, -tall * 0.22)]), col, arm)
			draw_line(px + Vector2(-wide * 0.2, -tall * 0.1), px + Vector2(-wide * 0.2, -tall * 0.92), t.canopy_light, maxf(wide * 0.25, 0.8))


# A boulder, or (flat-topped, with a longer shadow) a butte.
func _draw_rock(px: Vector2, r: float, h: int, col: Color, butte: bool) -> void:
	var body := _blob(px, r, r * 0.8, h, 7)
	draw_colored_polygon(_shifted(body, SHADOW_DIR * r * (0.5 if butte else 0.32)), Color(COLOR_SHADOW, 0.22))
	draw_colored_polygon(body, col.darkened(0.22))
	# The top catches the light: the same shape, smaller, set toward it.
	var k: float = 0.68 if butte else 0.6
	draw_colored_polygon(_blob(px - SHADOW_DIR * r * (1.0 - k) * 0.55, r * k, r * 0.8 * k, h, 7),
		col.lightened(0.1 if butte else 0.18))


# --- Shape helpers -----------------------------------------------------

# Yards on the hole to pixels on this node. Everything here is painted
# through it, so a painting that lays its holes out some other way
# (CoursePlan) has only this to change.
func _to_px(yard_pt: Vector2) -> Vector2:
	return view._to_px(yard_pt)


func _px_poly(yard_poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(yard_poly.size())
	for i in yard_poly.size():
		out[i] = _to_px(yard_poly[i])
	return out


static func _shifted(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = poly[i] + by
	return out


static func _rect_of(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


static func _drawable(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and absf(CourseShape.polygon_area(poly)) > 1.0


# A polygon grown (or, negative, shrunk) by `by` pixels. Shrinking can
# split a shape or leave nothing; either way only pieces worth drawing
# come back, and never the holes Clipper reports alongside them.
static func _grown(poly: PackedVector2Array, by: float) -> Array:
	var pieces: Array = Geometry2D.offset_polygon(poly, by, Geometry2D.JOIN_ROUND)
	var turn: bool = false
	var biggest := 0.0
	for piece in pieces:
		var area: float = absf(CourseShape.polygon_area(piece))
		if area > biggest:
			biggest = area
			turn = Geometry2D.is_polygon_clockwise(piece)
	var out: Array = []
	for piece in pieces:
		if _drawable(piece) and Geometry2D.is_polygon_clockwise(piece) == turn:
			out.append(piece)
	return out


# An antialiased line round a filled shape: polygons are filled with hard
# edges, and this is what takes the stair-steps off them.
func _outline(poly: PackedVector2Array, col: Color, width: float = 1.2) -> void:
	if poly.size() < 2:
		return
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, col, width, true)


# Paints `col` over a pixel-space polygon through a tiling alpha mask,
# `tile_px` pixels to a repeat. The pattern is pinned to the hole's own
# origin, so it sits still on the ground when the plate is resized.
func _fill_through(poly: PackedVector2Array, col: Color, mask: Texture2D, tile_px: float,
		nudge: Vector2 = Vector2.ZERO) -> void:
	if poly.size() < 3 or mask == null or tile_px <= 0.5:
		return
	var origin := _to_px(Vector2.ZERO) + nudge
	var uvs := PackedVector2Array()
	uvs.resize(poly.size())
	for i in poly.size():
		uvs[i] = (poly[i] - origin) / tile_px
	draw_colored_polygon(poly, col, uvs, mask)


# An uneven closed shape: an ellipse with each spoke pulled in or out.
static func _blob(c: Vector2, rx: float, ry: float, h: int, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var k: float = 0.78 + 0.34 * (float(hash(Vector2i(h, i)) & 0xFF) / 255.0)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry) * k)
	return out


static func _star(c: Vector2, outer: float, inner: float, points: int, turn: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var a: float = turn + PI * float(i) / float(points)
		out.append(c + Vector2.from_angle(a) * (outer if i % 2 == 0 else inner))
	return out


# A steady 0..1 for a grid cell.
static func _rand(i: int, j: int, k: int) -> float:
	return float(hash(Vector3i(i, j, k)) & 0xFFFFFF) / 16777215.0


# --- Masks -------------------------------------------------------------

static func _mask(w: int, h: int, alpha: PackedByteArray) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(w * h * 4)
	data.fill(255)
	for i in w * h:
		data[i * 4 + 3] = alpha[i]
	return ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data))


# Soft blotches: what makes a flat colour read as ground.
static func _mottle() -> ImageTexture:
	if _tex_mottle == null:
		var n := 128
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.03
		noise.fractal_octaves = 3
		var src: PackedByteArray = noise.get_seamless_image(n, n, false, false, 0.25).get_data()
		var alpha := PackedByteArray()
		alpha.resize(n * n)
		for i in n * n:
			alpha[i] = int(clampf((float(src[i]) / 255.0 - 0.36) / 0.36, 0.0, 1.0) * 255.0)
		_tex_mottle = _mask(n, n, alpha)
	return _tex_mottle


# The fairway's cross-cut: two sets of diagonal stripes, mown across each
# other into diamonds.
static func _cross() -> ImageTexture:
	if _tex_cross == null:
		var n := 64
		var alpha := PackedByteArray()
		alpha.resize(n * n)
		for y in n:
			for x in n:
				var a: int = posmod(x + y, 32) / 16
				var b: int = posmod(x - y, 32) / 16
				alpha[y * n + x] = 255 if a != b else 0
		_tex_cross = _mask(n, n, alpha)
	return _tex_cross


# Straight stripes, for greens and tee boxes.
static func _stripe() -> ImageTexture:
	if _tex_stripe == null:
		var n := 16
		var alpha := PackedByteArray()
		alpha.resize(n * n)
		for y in n:
			for x in n:
				alpha[y * n + x] = 255 if x < n / 2 else 0
		_tex_stripe = _mask(n, n, alpha)
	return _tex_stripe
