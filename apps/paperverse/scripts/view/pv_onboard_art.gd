class_name PVOnboardArt
extends Control
## Animated vector illustrations for the PaperVerse walkthrough.
## Kinds: "welcome" (emblem), "draw" (draw mountain/valley creases), "fold" (live fold), "animate" (timeline),
## "export" (file formats).

const EMBLEM: Texture2D = preload("res://assets/splash/emblem.png")

var kind: String = "welcome"
var _t: float = 0.0

var paper: Color = Color("fbf8f1")
var back: Color = Color("6b7ff0")
var ink: Color = Color("23233a")
var accent: Color = Color("4a5fd6")
var mountain: Color = Color("e8463a")
var valley: Color = Color("2f6be0")
var halo: Color = Color("dfe5ff")


func setup(k: String) -> PVOnboardArt:
	kind = k
	return self


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	var m: float = minf(s.x, s.y)
	draw_circle(s * 0.5, m * 0.46, halo)
	match kind:
		"welcome": _draw_welcome(s, m)
		"draw": _draw_draw(s, m)
		"fold": _draw_fold(s, m)
		"animate": _draw_animate(s, m)
		"export": _draw_export(s, m)


func _draw_welcome(s: Vector2, m: float) -> void:
	var side: float = m * 0.86
	var bob: float = sin(_t * 2.0) * side * 0.015
	draw_texture_rect(EMBLEM, Rect2(Vector2((s.x - side) * 0.5, (s.y - side) * 0.5 + bob), Vector2(side, side)), false)


func _line(a: Vector2, b: Vector2, col: Color, w: float, dash: float, dot: bool) -> void:
	var d: Vector2 = b - a
	var l: float = d.length()
	if l < 1.0:
		return
	var dir: Vector2 = d / l
	var x: float = 0.0
	while x < l:
		var seg: float = minf(dash, l - x)
		draw_line(a + dir * x, a + dir * (x + seg), col, w, true)
		x += dash * 1.6
		if dot and x < l:
			draw_circle(a + dir * minf(x, l), w * 0.6, col)
			x += dash * 0.6


