extends Control
## PaperVerse home: templates, saved projects, import. Opens PVStudio for editing.

const K = preload("res://addons/origamiverse_core/ui/ov_ui_kit.gd")

var studio: PVStudio
var home: Control
var _overlay: Control
var _toast: Label


func _ready() -> void:
	theme = Studio.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("template"):
		var p: PVProject = PVProject.from_template(PVTemplates.by_id(str(args.template)))
		open_project(p)
		if args.has("tab") and studio:
			studio._select_tab(str(args.tab))
	else:
		show_home()
	if args.has("capture"):
		_qa_capture(str(args.capture), float(args.get("delay", "3")))


func _qa_capture(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[qa] captured ", path)
	get_tree().quit()


func autosave() -> void:
	if studio:
		studio.autosave(true)


func go_back() -> void:
	if _overlay:
		_close_overlay()
	elif studio:
		if studio.has_overlay():
			studio.close_overlay()
		else:
			close_studio()
	else:
		get_tree().quit()


# ------------------------------------------------------------ home


func show_home() -> void:
	if home:
		home.queue_free()
	home = Control.new()
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(home)
	var bg: ColorRect = ColorRect.new()
	bg.color = Studio.palette.bg
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.add_child(bg)
	var root: MarginContainer = K.screen_root()
	home.add_child(root)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var v: VBoxContainer = K.vbox(26)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var title: Label = K.label("PaperVerse", "TitleLabel", HORIZONTAL_ALIGNMENT_LEFT)
	title.add_theme_font_size_override("font_size", int(K.s(96)))
	v.add_child(title)
	v.add_child(K.label("3D Origami Studio  ·  draw creases, fold them live, export anywhere", "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT))
	var actions: HBoxContainer = K.hbox(16)
	var nb: Button = K.button("New sheet", func() -> void: open_project(PVProject.from_template(PVTemplates.by_id("blank"))))
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(nb)
	var ib: Button = K.button("Import FOLD", _import, "CardButton")
	ib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(ib)
	v.add_child(actions)

	var projects: Array[Dictionary] = PVProjectStore.list()
	if not projects.is_empty():
		v.add_child(K.label("Your projects", "HeaderLabel", HORIZONTAL_ALIGNMENT_LEFT))
		var pg: GridContainer = GridContainer.new()
		pg.columns = 2
		pg.add_theme_constant_override("h_separation", int(K.s(18)))
		pg.add_theme_constant_override("v_separation", int(K.s(18)))
		for info in projects:
			pg.add_child(_project_card(info))
		v.add_child(pg)

	v.add_child(K.label("Templates", "HeaderLabel", HORIZONTAL_ALIGNMENT_LEFT))
	var tg: GridContainer = GridContainer.new()
	tg.columns = 2
	tg.add_theme_constant_override("h_separation", int(K.s(18)))
	tg.add_theme_constant_override("v_separation", int(K.s(18)))
	for t in PVTemplates.all():
		if t.id == "blank":
			continue
		tg.add_child(_template_card(t))
	v.add_child(tg)

	var about: PanelContainer = PanelContainer.new()
	var av: VBoxContainer = K.vbox(10)
	av.add_child(K.label("About", "HeaderLabel", HORIZONTAL_ALIGNMENT_LEFT))
	av.add_child(K.label("PaperVerse %s by F7 Developer, built on OrigamiVerse Core. Works offline; projects stay on this device. No accounts, no ads, no data collection." % ProjectSettings.get_setting("application/config/version"), "", HORIZONTAL_ALIGNMENT_LEFT))
	av.add_child(K.label("Classic patterns adapted from Origami Simulator examples by Amanda Ghassaei (MIT). FOLD format by Erik Demaine et al. Font: Outfit (OFL).", "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT))
	for key in ["music", "sfx"]:
		var h: HBoxContainer = K.hbox(16)
		var l: Label = K.label("Ambience" if key == "music" else "Sounds", "", HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size.x = K.s(200)
		h.add_child(l)
		var sl: HSlider = HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Studio.settings[key])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size.y = K.s(56)
		var k2: String = key
		sl.value_changed.connect(func(val: float) -> void: Studio.set_setting(k2, val))
		h.add_child(sl)
		av.add_child(h)
	var hp: CheckButton = CheckButton.new()
	hp.text = "Vibration"
	hp.button_pressed = bool(Studio.settings.haptics)
	hp.focus_mode = Control.FOCUS_NONE
	hp.toggled.connect(func(on: bool) -> void: Studio.set_setting("haptics", on))
	av.add_child(hp)
	about.add_child(av)
	v.add_child(about)

	_toast = K.label("", "MutedLabel")
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_toast)
	K.fade_in(home)


func _template_card(t: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv: VBoxContainer = K.vbox(8)
	card.add_child(cv)
	var prev: PVPatternPreview = PVPatternPreview.new().setup(PVTemplates.make_pattern(t), K.s(300))
	prev.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cv.add_child(prev)
	cv.add_child(K.label(t.title, "HeaderLabel"))
	var d: Label = K.label(t.description, "MutedLabel")
	d.custom_minimum_size.x = K.s(380)
	cv.add_child(d)
	var tt: Dictionary = t
	cv.add_child(K.button("Fold it", func() -> void: open_project(PVProject.from_template(tt))))
	return card


func _project_card(info: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv: VBoxContainer = K.vbox(8)
	card.add_child(cv)
	var thumb_path: String = PVProjectStore.thumb_for(info.id)
	var tr: TextureRect = TextureRect.new()
	tr.custom_minimum_size = Vector2(K.s(300), K.s(300))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if FileAccess.file_exists(thumb_path):
		var img: Image = Image.load_from_file(thumb_path)
		if img:
			tr.texture = ImageTexture.create_from_image(img)
	cv.add_child(tr)
	cv.add_child(K.label(info.name, "HeaderLabel"))
	cv.add_child(K.label(Time.get_datetime_string_from_unix_time(int(info.modified), true).substr(0, 16), "MutedLabel"))
	var row: HBoxContainer = K.hbox(10)
	var id: String = info.id
	var ob: Button = K.button("Open", func() -> void:
		var r: Dictionary = PVProjectStore.load_project(id)
		if r.ok:
			open_project(r.value)
		else:
			_show_toast(str(r.errors[0])))
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ob)
	row.add_child(K.button("More", func() -> void: _project_menu(info), "CardButton", 140))
	cv.add_child(row)
	return card


func _project_menu(info: Dictionary) -> void:
	var v: VBoxContainer = K.vbox(16)
	v.add_child(K.label(info.name, "HeaderLabel"))
	var id: String = info.id
	v.add_child(K.button("Duplicate", func() -> void:
		PVProjectStore.duplicate_project(id)
		_close_overlay()
		show_home(), "CardButton"))
	v.add_child(K.button("Delete", func() -> void:
		var cv: VBoxContainer = K.vbox(16)
		cv.add_child(K.label("Delete \"%s\"?" % info.name, "HeaderLabel"))
		cv.add_child(K.label("This cannot be undone.", "MutedLabel"))
		cv.add_child(K.button("Delete project", func() -> void:
			PVProjectStore.delete(id)
			_close_overlay()
			show_home()))
		cv.add_child(K.button("Cancel", _close_overlay, "CardButton"))
		_open_overlay(cv), "CardButton"))
	v.add_child(K.button("Close", _close_overlay))
	_open_overlay(v)


func _import() -> void:
	if not Studio.has_native_dialogs():
		_show_toast("This device has no file picker available.")
		return
	Studio.open_text(PackedStringArray(["*.fold,*.json;FOLD origami"]), func(text: String, name: String) -> void:
		if text == "":
			return
		var r: Dictionary = PVProject.from_fold_text(text, name)
		if not r.ok:
			_show_toast("Could not import: " + str(r.errors[0]))
			return
		var p: PVProject = r.value
		PVProjectStore.save(p)
		open_project(p))


func _show_toast(text: String) -> void:
	if _toast:
		_toast.text = text


func _open_overlay(content: Control) -> void:
	_close_overlay()
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.08, 0.08, 0.15, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size.x = K.s(780)
	card.add_child(K.margin(content, 16, 16, 16, 16))
	center.add_child(card)
	add_child(root)
	_overlay = root
	K.fade_in(root)


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


# ------------------------------------------------------------ studio


func open_project(p: PVProject) -> void:
	if home:
		home.queue_free()
		home = null
	studio = PVStudio.new()
	add_child(studio)
	studio.open(p)
	studio.exit_requested.connect(close_studio)
	Studio.audio.play("whoosh", 1.1, -4.0)


func close_studio() -> void:
	if studio:
		studio.autosave(true)
		studio.queue_free()
		studio = null
	show_home()
