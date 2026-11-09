class_name PVStudio
extends Control
## The PaperVerse editor: live 3D fold view on top, tabbed tools below. Every edit goes through OVUndoStack.

signal exit_requested

const K = preload("res://addons/origamiverse_core/ui/ov_ui_kit.gd")

var project: PVProject
var undo: OVUndoStack = OVUndoStack.new()
var view: PVFoldView
var viewport: SubViewport
var canvas: PVCreaseCanvas
var strip: PVTimelineStrip

var _status: Label
var _name_label: Button
var _undo_btn: Button
var _redo_btn: Button
var _tab_host: PanelContainer
var _tabs: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _fold_slider: HSlider
var _fold_label: Label
var _spin_slider: HSlider
var _play_btn: Button
var _time_label: Label
var _stats_label: Label
var _mode_soft: Button
var _mode_rigid: Button
var _pin_btn: Button
var _assign_toggle: CheckButton
var _front_picker: ColorPickerButton
var _back_picker: ColorPickerButton
var _tool_buttons: Dictionary = {}
var _grid_buttons: Dictionary = {}
var _ease_option: OptionButton
var _loop: bool = true

var _playing: bool = false
var _time: float = 0.0
var _dirty: bool = false
var _autosave_timer: float = 0.0
var _pin_mode: bool = false
var _view_gestures: OVGestureTracker
var _overlay: Control
var _status_tween: Tween


func open(p: PVProject) -> void:
	project = p
	theme = Studio.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	undo.changed.connect(_refresh_undo)
	_rebuild_model()
	_sync_material_ui()
	_refresh_undo()
	_select_tab("crease")


# ------------------------------------------------------------ layout


