class_name FSStarRow
extends Control
## Draws N paper-star badges (filled = earned). Vector drawn so no icon font is needed.

var count: int = 3
var filled: int = 0
var star_size: float = 48.0
var color_on: Color = Color("f2b440")
var color_off: Color = Color(0.0, 0.0, 0.0, 0.12)
var _pop: Array[float] = [1.0, 1.0, 1.0]


func setup(earned: int, size_px: float, animate: bool = false) -> FSStarRow:
	filled = earned
	star_size = size_px
	custom_minimum_size = Vector2(count * size_px * 1.15, size_px)
	if animate:
		_pop = [0.0, 0.0, 0.0]
		for i in count:
			var tw: Tween = create_tween()
			tw.tween_interval(0.25 + i * 0.22)
			tw.tween_method(func(v: float) -> void:
				_pop[i] = v
				queue_redraw(), 0.0, 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if i < earned:
				tw.tween_callback(func() -> void: Game.audio.play_note(i * 2))
	return self


func _draw() -> void:
	var total_w: float = count * star_size * 1.15
	var x0: float = (size.x - total_w) * 0.5 + star_size * 0.575
	for i in count:
		var c: Vector2 = Vector2(x0 + i * star_size * 1.15, size.y * 0.5)
		var r: float = star_size * 0.5 * _pop[i]
		if r <= 0.5:
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		for k in 10:
			var a: float = -PI / 2.0 + k * PI / 5.0
			var rr: float = r if k % 2 == 0 else r * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		var col: Color = color_on if i < filled else color_off
		draw_colored_polygon(pts, col)
		if i < filled:
			# Folded-paper look: lighter facet on one half of each point.
			for k in range(0, 10, 2):
				draw_colored_polygon(PackedVector2Array([c, pts[k], pts[(k + 1) % 10]]), col.lightened(0.25))
