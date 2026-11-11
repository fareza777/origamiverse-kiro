class_name OVOnboarding
extends Control
## Swipeable first-run walkthrough. Each page has an illustration Control, a title and a short body.
## Skip, Back, Next, page dots and left/right swipes; the last page's button says `finish_text`.

signal finished

const K = preload("res://addons/origamiverse_core/ui/ov_ui_kit.gd")

var pages: Array[Dictionary] = []
var index: int = 0
var finish_text: String = "Get started"

var _art_host: Control
var _title: Label
var _body: Label
var _dots: HBoxContainer
var _next: Button
var _back: Button
var _palette: Dictionary
var _drag_start: Vector2 = Vector2.INF
var _content: VBoxContainer


## pages: [{"title": String, "body": String, "art": Control}]
func setup(page_list: Array[Dictionary], palette: Dictionary, finish_label: String = "Get started") -> OVOnboarding:
	pages = page_list
	_palette = palette
	finish_text = finish_label
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg: ColorRect = ColorRect.new()
	bg.color = palette.get("bg", Color("f7f2e8"))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var root: MarginContainer = K.screen_root()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var v: VBoxContainer = K.vbox(22)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	var top: HBoxContainer = K.hbox(12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var step: Label = K.label("", "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT)
	step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step.name = "Step"
	top.add_child(step)
	top.add_child(K.button("Skip", _finish, "CardButton", 190))
	v.add_child(top)
	_content = K.vbox(26)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_content)
	_art_host = Control.new()
	_art_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_art_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_art_host)
	_title = K.label("", "TitleLabel")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", int(K.s(76)))
	_content.add_child(_title)
	_body = K.label("", "")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", int(K.s(44)))
	_body.add_theme_color_override("font_color", palette.get("muted", Color.GRAY).lerp(palette.get("ink", Color.BLACK), 0.45))
	_body.custom_minimum_size.y = K.s(220)
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_content.add_child(_body)
	_dots = K.hbox(14)
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in pages.size():
		var d: Panel = Panel.new()
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dots.add_child(d)
	v.add_child(_dots)
	var nav: HBoxContainer = K.hbox(18)
	_back = K.button("Back", func() -> void: show_page(index - 1), "CardButton", 260)
	nav.add_child(_back)
	_next = K.button("Next", _on_next)
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(_next)
	v.add_child(nav)
	show_page(0, false)
	return self


func _on_next() -> void:
	if index >= pages.size() - 1:
		_finish()
	else:
		show_page(index + 1)


func show_page(i: int, animate: bool = true) -> void:
	if i < 0 or i >= pages.size():
		return
	var dir: float = signf(float(i - index))
	index = i
	for c in _art_host.get_children():
		_art_host.remove_child(c)
	var art: Control = pages[i].get("art")
	if art:
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art_host.add_child(art)
	_title.text = str(pages[i].get("title", ""))
	_body.text = str(pages[i].get("body", ""))
	(find_child("Step", true, false) as Label).text = "%d of %d" % [i + 1, pages.size()]
	_back.visible = i > 0
	_next.text = finish_text if i == pages.size() - 1 else "Next"
	for d in _dots.get_child_count():
		var dot: Panel = _dots.get_child(d)
		var on: bool = d == i
		dot.custom_minimum_size = Vector2(K.s(46 if on else 18), K.s(18))
		dot.add_theme_stylebox_override("panel", OVThemeFactory.box(
			_palette.get("accent", Color.RED) if on else _palette.get("muted", Color.GRAY).lerp(_palette.get("bg", Color.WHITE), 0.5),
			int(K.s(9)), Color.TRANSPARENT, 0, 0.0, Vector2.ZERO))
	if animate:
		_content.modulate.a = 0.0
		_content.position.x = K.s(60) * dir
		var tw: Tween = create_tween().set_parallel(true)
		tw.tween_property(_content, "modulate:a", 1.0, 0.28)
		tw.tween_property(_content, "position:x", 0.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_drag_start = e.position
		elif _drag_start != Vector2.INF:
			var d: Vector2 = e.position - _drag_start
			_drag_start = Vector2.INF
			if absf(d.x) > K.s(120) and absf(d.x) > absf(d.y) * 1.5:
				if d.x < 0.0:
					_on_next()
				else:
					show_page(index - 1)


func _finish() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit()
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)
