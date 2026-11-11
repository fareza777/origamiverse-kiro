class_name FSWorld
extends Node3D
## 3D presentation and touch interaction for one FoldShift level.
## All folding is computed live by OrigamiVerse Core (OVHingeSolver) and rendered with OVPaperMesh.

signal state_changed
signal toast(text: String)
signal won
signal crane_collected(index: int)
signal seal_broken(index: int)
signal folded(flap: String)
signal walked_on_wall
signal intro_finished

const LANTERN: PackedScene = preload("res://assets/models/lantern.glb")
const CRANE: PackedScene = preload("res://assets/models/crane.glb")
const SEAL: PackedScene = preload("res://assets/models/seal.glb")

enum Mode { INTRO, IDLE, DRAG_FOLD, SETTLING, WALKING, DONE }

var _orbiting: bool = false

var puzzle: FSPuzzle
var style: Dictionary
var mode: int = Mode.INTRO
var undo: OVUndoStack = OVUndoStack.new()
var input_enabled: bool = true
var reduce_motion: bool = false

var rig: OVOrbitCamera
var kami: FSCharacter
var gestures: OVGestureTracker
var environment_node: FSEnvironment

var _meshes: Array[Dictionary] = []          # {"pm": OVPaperMesh, "island": int, "mi": MeshInstance3D}
var _flap_materials: Array[ShaderMaterial] = []
var _tile_bodies: Array[StaticBody3D] = []
var _goal: Node3D
var _goal_light: OmniLight3D
var _cranes: Array[Node3D] = []
var _seals: Array[Node3D] = []
var _highlight: MeshInstance3D
var _highlight_mesh: ImmediateMesh = ImmediateMesh.new()
var _geometry_dirty: bool = true
var _time: float = 0.0

var _drag_flap: int = -1
var _drag_local: Vector3
var _drag_angle: float = 0.0
var _drag_last_sound: float = 0.0
var _springs: Dictionary = {}                 # flap -> OVSpring
var _settle_callbacks: Dictionary = {}        # flap -> Callable
var _walk_path: PackedInt32Array = PackedInt32Array()
var _shake: float = 0.0


