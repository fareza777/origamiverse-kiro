class_name PVPatternPreview
extends Control
## Small static drawing of a crease pattern for gallery cards.

var pattern: OVCreasePattern
var bg: Color = Color("fbf8f1")


func setup(p: OVCreasePattern, min_size: float) -> PVPatternPreview:
	pattern = p
	custom_minimum_size = Vector2(min_size, min_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func _draw() -> void:
	if pattern == null:
		return
	var b: Rect2 = pattern.bounds()
	var side: float = minf(size.x, size.y) * 0.88
	var k: float = side / maxf(b.size.x, b.size.y)
	var center: Vector2 = size * 0.5
	var to_s := func(p: Vector2) -> Vector2:
		return center + Vector2(p.x - b.get_center().x, -(p.y - b.get_center().y)) * k
	var poly: PackedVector2Array = PackedVector2Array()
	for p in pattern.outline:
		poly.append(to_s.call(p))
	draw_colored_polygon(poly, bg)
	var w: float = maxf(1.5, side / 110.0)
	for s in pattern.segments:
		var col: Color = PVCreaseCanvas.COLORS.get(s.assign, Color.GRAY)
		if s.assign == OVCore.Assign.FLAT:
			col.a = 0.5
		draw_line(to_s.call(s.a), to_s.call(s.b), col, w, true)
	for i in poly.size():
		draw_line(poly[i], poly[(i + 1) % poly.size()], Color("2b2640"), w * 1.2, true)
