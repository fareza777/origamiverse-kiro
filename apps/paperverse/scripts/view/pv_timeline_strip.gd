class_name PVTimelineStrip
extends Control
## Timeline track view: keyframes of the "fold" and "spin" channels plus a draggable playhead.

signal scrubbed(t: float)

var timeline: OVTimeline
var playhead: float = 0.0
var _dragging: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = 150.0 * OVUIKit.scale


func set_timeline(tl: OVTimeline) -> void:
	timeline = tl
	queue_redraw()


func set_playhead(t: float) -> void:
	playhead = t
	queue_redraw()


func _x_for(t: float) -> float:
	var pad: float = 24.0 * OVUIKit.scale
	return pad + (size.x - pad * 2.0) * clampf(t / maxf(timeline.duration, 0.01), 0.0, 1.0)


func _t_for(x: float) -> float:
	var pad: float = 24.0 * OVUIKit.scale
	return clampf((x - pad) / maxf(size.x - pad * 2.0, 1.0), 0.0, 1.0) * timeline.duration


func _gui_input(event: InputEvent) -> void:
	if timeline == null:
		return
	var pos: Variant = null
	if event is InputEventScreenTouch:
		_dragging = event.pressed
		pos = event.position if event.pressed else null
	elif event is InputEventScreenDrag and _dragging:
		pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		_dragging = event.pressed
		pos = event.position if event.pressed else null
	elif event is InputEventMouseMotion and _dragging and event.device != InputEvent.DEVICE_ID_EMULATION:
		pos = event.position
	if pos != null:
		playhead = snappedf(_t_for((pos as Vector2).x), 0.05)
		scrubbed.emit(playhead)
		queue_redraw()
		accept_event()


func _draw() -> void:
	if timeline == null:
		return
	var s: float = OVUIKit.scale
	var ink: Color = Color("23233a")
	var rows: Array = [["fold", Color("4a5fd6"), size.y * 0.35], ["spin", Color("e8604c"), size.y * 0.72]]
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.0))
	# Second ticks.
	var secs: int = int(ceil(timeline.duration))
	for i in secs + 1:
		var x: float = _x_for(float(i))
		draw_line(Vector2(x, size.y * 0.12), Vector2(x, size.y * 0.92), Color(ink, 0.08), 1.0)
		draw_string(get_theme_default_font(), Vector2(x + 4 * s, size.y * 0.16), "%ds" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * s), Color(ink, 0.4))
	for row in rows:
		var y: float = row[2]
		draw_line(Vector2(_x_for(0.0), y), Vector2(_x_for(timeline.duration), y), Color(row[1], 0.25), 4.0 * s)
		var ks: Array = timeline.keys(row[0])
		for i in ks.size():
			var x2: float = _x_for(ks[i].t)
			if i > 0:
				draw_line(Vector2(_x_for(ks[i - 1].t), y), Vector2(x2, y), row[1], 4.0 * s)
			var r: float = 11.0 * s
			draw_colored_polygon(PackedVector2Array([Vector2(x2, y - r), Vector2(x2 + r, y), Vector2(x2, y + r), Vector2(x2 - r, y)]), row[1])
		draw_string(get_theme_default_font(), Vector2(4 * s, y - 14 * s), row[0].capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * s), Color(row[1], 0.9))
	var px: float = _x_for(playhead)
	draw_line(Vector2(px, 0), Vector2(px, size.y), ink, 3.0 * s)
	draw_circle(Vector2(px, 6 * s), 8 * s, ink)
