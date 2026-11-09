extends Node
## FoldShift scene flow and screens. The 3D world is a live FSWorld even behind menus.

const K = preload("res://scripts/ui/fs_ui_kit.gd")

var world_slot: Node3D
var ui: CanvasLayer
var overlay_layer: CanvasLayer
var world: FSWorld
var screen: Control
var screen_name: String = ""
var backdrop_level: String = ""
var current_level: String = ""
var used_undo: bool = false
var selected_chapter: int = 1

var _hud_title: Label
var _hud_folds: Label
var _hud_cranes: Label
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _overlay: Control
var _menu_orbit: bool = false


func _ready() -> void:
	world_slot = Node3D.new()
	add_child(world_slot)
	ui = CanvasLayer.new()
	ui.layer = 1
	add_child(ui)
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 5
	add_child(overlay_layer)
	Game.achievement_unlocked.connect(_on_achievement)
	# QA hooks (desktop): --level=<id> opens a level, --capture=<png> --delay=<s> saves a screenshot and quits.
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("level"):
		play_level(str(args.level))
	elif args.has("screen"):
		match str(args.screen):
			"chapters": show_chapters()
			"levels": show_levels(int(args.get("chapter", "1")))
			"settings": show_settings()
			"achievements": show_achievements()
			_: show_title()
	else:
		show_title()
	if args.has("capture"):
		_qa_capture(str(args.capture), float(args.get("delay", "3")))


func _qa_capture(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[qa] captured ", path)
	get_tree().quit()


func _process(dt: float) -> void:
	if _menu_orbit and world and world.rig:
		world.rig.yaw.target += dt * 6.0


# ------------------------------------------------------------ world management


func _load_world(level_id: String, interactive: bool, saved: Dictionary = {}) -> bool:
	if world:
		world.queue_free()
		world = null
	var L: FSLevelData = Game.level_data(level_id)
	if L == null:
		return false
	var p: FSPuzzle = FSPuzzle.new()
	var r: Dictionary = p.setup(L)
	if not r.ok:
		push_error(str(r.errors))
		return false
	world = FSWorld.new()
	world.input_enabled = interactive
	world.reduce_motion = bool(Game.data.settings.reduce_motion)
	world_slot.add_child(world)
	world.build(p, FSCatalog.chapter(L.chapter).preset, saved)
	Game.audio.set_ambience(FSCatalog.chapter(L.chapter).mood)
	return true


func _ensure_backdrop(level_id: String) -> void:
	if backdrop_level == level_id and world and not world.input_enabled:
		return
	backdrop_level = level_id
	_load_world(level_id, false)
	_menu_orbit = true


func _set_screen(c: Control, name: String) -> void:
	if screen:
		screen.queue_free()
	_close_overlay()
	screen = c
	screen_name = name
	c.theme = Game.theme
	ui.add_child(c)
	K.fade_in(c)


func _readability_gradient(top_alpha: float, bottom_alpha: float) -> TextureRect:
	var g: Gradient = Gradient.new()
	var bg: Color = Game.palette.bg
	g.set_color(0, Color(bg, top_alpha))
	g.set_color(1, Color(bg, bottom_alpha))
	g.add_point(0.2, Color(bg, 0.0))
	g.add_point(0.68, Color(bg, 0.0))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	var tr: TextureRect = TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


# ------------------------------------------------------------ title


func show_title() -> void:
	_ensure_backdrop(FSCatalog.LEVEL_IDS[0])
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_readability_gradient(0.92, 0.95))
	var m: MarginContainer = K.screen_root()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m)
	var v: VBoxContainer = K.vbox(26)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	v.add_child(K.spacer(120))
	var title: Label = K.label("FoldShift", "TitleLabel")
	title.add_theme_font_size_override("font_size", int(K.s(124)))
	v.add_child(title)
	v.add_child(K.label("Origami Puzzle Adventure", "MutedLabel"))
	v.add_child(K.expand_spacer())
	var col: VBoxContainer = K.vbox(22)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.custom_minimum_size.x = K.s(620)
	v.add_child(col)
	var resume: Dictionary = Game.data.resume
	if not resume.is_empty() and Game.level_data(str(resume.get("level", ""))) != null:
		var L: FSLevelData = Game.level_data(resume.level)
		col.add_child(K.button("Continue  %d-%d" % [L.chapter, L.index], func() -> void:
			play_level(resume.level, resume.get("state", {}), bool(resume.get("undo", false)))))
		col.add_child(K.button("Chapters", show_chapters, "CardButton"))
	else:
		col.add_child(K.button("Play", show_chapters))
	var row: HBoxContainer = K.hbox(20)
	var ach: Button = K.button("Achievements", show_achievements, "CardButton")
	ach.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st: Button = K.button("Settings", show_settings, "CardButton")
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ach)
	row.add_child(st)
	col.add_child(row)
	v.add_child(K.spacer(40))
	var stars: Label = K.label("%d / %d stars" % [Game.total_stars(), FSCatalog.LEVEL_IDS.size() * 3], "MutedLabel")
	v.add_child(stars)
	v.add_child(K.label("F7 Developer", "MutedLabel"))
	_set_screen(root, "title")