func build(p: FSPuzzle, style_id: String, saved_state: Dictionary = {}) -> void:
	puzzle = p
	style = FSStyles.get_style(style_id)
	puzzle.crane_collected.connect(_on_crane)
	puzzle.seal_broken.connect(_on_seal)

	environment_node = FSEnvironment.new()
	add_child(environment_node)

	var base_mat: ShaderMaterial = OVPaperMesh.make_material(style.base)
	base_mat.set_shader_parameter("grain_scale", 6.0)
	base_mat.set_shader_parameter("edge_strength", 0.45)
	for fi in puzzle.flap_count():
		var m: ShaderMaterial = OVPaperMesh.make_material(style.flap)
		m.set_shader_parameter("grain_scale", 6.0)
		m.set_shader_parameter("edge_strength", 0.45)
		_flap_materials.append(m)
	for island in puzzle.solvers.size():
		var groups: Dictionary = {-1: PackedInt32Array()}
		for fi in puzzle.flap_count():
			groups[fi] = PackedInt32Array()
		for t in puzzle.tile_count():
			if puzzle.tile_island[t] != island:
				continue
			var key: int = puzzle.tile_flap[t]
			groups[key].append_array(puzzle.tile_faces[t])
		for key in groups.keys():
			var faces: PackedInt32Array = groups[key]
			if faces.is_empty():
				continue
			var pm: OVPaperMesh = OVPaperMesh.new()
			pm.setup(puzzle.docs[island], base_mat if key == -1 else _flap_materials[key], faces)
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = pm.mesh
			add_child(mi)
			_meshes.append({"pm": pm, "island": island, "mi": mi})

	for t in puzzle.tile_count():
		var body: StaticBody3D = OVCollisionSync.make_tile_body(t)
		add_child(body)
		_tile_bodies.append(body)

	_goal = LANTERN.instantiate()
	_goal.scale = Vector3.ONE * 1.3
	add_child(_goal)
	_goal_light = OmniLight3D.new()
	_goal_light.light_color = Color("ffc46b")
	_goal_light.light_energy = 1.6
	_goal_light.omni_range = 3.0
	_goal_light.position = Vector3(0, 0.45, 0)
	_goal.add_child(_goal_light)
	for i in puzzle.level.cranes.size():
		var c: Node3D = CRANE.instantiate()
		c.scale = Vector3.ONE * 1.6
		add_child(c)
		_cranes.append(c)
	for i in puzzle.level.seals.size():
		var s: Node3D = SEAL.instantiate()
		_tint_model(s, FSStyles.SEAL_COLORS[i % FSStyles.SEAL_COLORS.size()])
		add_child(s)
		_seals.append(s)

	_highlight = MeshInstance3D.new()
	_highlight.mesh = _highlight_mesh
	var hm: StandardMaterial3D = StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.vertex_color_use_as_albedo = true
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.no_depth_test = false
	_highlight.material_override = hm
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_highlight)

	kami = FSCharacter.new()
	add_child(kami)
	kami.stepped.connect(_on_kami_step)
	kami.arrived.connect(_on_kami_arrived)

	rig = OVOrbitCamera.new()
	add_child(rig)
	gestures = OVGestureTracker.new()
	add_child(gestures)
	gestures.tap.connect(_on_tap)
	gestures.double_tap.connect(func(_p: Vector2) -> void: rig.recenter())
	gestures.drag_started.connect(_on_drag_started)
	gestures.dragged.connect(_on_dragged)
	gestures.drag_ended.connect(_on_drag_ended)
	gestures.pinched.connect(func(f: float, _c: Vector2) -> void: if mode != Mode.DRAG_FOLD: rig.zoom(f))
	gestures.twisted.connect(func(r: float, _c: Vector2) -> void: if mode != Mode.DRAG_FOLD: rig.twist(r))

	_update_lock_tints()
	if not saved_state.is_empty():
		puzzle.restore(saved_state)
		mode = Mode.IDLE
	_refresh_geometry()
	var bounds: AABB = _play_bounds()
	environment_node.build(style, puzzle, bounds, hash(puzzle.level.id))
	var aspect: float = 0.5625
	if get_viewport():
		var vs: Vector2 = get_viewport().get_visible_rect().size
		aspect = vs.x / maxf(vs.y, 1.0)
	rig.frame_bounds(bounds, puzzle.level.camera, aspect)
	_place_kami()
	if saved_state.is_empty():
		_start_intro()
	else:
		_refresh_highlight()


func _play_bounds() -> AABB:
	var box: AABB = AABB(puzzle.tile_center(0), Vector3.ZERO)
	for t in puzzle.tile_count():
		for c in puzzle.tile_corners(t):
			box = box.expand(c)
	# Include every flap at every allowed angle so the camera frame never cuts a fold.
	return box.grow(1.0)


func _start_intro() -> void:
	mode = Mode.INTRO
	var any: bool = false
	for fi in puzzle.flap_count():
		var target: float = puzzle.current_angle(fi)
		if is_zero_approx(target):
			continue
		any = true
		puzzle.set_live_angle(fi, 0.0)
		var sp: OVSpring = OVSpring.new(0.0, 1.1 + 0.15 * fi, 0.8)
		sp.target = target
		_springs[fi] = sp
	_geometry_dirty = true
	if not any:
		_finish_intro()
	else:
		Game.audio.play("whoosh")
		get_tree().create_timer(2.2 if not reduce_motion else 0.6).timeout.connect(_finish_intro)


func _finish_intro() -> void:
	if mode != Mode.INTRO:
		return
	for fi in _springs.keys():
		puzzle.set_live_angle(fi, puzzle.current_angle(fi))
	_springs.clear()
	puzzle.apply_indices(puzzle.indices)
	_geometry_dirty = true
	mode = Mode.IDLE
	_refresh_highlight()
	Game.audio.play("snap", 0.9)
	intro_finished.emit()


# ------------------------------------------------------------ frame update


