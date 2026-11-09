extends OVTestCase

const A := OVCore.Assign


func test_paper_mesh_codes() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0), Vector2(1, 1), A.VALLEY)
	var doc: OVFoldDocument = cp.to_document()
	var pm: OVPaperMesh = OVPaperMesh.new()
	pm.setup(doc, OVPaperMesh.make_material(OVPaperPresets.by_id("kami_coral")))
	check_eq(pm.triangle_count, 2, "two triangles")
	check_eq(pm.mesh.get_surface_count(), 1, "one surface")
	var arrays: Array = pm.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var valley_found: int = 0
	var edge_found: int = 0
	for c in colors:
		# Vertex colors are stored as 8-bit, so compare with a quantization tolerance.
		for ch in [c.r, c.g, c.b]:
			if absf(ch - OVPaperMesh.CODE_VALLEY) < 0.01:
				valley_found += 1
			if absf(ch - OVPaperMesh.CODE_EDGE) < 0.01:
				edge_found += 1
	check_eq(valley_found, 6, "diagonal coded valley on both triangles (3 corners each)")
	check_eq(edge_found, 12, "4 boundary edges coded")
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	check_vec_near(normals[0], Vector3.UP, 1e-3, "flat sheet front faces +Y")


func test_paper_mesh_follows_hinge_solver() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0.5, 0), Vector2(0.5, 1), A.VALLEY)
	var doc: OVFoldDocument = cp.to_document()
	var s: OVHingeSolver = OVHingeSolver.new()
	s.build(doc)
	s.set_angle(0, 90.0)
	s.update()
	var pm: OVPaperMesh = OVPaperMesh.new()
	pm.setup(doc)
	pm.update_from_hinge_solver(s)
	check(pm.aabb().size.y > 0.45, "mesh is folded (height %.3f)" % pm.aabb().size.y)


func test_presets_round_trip() -> void:
	var p: Dictionary = OVPaperPresets.by_id("washi_indigo")
	var d: Dictionary = JSON.parse_string(JSON.stringify(OVPaperPresets.to_dict(p)))
	var back: Dictionary = OVPaperPresets.from_dict(d)
	check((back.back as Color).is_equal_approx(p.back), "color restored")
	check_eq(OVPaperPresets.by_id("missing").id, "kami_coral", "unknown id falls back")


func test_timeline_sampling() -> void:
	var tl: OVTimeline = OVTimeline.new()
	tl.set_key("fold", 0.0, 0.0, OVTimeline.Ease.LINEAR)
	tl.set_key("fold", 2.0, 1.0, OVTimeline.Ease.SMOOTH)
	tl.set_key("fold", 1.0, 0.25, OVTimeline.Ease.LINEAR)
	check_eq(tl.keys("fold").size(), 3, "three keys sorted")
	check_near(tl.sample("fold", 0.5), 0.125, 1e-6, "linear segment")
	check_near(tl.sample("fold", 1.5), 0.625, 1e-6, "linear key -> midpoint")
	check_near(tl.sample("fold", -1.0), 0.0, 1e-6, "clamped before")
	check_near(tl.sample("fold", 9.0), 1.0, 1e-6, "clamped after")
	check_near(tl.sample("missing", 1.0, 0.7), 0.7, 1e-6, "fallback")
	tl.set_key("fold", 1.0, 0.5, OVTimeline.Ease.HOLD)
	check_eq(tl.keys("fold").size(), 3, "same time overwrites")
	check_near(tl.sample("fold", 1.9), 0.5, 1e-6, "hold ease")
	var tl2: OVTimeline = OVTimeline.from_dict(JSON.parse_string(JSON.stringify(tl.to_dict())))
	check_near(tl2.sample("fold", 0.5), tl.sample("fold", 0.5), 1e-6, "serialization")
	for e in OVTimeline.Ease.values():
		check_near(OVTimeline.apply_ease(e, 1.0), 1.0, 1e-4, "ease %d ends at 1" % e)
		if e != OVTimeline.Ease.HOLD:
			check_near(OVTimeline.apply_ease(e, 0.0), 0.0, 1e-4, "ease %d starts at 0" % e)


func test_spring_settles() -> void:
	var sp: OVSpring = OVSpring.new(0.0, 4.0, 0.8)
	sp.target = 90.0
	for i in 120:
		sp.step(1.0 / 60.0)
	check(sp.is_settled(0.5), "spring settles in 2 s (value %.3f)" % sp.value)
	sp.step(0.5)
	check(is_finite(sp.value), "large dt stays finite")


func test_undo_redo() -> void:
	var stack: OVUndoStack = OVUndoStack.new()
	var state: Array = [0]
	stack.perform("add 1", func() -> void: state[0] += 1, func() -> void: state[0] -= 1)
	stack.perform("add 10", func() -> void: state[0] += 10, func() -> void: state[0] -= 10)
	check_eq(state[0], 11, "applied")
	check_eq(stack.undo_label(), "add 10", "label")
	stack.undo()
	check_eq(state[0], 1, "undo")
	stack.redo()
	check_eq(state[0], 11, "redo")
	stack.undo()
	stack.perform("add 5", func() -> void: state[0] += 5, func() -> void: state[0] -= 5)
	check(not stack.can_redo(), "new action clears redo")
	stack.max_history = 3
	for i in 5:
		stack.perform("x", func() -> void: pass, func() -> void: pass)
	check_eq(stack.size(), 3, "history capped")
