class_name FSOnboardArt
extends Control
## Animated vector illustrations for the FoldShift walkthrough (no image assets besides the emblem).
## Kinds: "kami" (meet the hero), "fold" (drag a flap into a bridge), "walk" (tap to walk), "goal" (stars, cranes).

const EMBLEM: Texture2D = preload("res://assets/splash/emblem.png")

var kind: String = "kami"
var _t: float = 0.0

var paper: Color = Color("fbf3e6")
var paper_side: Color = Color("d9c39c")
var flap: Color = Color("e8604c")
var ink: Color = Color("2b2640")
var sea: Color = Color("9fd6e2")
var gold: Color = Color("f2b440")


func setup(k: String) -> FSOnboardArt:
	kind = k
	return self


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


## Isometric projection around the control center; `u` = one tile in pixels.
func _iso(x: float, y: float, z: float, u: float, origin: Vector2) -> Vector2:
	return origin + Vector2((x - y) * u * 0.87, (x + y) * u * 0.5 - z * u)


func _tile(x: float, y: float, u: float, o: Vector2, top: Color, depth: float = 0.28) -> void:
	var a: Vector2 = _iso(x, y, 0, u, o)
	var b: Vector2 = _iso(x + 1, y, 0, u, o)
	var c: Vector2 = _iso(x + 1, y + 1, 0, u, o)
	var d: Vector2 = _iso(x, y + 1, 0, u, o)
	var dz: Vector2 = Vector2(0, depth * u)
	draw_colored_polygon(PackedVector2Array([d, c, c + dz, d + dz]), paper_side.darkened(0.1))
	draw_colored_polygon(PackedVector2Array([b, c, c + dz, b + dz]), paper_side)
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), top)
	draw_polyline(PackedVector2Array([a, b, c, d, a]), Color(ink, 0.12), 2.0, true)


func _finger(p: Vector2, u: float, pressed: bool) -> void:
	var r: float = u * (0.22 if pressed else 0.27)
	draw_circle(p, r * 1.7, Color(1, 1, 1, 0.35))
	draw_circle(p, r, Color(ink, 0.85))
	draw_circle(p, r * 0.55, Color(1, 1, 1, 0.9))


func _draw() -> void:
	var s: Vector2 = size
	var u: float = minf(s.x, s.y) * 0.16
	draw_circle(Vector2(s.x * 0.5, s.y * 0.5), minf(s.x, s.y) * 0.46, Color(sea, 0.35))
	match kind:
		"kami": _draw_kami(s)
		"fold":
			var f: Array = _fit(s, 5.0, 3.0, 1.0)
			_draw_fold(f[0], f[1])
		"walk":
			var f2: Array = _fit(s, 5.0, 4.0, 0.6)
			_draw_walk(f2[0], f2[1])
		"goal": _draw_goal(s, u)


## Tile size and origin that fit a `cols` x `rows` isometric grid (plus `lift` tiles of height above it)
## inside the control, centered. The diamond spans (cols + rows) * 0.87 tiles across.
func _fit(s: Vector2, cols: float, rows: float, lift: float) -> Array:
	var m: float = minf(s.x, s.y)
	var u: float = minf(m * 0.16, s.x * 0.9 / ((cols + rows) * 0.87))
	var height: float = ((cols + rows) * 0.5 + lift + 0.28) * u
	var o: Vector2 = Vector2(s.x * 0.5 - (cols - rows) * 0.5 * 0.87 * u, s.y * 0.5 - height * 0.5 + lift * u)
	return [u, o]


func _draw_kami(s: Vector2) -> void:
	var side: float = minf(s.x, s.y) * 0.86
	var bob: float = sin(_t * 2.0) * side * 0.015
	var r: Rect2 = Rect2(Vector2((s.x - side) * 0.5, (s.y - side) * 0.5 + bob), Vector2(side, side))
	draw_texture_rect(EMBLEM, r, false)


## Two islands with a gap; the coral strip swings over on its hinge and becomes a bridge.
func _draw_fold(u: float, o: Vector2) -> void:
	var cycle: float = fmod(_t, 3.2)
	var k: float = clampf((cycle - 0.5) / 1.4, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var angle: float = PI * (1.0 - k)
	for y in 3:
		for x in 2:
			_tile(x, y, u, o, paper)
		for x in range(3, 5):
			_tile(x, y, u, o, paper)
	# Strip hinged at x = 2, rotating about the y axis line; at angle PI it lies folded back over x in [1, 2].
	var hinge: float = 2.0
	var far_x: float = hinge + cos(PI - angle)
	var far_z: float = sin(PI - angle)
	var p0: Vector2 = _iso(hinge, 0, 0.02, u, o)
	var p1: Vector2 = _iso(hinge, 3, 0.02, u, o)
	var p2: Vector2 = _iso(far_x, 3, far_z + 0.02, u, o)
	var p3: Vector2 = _iso(far_x, 0, far_z + 0.02, u, o)
	var facing_up: bool = angle < PI * 0.5
	var col: Color = paper.darkened(0.03) if facing_up else flap
	draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), col)
	draw_polyline(PackedVector2Array([p0, p1, p2, p3, p0]), Color(ink, 0.25), 2.0, true)
	draw_line(p0, p1, Color(ink, 0.45), 3.0, true)
	var grab: Vector2 = (p2 + p3) * 0.5
	if cycle < 2.2:
		_finger(grab + Vector2(u * 0.1, u * 0.1), u, cycle > 0.4)


