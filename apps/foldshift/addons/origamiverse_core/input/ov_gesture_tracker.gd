class_name OVGestureTracker
extends Node
## Converts raw touch (and mouse, for desktop QA) into high-level gestures.
## Feed events with `handle(event)`; it returns true when the event was consumed.

signal touch_down(pos: Vector2)
signal tap(pos: Vector2)
signal double_tap(pos: Vector2)
signal long_press(pos: Vector2)
signal drag_started(pos: Vector2)
signal dragged(pos: Vector2, relative: Vector2)
signal drag_ended(pos: Vector2, velocity: Vector2)
signal pinched(factor: float, center: Vector2)
signal twisted(radians: float, center: Vector2)
signal two_finger_panned(relative: Vector2)

var tap_slop_dp: float = 10.0
var long_press_time: float = 0.45
var double_tap_time: float = 0.3

var _touches: Dictionary = {}       # index -> position
var _start_pos: Vector2
var _start_time: float = 0.0
var _dragging: bool = false
var _multi: bool = false
var _long_fired: bool = false
var _last_tap_time: float = -10.0
var _last_tap_pos: Vector2
var _prev_span: float = 0.0
var _prev_angle: float = 0.0
var _prev_center: Vector2
var _velocity: Vector2
var _last_move_time: float = 0.0
var _mouse_down: bool = false


func _ready() -> void:
	set_process(true)


func slop_px() -> float:
	var dpi: int = DisplayServer.screen_get_dpi()
	return tap_slop_dp * maxf(1.0, float(dpi) / 160.0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_dt: float) -> void:
	if _touches.size() == 1 and not _dragging and not _multi and not _long_fired:
		if _now() - _start_time >= long_press_time:
			_long_fired = true
			long_press.emit(_start_pos)


func is_active() -> bool:
	return not _touches.is_empty()


func cancel() -> void:
	_touches.clear()
	_dragging = false
	_multi = false


func handle(event: InputEvent) -> bool:
	# Mouse events synthesized from touch (emulate_mouse_from_touch) would double count; touch is handled directly.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_touches[t.index] = t.position
			if _touches.size() == 1:
				_begin_single(t.position)
			else:
				_begin_multi()
		else:
			_touches.erase(t.index)
			if _touches.is_empty():
				_end_single(t.position)
			elif _touches.size() == 1:
				# Second finger lifted: stay in multi mode until all fingers are up.
				pass
		return true
	if event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		_touches[d.index] = d.position
		if _multi or _touches.size() >= 2:
			_update_multi()
		else:
			_move_single(d.position, d.relative)
		return true
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			pinched.emit(1.1, mb.position)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			pinched.emit(1.0 / 1.1, mb.position)
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_down = true
				_touches[0] = mb.position
				_begin_single(mb.position)
			else:
				_mouse_down = false
				_touches.erase(0)
				_end_single(mb.position)
			return true
	if event is InputEventMouseMotion and _mouse_down:
		var mm: InputEventMouseMotion = event
		_touches[0] = mm.position
		_move_single(mm.position, mm.relative)
		return true
	return false


func _begin_single(pos: Vector2) -> void:
	_start_pos = pos
	_start_time = _now()
	_dragging = false
	_multi = false
	_long_fired = false
	_velocity = Vector2.ZERO
	_last_move_time = _start_time
	touch_down.emit(pos)


func _move_single(pos: Vector2, rel: Vector2) -> void:
	if not _dragging:
		if pos.distance_to(_start_pos) < slop_px():
			return
		_dragging = true
		drag_started.emit(_start_pos)
		rel = pos - _start_pos
	var now: float = _now()
	var dt: float = maxf(now - _last_move_time, 1e-3)
	_velocity = _velocity.lerp(rel / dt, 0.4)
	_last_move_time = now
	dragged.emit(pos, rel)


func _end_single(pos: Vector2) -> void:
	if _multi:
		_multi = false
		return
	if _dragging:
		_dragging = false
		var vel: Vector2 = _velocity if _now() - _last_move_time < 0.08 else Vector2.ZERO
		drag_ended.emit(pos, vel)
		return
	if _long_fired:
		return
	var now: float = _now()
	if now - _last_tap_time < double_tap_time and pos.distance_to(_last_tap_pos) < slop_px() * 3.0:
		_last_tap_time = -10.0
		double_tap.emit(pos)
	else:
		_last_tap_time = now
		_last_tap_pos = pos
		tap.emit(pos)


func _begin_multi() -> void:
	if _dragging:
		_dragging = false
		drag_ended.emit(_touches.values()[0], Vector2.ZERO)
	_multi = true
	var pts: Array = _touches.values()
	_prev_span = (pts[0] as Vector2).distance_to(pts[1])
	_prev_angle = ((pts[1] as Vector2) - (pts[0] as Vector2)).angle()
	_prev_center = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


func _update_multi() -> void:
	if not _multi:
		_begin_multi()
		return
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var span: float = a.distance_to(b)
	var ang: float = (b - a).angle()
	var center: Vector2 = (a + b) * 0.5
	if _prev_span > 1.0 and span > 1.0:
		pinched.emit(span / _prev_span, center)
	twisted.emit(wrapf(ang - _prev_angle, -PI, PI), center)
	two_finger_panned.emit(center - _prev_center)
	_prev_span = span
	_prev_angle = ang
	_prev_center = center
