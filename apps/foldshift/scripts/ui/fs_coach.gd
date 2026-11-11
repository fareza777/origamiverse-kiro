class_name FSCoach
extends Control
## In-level tutorial coach mark: a pulsing finger over a world point with a caption card.
## The target is a Callable returning a screen position, so the mark follows folds and camera moves.
## Input passes through, so the player performs the real action under the mark.

const K = preload("res://addons/origamiverse_core/ui/ov_ui_kit.gd")

var target: Callable = Callable()
## Optional drag hint: the finger slides by this screen offset (pixels) and back.
var drag: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _card: PanelContainer
var _label: Label
var _ink: Color = Color("2b2640")
var _accent: Color = Color("e8604c")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", OVThemeFactory.box(_ink, int(K.s(28)), Color.TRANSPARENT, 0, 0.25, Vector2(K.s(30), K.s(22))))
	_label = K.label("", "")
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.custom_minimum_size.x = K.s(760)
	_card.add_child(_label)
	add_child(_card)


func show_step(text: String, target_fn: Callable, drag_offset: Vector2 = Vector2.ZERO) -> void:
	_label.text = text
	target = target_fn
	drag = drag_offset
	_t = 0.0
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()
	if not target.is_valid():
		return
	var p: Vector2 = target.call()
	# Caption above the finger, kept on screen.
	var vs: Vector2 = get_viewport_rect().size
	var cs: Vector2 = _card.get_combined_minimum_size()
	_card.size = cs
	var y: float = p.y - cs.y - K.s(150)
	if y < K.s(260):
		y = p.y + K.s(150)
	_card.position = Vector2(clampf(p.x - cs.x * 0.5, K.s(30), vs.x - cs.x - K.s(30)), clampf(y, K.s(240), vs.y - cs.y - K.s(260)))


func _draw() -> void:
	if not target.is_valid():
		return
	var p: Vector2 = target.call()
	var cycle: float = fmod(_t, 1.8)
	var slide: float = 0.0
	if drag != Vector2.ZERO:
		slide = clampf((cycle - 0.35) / 0.9, 0.0, 1.0)
		slide = slide * slide * (3.0 - 2.0 * slide)
	var fp: Vector2 = p + drag * slide
	var ring: float = fmod(_t * 1.2, 1.0)
	draw_arc(p, K.s(40) + ring * K.s(70), 0.0, TAU, 48, Color(1, 1, 1, 0.8 * (1.0 - ring)), K.s(6), true)
	if drag != Vector2.ZERO:
		draw_dashed_line(p, p + drag, Color(1, 1, 1, 0.75), K.s(6), K.s(18), true)
		var dir: Vector2 = drag.normalized()
		var tip: Vector2 = p + drag
		var side: Vector2 = Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * K.s(34) + side * K.s(20), tip - dir * K.s(34) - side * K.s(20)]), Color(1, 1, 1, 0.85))
	var pressed: bool = cycle > 0.25 and cycle < 1.4
	var r: float = K.s(34 if pressed else 40)
	draw_circle(fp, r * 1.6, Color(_accent, 0.25))
	draw_circle(fp, r, _ink)
	draw_circle(fp, r * 0.5, Color.WHITE)