## Kami (a coral dot with ears) hops along tiles to the lantern.
func _draw_walk(u: float, o: Vector2) -> void:
	var path: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(2, 1), Vector2(2, 2), Vector2(3, 2), Vector2(4, 2)]
	for y in 4:
		for x in 5:
			if (x == 4 and y == 0) or (x == 0 and y == 3):
				continue
			_tile(x, y, u, o, paper)
	var goal: Vector2 = _iso(4.5, 2.5, 0.0, u, o)
	var glow: float = 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(goal, u * (0.55 + 0.08 * glow), Color(gold, 0.25))
	draw_circle(goal - Vector2(0, u * 0.3), u * 0.26, gold)
	draw_rect(Rect2(goal - Vector2(u * 0.12, u * 0.62), Vector2(u * 0.24, u * 0.1)), ink)
	var cycle: float = fmod(_t, 4.0)
	var tap_t: float = 0.6
	if cycle < tap_t + 0.4:
		_finger(goal + Vector2(u * 0.2, u * 0.15), u, cycle > tap_t)
	var prog: float = clampf((cycle - tap_t - 0.2) / 2.4, 0.0, 1.0) * float(path.size() - 1)
	for i in path.size():
		if float(i) > prog:
			var dp: Vector2 = _iso(path[i].x + 0.5, path[i].y + 0.5, 0.05, u, o)
			draw_circle(dp, u * 0.07, Color(ink, 0.3))
	var i0: int = mini(int(prog), path.size() - 1)
	var i1: int = mini(i0 + 1, path.size() - 1)
	var f: float = prog - float(i0)
	var cell: Vector2 = path[i0].lerp(path[i1], f)
	var hop: float = sin(f * PI) * 0.35
	var kp: Vector2 = _iso(cell.x + 0.5, cell.y + 0.5, 0.25 + hop, u, o)
	draw_circle(kp + Vector2(0, u * (0.25 + hop)), u * 0.18, Color(ink, 0.15))
	draw_circle(kp, u * 0.22, flap)
	draw_colored_polygon(PackedVector2Array([kp + Vector2(-u * 0.2, -u * 0.05), kp + Vector2(-u * 0.12, -u * 0.42), kp + Vector2(-u * 0.02, -u * 0.12)]), flap)
	draw_colored_polygon(PackedVector2Array([kp + Vector2(u * 0.2, -u * 0.05), kp + Vector2(u * 0.12, -u * 0.42), kp + Vector2(u * 0.02, -u * 0.12)]), flap)
	draw_circle(kp + Vector2(0, u * 0.02), u * 0.1, paper)


## Three stars pop in one after another above a paper crane.
func _draw_goal(s: Vector2, u: float) -> void:
	var c: Vector2 = Vector2(s.x * 0.5, s.y * 0.38)
	var cycle: float = fmod(_t, 3.0)
	for i in 3:
		var appear: float = clampf((cycle - 0.25 - i * 0.3) / 0.3, 0.0, 1.0)
		var pop: float = appear * (1.0 + 0.25 * sin(appear * PI))
		var r: float = u * (0.85 if i == 1 else 0.68) * pop
		var p: Vector2 = c + Vector2((i - 1) * u * 1.75, -u * 0.35 if i == 1 else 0.0)
		if r < 1.0:
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		for k in 10:
			var a: float = -PI / 2.0 + k * PI / 5.0
			pts.append(p + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, gold)
		for k in range(0, 10, 2):
			draw_colored_polygon(PackedVector2Array([p, pts[k], pts[(k + 1) % 10]]), gold.lightened(0.3))
	# Paper crane: body diamond, two wings, neck and tail.
	var b: Vector2 = Vector2(s.x * 0.5, s.y * 0.72 + sin(_t * 2.0) * u * 0.08)
	var w: float = u * 1.3
	var flapw: float = sin(_t * 4.0) * 0.25
	draw_colored_polygon(PackedVector2Array([b + Vector2(-w * 1.4, -w * (0.9 + flapw)), b + Vector2(-w * 0.1, -w * 0.05), b + Vector2(-w * 0.35, w * 0.15)]), paper.darkened(0.05))
	draw_colored_polygon(PackedVector2Array([b + Vector2(w * 1.4, -w * (0.9 + flapw)), b + Vector2(w * 0.1, -w * 0.05), b + Vector2(w * 0.35, w * 0.15)]), paper.darkened(0.12))
	draw_colored_polygon(PackedVector2Array([b + Vector2(-w * 0.4, 0), b + Vector2(0, -w * 0.25), b + Vector2(w * 0.4, 0), b + Vector2(0, w * 0.35)]), paper)
	draw_colored_polygon(PackedVector2Array([b + Vector2(w * 0.3, 0), b + Vector2(w * 0.95, -w * 0.75), b + Vector2(w * 0.42, w * 0.05)]), paper.darkened(0.08))
	draw_colored_polygon(PackedVector2Array([b + Vector2(-w * 0.3, 0), b + Vector2(-w * 1.0, -w * 0.45), b + Vector2(-w * 0.42, w * 0.08)]), paper.darkened(0.08))
	draw_colored_polygon(PackedVector2Array([b + Vector2(w * 0.95, -w * 0.75), b + Vector2(w * 1.15, -w * 0.62), b + Vector2(w * 0.9, -w * 0.66)]), flap)