## The sheet with creases appearing one by one as a finger draws them.
func _draw_draw(s: Vector2, m: float) -> void:
	var side: float = m * 0.62
	var o: Vector2 = (s - Vector2(side, side)) * 0.5
	draw_rect(Rect2(o + Vector2(8, 10), Vector2(side, side)), Color(ink, 0.08))
	draw_rect(Rect2(o, Vector2(side, side)), paper)
	for i in range(1, 8):
		var g: float = side * i / 8.0
		draw_line(o + Vector2(g, 0), o + Vector2(g, side), Color(ink, 0.06), 1.5)
		draw_line(o + Vector2(0, g), o + Vector2(side, g), Color(ink, 0.06), 1.5)
	draw_rect(Rect2(o, Vector2(side, side)), ink, false, 3.0)
	var lines: Array = [
		[Vector2(0, 0), Vector2(1, 1), false], [Vector2(1, 0), Vector2(0, 1), false],
		[Vector2(0.5, 0), Vector2(0.5, 1), true], [Vector2(0, 0.5), Vector2(1, 0.5), true]]
	var cycle: float = fmod(_t, 5.0)
	var w: float = maxf(3.0, m * 0.012)
	for i in lines.size():
		var k: float = clampf((cycle - i * 1.0) / 0.8, 0.0, 1.0)
		if k <= 0.0:
			continue
		var a: Vector2 = o + (lines[i][0] as Vector2) * side
		var b: Vector2 = o + (lines[i][1] as Vector2) * side
		var tip: Vector2 = a.lerp(b, k)
		var is_m: bool = lines[i][2]
		_line(a, tip, mountain if is_m else valley, w, m * 0.035, is_m)
		draw_circle(a, w * 1.4, ink)
		if k < 1.0:
			draw_circle(tip, m * 0.05, Color(1, 1, 1, 0.5))
			draw_circle(tip, m * 0.03, ink)
			draw_circle(tip, m * 0.015, Color.WHITE)
	# Legend: two "sample line + label" pairs, measured so they never overlap and centered under the sheet.
	var ly: float = o.y + side + m * 0.07
	var font: Font = get_theme_default_font()
	var fs: int = int(m * 0.05)
	var sample: float = m * 0.1
	var gap: float = m * 0.025
	var mw: float = font.get_string_size("Mountain", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var vw: float = font.get_string_size("Valley", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var total: float = sample + gap + mw + m * 0.08 + sample + gap + vw
	var x: float = s.x * 0.5 - total * 0.5
	var ty: float = ly + fs * 0.35
	_line(Vector2(x, ly), Vector2(x + sample, ly), mountain, w, m * 0.03, true)
	draw_string(font, Vector2(x + sample + gap, ty), "Mountain", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	x += sample + gap + mw + m * 0.08
	_line(Vector2(x, ly), Vector2(x + sample, ly), valley, w, m * 0.03, false)
	draw_string(font, Vector2(x + sample + gap, ty), "Valley", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## A square folding in half along its diagonal, in a simple oblique 3D view.
func _draw_fold(s: Vector2, m: float) -> void:
	var c: Vector2 = s * 0.5 + Vector2(0, m * 0.04)
	# The sheet's side corners sit (2 * 0.87) r from the center; keep them inside the halo circle.
	var r: float = m * 0.24
	var k: float = 0.5 - 0.5 * cos(fmod(_t, 4.0) / 4.0 * TAU)
	var ang: float = k * PI * 0.92
	# Sheet corners in 3D (x right, y depth, z up); diagonal from (-1, -1) to (1, 1).
	var proj: Callable = func(p: Vector3) -> Vector2:
		return c + Vector2((p.x - p.y) * 0.87, (p.x + p.y) * 0.45 - p.z) * r
	var a: Vector3 = Vector3(-1, -1, 0)
	var b: Vector3 = Vector3(1, 1, 0)
	var fixed: Vector3 = Vector3(1, -1, 0)
	var moving: Vector3 = Vector3(-1, 1, 0)
	var axis: Vector3 = (b - a).normalized()
	var rotated: Vector3 = moving.rotated(axis, -ang)
	var shadow: PackedVector2Array = PackedVector2Array([proj.call(a), proj.call(fixed), proj.call(b), proj.call(Vector3(rotated.x, rotated.y, 0))])
	draw_colored_polygon(shadow, Color(ink, 0.06))
	draw_colored_polygon(PackedVector2Array([proj.call(a), proj.call(fixed), proj.call(b)]), paper.darkened(0.04))
	var flap: PackedVector2Array = PackedVector2Array([proj.call(a), proj.call(b), proj.call(rotated)])
	var showing_back: bool = ang > PI * 0.5
	draw_colored_polygon(flap, back if showing_back else paper)
	draw_polyline(PackedVector2Array([flap[0], flap[1], flap[2], flap[0]]), Color(ink, 0.35), 2.5, true)
	_line(proj.call(a), proj.call(b), valley, maxf(3.0, m * 0.01), m * 0.03, false)
	draw_string(get_theme_default_font(), Vector2(s.x * 0.5 - m * 0.12, s.y - m * 0.08), "%d%%" % roundi(k * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(m * 0.09), accent)


func _draw_animate(s: Vector2, m: float) -> void:
	var w: float = m * 0.8
	var x0: float = (s.x - w) * 0.5
	var y: float = s.y * 0.66
	var cycle: float = fmod(_t, 4.0) / 4.0
	draw_rect(Rect2(Vector2(x0, y - m * 0.06), Vector2(w, m * 0.12)), paper)
	draw_rect(Rect2(Vector2(x0, y - m * 0.06), Vector2(w, m * 0.12)), Color(ink, 0.2), false, 2.0)
	for kx in [0.0, 0.45, 1.0]:
		var p: Vector2 = Vector2(x0 + w * kx, y)
		var d: float = m * 0.035
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), accent)
	var px: float = x0 + w * cycle
	draw_line(Vector2(px, y - m * 0.11), Vector2(px, y + m * 0.11), mountain, maxf(3.0, m * 0.01))
	draw_circle(Vector2(px, y - m * 0.11), m * 0.02, mountain)
	# Sheet above follows the playhead: fold rises until the middle key, then spins.
	var fold: float = clampf(cycle / 0.45, 0.0, 1.0)
	var spin: float = clampf((cycle - 0.45) / 0.55, 0.0, 1.0) * PI * 0.5
	var c: Vector2 = Vector2(s.x * 0.5, s.y * 0.36)
	var r: float = m * 0.18
	var pts: Array[Vector2] = []
	for i in 4:
		var a: float = spin + PI * 0.25 + i * PI * 0.5
		pts.append(c + Vector2(cos(a), sin(a) * 0.55) * r * 1.3)
	draw_colored_polygon(PackedVector2Array([pts[0], pts[1], pts[2]]), paper.darkened(0.04))
	var lift: Vector2 = Vector2(0, -r * 1.2 * sin(fold * PI * 0.5))
	var mid: Vector2 = (pts[0] + pts[2]) * 0.5
	var tip: Vector2 = pts[3].lerp(mid, fold * 0.5) + lift
	draw_colored_polygon(PackedVector2Array([pts[0], pts[2], tip]), back if fold > 0.5 else paper)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], tip, pts[0]]), Color(ink, 0.3), 2.0, true)


func _draw_export(s: Vector2, m: float) -> void:
	var names: PackedStringArray = ["FOLD", "GLB", "OBJ", "PNG"]
	var cols: Array[Color] = [accent, Color("3fb59a"), Color("f2a33a"), mountain]
	var cw: float = m * 0.34
	var ch: float = m * 0.42
	var cycle: float = fmod(_t, 4.0)
	for i in 4:
		var k: float = clampf((cycle - i * 0.35) / 0.5, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		var col: int = i % 2
		var row: int = i / 2
		var target: Vector2 = s * 0.5 + Vector2((col - 0.5) * cw * 1.25 - cw * 0.5, (row - 0.5) * ch * 1.15 - ch * 0.5)
		var p: Vector2 = target + Vector2(0, (1.0 - k) * m * 0.2)
		var a: float = k
		var fold: float = cw * 0.22
		draw_colored_polygon(PackedVector2Array([p, p + Vector2(cw - fold, 0), p + Vector2(cw, fold), p + Vector2(cw, ch), p + Vector2(0, ch)]), Color(paper, a))
		draw_colored_polygon(PackedVector2Array([p + Vector2(cw - fold, 0), p + Vector2(cw, fold), p + Vector2(cw - fold, fold)]), Color(paper.darkened(0.12), a))
		draw_rect(Rect2(p + Vector2(cw * 0.12, ch * 0.58), Vector2(cw * 0.76, ch * 0.24)), Color(cols[i], a))
		draw_string(get_theme_default_font(), p + Vector2(cw * 0.16, ch * 0.76), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(m * 0.06), Color(1, 1, 1, a))
		for l in 3:
			draw_line(p + Vector2(cw * 0.14, ch * (0.18 + l * 0.11)), p + Vector2(cw * (0.7 - l * 0.12), ch * (0.18 + l * 0.11)), Color(ink, 0.2 * a), 3.0)