# ------------------------------------------------------------ chapters and levels


func _header(text: String, back: Callable) -> HBoxContainer:
	var h: HBoxContainer = K.hbox(24)
	var b: Button = K.button("Back", back, "CardButton", 180)
	h.add_child(b)
	var l: Label = K.label(text, "HeaderLabel", HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


func show_chapters() -> void:
	_ensure_backdrop(FSCatalog.levels_in_chapter(selected_chapter)[0])
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_readability_gradient(0.95, 0.9))
	var m: MarginContainer = K.screen_root()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m)
	var v: VBoxContainer = K.vbox(28)
	m.add_child(v)
	v.add_child(_header("Chapters", show_title))
	v.add_child(K.expand_spacer())
	for ch in FSCatalog.CHAPTERS:
		var unlocked: bool = Game.is_chapter_unlocked(ch.id)
		var st: Dictionary = Game.chapter_stats(ch.id)
		var card: PanelContainer = K.card()
		var cv: VBoxContainer = K.vbox(10)
		card.add_child(cv)
		var t: Label = K.label("%d · %s" % [ch.id, ch.title], "HeaderLabel", HORIZONTAL_ALIGNMENT_LEFT)
		cv.add_child(t)
		cv.add_child(K.label(ch.subtitle if unlocked else "Clear the previous chapter to unlock.", "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT))
		if unlocked:
			cv.add_child(K.label("%d/%d levels   ·   %d/%d stars   ·   %d/%d cranes" % [st.done, st.count, st.stars, st.max_stars, st.cranes, st.crane_total], "", HORIZONTAL_ALIGNMENT_LEFT))
			var id: int = ch.id
			var b: Button = K.button("Open", func() -> void:
				selected_chapter = id
				show_levels(id))
			cv.add_child(b)
		else:
			card.modulate = Color(1, 1, 1, 0.65)
		v.add_child(card)
	v.add_child(K.expand_spacer())
	_set_screen(root, "chapters")


func show_levels(chapter: int) -> void:
	selected_chapter = chapter
	var ids: PackedStringArray = FSCatalog.levels_in_chapter(chapter)
	_ensure_backdrop(ids[0])
	var ch: Dictionary = FSCatalog.chapter(chapter)
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_readability_gradient(0.95, 0.9))
	var m: MarginContainer = K.screen_root()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m)
	var v: VBoxContainer = K.vbox(22)
	m.add_child(v)
	v.add_child(_header(ch.title, show_chapters))
	v.add_child(K.expand_spacer())
	for id in ids:
		var L: FSLevelData = Game.level_data(id)
		var rec: Dictionary = Game.level_record(id)
		var unlocked: bool = Game.is_level_unlocked(id)
		var card: PanelContainer = K.card()
		var h: HBoxContainer = K.hbox(24)
		card.add_child(h)
		var num: Label = K.label("%d-%d" % [L.chapter, L.index], "HeaderLabel")
		num.custom_minimum_size.x = K.s(120)
		h.add_child(num)
		var info: VBoxContainer = K.vbox(4)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(K.label(L.title, "", HORIZONTAL_ALIGNMENT_LEFT))
		var got: int = 0
		for c in rec.get("cranes", []):
			got += 1 if c else 0
		var sub: String = "Par %d" % L.par
		if rec.get("done", false):
			sub += "  ·  best %d" % int(rec.best)
		if L.cranes.size() > 0:
			sub += "  ·  cranes %d/%d" % [got, L.cranes.size()]
		info.add_child(K.label(sub if unlocked else "Locked", "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT))
		h.add_child(info)
		var stars: FSStarRow = FSStarRow.new().setup(int(rec.get("stars", 0)), K.s(40))
		stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(stars)
		if unlocked:
			var lid: String = id
			var b: Button = K.button("Play", func() -> void: play_level(lid), "", 170)
			h.add_child(b)
		else:
			card.modulate = Color(1, 1, 1, 0.6)
		v.add_child(card)
	v.add_child(K.expand_spacer())
	_set_screen(root, "levels")


# ------------------------------------------------------------ gameplay


func play_level(id: String, saved: Dictionary = {}, undo_used: bool = false) -> void:
	_menu_orbit = false
	backdrop_level = ""
	current_level = id
	used_undo = undo_used
	if not _load_world(id, true, saved):
		show_levels(selected_chapter)
		return
	var L: FSLevelData = world.puzzle.level
	selected_chapter = L.chapter
	world.toast.connect(show_toast)
	world.state_changed.connect(_update_hud)
	world.won.connect(_on_won)
	world.folded.connect(func(_f: String) -> void: Game.add_stat("folds"))
	world.seal_broken.connect(func(_i: int) -> void: Game.unlock("seal_breaker"))
	world.walked_on_wall.connect(func() -> void: Game.unlock("wall_walker"))
	world.crane_collected.connect(_on_crane)
	_build_hud(L)
	if saved.is_empty():
		get_tree().create_timer(2.3).timeout.connect(func() -> void:
			if is_instance_valid(world) and current_level == id:
				show_toast(L.hint, 5.0))


func _build_hud(L: FSLevelData) -> void:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m: MarginContainer = K.screen_root()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m)
	var v: VBoxContainer = K.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var top: HBoxContainer = K.hbox(18)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	top.add_child(K.button("Menu", show_pause, "CardButton", 170))
	var tv: VBoxContainer = K.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_title = K.label("%d-%d  %s" % [L.chapter, L.index, L.title], "HudLabel")
	_hud_folds = K.label("", "HudLabel")
	_hud_folds.add_theme_font_size_override("font_size", int(K.s(26)))
	tv.add_child(_hud_title)
	tv.add_child(_hud_folds)
	top.add_child(tv)
	_hud_cranes = K.label("", "HudLabel")
	_hud_cranes.custom_minimum_size.x = K.s(170)
	top.add_child(_hud_cranes)
	var mid: Control = K.expand_spacer()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mid)
	_toast_panel = PanelContainer.new()
	_toast_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label = K.label("")
	_toast_label.custom_minimum_size.x = K.s(760)
	_toast_panel.add_child(_toast_label)
	_toast_panel.modulate.a = 0.0
	v.add_child(_toast_panel)
	v.add_child(K.spacer(24))
	var bottom: HBoxContainer = K.hbox(18)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(K.button("Undo", _on_undo, "CardButton", 220))
	bottom.add_child(K.button("Hint", func() -> void: show_toast(L.hint, 5.0), "CardButton", 220))
	bottom.add_child(K.button("Restart", restart_level, "CardButton", 220))
	v.add_child(bottom)
	_set_screen(root, "hud")
	_update_hud()


