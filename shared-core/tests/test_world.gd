extends OVTestCase


func _tile(id: int, center: Vector3, x: Vector3, z: Vector3) -> Dictionary:
	# Corners CCW seen from the front: front normal = x_axis cross (-z) ... built so that normal = (c1-c0) x (c3-c0).
	var hx: Vector3 = x * 0.5
	var hz: Vector3 = z * 0.5
	var c: PackedVector3Array = PackedVector3Array([center - hx + hz, center + hx + hz, center + hx - hz, center - hx - hz])
	return {"id": id, "corners": c}


func _floor(id: int, cx: float, cz: float, y: float = 0.0) -> Dictionary:
	return _tile(id, Vector3(cx, y, cz), Vector3.RIGHT, Vector3.BACK)


func test_tile_normal_convention() -> void:
	var t: Dictionary = _floor(0, 0, 0)
	var c: PackedVector3Array = t.corners
	check_vec_near((c[1] - c[0]).cross(c[3] - c[0]).normalized(), Vector3.UP, 1e-6, "floor tile faces up")


func test_flat_path() -> void:
	var nav: OVSurfaceNavigator = OVSurfaceNavigator.new()
	nav.build([_floor(0, 0, 0), _floor(1, 1, 0), _floor(2, 2, 0), _floor(3, 4, 0)])
	var a: int = nav.best_node_for_tile(0)
	var c: int = nav.best_node_for_tile(2)
	check_eq(nav.node_side(a), 0, "front side is up")
	check_eq(nav.path(a, c).size(), 3, "walks across 3 tiles")
	check(nav.path(a, nav.best_node_for_tile(3)).is_empty(), "gap blocks the path")
	check(not nav.is_walkable(nav.node_of(0, 1)), "underside of a floor is a ceiling")


func test_wall_concave_and_ledge_convex() -> void:
	var nav: OVSurfaceNavigator = OVSurfaceNavigator.new()
	# Floor at x=0; wall rising at x=0.5 (spanning y 0..1); upper floor at y=1 beyond the wall (x=1).
	var wall: Dictionary = _tile(1, Vector3(0.5, 0.5, 0), Vector3.UP, Vector3.BACK)
	var upper: Dictionary = _floor(2, 1.0, 0, 1.0)
	nav.build([_floor(0, 0, 0), wall, upper])
	var start: int = nav.best_node_for_tile(0)
	var goal: int = nav.best_node_for_tile(2)
	var p: PackedInt32Array = nav.path(start, goal)
	check_eq(p.size(), 3, "floor -> wall -> over the top onto upper floor")
	if p.size() == 3:
		check(nav.node_normal(p[1]).dot(Vector3.LEFT) > 0.9, "walker stands on the wall face that looks back at the floor")


func test_hanging_wall_convex() -> void:
	var nav: OVSurfaceNavigator = OVSurfaceNavigator.new()
	var hang: Dictionary = _tile(1, Vector3(0.5, -0.5, 0), Vector3.UP, Vector3.BACK)
	nav.build([_floor(0, 0, 0), hang, _floor(2, 1.0, 0, -1.0)])
	var p: PackedInt32Array = nav.path(nav.best_node_for_tile(0), nav.best_node_for_tile(2))
	check_eq(p.size(), 3, "over the ledge, down the hanging wall, onto the lower floor")


func test_covered_tile() -> void:
	var nav: OVSurfaceNavigator = OVSurfaceNavigator.new()
	var t: float = nav.thickness
	# Tile 1 is a flap folded on top of tile 0 (back side up).
	var flap: Dictionary = _tile(1, Vector3(0, t, 0), Vector3.LEFT, Vector3.BACK)
	nav.build([_floor(0, 0, 0), flap, _floor(2, 1, 0)])
	check(not nav.is_walkable(nav.node_of(0, 0)), "covered floor not walkable")
	var top: int = nav.best_node_for_tile(1)
	check(top >= 0 and nav.node_normal(top).dot(Vector3.UP) > 0.9, "flap back side is walkable")
	check_eq(nav.path(nav.best_node_for_tile(2), top).size(), 2, "step from neighbor onto the folded flap")


func test_collision_tile_transform() -> void:
	var t: Dictionary = _tile(0, Vector3(1, 2, 3), Vector3.UP, Vector3.BACK)
	var xf: Transform3D = OVCollisionSync.tile_transform(t.corners)
	check_vec_near(xf.origin, Vector3(1, 2, 3), 1e-6, "origin at center")
	check_vec_near(xf.basis.y, Vector3.LEFT, 1e-6, "Y axis = tile normal")
	var body: StaticBody3D = OVCollisionSync.make_tile_body(42)
	check_eq(int(body.get_meta("tile_id")), 42, "tile id stored")
	body.free()


func test_audio_synthesis() -> void:
	var amb: AudioStreamWAV = OVPaperAudio.make_ambience("night", 2.0)
	check_eq(amb.data.size(), int(2.0 * OVPaperAudio.RATE) * 2, "16-bit mono loop")
	check_eq(amb.loop_mode, AudioStreamWAV.LOOP_FORWARD, "loops")
	var audio: OVPaperAudio = OVPaperAudio.new()
	tree.root.add_child(audio)
	check(AudioServer.get_bus_index("SFX") >= 0, "SFX bus created")
	check(AudioServer.get_bus_index("Music") >= 0, "Music bus created")
	audio.play("fold")
	audio.play_note(3)
	audio.queue_free()


func test_gestures() -> void:
	var g: OVGestureTracker = OVGestureTracker.new()
	tree.root.add_child(g)
	var log: Array = []
	g.tap.connect(func(p: Vector2) -> void: log.append("tap"))
	g.drag_started.connect(func(p: Vector2) -> void: log.append("drag_start"))
	g.drag_ended.connect(func(p: Vector2, v: Vector2) -> void: log.append("drag_end"))
	g.pinched.connect(func(f: float, c: Vector2) -> void: log.append("pinch:%.2f" % f))
	g.handle(_touch(0, Vector2(100, 100), true))
	g.handle(_touch(0, Vector2(101, 100), false))
	check(log.has("tap"), "tap recognized")
	log.clear()
	g.handle(_touch(0, Vector2(100, 100), true))
	g.handle(_drag(0, Vector2(200, 100), Vector2(100, 0)))
	g.handle(_touch(0, Vector2(200, 100), false))
	check(log.has("drag_start") and log.has("drag_end"), "drag recognized: %s" % str(log))
	log.clear()
	g.handle(_touch(0, Vector2(100, 100), true))
	g.handle(_touch(1, Vector2(200, 100), true))
	g.handle(_drag(1, Vector2(300, 100), Vector2(100, 0)))
	check(log.has("pinch:2.00"), "pinch factor 2: %s" % str(log))
	g.handle(_touch(1, Vector2(300, 100), false))
	g.handle(_touch(0, Vector2(100, 100), false))
	check(not log.has("tap"), "multi-touch does not tap")
	g.queue_free()


func _touch(i: int, p: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = pressed
	return e


func _drag(i: int, p: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = i
	e.position = p
	e.relative = rel
	return e
