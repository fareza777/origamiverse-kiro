class_name PVCreaseCanvas
extends Control
## Touch crease-pattern editor. Emits edit requests; the studio applies them through the undo stack.

signal add_requested(a: Vector2, b: Vector2, assign: int)
signal erase_requested(index: int)
signal flip_requested(index: int)
signal message(text: String)

enum Tool { MOUNTAIN, VALLEY, CUT, FLAT, ERASE, FLIP }

const COLORS: Dictionary = {
	OVCore.Assign.MOUNTAIN: Color("e2483c"),
	OVCore.Assign.VALLEY: Color("2f6fe0"),
	OVCore.Assign.CUT: Color("2b2640"),
	OVCore.Assign.FLAT: Color("a49fb0"),
	OVCore.Assign.BOUNDARY: Color("2b2640"),
}

var pattern: OVCreasePattern
var tool: int = Tool.VALLEY
var grid: int = 8
var paper_color: Color = Color("fbf8f1")

var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _gestures: OVGestureTracker
var _drawing: bool = false
var _draw_a: Vector2
var _draw_b: Vector2
var _snap_hint: Variant = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_gestures = OVGestureTracker.new()
	add_child(_gestures)
	_gestures.tap.connect(_on_tap)
	_gestures.drag_started.connect(_on_drag_start)
	_gestures.dragged.connect(_on_drag)
	_gestures.drag_ended.connect(_on_drag_end)
	_gestures.pinched.connect(_on_pinch)
	_gestures.two_finger_panned.connect(func(rel: Vector2) -> void:
		_pan += rel
		queue_redraw())
	_gestures.double_tap.connect(func(_p: Vector2) -> void:
		_zoom = 1.0
		_pan = Vector2.ZERO
		queue_redraw())
	resized.connect(queue_redraw)


func set_pattern(p: OVCreasePattern) -> void:
	pattern = p
	queue_redraw()


func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()


# ------------------------------------------------------------ coordinates


func _base_rect() -> Rect2:
	var side: float = minf(size.x, size.y) * 0.9
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


func _scale() -> float:
	var b: Rect2 = pattern.bounds() if pattern else Rect2(0, 0, 1, 1)
	return _base_rect().size.x / maxf(b.size.x, b.size.y) * _zoom


func to_screen(p: Vector2) -> Vector2:
	var b: Rect2 = pattern.bounds()
	var r: Rect2 = _base_rect()
	var center: Vector2 = r.get_center() + _pan
	var pc: Vector2 = b.get_center()
	var k: float = _scale()
	return center + Vector2(p.x - pc.x, -(p.y - pc.y)) * k


func to_pattern(s: Vector2) -> Vector2:
	var b: Rect2 = pattern.bounds()
	var r: Rect2 = _base_rect()
	var center: Vector2 = r.get_center() + _pan
	var k: float = _scale()
	var d: Vector2 = (s - center) / k
	return b.get_center() + Vector2(d.x, -d.y)


func _snap_radius() -> float:
	return 22.0 * OVUIKit.scale / _scale()


# ------------------------------------------------------------ input


func _gui_input(event: InputEvent) -> void:
	if pattern == null:
		return
	if _gestures.handle(event):
		accept_event()


func _draw_tool() -> bool:
	return tool in [Tool.MOUNTAIN, Tool.VALLEY, Tool.CUT, Tool.FLAT]


func _tool_assign() -> int:
	match tool:
		Tool.MOUNTAIN: return OVCore.Assign.MOUNTAIN
		Tool.VALLEY: return OVCore.Assign.VALLEY
		Tool.CUT: return OVCore.Assign.CUT
	return OVCore.Assign.FLAT


func _on_tap(pos: Vector2) -> void:
	var p: Vector2 = to_pattern(pos)
	var idx: int = pattern.pick_segment(p, _snap_radius())
	match tool:
		Tool.ERASE:
			if idx >= 0:
				erase_requested.emit(idx)
			else:
				message.emit("Tap directly on a crease to erase it.")
		Tool.FLIP:
			if idx >= 0:
				flip_requested.emit(idx)
			else:
				message.emit("Tap a crease to swap mountain and valley.")
		_:
			message.emit("Drag from point to point to draw a crease.")


func _on_drag_start(pos: Vector2) -> void:
	if not _draw_tool():
		return
	_drawing = true
	_draw_a = pattern.snap(to_pattern(pos), grid, _snap_radius())
	_draw_b = _draw_a
	queue_redraw()


