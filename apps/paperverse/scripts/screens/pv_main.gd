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
		_show_launch_sequence()
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
	for c in get_children():
		if c is OVOnboarding:
			var ob: OVOnboarding = c
			if ob.index > 0:
				ob.show_page(ob.index - 1)
			else:
				ob._finish()
			return
		if c is OVSplash:
			return
	if _overlay:
		_close_overlay()
	elif studio:
		if studio.has_overlay():
			studio.close_overlay()
		else:
			close_studio()
	elif home and home.has_meta("settings"):
		show_home()
	else:
		get_tree().quit()


# ------------------------------------------------------------ home


func show_home(scroll_to: int = 0) -> void:
	_clear_screen()
	home = Control.new()
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(home)
	var bg: ColorRect = ColorRect.new()
	bg.color = Studio.palette.bg
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.add_child(bg)
	var root: MarginContainer = K.screen_root()
	home.add_child(root)
	var outer: VBoxContainer = K.vbox(18)
	root.add_child(outer)
	var head: HBoxContainer = K.hbox(16)
	var title: Label = K.label("PaperVerse", "TitleLabel", HORIZONTAL_ALIGNMENT_LEFT)
	title.add_theme_font_size_override("font_size", int(K.s(92)))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var sb: Button = K.button("Settings", show_settings, "CardButton", 220)
	sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sb)
	outer.add_child(head)
	var scroll: ScrollContainer = K.scroll()
	outer.add_child(scroll)
	var v: VBoxContainer = K.vbox(28)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var sub: Label = K.label("Draw creases, watch them fold live in 3D, animate and export.", "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT)
	v.add_child(sub)
	var actions: HBoxContainer = K.hbox(16)
	var nb: Button = K.button("New sheet", func() -> void: open_project(_new_project(PVTemplates.by_id("blank"))))
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
	v.add_child(K.label("Tap a pattern to open it folded. Every crease stays editable.", "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT))
	var tg: GridContainer = GridContainer.new()
	tg.columns = 2
	tg.add_theme_constant_override("h_separation", int(K.s(18)))
	tg.add_theme_constant_override("v_separation", int(K.s(18)))
	for t in PVTemplates.all():
		if t.id == "blank":
			continue
		tg.add_child(_template_card(t))
	v.add_child(tg)
	var foot: Label = K.label("PaperVerse %s � F7 Developer � works offline" % OVPlatform.version(), "MutedLabel")
	v.add_child(K.spacer(10))
	v.add_child(foot)
	v.add_child(K.spacer(30))

	_toast = K.label("", "MutedLabel")
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_toast)
	K.fade_in(home)
	if scroll_to > 0:
		await get_tree().process_frame
		scroll.scroll_vertical = scroll_to


func _clear_screen() -> void:
	if home:
		home.queue_free()
		home = null


## New project from a template with the user's defaults applied.
func _new_project(t: Dictionary) -> PVProject:
	var p: PVProject = PVProject.from_template(t)
	p.show_assignment = bool(Studio.settings.default_colors)
	p.rigid = bool(Studio.settings.default_rigid)
	return p


# ------------------------------------------------------------ launch, onboarding


func _show_launch_sequence() -> void:
	var splash: OVSplash = OVSplash.new().setup(load("res://assets/splash/emblem.png"), "PaperVerse",
		"3D Origami Studio", Studio.palette, 0.9)
	splash.theme = Studio.theme
	add_child(splash)
	splash.finished.connect(func() -> void:
		if not bool(Studio.settings.seen_intro):
			show_onboarding())


func show_onboarding() -> void:
	var pages: Array[Dictionary] = [
		{"title": "Welcome to PaperVerse", "body": "A pocket origami studio. Design a crease pattern and watch real paper physics fold it in 3D.",
			"art": PVOnboardArt.new().setup("welcome")},
		{"title": "Draw creases", "body": "Pick Mountain or Valley and drag across the sheet. Lines snap to the grid, corners, midpoints and 22.5� angles.",
			"art": PVOnboardArt.new().setup("draw")},
		{"title": "Fold it live", "body": "Open the Fold tab and slide from flat to folded. Drag the 3D view to orbit, pinch to zoom, double-tap to recenter.",
			"art": PVOnboardArt.new().setup("fold")},
		{"title": "Animate", "body": "Set fold and spin keys on the timeline, choose an ease, and press Play. The paper refolds in real time.",
			"art": PVOnboardArt.new().setup("animate")},
		{"title": "Export anywhere", "body": "Save as FOLD for origami tools, GLB or OBJ for 3D apps, or a PNG snapshot. Projects stay on your device.",
			"art": PVOnboardArt.new().setup("export")},
	]
	var ob: OVOnboarding = OVOnboarding.new().setup(pages, Studio.palette, "Start folding")
	ob.theme = Studio.theme
	add_child(ob)
	ob.finished.connect(func() -> void: Studio.set_setting("seen_intro", true))


# ------------------------------------------------------------ settings


func show_settings(scroll_to: int = 0) -> void:
	var S = OVSettingsKit
	var st: Dictionary = Studio.settings
	_clear_screen()
	home = Control.new()
	home.set_meta("settings", true)
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(home)
	var bg: ColorRect = ColorRect.new()
	bg.color = Studio.palette.bg
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.add_child(bg)
	var root: MarginContainer = K.screen_root()
	home.add_child(root)
	var v: VBoxContainer = K.vbox(20)
	root.add_child(v)
	var head: HBoxContainer = K.hbox(24)
	head.add_child(K.button("Back", func() -> void: show_home(), "CardButton", 180))
	var hl: Label = K.label("Settings", "HeaderLabel", HORIZONTAL_ALIGNMENT_LEFT)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	v.add_child(head)
	var sc: ScrollContainer = K.scroll()
	v.add_child(sc)
	var list: VBoxContainer = K.vbox(30)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)

	var snd: VBoxContainer = S.section("Sound")
	S.rows(snd).add_child(S.slider("Ambience", float(st.music), func(x: float) -> void: Studio.set_setting("music", x)))
	S.rows(snd).add_child(S.slider("Sounds", float(st.sfx), func(x: float) -> void: Studio.set_setting("sfx", x)))
	S.rows(snd).add_child(S.switch("Vibration", "Short haptic taps on folds and buttons.", bool(st.haptics),
		func(on: bool) -> void: Studio.set_setting("haptics", on)))
	list.add_child(snd)

	var ed: VBoxContainer = S.section("Studio")
	var grids: PackedInt32Array = [4, 8, 16]
	S.rows(ed).add_child(S.choice("Crease grid", "Snap spacing on the crease canvas.", PackedStringArray(["4 � 4", "8 � 8", "16 � 16"]),
		maxi(0, grids.find(int(st.grid))), func(i: int) -> void: Studio.set_setting("grid", grids[i])))
	S.rows(ed).add_child(S.switch("Color creases in 3D", "New projects show mountains red and valleys blue on the folded paper.",
		bool(st.default_colors), func(on: bool) -> void: Studio.set_setting("default_colors", on)))
	S.rows(ed).add_child(S.switch("Start in rigid mode", "New projects fold flat panels on exact hinges when the pattern allows it.",
		bool(st.default_rigid), func(on: bool) -> void: Studio.set_setting("default_rigid", on)))
	list.add_child(ed)

	var gfx: VBoxContainer = S.section("Graphics and battery")
	S.rows(gfx).add_child(S.choice("3D quality", "Auto keeps folding smooth by adjusting 3D sharpness to your phone.",
		OVRenderQuality.MODE_NAMES, int(st.quality), func(i: int) -> void: Studio.set_setting("quality", i)))
	S.rows(gfx).add_child(S.switch("Battery saver", "Limit to 30 frames per second.", bool(st.battery_fps),
		func(on: bool) -> void: Studio.set_setting("battery_fps", on)))
	S.rows(gfx).add_child(S.switch("Show FPS", "Frame rate and render time in the corner.", bool(st.show_fps),
		func(on: bool) -> void: Studio.set_setting("show_fps", on)))
	list.add_child(gfx)

	var acc: VBoxContainer = S.section("Accessibility")
	S.rows(acc).add_child(S.choice("Text size", "", PackedStringArray(["Normal", "Large", "Extra large"]), int(st.text_size),
		func(i: int) -> void:
			Studio.set_setting("text_size", i)
			Studio.rebuild_theme()
			theme = Studio.theme
			show_settings(sc.scroll_vertical)))
	list.add_child(acc)

	var help: VBoxContainer = S.section("Help")
	S.rows(help).add_child(S.link("How PaperVerse works", "Replay the five-step introduction.", show_onboarding))
	S.rows(help).add_child(S.divider())
	S.rows(help).add_child(S.link("Gestures and tips", "Orbit, zoom, pin, snapping and solver modes.", func() -> void:
		_show_text_page("Gestures and tips", HELP_TEXT)))
	list.add_child(help)

	list.add_child(S.support_section("PaperVerse", Studio.PACKAGE,
		"Design origami crease patterns and fold them live in 3D with PaperVerse:", _notify))

	var data: VBoxContainer = S.section("Storage")
	var projects: Array[Dictionary] = PVProjectStore.list()
	S.rows(data).add_child(S.info("%d saved project%s on this device. Projects autosave while you work." % [projects.size(), "" if projects.size() == 1 else "s"]))
	if not projects.is_empty():
		S.rows(data).add_child(S.divider())
		S.rows(data).add_child(S.link("Delete all projects", "Templates stay available. This cannot be undone.", func() -> void:
			var cv: VBoxContainer = K.vbox(16)
			cv.add_child(K.label("Delete all %d projects?" % projects.size(), "HeaderLabel"))
			cv.add_child(K.label("Exported files are not affected.", "MutedLabel"))
			cv.add_child(K.button("Delete everything", func() -> void:
				for info in PVProjectStore.list():
					PVProjectStore.delete(str(info.id))
				_close_overlay()
				show_settings()))
			cv.add_child(K.button("Cancel", _close_overlay, "CardButton"))
			_open_overlay(cv), ""))
	list.add_child(data)

	list.add_child(S.about_section("PaperVerse", "3D Origami Studio. Draw crease patterns, fold them with real-time paper physics, animate and export.",
		"PaperVerse is built with Godot Engine (MIT) and OrigamiVerse Core.\n\nClassic patterns adapted from Origami Simulator examples by Amanda Ghassaei (MIT).\n\nFOLD file format by Erik Demaine, Jason Ku and Robert Lang.\n\nFont: Outfit by the Outfit Project Authors, SIL Open Font License 1.1.\n\nSounds are synthesized by the app.",
		_show_text_page))
	list.add_child(K.spacer(40))
	K.fade_in(home)
	if scroll_to > 0:
		await get_tree().process_frame
		sc.scroll_vertical = scroll_to


const HELP_TEXT: String = "3D view\n� Drag to orbit, pinch to zoom, twist with two fingers to turn.\n� Double-tap to recenter.\n\nCrease canvas\n� Mountain and Valley draw creases. Cut slits the paper. Guide adds a flat helper line.\n� Erase removes a crease, Flip swaps mountain and valley.\n� Lines snap to the grid, existing vertices, midpoints, intersections and 22.5� angles.\n� Pinch to zoom the canvas, drag with two fingers to pan, double-tap to fit.\n\nFold tab\n� Soft paper bends like real paper and works with any pattern.\n� Rigid hinges fold flat panels exactly when the creases form a tree.\n� Pin a face to choose which part of the paper stays still.\n\nAnimate tab\n� Move the playhead, then Key fold or Key spin to store the current pose.\n� New keys use the selected ease. Length +1 s extends the clip.\n\nExport\n� FOLD keeps the crease pattern and folded shape for other origami tools.\n� GLB and OBJ open in Blender and most 3D apps. PNG saves the current view."


func _show_text_page(title: String, text: String) -> void:
	var cv: VBoxContainer = K.vbox(20)
	cv.add_child(K.label(title, "HeaderLabel"))
	var sc: ScrollContainer = K.scroll()
	sc.custom_minimum_size.y = K.s(1000)
	var l: Label = K.label(text, "", HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(l)
	cv.add_child(sc)
	cv.add_child(K.button("Close", _close_overlay))
	_open_overlay(cv)


func _notify(text: String) -> void:
	var p: PanelContainer = PanelContainer.new()
	p.theme = Studio.theme
	p.add_theme_stylebox_override("panel", OVThemeFactory.box(Studio.palette.ink, int(K.s(26)), Color.TRANSPARENT, 0, 0.25, Vector2(K.s(30), K.s(20))))
	var l: Label = K.label(text, "")
	l.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(l)
	add_child(p)
	await get_tree().process_frame
	var vs: Vector2 = get_viewport_rect().size
	p.position = Vector2((vs.x - p.size.x) * 0.5, vs.y - p.size.y - K.s(220))
	p.modulate.a = 0.0
	var tw: Tween = p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)

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
	cv.add_child(K.button("Fold it", func() -> void: open_project(_new_project(tt))))
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
	_clear_screen()
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
