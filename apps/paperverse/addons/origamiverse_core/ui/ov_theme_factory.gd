class_name OVThemeFactory
extends RefCounted
## Shared premium UI theme (rounded paper cards, Outfit typeface). Each app passes its own palette.

const FONT_PATH: String = "res://addons/origamiverse_core/ui/fonts/Outfit-Variable.ttf"


static func font(weight: int = 500) -> FontVariation:
	var base: FontFile = load(FONT_PATH)
	var fv: FontVariation = FontVariation.new()
	fv.base_font = base
	var ts: TextServer = TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	return fv


static func box(bg: Color, radius: int = 18, border: Color = Color.TRANSPARENT, border_w: int = 0,
		shadow: float = 0.0, pad: Vector2 = Vector2(22, 14)) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 8
	s.anti_aliasing = true
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	if shadow > 0.0:
		s.shadow_color = Color(0, 0, 0, shadow)
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s


## palette keys: bg, card, ink, muted, accent, accent_ink, danger
static func build(palette: Dictionary, scale: float = 1.0) -> Theme:
	var t: Theme = Theme.new()
	var regular: FontVariation = font(450)
	var bold: FontVariation = font(700)
	t.default_font = regular
	t.default_font_size = int(30 * scale)
	var ink: Color = palette.get("ink", Color("23233a"))
	var card: Color = palette.get("card", Color("fffaf0"))
	var accent: Color = palette.get("accent", Color("e8604c"))
	var accent_ink: Color = palette.get("accent_ink", Color.WHITE)
	var muted: Color = palette.get("muted", Color("8a8597"))

	# Buttons: accent pill.
	var r: int = int(26 * scale)
	t.set_stylebox("normal", "Button", box(accent, r, Color.TRANSPARENT, 0, 0.18, Vector2(28, 16) * scale))
	t.set_stylebox("hover", "Button", box(accent.lightened(0.08), r, Color.TRANSPARENT, 0, 0.22, Vector2(28, 16) * scale))
	t.set_stylebox("pressed", "Button", box(accent.darkened(0.12), r, Color.TRANSPARENT, 0, 0.08, Vector2(28, 16) * scale))
	t.set_stylebox("disabled", "Button", box(muted.lerp(card, 0.5), r, Color.TRANSPARENT, 0, 0.0, Vector2(28, 16) * scale))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", accent_ink)
	t.set_color("font_hover_color", "Button", accent_ink)
	t.set_color("font_pressed_color", "Button", accent_ink)
	t.set_color("font_focus_color", "Button", accent_ink)
	t.set_color("font_disabled_color", "Button", card)
	t.set_color("icon_normal_color", "Button", accent_ink)
	t.set_color("icon_pressed_color", "Button", accent_ink)
	t.set_color("icon_hover_color", "Button", accent_ink)
	t.set_font("font", "Button", bold)
	t.set_font_size("font_size", "Button", int(30 * scale))

	# Secondary buttons: paper card style (type variation).
	t.add_type("CardButton")
	t.set_type_variation("CardButton", "Button")
	t.set_stylebox("normal", "CardButton", box(card, r, ink.lerp(card, 0.85), 2, 0.12, Vector2(24, 14) * scale))
	t.set_stylebox("hover", "CardButton", box(card.darkened(0.03), r, ink.lerp(card, 0.75), 2, 0.14, Vector2(24, 14) * scale))
	t.set_stylebox("pressed", "CardButton", box(card.darkened(0.08), r, accent, 2, 0.06, Vector2(24, 14) * scale))
	t.set_stylebox("disabled", "CardButton", box(card.darkened(0.04), r, Color.TRANSPARENT, 0, 0.0, Vector2(24, 14) * scale))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "CardButton", ink)
	t.set_color("font_disabled_color", "CardButton", muted)
	for c in ["icon_normal_color", "icon_pressed_color", "icon_hover_color", "icon_focus_color"]:
		t.set_color(c, "CardButton", ink)

	# Toggle chips for tool palettes.
	t.add_type("ChipButton")
	t.set_type_variation("ChipButton", "Button")
	t.set_stylebox("normal", "ChipButton", box(card, int(20 * scale), ink.lerp(card, 0.8), 2, 0.0, Vector2(18, 10) * scale))
	t.set_stylebox("hover", "ChipButton", box(card.darkened(0.03), int(20 * scale), ink.lerp(card, 0.7), 2, 0.0, Vector2(18, 10) * scale))
	t.set_stylebox("pressed", "ChipButton", box(accent, int(20 * scale), accent, 2, 0.0, Vector2(18, 10) * scale))
	t.set_stylebox("hover_pressed", "ChipButton", box(accent.lightened(0.05), int(20 * scale), accent, 2, 0.0, Vector2(18, 10) * scale))
	t.set_stylebox("disabled", "ChipButton", box(card.darkened(0.05), int(20 * scale), Color.TRANSPARENT, 0, 0.0, Vector2(18, 10) * scale))
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "ChipButton", ink)
	t.set_color("font_pressed_color", "ChipButton", accent_ink)
	t.set_color("font_hover_pressed_color", "ChipButton", accent_ink)
	t.set_color("font_disabled_color", "ChipButton", muted)
	t.set_font_size("font_size", "ChipButton", int(24 * scale))
	t.set_font("font", "ChipButton", bold)

	# Panels and labels.
	t.set_stylebox("panel", "PanelContainer", box(card, int(28 * scale), Color.TRANSPARENT, 0, 0.2, Vector2(28, 24) * scale))
	t.set_stylebox("panel", "Panel", box(card, int(28 * scale), Color.TRANSPARENT, 0, 0.2))
	t.set_color("font_color", "Label", ink)
	t.add_type("TitleLabel")
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", bold)
	t.set_font_size("font_size", "TitleLabel", int(56 * scale))
	t.set_color("font_color", "TitleLabel", ink)
	t.add_type("HeaderLabel")
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", bold)
	t.set_font_size("font_size", "HeaderLabel", int(36 * scale))
	t.set_color("font_color", "HeaderLabel", ink)
	t.add_type("MutedLabel")
	t.set_type_variation("MutedLabel", "Label")
	t.set_font_size("font_size", "MutedLabel", int(24 * scale))
	t.set_color("font_color", "MutedLabel", muted)
	t.add_type("HudLabel")
	t.set_type_variation("HudLabel", "Label")
	t.set_font("font", "HudLabel", bold)
	t.set_font_size("font_size", "HudLabel", int(30 * scale))
	t.set_color("font_color", "HudLabel", ink)
	t.set_color("font_outline_color", "HudLabel", card)
	t.set_constant("outline_size", "HudLabel", int(8 * scale))

	# Sliders.
	var track: StyleBoxFlat = box(ink.lerp(card, 0.8), int(8 * scale), Color.TRANSPARENT, 0, 0.0, Vector2(0, 5) * scale)
	var fill: StyleBoxFlat = box(accent, int(8 * scale), Color.TRANSPARENT, 0, 0.0, Vector2(0, 5) * scale)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _circle_texture(int(40 * scale), accent, card))
	t.set_icon("grabber_highlight", "HSlider", _circle_texture(int(44 * scale), accent.lightened(0.1), card))

	# Check buttons render as switches.
	t.set_font_size("font_size", "CheckButton", int(28 * scale))
	t.set_color("font_color", "CheckButton", ink)
	t.set_color("font_pressed_color", "CheckButton", ink)
	t.set_color("font_hover_color", "CheckButton", ink)
	t.set_color("font_hover_pressed_color", "CheckButton", ink)
	t.set_color("font_focus_color", "CheckButton", ink)
	t.set_icon("checked", "CheckButton", _switch_texture(scale, true, accent, card, ink))
	t.set_icon("unchecked", "CheckButton", _switch_texture(scale, false, accent, card, ink))
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())

	# Line edits.
	t.set_stylebox("normal", "LineEdit", box(card.darkened(0.04), int(16 * scale), ink.lerp(card, 0.8), 2, 0.0, Vector2(18, 12) * scale))
	t.set_stylebox("focus", "LineEdit", box(card, int(16 * scale), accent, 3, 0.0, Vector2(18, 12) * scale))
	t.set_color("font_color", "LineEdit", ink)
	t.set_color("caret_color", "LineEdit", accent)
	t.set_font_size("font_size", "LineEdit", int(30 * scale))

	# Scroll bars: slim.
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.05), 6, Color.TRANSPARENT, 0, 0.0, Vector2(3, 3)))
	t.set_stylebox("grabber", "VScrollBar", box(ink.lerp(card, 0.6), 6, Color.TRANSPARENT, 0, 0.0, Vector2(3, 3)))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(accent, 6, Color.TRANSPARENT, 0, 0.0, Vector2(3, 3)))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(accent, 6, Color.TRANSPARENT, 0, 0.0, Vector2(3, 3)))
	t.set_stylebox("scroll", "HScrollBar", box(Color(0, 0, 0, 0.05), 6, Color.TRANSPARENT, 0, 0.0, Vector2(3, 3)))
	t.set_stylebox("grabber", "HScrollBar", box(ink.lerp(card, 0.6), 6, Color.TRANSPARENT, 0, 0.0, Vector2(3, 3)))

	# Popups (OptionButton menus, dialogs).
	t.set_stylebox("panel", "PopupMenu", box(card, int(18 * scale), ink.lerp(card, 0.85), 2, 0.25, Vector2(12, 12) * scale))
	t.set_color("font_color", "PopupMenu", ink)
	t.set_color("font_hover_color", "PopupMenu", accent)
	t.set_stylebox("hover", "PopupMenu", box(accent.lerp(card, 0.85), int(12 * scale)))
	t.set_font_size("font_size", "PopupMenu", int(30 * scale))
	t.set_constant("v_separation", "PopupMenu", int(18 * scale))
	t.set_stylebox("panel", "AcceptDialog", box(card, int(24 * scale), Color.TRANSPARENT, 0, 0.3, Vector2(24, 24) * scale))
	t.set_stylebox("normal", "OptionButton", box(card, r, ink.lerp(card, 0.8), 2, 0.0, Vector2(22, 12) * scale))
	t.set_stylebox("hover", "OptionButton", box(card.darkened(0.03), r, ink.lerp(card, 0.7), 2, 0.0, Vector2(22, 12) * scale))
	t.set_stylebox("pressed", "OptionButton", box(card.darkened(0.06), r, accent, 2, 0.0, Vector2(22, 12) * scale))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "OptionButton", ink)
	t.set_font_size("font_size", "OptionButton", int(26 * scale))

	t.set_stylebox("panel", "TooltipPanel", box(ink, 12, Color.TRANSPARENT, 0, 0.2, Vector2(12, 8)))
	t.set_color("font_color", "TooltipLabel", card)
	return t


