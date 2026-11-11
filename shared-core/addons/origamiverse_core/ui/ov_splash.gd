class_name OVSplash
extends Control
## Animated launch splash: the app emblem settles in, the name and studio fade up, then the splash
## dissolves into the first screen. It continues the native boot splash (same background and emblem),
## and gives the renderer a second to compile shaders behind an opaque layer. A tap skips it.

signal finished

const K = preload("res://addons/origamiverse_core/ui/ov_ui_kit.gd")

var _done: bool = false
var _hold: float = 1.1


## `palette` needs bg, ink, muted, accent. `emblem` may be null.
func setup(emblem: Texture2D, app_name: String, tagline: String, palette: Dictionary, hold: float = 1.1) -> OVSplash:
	_hold = hold
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg: ColorRect = ColorRect.new()
	bg.color = palette.get("bg", Color("f7f2e8"))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# The emblem sits exactly at screen center at 640 px, like the native boot splash, so the hand-off is seamless.
	var art: TextureRect = TextureRect.new()
	art.texture = emblem
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(K.s(640), K.s(640))
	art.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	art.offset_left = -K.s(320)
	art.offset_top = -K.s(320)
	art.offset_right = K.s(320)
	art.offset_bottom = K.s(320)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	var center: VBoxContainer = K.vbox(12)
	center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.5
	center.anchor_bottom = 0.5
	center.offset_top = K.s(300)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var title: Label = K.label(app_name, "TitleLabel")
	title.add_theme_font_size_override("font_size", int(K.s(112)))
	title.add_theme_color_override("font_color", palette.get("ink", Color.BLACK))
	center.add_child(title)
	var tag: Label = K.label(tagline, "MutedLabel")
	tag.add_theme_font_size_override("font_size", int(K.s(40)))
	center.add_child(tag)
	var studio: Label = K.label("F7 DEVELOPER", "SectionLabel")
	studio.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	studio.grow_horizontal = Control.GROW_DIRECTION_BOTH
	studio.grow_vertical = Control.GROW_DIRECTION_BEGIN
	studio.offset_bottom = -K.s(140)
	studio.add_theme_color_override("font_color", palette.get("accent", Color.BLACK))
	add_child(studio)
	_animate(art, title, tag, studio)
	return self


func _animate(art: Control, title: Control, tag: Control, studio: Control) -> void:
	for c in [title, tag, studio]:
		c.modulate.a = 0.0
	art.pivot_offset = Vector2(K.s(320), K.s(320))
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(art, "scale", Vector2(1.05, 1.05), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(art, "scale", Vector2.ONE, 0.45).set_delay(0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "modulate:a", 1.0, 0.45).set_delay(0.2)
	tw.tween_property(tag, "modulate:a", 1.0, 0.45).set_delay(0.35)
	tw.tween_property(studio, "modulate:a", 1.0, 0.45).set_delay(0.45)
	tw.chain().tween_interval(_hold)
	tw.chain().tween_callback(dismiss)


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		dismiss()


func dismiss() -> void:
	if _done:
		return
	_done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit()
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.45)
	tw.tween_callback(queue_free)
