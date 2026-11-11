class_name OVSettingsKit
extends RefCounted
## Settings screen building blocks shared by both apps: grouped cards with captions, slider rows,
## switch rows, segmented choice rows and tappable link rows. Everything is sized from OVUIKit.scale.

const K = preload("res://addons/origamiverse_core/ui/ov_ui_kit.gd")


## A captioned group. Add rows to the returned VBox (`group.get_meta("rows")`).
static func section(title: String) -> VBoxContainer:
	var outer: VBoxContainer = K.vbox(12)
	var cap: Label = K.label(title.to_upper(), "SectionLabel", HORIZONTAL_ALIGNMENT_LEFT)
	outer.add_child(K.margin(cap, 12, 10, 0, 0))
	var card: PanelContainer = K.card()
	var rows: VBoxContainer = K.vbox(6)
	card.add_child(rows)
	outer.add_child(card)
	outer.set_meta("rows", rows)
	return outer


static func rows(section_box: VBoxContainer) -> VBoxContainer:
	return section_box.get_meta("rows")


static func _text_block(title: String, subtitle: String) -> VBoxContainer:
	var tv: VBoxContainer = K.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Label = K.label(title, "", HORIZONTAL_ALIGNMENT_LEFT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(t)
	if subtitle != "":
		var st: Label = K.label(subtitle, "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(st)
	return tv


static func slider(title: String, value: float, on_change: Callable, min_v: float = 0.0, max_v: float = 1.0,
		step: float = 0.05, format: Callable = Callable()) -> VBoxContainer:
	var v: VBoxContainer = K.vbox(4)
	var h: HBoxContainer = K.hbox(12)
	var t: Label = K.label(title, "", HORIZONTAL_ALIGNMENT_LEFT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var fmt: Callable = format if format.is_valid() else func(x: float) -> String: return "%d%%" % roundi(x / max_v * 100.0)
	var val: Label = K.label(fmt.call(value), "MutedLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	h.add_child(val)
	v.add_child(h)
	var sl: HSlider = HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size.y = K.s(64)
	sl.value_changed.connect(func(x: float) -> void:
		val.text = fmt.call(x)
		on_change.call(x))
	v.add_child(sl)
	return _wrap(v)


static func _wrap(c: Control) -> VBoxContainer:
	var w: VBoxContainer = VBoxContainer.new()
	w.add_child(K.margin(c, 8, 10, 8, 10))
	return w


static func switch(title: String, subtitle: String, on: bool, on_toggle: Callable) -> Control:
	var h: HBoxContainer = K.hbox(16)
	h.add_child(_text_block(title, subtitle))
	var cb: CheckButton = CheckButton.new()
	cb.button_pressed = on
	cb.focus_mode = Control.FOCUS_NONE
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The row button handles taps; the switch only shows the state.
	cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cb.toggled.connect(func(x: bool) -> void:
		if K.on_click.is_valid():
			K.on_click.call()
		on_toggle.call(x))
	h.add_child(cb)
	var row: Button = Button.new()
	row.theme_type_variation = "RowButton"
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = K.s(112)
	row.pressed.connect(func() -> void:
		if Time.get_ticks_msec() - K._scroll_moved_ms < 120:
			return
		cb.button_pressed = not cb.button_pressed)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m: MarginContainer = K.margin(h, 8, 0, 8, 0)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(m)
	m.minimum_size_changed.connect(func() -> void: row.custom_minimum_size.y = maxf(K.s(112), m.get_combined_minimum_size().y))
	return row


## Segmented control. `options` are labels; `on_pick` receives the index.
static func choice(title: String, subtitle: String, options: PackedStringArray, index: int, on_pick: Callable) -> Control:
	var v: VBoxContainer = K.vbox(12)
	v.add_child(_text_block(title, subtitle))
	var h: HBoxContainer = K.hbox(10)
	var group: ButtonGroup = ButtonGroup.new()
	for i in options.size():
		var b: Button = Button.new()
		b.text = options[i]
		b.theme_type_variation = "ChipButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == index
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.custom_minimum_size.y = K.s(92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx: int = i
		b.pressed.connect(func() -> void:
			if K.on_click.is_valid():
				K.on_click.call()
			on_pick.call(idx))
		h.add_child(b)
	v.add_child(h)
	return _wrap(v)


## Tappable row with an optional trailing value or chevron.
static func link(title: String, subtitle: String, cb: Callable, trailing: String = "›") -> Control:
	var row: Button = Button.new()
	row.theme_type_variation = "RowButton"
	row.focus_mode = Control.FOCUS_NONE
	var h: HBoxContainer = K.hbox(16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_text_block(title, subtitle))
	if trailing != "":
		var tl: Label = K.label(trailing, "HeaderLabel" if trailing == "›" else "MutedLabel")
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tl)
	var m: MarginContainer = K.margin(h, 8, 0, 8, 0)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(m)
	row.custom_minimum_size.y = K.s(112)
	m.minimum_size_changed.connect(func() -> void: row.custom_minimum_size.y = maxf(K.s(112), m.get_combined_minimum_size().y))
	row.pressed.connect(func() -> void:
		if Time.get_ticks_msec() - K._scroll_moved_ms < 120:
			return
		if K.on_click.is_valid():
			K.on_click.call()
		cb.call())
	return row


static func info(text: String) -> Control:
	var l: Label = K.label(text, "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return _wrap(l)


static func divider() -> Control:
	var c: ColorRect = ColorRect.new()
	c.color = Color(0, 0, 0, 0.06)
	c.custom_minimum_size.y = maxf(1.0, K.s(2))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


const PRIVACY_TEXT: String = "We collect no personal data.\n\n• No account, sign-in or registration.\n• No analytics, advertising or tracking SDKs.\n• Nothing is sent to any server. The app works fully offline.\n• Progress and projects stay in the app's private storage on this device. Uninstalling removes them.\n• Exports are written only where you choose.\n• No sensitive permissions. Vibration follows your setting.\n\nPublisher: F7 Developer. Contact: see the F7 Developer page on Google Play."


## "Support" section shared by both apps: rate, share, more apps. `notify` receives a short status message.
static func support_section(app_name: String, package: String, share_message: String, notify: Callable) -> VBoxContainer:
	var sec: VBoxContainer = section("Support %s" % app_name)
	var r: VBoxContainer = rows(sec)
	r.add_child(link("Rate %s" % app_name, "Enjoying it? A rating on Google Play helps a small studio a lot.", func() -> void:
		if not OVPlatform.open_store_page(package):
			notify.call("Could not open Google Play.")))
	r.add_child(divider())
	r.add_child(link("Share with a friend", "Send a link to %s." % app_name, func() -> void:
		var res: String = OVPlatform.share_text(share_message + " " + OVPlatform.store_url(package), "Share " + app_name)
		if res == "copied":
			notify.call("Link copied to the clipboard.")))
	r.add_child(divider())
	r.add_child(link("More from F7 Developer", "Our other origami apps on Google Play.", func() -> void:
		if not OVPlatform.open_url(OVPlatform.DEVELOPER_PAGE):
			notify.call("Could not open Google Play.")))
	return sec


## About card content: app name + version, maker line, credits, and privacy/licence rows.
static func about_section(app_name: String, tagline: String, credits: String, open_text: Callable) -> VBoxContainer:
	var sec: VBoxContainer = section("About")
	var r: VBoxContainer = rows(sec)
	var head: VBoxContainer = K.vbox(4)
	head.add_child(K.label("%s %s" % [app_name, OVPlatform.version()], "HeaderLabel", HORIZONTAL_ALIGNMENT_LEFT))
	var tl: Label = K.label(tagline, "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(tl)
	head.add_child(K.label("Made by F7 Developer with OrigamiVerse Core %s." % OVCore.VERSION, "", HORIZONTAL_ALIGNMENT_LEFT))
	(head.get_child(2) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_child(_wrap(head))
	r.add_child(divider())
	r.add_child(link("Privacy policy", "No accounts, no ads, no tracking. Everything stays on your device.", func() -> void:
		open_text.call("Privacy policy", PRIVACY_TEXT)))
	r.add_child(divider())
	r.add_child(link("Credits and licences", "Fonts, formats and open-source tools.", func() -> void:
		open_text.call("Credits and licences", credits)))
	return sec