func _build_ui() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Studio.palette.bg
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: MarginContainer = K.screen_root()
	root.add_theme_constant_override("margin_left", int(K.s(20)))
	root.add_theme_constant_override("margin_right", int(K.s(20)))
	add_child(root)
	var v: VBoxContainer = K.vbox(12)
	root.add_child(v)

	var top: HBoxContainer = K.hbox(12)
	top.add_child(K.button("Home", func() -> void: exit_requested.emit(), "CardButton", 150))
	_name_label = K.button(project.name, _rename_dialog, "CardButton")
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	top.add_child(_name_label)
	_undo_btn = K.button("Undo", func() -> void: undo.undo(), "CardButton", 130)
	_redo_btn = K.button("Redo", func() -> void: undo.redo(), "CardButton", 130)
	top.add_child(_undo_btn)
	top.add_child(_redo_btn)
	top.add_child(K.button("Export", _export_dialog, "", 160))
	v.add_child(top)

	var svc: SubViewportContainer = SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.size_flags_stretch_ratio = 1.0
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	svc.add_child(viewport)
	view = PVFoldView.new()
	viewport.add_child(view)
	view.stats_changed.connect(func(t: String) -> void:
		if _stats_label:
			_stats_label.text = t)
	_view_gestures = OVGestureTracker.new()
	add_child(_view_gestures)
	svc.gui_input.connect(func(e: InputEvent) -> void:
		if _view_gestures.handle(e):
			svc.accept_event())
	_view_gestures.dragged.connect(func(_p: Vector2, rel: Vector2) -> void: view.camera_rig.orbit(rel))
	_view_gestures.pinched.connect(func(f: float, _c: Vector2) -> void: view.camera_rig.zoom(f))
	_view_gestures.twisted.connect(func(r: float, _c: Vector2) -> void: view.camera_rig.twist(r))
	_view_gestures.double_tap.connect(func(_p: Vector2) -> void: view.camera_rig.recenter())
	_view_gestures.tap.connect(_on_view_tap)
	var frame: PanelContainer = PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", OVThemeFactory.box(Color("efece6"), int(K.s(28)), Color.TRANSPARENT, 0, 0.12, Vector2.ZERO))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	frame.add_child(svc)
	v.add_child(frame)

	_status = K.label("", "MutedLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = K.s(34)
	v.add_child(_status)

	_tab_host = PanelContainer.new()
	_tab_host.custom_minimum_size.y = K.s(840)
	v.add_child(_tab_host)
	_tabs["crease"] = _build_crease_tab()
	_tabs["fold"] = _build_fold_tab()
	_tabs["animate"] = _build_animate_tab()
	_tabs["paper"] = _build_paper_tab()
	for k in _tabs.keys():
		_tab_host.add_child(_tabs[k])

	var bar: HBoxContainer = K.hbox(10)
	for pair in [["crease", "Crease"], ["fold", "Fold"], ["animate", "Animate"], ["paper", "Paper"]]:
		var b: Button = K.button(pair[1], _select_tab.bind(pair[0]), "ChipButton")
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(b)
		_tab_buttons[pair[0]] = b
	v.add_child(bar)


func _select_tab(id: String) -> void:
	for k in _tabs.keys():
		_tabs[k].visible = k == id
		_tab_buttons[k].set_pressed_no_signal(k == id)
	if id != "fold" and _pin_mode:
		_set_pin_mode(false)


func _chip(text: String, cb: Callable, group: ButtonGroup = null) -> Button:
	var b: Button = K.button(text, cb, "ChipButton")
	b.toggle_mode = true
	b.custom_minimum_size.y = K.s(76)
	if group:
		b.button_group = group
	return b


func _build_crease_tab() -> Control:
	var v: VBoxContainer = K.vbox(12)
	var tools: HBoxContainer = K.hbox(8)
	var group: ButtonGroup = ButtonGroup.new()
	for pair in [[PVCreaseCanvas.Tool.MOUNTAIN, "Mountain"], [PVCreaseCanvas.Tool.VALLEY, "Valley"], [PVCreaseCanvas.Tool.CUT, "Cut"],
			[PVCreaseCanvas.Tool.FLAT, "Guide"], [PVCreaseCanvas.Tool.ERASE, "Erase"], [PVCreaseCanvas.Tool.FLIP, "Flip"]]:
		var t: int = pair[0]
		var b: Button = _chip(pair[1], func() -> void: canvas.tool = t, group)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", int(K.s(21)))
		tools.add_child(b)
		_tool_buttons[t] = b
	v.add_child(tools)
	canvas = PVCreaseCanvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.set_pattern(project.pattern)
	canvas.grid = int(Studio.settings.grid)
	canvas.tool = PVCreaseCanvas.Tool.VALLEY
	_tool_buttons[PVCreaseCanvas.Tool.VALLEY].set_pressed_no_signal(true)
	canvas.add_requested.connect(_on_add_segment)
	canvas.erase_requested.connect(_on_erase_segment)
	canvas.flip_requested.connect(_on_flip_segment)
	canvas.message.connect(show_status)
	v.add_child(canvas)
	var row: HBoxContainer = K.hbox(8)
	var ggroup: ButtonGroup = ButtonGroup.new()
	var grid_label: Label = K.label("Grid", "MutedLabel")
	grid_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(grid_label)
	for n in [4, 8, 16]:
		var gn: int = n
		var b2: Button = _chip(str(n), func() -> void:
			canvas.grid = gn
			canvas.queue_redraw()
			Studio.set_setting("grid", gn), ggroup)
		b2.set_pressed_no_signal(gn == canvas.grid)
		row.add_child(b2)
		_grid_buttons[n] = b2
	var sp: Control = K.expand_spacer()
	row.add_child(sp)
	row.add_child(K.button("Fit", func() -> void: canvas.reset_view(), "CardButton", 120))
	row.add_child(K.button("Clear", _on_clear, "CardButton", 140))
	v.add_child(row)
	return v


func _build_fold_tab() -> Control:
	var v: VBoxContainer = K.vbox(22)
	v.add_child(K.spacer(6))
	var h: HBoxContainer = K.hbox(16)
	h.add_child(K.label("Fold", "HeaderLabel"))
	_fold_slider = HSlider.new()
	_fold_slider.min_value = 0.0
	_fold_slider.max_value = 1.0
	_fold_slider.step = 0.005
	_fold_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fold_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fold_slider.custom_minimum_size.y = K.s(64)
	_fold_slider.value = project.fold_percent
	_fold_slider.value_changed.connect(func(val: float) -> void:
		project.fold_percent = val
		view.set_fold(val)
		_fold_label.text = "%d%%" % roundi(val * 100.0)
		_mark_dirty())
	h.add_child(_fold_slider)
	_fold_label = K.label("%d%%" % roundi(project.fold_percent * 100.0), "HeaderLabel")
	_fold_label.custom_minimum_size.x = K.s(110)
	h.add_child(_fold_label)
	v.add_child(h)
	var presets: HBoxContainer = K.hbox(10)
	for pct in [0, 25, 50, 75, 100]:
		var pv: float = pct / 100.0
		var b: Button = K.button("%d%%" % pct, func() -> void: _fold_slider.value = pv, "CardButton")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		presets.add_child(b)
	v.add_child(presets)
	var modes: HBoxContainer = K.hbox(10)
	var solver_label: Label = K.label("Solver", "MutedLabel")
	solver_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	modes.add_child(solver_label)
	var mg: ButtonGroup = ButtonGroup.new()
	_mode_soft = _chip("Soft paper", func() -> void: _set_rigid(false), mg)
	_mode_rigid = _chip("Rigid hinges", func() -> void: _set_rigid(true), mg)
	_mode_soft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_rigid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.add_child(_mode_soft)
	modes.add_child(_mode_rigid)
	v.add_child(modes)
	var tools: HBoxContainer = K.hbox(10)
	_pin_btn = _chip("Pin a face", func() -> void: _set_pin_mode(not _pin_mode))
	_pin_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_pin_btn)
	var rs: Button = K.button("Refold", func() -> void:
		view.reset_shape()
		Studio.audio.play("whoosh"), "CardButton")
	rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(rs)
	var rc: Button = K.button("Recenter", func() -> void: view.camera_rig.recenter(), "CardButton")
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(rc)
	v.add_child(tools)
	_stats_label = K.label("", "MutedLabel")
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_stats_label)
	v.add_child(K.label("Soft paper bends like real paper and handles any pattern. Rigid hinges fold flat panels exactly when the creases form a tree (try Tray). Drag the 3D view to orbit, pinch to zoom, double-tap to recenter.", "MutedLabel"))
	return v


