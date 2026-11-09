class_name OVUIKit
extends RefCounted
## Small UI helpers shared by both apps so screens read as layout, not boilerplate.
## Apps set `scale` (from OVThemeFactory.ui_scale_for) and `on_click` (sound + haptic) once at startup.

static var scale: float = 1.0
static var on_click: Callable = Callable()


static func s(v: float) -> float:
	return v * scale


static func button(text: String, cb: Callable, variation: String = "", min_w: float = 0.0) -> Button:
	var b: Button = Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(s(min_w), s(96))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		if on_click.is_valid():
			on_click.call()
		cb.call())
	return b


static func label(text: String, variation: String = "", align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l: Label = Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	l.horizontal_alignment = align
	# Short labels inside rows must never wrap letter by letter; only sentences wrap.
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if text.length() > 18 else TextServer.AUTOWRAP_OFF
	return l


static func vbox(sep: float = 24.0) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", int(s(sep)))
	return v


static func hbox(sep: float = 20.0) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", int(s(sep)))
	return h


static func spacer(h: float) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(0, s(h))
	return c


static func expand_spacer() -> Control:
	var c: Control = Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func card() -> PanelContainer:
	return PanelContainer.new()


static func margin(child: Control, l: float, t: float, r: float, b: float) -> MarginContainer:
	var m: MarginContainer = MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(s(l)))
	m.add_theme_constant_override("margin_top", int(s(t)))
	m.add_theme_constant_override("margin_right", int(s(r)))
	m.add_theme_constant_override("margin_bottom", int(s(b)))
	m.add_child(child)
	return m


## Full-screen root that respects the display safe area (notches, gesture bars).
static func screen_root() -> MarginContainer:
	var m: MarginContainer = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var screen: Vector2i = DisplayServer.screen_get_size()
	var vp: Vector2 = (Engine.get_main_loop() as SceneTree).root.get_visible_rect().size
	var k: float = vp.y / maxf(float(screen.y), 1.0) if screen.y > 0 else 1.0
	var top: float = maxf(0.0, safe.position.y * k) if OS.has_feature("mobile") else 0.0
	var bottom: float = maxf(0.0, (screen.y - safe.end.y) * k) if OS.has_feature("mobile") else 0.0
	m.add_theme_constant_override("margin_left", int(s(40)))
	m.add_theme_constant_override("margin_right", int(s(40)))
	m.add_theme_constant_override("margin_top", int(s(36) + top))
	m.add_theme_constant_override("margin_bottom", int(s(36) + bottom))
	return m


static func fade_in(c: CanvasItem, delay: float = 0.0) -> void:
	c.modulate.a = 0.0
	var tw: Tween = c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.35)