func _process(dt: float) -> void:
	_time += dt
	if not _springs.is_empty():
		var done: Array = []
		for fi in _springs.keys():
			var sp: OVSpring = _springs[fi]
			sp.step(dt)
			puzzle.set_live_angle(fi, sp.value)
			if mode != Mode.INTRO and sp.is_settled(0.4):
				done.append(fi)
		for fi in done:
			_springs.erase(fi)
			puzzle.set_live_angle(fi, puzzle.current_angle(fi))
			var cb: Callable = _settle_callbacks.get(fi, Callable())
			_settle_callbacks.erase(fi)
			if cb.is_valid():
				cb.call()
		_geometry_dirty = true
	if _geometry_dirty:
		_refresh_geometry()
		_geometry_dirty = false
		if mode != Mode.WALKING:
			_place_kami()
	_animate_markers(dt)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 3.0)
		rig.camera.h_offset = sin(_time * 70.0) * 0.06 * _shake
	else:
		rig.camera.h_offset = 0.0


func _refresh_geometry() -> void:
	for m in _meshes:
		(m.pm as OVPaperMesh).update_from_hinge_solver(puzzle.solvers[m.island])
	for t in _tile_bodies.size():
		OVCollisionSync.sync_tile_body(_tile_bodies[t], puzzle.tile_corners(t))
	_place_markers()


func _surface_frame(t: int, side: int, lift: float = 0.0) -> Transform3D:
	var c: PackedVector3Array = puzzle.tile_corners(t)
	var center: Vector3 = (c[0] + c[1] + c[2] + c[3]) * 0.25
	var n: Vector3 = (c[1] - c[0]).cross(c[3] - c[0]).normalized()
	if side == 1:
		n = -n
	var x: Vector3 = (c[1] - c[0]).normalized()
	var z: Vector3 = x.cross(n).normalized()
	x = n.cross(z).normalized()
	return Transform3D(Basis(x, n, z), center + n * (OVCore.PAPER_THICKNESS * 0.6 + lift))


func _place_markers() -> void:
	var gt: int = puzzle.tile_of[puzzle.level.goal]
	var goal_side: int = 0 if puzzle.side_normal(gt, 0).dot(Vector3.UP) >= puzzle.side_normal(gt, 1).dot(Vector3.UP) else 1
	_goal.global_transform = _surface_frame(gt, goal_side).scaled_local(Vector3.ONE * 1.3)
	for i in _cranes.size():
		var cr: Dictionary = puzzle.level.cranes[i]
		var t: int = puzzle.tile_of[cr.at]
		if puzzle.collected[i] == 1 and not _cranes[i].has_meta("flying"):
			_cranes[i].visible = false
			continue
		if _cranes[i].has_meta("flying"):
			continue
		var frame: Transform3D = _surface_frame(t, cr.side, 0.12)
		_cranes[i].global_transform = frame.scaled_local(Vector3.ONE * 1.6)
		# Secrets printed on a face pointing down stay hidden until a fold turns them up.
		_cranes[i].visible = frame.basis.y.dot(Vector3.UP) > -0.3
	for i in _seals.size():
		var s: Dictionary = puzzle.level.seals[i]
		var t2: int = puzzle.tile_of[s.at]
		if puzzle.seal_broken_flags[i] == 1 and not _seals[i].has_meta("breaking"):
			_seals[i].visible = false
			continue
		if not _seals[i].has_meta("breaking"):
			_seals[i].global_transform = _surface_frame(t2, 0)


func _animate_markers(dt: float) -> void:
	for i in _cranes.size():
		var c: Node3D = _cranes[i]
		if not c.visible or c.has_meta("flying"):
			continue
		var bob: float = sin(_time * 2.2 + i) * 0.05
		c.rotate_object_local(Vector3.UP, dt * 1.2)
		c.translate_object_local(Vector3(0, bob * dt, 0))
	_goal_light.light_energy = 1.4 + sin(_time * 3.0) * 0.25


func _place_kami() -> void:
	if puzzle.player_node < 0:
		return
	var t: int = puzzle.player_node / 2
	var frame: Transform3D = _surface_frame(t, puzzle.player_node % 2)
	kami.place(frame.origin, frame.basis.y)