func _on_drag(pos: Vector2, _rel: Vector2) -> void:
	if not _drawing:
		if not _draw_tool():
			_pan += _rel
			queue_redraw()
		return
	var raw: Vector2 = to_pattern(pos)
	_draw_b = pattern.snap(raw, grid, _snap_radius(), _draw_a)
	_snap_hint = _draw_b if _draw_b.distance_to(raw) > 1e-6 else null
	queue_redraw()


func _on_drag_end(_pos: Vector2, _vel: Vector2) -> void:
	if not _drawing:
		return
	_drawing = false
	_snap_hint = null
	if _draw_a.distance_to(_draw_b) > _snap_radius() * 0.5:
		add_requested.emit(_draw_a, _draw_b, _tool_assign())
	queue_redraw()


func _on_pinch(factor: float, center: Vector2) -> void:
	var before: Vector2 = to_pattern(center)
	_zoom = clampf(_zoom * factor, 0.6, 8.0)
	var after: Vector2 = to_screen(before)
	_pan += center - after
	queue_redraw()


# ------------------------------------------------------------ drawing


func _draw() -> void:
	if pattern == null:
		return
	var outline: PackedVector2Array = PackedVector2Array()
	for p in pattern.outline:
		outline.append(to_screen(p))
	draw_colored_polygon(outline, paper_color)
	# Grid (only inside the sheet's bounding square).
	if grid > 0:
		var b: Rect2 = pattern.bounds()
		var gc: Color = Color(0.17, 0.15, 0.25, 0.07)
		for i in range(1, grid):
			var t: float = float(i) / grid
			draw_line(to_screen(Vector2(b.position.x + b.size.x * t, b.position.y)), to_screen(Vector2(b.position.x + b.size.x * t, b.end.y)), gc, 1.0)
			draw_line(to_screen(Vector2(b.position.x, b.position.y + b.size.y * t)), to_screen(Vector2(b.end.x, b.position.y + b.size.y * t)), gc, 1.0)
	var w: float = maxf(2.0, 3.0 * OVUIKit.scale)
	for s in pattern.segments:
		_draw_crease(to_screen(s.a), to_screen(s.b), s.assign, w)
	for i in outline.size():
		draw_line(outline[i], outline[(i + 1) % outline.size()], COLORS[OVCore.Assign.BOUNDARY], w * 1.2, true)
	# Vertices.
	for s in pattern.segments:
		for p in [s.a, s.b]:
			draw_circle(to_screen(p), w * 1.1, Color(0.17, 0.15, 0.25, 0.55))
	if _drawing:
		_draw_crease(to_screen(_draw_a), to_screen(_draw_b), _tool_assign(), w * 1.3)
		draw_circle(to_screen(_draw_a), w * 2.6, Color(1, 0.7, 0.28, 0.9))
		draw_arc(to_screen(_draw_b), w * 4.0, 0, TAU, 24, Color(1, 0.7, 0.28, 0.9), w * 0.8, true)


func _draw_crease(a: Vector2, b: Vector2, assign: int, w: float) -> void:
	var col: Color = COLORS.get(assign, Color.GRAY)
	match assign:
		OVCore.Assign.VALLEY:
			_dashed(a, b, col, w, 14.0 * OVUIKit.scale, 9.0 * OVUIKit.scale)
		OVCore.Assign.MOUNTAIN:
			_dash_dot(a, b, col, w)
		OVCore.Assign.FLAT:
			draw_line(a, b, Color(col, 0.7), w * 0.6, true)
		_:
			draw_line(a, b, col, w * 1.2, true)


func _dashed(a: Vector2, b: Vector2, col: Color, w: float, dash: float, gap: float) -> void:
	var len: float = a.distance_to(b)
	if len < 1.0:
		return
	var dir: Vector2 = (b - a) / len
	var t: float = 0.0
	while t < len:
		draw_line(a + dir * t, a + dir * minf(t + dash, len), col, w, true)
		t += dash + gap


func _dash_dot(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var len: float = a.distance_to(b)
	if len < 1.0:
		return
	var dir: Vector2 = (b - a) / len
	var dash: float = 16.0 * OVUIKit.scale
	var gap: float = 6.0 * OVUIKit.scale
	var t: float = 0.0
	while t < len:
		draw_line(a + dir * t, a + dir * minf(t + dash, len), col, w, true)
		var dot_t: float = t + dash + gap
		if dot_t < len:
			draw_circle(a + dir * dot_t, w * 0.7, col)
		t += dash + gap * 2.0 + w