func _build_animate_tab() -> Control:
	var v: VBoxContainer = K.vbox(16)
	var top: HBoxContainer = K.hbox(12)
	_play_btn = K.button("Play", _toggle_play, "", 170)
	top.add_child(_play_btn)
	var loop: CheckButton = CheckButton.new()
	loop.text = "Loop"
	loop.button_pressed = _loop
	loop.focus_mode = Control.FOCUS_NONE
	loop.toggled.connect(func(on: bool) -> void: _loop = on)
	top.add_child(loop)
	var sp: Control = K.expand_spacer()
	top.add_child(sp)
	_time_label = K.label("0.0 s", "HeaderLabel")
	top.add_child(_time_label)
	v.add_child(top)
	strip = PVTimelineStrip.new()
	strip.set_timeline(project.timeline)
	strip.scrubbed.connect(func(t: float) -> void:
		_playing = false
		_play_btn.text = "Play"
		_set_time(t))
	v.add_child(strip)
	var spin_row: HBoxContainer = K.hbox(12)
	spin_row.add_child(K.label("Spin", "MutedLabel"))
	_spin_slider = HSlider.new()
	_spin_slider.min_value = -180.0
	_spin_slider.max_value = 360.0
	_spin_slider.step = 5.0
	_spin_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spin_slider.custom_minimum_size.y = K.s(56)
	_spin_slider.value_changed.connect(func(val: float) -> void: view.set_spin(val))
	spin_row.add_child(_spin_slider)
	v.add_child(spin_row)
	var ease_row: HBoxContainer = K.hbox(12)
	ease_row.add_child(K.label("New keys ease", "MutedLabel"))
	_ease_option = OptionButton.new()
	for i in OVTimeline.EASE_NAMES.size():
		_ease_option.add_item(OVTimeline.EASE_NAMES[i], i)
	_ease_option.select(OVTimeline.Ease.SMOOTH)
	_ease_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ease_row.add_child(_ease_option)
	v.add_child(ease_row)
	var keys: GridContainer = GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", int(K.s(12)))
	keys.add_theme_constant_override("v_separation", int(K.s(12)))
	for spec in [["Key fold", _key_fold], ["Key spin", _key_spin], ["Delete keys here", _delete_keys], ["Length +1 s", _extend]]:
		var b: Button = K.button(spec[0], spec[1], "CardButton")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys.add_child(b)
	v.add_child(keys)
	v.add_child(K.label("Keys store the Fold slider and Spin at the playhead. Playback refolds the paper live.", "MutedLabel"))
	return v