func _node_point(node: int) -> Dictionary:
	var frame: Transform3D = _surface_frame(node / 2, node % 2)
	return {"pos": frame.origin, "normal": frame.basis.y}


## Screen position of a tile's live center (follows folds and the camera). Used by tutorial coach marks.
func tile_screen_position(t: int) -> Vector2:
	var c: PackedVector3Array = puzzle.tile_corners(t)
	var center: Vector3 = (c[0] + c[1] + c[2] + c[3]) * 0.25
	if rig == null or rig.camera == null or rig.camera.is_position_behind(center):
		return Vector2(-10000, -10000)
	return rig.camera.unproject_position(center)


## First tile belonging to flap `fi`, or -1.
func flap_tile(fi: int) -> int:
	for t in puzzle.tile_count():
		if puzzle.tile_flap[t] == fi:
			return t
	return -1


func _refresh_highlight() -> void:
	_highlight_mesh.clear_surfaces()
	if mode == Mode.DONE or puzzle.nav == null or not input_enabled:
		return
	var nodes: PackedInt32Array = puzzle.nav.reachable(puzzle.player_node)
	if nodes.size() <= 1:
		return
	_highlight_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var col: Color = Color(1.0, 0.98, 0.85, 0.32)
	for node in nodes:
		if node == puzzle.player_node:
			continue
		var f: Transform3D = _surface_frame(node / 2, node % 2, 0.004)
		var s: float = 0.36
		var a: Vector3 = f * Vector3(-s, 0, -s)
		var b: Vector3 = f * Vector3(s, 0, -s)
		var c: Vector3 = f * Vector3(s, 0, s)
		var d: Vector3 = f * Vector3(-s, 0, s)
		for v in [a, b, c, a, c, d]:
			_highlight_mesh.surface_set_color(col)
			_highlight_mesh.surface_add_vertex(v)
	_highlight_mesh.surface_end()


func _update_lock_tints() -> void:
	for fi in puzzle.flap_count():
		var tint: Color = Color.WHITE
		if puzzle.is_locked(fi):
			for i in puzzle.level.seals.size():
				if puzzle.level.seals[i].unlocks.has(puzzle.flap_names[fi]):
					tint = Color.WHITE.lerp(FSStyles.SEAL_COLORS[i % FSStyles.SEAL_COLORS.size()], 0.45)
		_flap_materials[fi].set_shader_parameter("tint", tint)


func _tint_model(n: Node, color: Color) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.35
		mi.material_override = m
	for c in n.get_children():
		_tint_model(c, color)


# ------------------------------------------------------------ input


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if gestures.handle(event):
		get_viewport().set_input_as_handled()


func _pick_tile(screen: Vector2) -> Dictionary:
	var hit: Dictionary = OVCollisionSync.pick(rig.camera, screen)
	if hit.is_empty() or not hit.collider.has_meta("tile_id"):
		return {}
	return {"tile": int(hit.collider.get_meta("tile_id")), "pos": hit.position}


func _on_tap(screen: Vector2) -> void:
	if mode != Mode.IDLE:
		return
	var pick: Dictionary = _pick_tile(screen)
	if pick.is_empty():
		return
	var t: int = pick.tile
	if t == puzzle.player_node / 2:
		return
	var path: PackedInt32Array = puzzle.path_to_tile(t)
	if path.is_empty():
		Game.audio.play("ui_back", 0.8, -6.0)
		toast.emit("Kami can't reach that spot yet.")
		return
	_walk_path = path
	var points: Array = []
	var on_wall: bool = false
	for node in path:
		var p: Dictionary = _node_point(node)
		points.append(p)
		if (p.normal as Vector3).dot(Vector3.UP) < 0.5:
			on_wall = true
	if on_wall:
		walked_on_wall.emit()
	mode = Mode.WALKING
	_highlight_mesh.clear_surfaces()
	kami.walk(points)


func _on_kami_step(index: int) -> void:
	if index < _walk_path.size():
		puzzle.walk(PackedInt32Array([_walk_path[index]]))
	Game.audio.play("step", randf_range(0.9, 1.15), -4.0)