func _update_hud() -> void:
	if world == null or _hud_folds == null or not is_instance_valid(_hud_folds):
		return
	var p: FSPuzzle = world.puzzle
	_hud_folds.text = "Folds %d   ·   Par %d" % [p.folds, p.level.par]
	_hud_cranes.text = "Cranes %d/%d" % [p.cranes_collected(), p.level.cranes.size()] if p.level.cranes.size() > 0 else ""


func show_toast(text: String, seconds: float = 2.6) -> void:
	if _toast_panel == null or not is_instance_valid(_toast_panel) or text == "":
		return
	_toast_label.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.4)


func _on_undo() -> void:
	if world and world.undo_last():
		used_undo = true
	else:
		show_toast("Nothing to undo.")


func _on_crane(i: int) -> void:
	_update_hud()
	Game.add_stat("cranes")
	if world.puzzle.level.cranes[i].side == 1:
		Game.unlock("secret_keeper")


func restart_level() -> void:
	_close_overlay()
	play_level(current_level)


func _on_won() -> void:
	var p: FSPuzzle = world.puzzle
	var res: Dictionary = Game.record_clear(current_level, p.folds, p.collected, used_undo)
	_show_complete(p, res)


func capture_resume() -> void:
	if screen_name == "hud" and world and world.mode != FSWorld.Mode.DONE and current_level != "":
		Game.data.resume = {"level": current_level, "state": world.puzzle.snapshot(), "undo": used_undo}