func _build_paper_tab() -> Control:
	var v: VBoxContainer = K.vbox(16)
	v.add_child(K.label("Paper", "HeaderLabel", HORIZONTAL_ALIGNMENT_LEFT))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(K.s(12)))
	grid.add_theme_constant_override("v_separation", int(K.s(12)))
	for p in OVPaperPresets.PRESETS:
		var preset: Dictionary = p
		var b: Button = K.button(preset.name, func() -> void: _apply_preset_undoable(preset.duplicate()), "CardButton")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sw: StyleBoxFlat = OVThemeFactory.box(preset.back, int(K.s(26)), preset.front.darkened(0.1), int(K.s(6)), 0.1, Vector2(24, 14) * K.scale)
		b.add_theme_stylebox_override("normal", sw)
		b.add_theme_color_override("font_color", Color.WHITE if (preset.back as Color).get_luminance() < 0.55 else Color("23233a"))
		grid.add_child(b)
	v.add_child(grid)
	var colors: HBoxContainer = K.hbox(16)
	colors.add_child(K.label("Front", "MutedLabel"))
	_front_picker = ColorPickerButton.new()
	_front_picker.custom_minimum_size = Vector2(K.s(150), K.s(80))
	_front_picker.edit_alpha = false
	_front_picker.popup_closed.connect(func() -> void:
		var p: Dictionary = project.material.duplicate()
		p.front = _front_picker.color
		_apply_preset_undoable(p))
	colors.add_child(_front_picker)
	colors.add_child(K.label("Back", "MutedLabel"))
	_back_picker = ColorPickerButton.new()
	_back_picker.custom_minimum_size = Vector2(K.s(150), K.s(80))
	_back_picker.edit_alpha = false
	_back_picker.popup_closed.connect(func() -> void:
		var p: Dictionary = project.material.duplicate()
		p.back = _back_picker.color
		_apply_preset_undoable(p))
	colors.add_child(_back_picker)
	v.add_child(colors)
	_assign_toggle = CheckButton.new()
	_assign_toggle.text = "Show mountain/valley colors in 3D"
	_assign_toggle.focus_mode = Control.FOCUS_NONE
	_assign_toggle.button_pressed = project.show_assignment
	_assign_toggle.toggled.connect(func(on: bool) -> void:
		project.show_assignment = on
		view.set_show_assignment(on)
		_mark_dirty())
	v.add_child(_assign_toggle)
	return v


# ------------------------------------------------------------ model


func _rebuild_model() -> void:
	var doc: OVFoldDocument = project.build_document()
	var r: Dictionary = view.load_document(doc, project.pin_face, project.rigid)
	view.set_preset(project.material)
	view.set_show_assignment(project.show_assignment)
	view.set_fold(project.fold_percent)
	view.set_spin(_spin_slider.value if _spin_slider else 0.0)
	view.wake()
	canvas.queue_redraw()
	if not r.ok:
		show_status(r.message)
	elif r.message != "":
		show_status(r.message)
		project.rigid = false
	elif not project.pattern.last_warnings.is_empty():
		show_status(project.pattern.last_warnings[0])
	_mode_soft.set_pressed_no_signal(not view.rigid)
	_mode_rigid.set_pressed_no_signal(view.rigid)
	_mark_dirty()