## UI scale so layouts designed for a 1080-px-wide portrait screen look right on any device.
static func ui_scale_for(viewport_size: Vector2) -> float:
	return clampf(minf(viewport_size.x, viewport_size.y) / 1080.0, 0.6, 1.6)


static func _circle_texture(size: int, fill: Color, ring: Color) -> ImageTexture:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c: Vector2 = Vector2(size, size) * 0.5
	var rad: float = size * 0.5 - 1.0
	for y in size:
		for x in size:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			var col: Color = Color(0, 0, 0, 0)
			if d <= rad:
				col = fill if d < rad - 4.0 else ring
				col.a = clampf(rad - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _switch_texture(scale: float, on: bool, accent: Color, card: Color, ink: Color) -> ImageTexture:
	var w: int = int(84 * scale)
	var h: int = int(46 * scale)
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track: Color = accent if on else ink.lerp(card, 0.7)
	var r: float = h * 0.5
	var knob_c: Vector2 = Vector2(w - r if on else r, r)
	for y in h:
		for x in w:
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			var cx: float = clampf(p.x, r, w - r)
			var d: float = p.distance_to(Vector2(cx, r))
			var col: Color = Color(0, 0, 0, 0)
			if d <= r:
				col = track
				col.a = clampf(r - d + 0.5, 0.0, 1.0)
			var kd: float = p.distance_to(knob_c)
			if kd <= r - 4.0:
				col = card
				col.a = clampf(r - 4.0 - kd + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