func _on_kami_arrived() -> void:
	puzzle.walk(PackedInt32Array([_walk_path[_walk_path.size() - 1]]))
	mode = Mode.IDLE
	_place_kami()
	state_changed.emit()
	if puzzle.is_won():
		_win()
	else:
		_refresh_highlight()


func _on_drag_started(screen: Vector2) -> void:
	if mode != Mode.IDLE:
		_orbiting = true
		return
	var pick: Dictionary = _pick_tile(screen)
	if not pick.is_empty() and puzzle.tile_flap[pick.tile] >= 0:
		var fi: int = puzzle.tile_flap[pick.tile]
		if puzzle.is_locked(fi):
			Game.audio.play("error")
			Game.audio.haptic(30)
			toast.emit("Sealed. Walk Kami onto the matching wax seal.")
			_shake = 0.6
			_orbiting = true
			return
		_drag_flap = fi
		var s: OVHingeSolver = puzzle.solvers[puzzle.flap_island[fi]]
		_drag_local = s.panel_transforms[puzzle.flap_panel[fi]].affine_inverse() * pick.pos
		_drag_angle = puzzle.current_angle(fi)
		_drag_last_sound = _drag_angle
		_flap_materials[fi].set_shader_parameter("emission_amount", 0.12)
		mode = Mode.DRAG_FOLD
		Game.audio.play("fold_soft", 1.1, -6.0)
		Game.audio.haptic(10, 0.3)
		_highlight_mesh.clear_surfaces()
	else:
		_orbiting = true


func _on_dragged(screen: Vector2, rel: Vector2) -> void:
	if _orbiting:
		rig.orbit(rel)
		return
	if mode != Mode.DRAG_FOLD:
		return
	var fi: int = _drag_flap
	var angles: PackedFloat32Array = puzzle.flap_angles[fi]
	var lo: float = angles[0]
	var hi: float = angles[0]
	for a in angles:
		lo = minf(lo, a)
		hi = maxf(hi, a)
	var best: float = _drag_angle
	var best_d: float = INF
	var a2: float = lo
	while a2 <= hi + 0.01:
		var d: float = _screen_distance(fi, a2, screen) + absf(a2 - _drag_angle) * 0.4
		if d < best_d:
			best_d = d
			best = a2
		a2 += 4.0
	var center: float = best
	var r: float = center - 4.0
	while r <= center + 4.0:
		var rr: float = clampf(r, lo, hi)
		var d2: float = _screen_distance(fi, rr, screen) + absf(rr - _drag_angle) * 0.4
		if d2 < best_d:
			best_d = d2
			best = rr
		r += 0.5
	_drag_angle = best
	puzzle.set_live_angle(fi, _drag_angle)
	_geometry_dirty = true
	if absf(_drag_angle - _drag_last_sound) > 22.0:
		_drag_last_sound = _drag_angle
		Game.audio.play("fold_soft", randf_range(0.95, 1.2), -8.0)


func _screen_distance(fi: int, angle: float, screen: Vector2) -> float:
	var s: OVHingeSolver = puzzle.solvers[puzzle.flap_island[fi]]
	var h: int = puzzle.flap_hinge[fi]
	var keep: float = s.hinge_angle[h]
	s.hinge_angle[h] = angle
	var world: Vector3 = s.panel_transforms[s.hinge_parent[h]] * s.hinge_local_transform(h) * _drag_local
	s.hinge_angle[h] = keep
	if rig.camera.is_position_behind(world):
		return INF
	return rig.camera.unproject_position(world).distance_to(screen)