func _on_add_segment(a: Vector2, b: Vector2, assign: int) -> void:
	var seg: Dictionary = OVCreasePattern.make_segment(a, b, assign)
	var idx: int = project.pattern.segments.size()
	undo.perform("Add crease", func() -> void:
		project.pattern.insert_segment(idx, seg)
		_rebuild_model(),
		func() -> void:
			project.pattern.remove_segment(idx)
			_rebuild_model())
	Studio.audio.play("fold_soft", 1.1, -4.0)
	Studio.audio.haptic(10)


func _on_erase_segment(index: int) -> void:
	var seg: Dictionary = project.pattern.segments[index].duplicate()
	undo.perform("Erase crease", func() -> void:
		project.pattern.remove_segment(index)
		_rebuild_model(),
		func() -> void:
			project.pattern.insert_segment(index, seg)
			_rebuild_model())
	Studio.audio.play("ui_back")


func _on_flip_segment(index: int) -> void:
	var before: Dictionary = project.pattern.segments[index].duplicate()
	var after: Dictionary = before.duplicate()
	match int(before.assign):
		OVCore.Assign.MOUNTAIN:
			after.assign = OVCore.Assign.VALLEY
		OVCore.Assign.VALLEY:
			after.assign = OVCore.Assign.MOUNTAIN
		_:
			show_status("Only mountain and valley creases can be flipped.")
			return
	after.angle = -float(before.angle)
	undo.perform("Flip crease", func() -> void:
		project.pattern.set_segment(index, after)
		_rebuild_model(),
		func() -> void:
			project.pattern.set_segment(index, before)
			_rebuild_model())
	Studio.audio.play("snap", 1.2, -6.0)


func _on_clear() -> void:
	if project.pattern.segments.is_empty():
		return
	var saved: Array[Dictionary] = []
	for s in project.pattern.segments:
		saved.append(s.duplicate())
	undo.perform("Clear pattern", func() -> void:
		project.pattern.segments.clear()
		_rebuild_model(),
		func() -> void:
			project.pattern.segments.assign(saved.map(func(s: Dictionary) -> Dictionary: return s.duplicate()))
			_rebuild_model())


func _set_rigid(on: bool) -> void:
	if on == project.rigid:
		return
	project.rigid = on
	_rebuild_model()
	if on and not view.rigid:
		_mode_soft.set_pressed_no_signal(true)
		_mode_rigid.set_pressed_no_signal(false)


func _set_pin_mode(on: bool) -> void:
	_pin_mode = on
	_pin_btn.set_pressed_no_signal(on)
	if on:
		show_status("Tap a face in the 3D view to keep it still.")


func _on_view_tap(pos: Vector2) -> void:
	if not _pin_mode:
		return
	var fi: int = view.pick_face(pos)
	if fi < 0:
		show_status("No paper there. Tap directly on the model.")
		return
	var before: int = view.pinned_face()
	undo.perform("Pin face", func() -> void:
		project.pin_face = fi
		view.set_pinned_face(fi)
		_mark_dirty(),
		func() -> void:
			project.pin_face = before
			view.set_pinned_face(before)
			_mark_dirty())
	_set_pin_mode(false)
	show_status("Pinned. That face now stays in place while folding.")
	Studio.audio.play("snap")


func _apply_preset_undoable(p: Dictionary) -> void:
	var before: Dictionary = project.material.duplicate()
	undo.perform("Change paper", func() -> void:
		project.material = p
		view.set_preset(p)
		_sync_material_ui()
		_mark_dirty(),
		func() -> void:
			project.material = before
			view.set_preset(before)
			_sync_material_ui()
			_mark_dirty())
	Studio.audio.play("fold_soft", 0.9, -6.0)