func go_back() -> void:
	if _overlay:
		if screen_name == "hud":
			_close_overlay()
			world.input_enabled = true
		else:
			_close_overlay()
		return
	match screen_name:
		"hud": show_pause()
		"levels": show_chapters()
		"chapters", "settings", "achievements": show_title()
		"title":
			Game.save()
			get_tree().quit()


# ------------------------------------------------------------ overlays


func _open_overlay(card_content: Control) -> void:
	_close_overlay()
	var root: Control = Control.new()
	root.theme = Game.theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.15, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card: PanelContainer = K.card()
	card.custom_minimum_size.x = K.s(820)
	card.add_child(K.margin(card_content, 20, 20, 20, 20))
	center.add_child(card)
	ui.add_child(root)
	_overlay = root
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.92, 0.92)
	var tw: Tween = card.create_tween()
	tw.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	K.fade_in(root)


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func show_pause() -> void:
	if world == null:
		return
	world.input_enabled = false
	var v: VBoxContainer = K.vbox(22)
	v.add_child(K.label("Paused", "HeaderLabel"))
	v.add_child(K.label(world.puzzle.level.hint, "MutedLabel"))
	v.add_child(K.spacer(10))
	v.add_child(K.button("Resume", func() -> void:
		_close_overlay()
		world.input_enabled = true))
	v.add_child(K.button("Restart level", restart_level, "CardButton"))
	v.add_child(K.button("Level select", func() -> void:
		capture_resume()
		Game.save()
		show_levels(selected_chapter), "CardButton"))
	v.add_child(_settings_rows())
	_open_overlay(v)


func _show_complete(p: FSPuzzle, res: Dictionary) -> void:
	world.input_enabled = false
	var v: VBoxContainer = K.vbox(20)
	v.add_child(K.label("Level clear!", "TitleLabel"))
	var stars: FSStarRow = FSStarRow.new().setup(res.stars, K.s(96), true)
	stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(stars)
	v.add_child(K.label("Folds %d  ·  Par %d" % [p.folds, p.level.par], "HeaderLabel"))
	if p.level.cranes.size() > 0:
		v.add_child(K.label("Paper cranes %d / %d" % [p.cranes_collected(), p.level.cranes.size()], ""))
	if res.stars < 3:
		v.add_child(K.label("Reach the lantern in %d folds for 3 stars." % p.level.par, "MutedLabel"))
	elif res.new_best:
		v.add_child(K.label("New best!", "MutedLabel"))
	v.add_child(K.spacer(8))
	var next_id: String = FSCatalog.next_level(current_level)
	if next_id != "" and Game.is_level_unlocked(next_id):
		v.add_child(K.button("Next level", func() -> void: play_level(next_id)))
	elif next_id == "":
		v.add_child(K.label("You folded every world. Thank you for playing!", ""))
	v.add_child(K.button("Replay", restart_level, "CardButton"))
	v.add_child(K.button("Level select", func() -> void: show_levels(selected_chapter), "CardButton"))
	_open_overlay(v)


func _settings_rows() -> VBoxContainer:
	var v: VBoxContainer = K.vbox(14)
	for key in ["music", "sfx"]:
		var h: HBoxContainer = K.hbox(18)
		var l: Label = K.label("Music" if key == "music" else "Sound", "", HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size.x = K.s(170)
		h.add_child(l)
		var sl: HSlider = HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Game.data.settings[key])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size.y = K.s(56)
		var k: String = key
		sl.value_changed.connect(func(val: float) -> void: Game.set_setting(k, val))
		h.add_child(sl)
		v.add_child(h)
	for pair in [["haptics", "Vibration"], ["reduce_motion", "Reduce motion"]]:
		var cb: CheckButton = CheckButton.new()
		cb.text = pair[1]
		cb.button_pressed = bool(Game.data.settings[pair[0]])
		cb.focus_mode = Control.FOCUS_NONE
		var k2: String = pair[0]
		cb.toggled.connect(func(on: bool) -> void:
			Game.set_setting(k2, on)
			if world:
				world.reduce_motion = bool(Game.data.settings.reduce_motion))
		v.add_child(cb)
	return v