func _on_drag_ended(_screen: Vector2, _velocity: Vector2) -> void:
	if _orbiting:
		_orbiting = false
		return
	if mode != Mode.DRAG_FOLD:
		return
	var fi: int = _drag_flap
	_drag_flap = -1
	_flap_materials[fi].set_shader_parameter("emission_amount", 0.0)
	var angles: PackedFloat32Array = puzzle.flap_angles[fi]
	var target: int = 0
	for j in angles.size():
		if absf(angles[j] - _drag_angle) < absf(angles[target] - _drag_angle):
			target = j
	var before: Dictionary = puzzle.snapshot()
	var check: Dictionary = puzzle.check_fold(fi, target)
	puzzle.set_live_angle(fi, _drag_angle)
	mode = Mode.SETTLING
	if target == puzzle.indices[fi] or not check.ok:
		if not check.ok and str(check.reason) != "":
			toast.emit(check.reason)
			Game.audio.play("error")
			Game.audio.haptic(40, 0.6)
			_shake = 1.0
		_animate_flap(fi, puzzle.current_angle(fi), func() -> void:
			mode = Mode.IDLE
			_refresh_highlight())
		return
	puzzle.try_fold(fi, target)
	puzzle.set_live_angle(fi, _drag_angle)
	var after: Dictionary = puzzle.snapshot()
	undo.push("fold " + puzzle.flap_names[fi], func() -> void: _restore(after), func() -> void: _restore(before))
	_animate_flap(fi, puzzle.current_angle(fi), func() -> void:
		Game.audio.play("snap")
		Game.audio.play("fold", 1.0, -6.0)
		Game.audio.haptic(22, 0.7)
		mode = Mode.IDLE
		folded.emit(puzzle.flap_names[fi])
		state_changed.emit()
		_refresh_highlight())


func _animate_flap(fi: int, target: float, on_done: Callable) -> void:
	var sp: OVSpring = OVSpring.new(_drag_angle, 3.2, 0.62)
	sp.target = target
	if reduce_motion:
		sp.frequency = 6.0
		sp.damping_ratio = 1.0
	_springs[fi] = sp
	_settle_callbacks[fi] = on_done


func _restore(s: Dictionary) -> void:
	puzzle.restore(s)
	puzzle.apply_indices(puzzle.indices)
	_springs.clear()
	_settle_callbacks.clear()
	kami.stop()
	mode = Mode.IDLE
	_update_lock_tints()
	_geometry_dirty = true
	_refresh_geometry()
	_place_kami()
	_refresh_highlight()
	state_changed.emit()


func undo_last() -> bool:
	if mode != Mode.IDLE or not undo.can_undo():
		return false
	undo.undo()
	Game.audio.play("whoosh", 1.3, -6.0)
	return true


func _on_crane(i: int) -> void:
	var c: Node3D = _cranes[i]
	c.set_meta("flying", true)
	Game.audio.play_note(2 + puzzle.cranes_collected())
	Game.audio.haptic(15)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "global_position", c.global_position + Vector3(0, 1.6, 0), 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector3.ONE * 0.01, 0.7).set_delay(0.25)
	tw.chain().tween_callback(func() -> void:
		c.visible = false
		c.remove_meta("flying"))
	crane_collected.emit(i)


func _on_seal(i: int) -> void:
	var s: Node3D = _seals[i]
	s.set_meta("breaking", true)
	Game.audio.play("unlock")
	Game.audio.haptic(30)
	var tw: Tween = create_tween()
	tw.tween_property(s, "scale", Vector3(1.4, 0.2, 1.4), 0.18)
	tw.tween_property(s, "scale", Vector3.ONE * 0.01, 0.25)
	tw.tween_callback(func() -> void:
		s.visible = false
		s.remove_meta("breaking"))
	_update_lock_tints()
	toast.emit("Seal broken! A colored flap is free to fold.")
	seal_broken.emit(i)


func _win() -> void:
	mode = Mode.DONE
	_highlight_mesh.clear_surfaces()
	Game.audio.play_fanfare()
	Game.audio.haptic(60, 0.8)
	var tw: Tween = create_tween()
	tw.tween_property(_goal_light, "light_energy", 5.0, 0.4)
	tw.tween_property(_goal_light, "light_energy", 2.0, 0.6)
	var spin: Tween = create_tween()
	spin.tween_property(kami, "rotation:y", kami.rotation.y + TAU, 0.8).set_trans(Tween.TRANS_CUBIC)
	get_tree().create_timer(1.0).timeout.connect(func() -> void: won.emit())