func _sync_material_ui() -> void:
	if _front_picker:
		_front_picker.color = project.material.front
		_back_picker.color = project.material.back
	if canvas:
		canvas.paper_color = (project.material.front as Color).lerp(Color.WHITE, 0.4)
		canvas.queue_redraw()


# ------------------------------------------------------------ timeline


func _toggle_play() -> void:
	_playing = not _playing
	_play_btn.text = "Pause" if _playing else "Play"
	if _playing and _time >= project.timeline.duration - 0.01:
		_time = 0.0


func _set_time(t: float) -> void:
	_time = t
	strip.set_playhead(t)
	_time_label.text = "%.1f s" % t
	if project.timeline.has_keys("fold"):
		_fold_slider.value = clampf(project.timeline.sample("fold", t, project.fold_percent), 0.0, 1.0)
	if project.timeline.has_keys("spin"):
		_spin_slider.set_value_no_signal(project.timeline.sample("spin", t, 0.0))
		view.set_spin(_spin_slider.value)


func _key_fold() -> void:
	_add_key("fold", _fold_slider.value)


func _key_spin() -> void:
	_add_key("spin", _spin_slider.value)


func _add_key(channel: String, value: float) -> void:
	var t: float = snappedf(_time, 0.05)
	var before: Dictionary = project.timeline.to_dict()
	var ease: int = _ease_option.get_selected_id()
	undo.perform("Add %s key" % channel, func() -> void:
		project.timeline.set_key(channel, t, value, ease)
		strip.queue_redraw()
		_mark_dirty(),
		func() -> void:
			_restore_timeline(before))
	show_status("%s key at %.2f s" % [channel.capitalize(), t])
	Studio.audio.play_note(3, -6.0)


func _delete_keys() -> void:
	var t: float = snappedf(_time, 0.05)
	var before: Dictionary = project.timeline.to_dict()
	var had: bool = false
	for ch in ["fold", "spin"]:
		for k in project.timeline.keys(ch):
			if absf(k.t - t) < 0.06:
				had = true
	if not had:
		show_status("No keys at the playhead. Drag the playhead onto a diamond first.")
		return
	undo.perform("Delete keys", func() -> void:
		for ch in ["fold", "spin"]:
			for k in project.timeline.keys(ch).duplicate():
				if absf(k.t - t) < 0.06:
					project.timeline.remove_key(ch, k.t)
		strip.queue_redraw()
		_mark_dirty(),
		func() -> void:
			_restore_timeline(before))


func _extend() -> void:
	var before: float = project.timeline.duration
	var after: float = minf(before + 1.0, 20.0)
	undo.perform("Lengthen timeline", func() -> void:
		project.timeline.duration = after
		strip.queue_redraw(),
		func() -> void:
			project.timeline.duration = before
			strip.queue_redraw())


func _restore_timeline(d: Dictionary) -> void:
	var tl: OVTimeline = OVTimeline.from_dict(d)
	project.timeline.channels = tl.channels
	project.timeline.duration = tl.duration
	strip.queue_redraw()
	_mark_dirty()


# ------------------------------------------------------------ frame


func _process(dt: float) -> void:
	if _playing:
		var t: float = _time + dt
		if t > project.timeline.duration:
			if _loop:
				t = fmod(t, maxf(project.timeline.duration, 0.01))
			else:
				t = project.timeline.duration
				_playing = false
				_play_btn.text = "Play"
		_set_time(t)
	if _dirty:
		_autosave_timer -= dt
		if _autosave_timer <= 0.0:
			autosave()


func _mark_dirty() -> void:
	_dirty = true
	_autosave_timer = 2.0


func autosave(with_thumbnail: bool = false) -> void:
	if project == null:
		return
	PVProjectStore.save(project, _normalized_folded())
	if with_thumbnail:
		PVProjectStore.save_thumbnail(project.id, viewport.get_texture().get_image())
	_dirty = false