# ------------------------------------------------------------ settings and achievements


func show_settings() -> void:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_readability_gradient(0.96, 0.96))
	var m: MarginContainer = K.screen_root()
	root.add_child(m)
	var v: VBoxContainer = K.vbox(26)
	m.add_child(v)
	v.add_child(_header("Settings", show_title))
	var card: PanelContainer = K.card()
	card.add_child(_settings_rows())
	v.add_child(card)
	var reset_btn: Button = K.button("Reset progress", func() -> void:
		var cv: VBoxContainer = K.vbox(20)
		cv.add_child(K.label("Reset all progress?", "HeaderLabel"))
		cv.add_child(K.label("Stars, cranes and achievements will be erased. Settings are kept.", "MutedLabel"))
		cv.add_child(K.button("Erase progress", func() -> void:
			Game.reset_progress()
			_close_overlay()
			show_title()))
		cv.add_child(K.button("Cancel", _close_overlay, "CardButton"))
		_open_overlay(cv), "CardButton")
	v.add_child(reset_btn)
	v.add_child(K.expand_spacer())
	var about: PanelContainer = K.card()
	var av: VBoxContainer = K.vbox(8)
	av.add_child(K.label("FoldShift %s" % ProjectSettings.get_setting("application/config/version"), "HeaderLabel"))
	av.add_child(K.label("Made by F7 Developer with OrigamiVerse Core.", ""))
	av.add_child(K.label("Privacy: FoldShift works fully offline and collects no personal data. Your progress is stored only on this device.", "MutedLabel"))
	av.add_child(K.label("Font: Outfit (SIL Open Font License). Sounds and 3D models are generated by the app and its open-source pipeline.", "MutedLabel"))
	about.add_child(av)
	v.add_child(about)
	_set_screen(root, "settings")


func show_achievements() -> void:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_readability_gradient(0.96, 0.96))
	var m: MarginContainer = K.screen_root()
	root.add_child(m)
	var v: VBoxContainer = K.vbox(20)
	m.add_child(v)
	v.add_child(_header("Achievements  %d/%d" % [Game.data.achievements.size(), Game.ACHIEVEMENTS.size()], show_title))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list: VBoxContainer = K.vbox(16)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for a in Game.ACHIEVEMENTS:
		var got: bool = Game.data.achievements.has(a.id)
		var card: PanelContainer = K.card()
		var cv: VBoxContainer = K.vbox(4)
		cv.add_child(K.label(a.title, "HeaderLabel" if got else "", HORIZONTAL_ALIGNMENT_LEFT))
		var when: String = ""
		if got:
			when = "  ·  " + Time.get_date_string_from_unix_time(int(Game.data.achievements[a.id]))
		cv.add_child(K.label(a.desc + when, "MutedLabel", HORIZONTAL_ALIGNMENT_LEFT))
		card.add_child(cv)
		if not got:
			card.modulate = Color(1, 1, 1, 0.55)
		list.add_child(card)
	_set_screen(root, "achievements")


func _on_achievement(id: String) -> void:
	var a: Dictionary = Game.achievement(id)
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = Game.theme
	var v: VBoxContainer = K.vbox(2)
	v.add_child(K.label("Achievement unlocked", "MutedLabel"))
	v.add_child(K.label(a.get("title", id), "HeaderLabel"))
	panel.add_child(v)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	overlay_layer.add_child(panel)
	await get_tree().process_frame
	panel.position = Vector2((get_viewport().get_visible_rect().size.x - panel.size.x) * 0.5, -panel.size.y)
	Game.audio.play("unlock", 1.2, -4.0)
	var tw: Tween = panel.create_tween()
	tw.tween_property(panel, "position:y", K.s(150), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.4)
	tw.tween_property(panel, "position:y", -panel.size.y - 20, 0.3)
	tw.tween_callback(panel.queue_free)