## Folded positions scaled back to sheet units so they line up with the FOLD crease pattern.
func _normalized_folded() -> PackedVector3Array:
	var pos: PackedVector3Array = view.folded_vertices().duplicate()
	var r: Rect2 = project.pattern.bounds()
	var k: float = maxf(r.size.x, r.size.y) / PVFoldView.MODEL_SCALE
	for i in pos.size():
		pos[i] *= k
	return pos


func _refresh_undo() -> void:
	_undo_btn.disabled = not undo.can_undo()
	_redo_btn.disabled = not undo.can_redo()


func show_status(text: String) -> void:
	_status.text = text
	_status.modulate.a = 1.0
	if _status_tween:
		_status_tween.kill()
	_status_tween = create_tween()
	_status_tween.tween_interval(3.5)
	_status_tween.tween_property(_status, "modulate:a", 0.0, 0.6)


# ------------------------------------------------------------ dialogs


func _open_overlay(content: Control) -> void:
	_close_overlay()
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.08, 0.08, 0.15, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			_close_overlay())
	root.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size.x = K.s(840)
	card.add_child(K.margin(content, 16, 16, 16, 16))
	center.add_child(card)
	add_child(root)
	_overlay = root
	K.fade_in(root)


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func has_overlay() -> bool:
	return _overlay != null


func close_overlay() -> void:
	_close_overlay()


func _rename_dialog() -> void:
	var v: VBoxContainer = K.vbox(20)
	v.add_child(K.label("Rename project", "HeaderLabel"))
	var le: LineEdit = LineEdit.new()
	le.text = project.name
	le.max_length = 40
	le.select_all_on_focus = true
	v.add_child(le)
	var ok: Callable = func() -> void:
		var n: String = le.text.strip_edges()
		if n == "":
			return
		var before: String = project.name
		undo.perform("Rename", func() -> void:
			project.name = n
			_name_label.text = n
			_mark_dirty(),
			func() -> void:
				project.name = before
				_name_label.text = before
				_mark_dirty())
		_close_overlay()
	le.text_submitted.connect(func(_t: String) -> void: ok.call())
	v.add_child(K.button("Save name", ok))
	v.add_child(K.button("Cancel", _close_overlay, "CardButton"))
	_open_overlay(v)
	le.grab_focus.call_deferred()


func _export_dialog() -> void:
	var v: VBoxContainer = K.vbox(16)
	v.add_child(K.label("Export", "HeaderLabel"))
	v.add_child(K.label("Exports the current folded state of \"%s\"." % project.name, "MutedLabel"))
	var safe: String = project.name.validate_filename().replace(" ", "_")
	if safe == "":
		safe = "origami"
	v.add_child(K.button("FOLD file (crease pattern + folded form)", func() -> void:
		_save(safe + ".fold", "*.fold;FOLD origami", project.to_fold_text(_normalized_folded()).to_utf8_buffer()), "CardButton"))
	v.add_child(K.button("3D model (GLB)", func() -> void:
		var bytes: PackedByteArray = OVExporter.glb_bytes(view.export_corners(), project.material.front, project.material.back, project.name)
		_save(safe + ".glb", "*.glb;glTF binary", bytes), "CardButton"))
	v.add_child(K.button("3D model (OBJ)", func() -> void:
		_save(safe + ".obj", "*.obj;Wavefront OBJ", OVExporter.obj_text(view.export_corners(), "").to_utf8_buffer()), "CardButton"))
	v.add_child(K.button("Image (PNG)", func() -> void:
		var img: Image = viewport.get_texture().get_image()
		_save(safe + ".png", "*.png;PNG image", img.save_png_to_buffer()), "CardButton"))
	v.add_child(K.button("Close", _close_overlay))
	_open_overlay(v)


func _save(file_name: String, filter: String, bytes: PackedByteArray) -> void:
	_close_overlay()
	if bytes.is_empty():
		show_status("Export failed: nothing to write.")
		return
	Studio.save_bytes(file_name, filter, bytes, func(ok: bool, where: String) -> void:
		if ok:
			show_status("Saved %s" % where)
			Studio.audio.play("unlock", 1.3, -6.0)
		else:
			show_status("Export cancelled."))
