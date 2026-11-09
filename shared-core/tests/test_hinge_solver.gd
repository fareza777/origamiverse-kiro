extends OVTestCase

const A := OVCore.Assign


func _strips(cuts: Array, assign: int = A.VALLEY) -> OVFoldDocument:
	var cp: OVCreasePattern = OVCreasePattern.new()
	for x in cuts:
		cp.add_segment(Vector2(x, 0), Vector2(x, 1), assign)
	return cp.to_document()


func _face_with_point(doc: OVFoldDocument, uv: Vector2) -> int:
	for fi in doc.face_count():
		var f: PackedInt32Array = doc.faces[fi]
		var tri: PackedVector2Array = PackedVector2Array()
		for vi in f:
			tri.append(OVCore.sheet_uv(doc.vertices[vi]))
		if Geometry2D.is_point_in_polygon(uv, tri):
			return fi
	return -1


func test_half_valley_90() -> void:
	var doc: OVFoldDocument = _strips([0.5])
	var s: OVHingeSolver = OVHingeSolver.new()
	s.thickness = 0.0
	var r: Dictionary = s.build(doc, _face_with_point(doc, Vector2(0.2, 0.5)))
	check(r.ok, "builds: %s" % str(r.errors))
	check_eq(s.panel_count(), 2, "two panels")
	check_eq(s.hinge_count(), 1, "one hinge")
	s.set_angle(0, 90.0)
	s.update()
	var child: int = s.hinge_child[0]
	var p: Vector3 = s.panel_transforms[child] * OVCore.fold_to_godot(1.0, 0.5)
	check_vec_near(p, Vector3(0.5, 0.5, -0.5), 1e-5, "valley lifts the far edge straight up")


func test_mountain_goes_down() -> void:
	var doc: OVFoldDocument = _strips([0.5], A.MOUNTAIN)
	var s: OVHingeSolver = OVHingeSolver.new()
	s.thickness = 0.0
	s.build(doc, _face_with_point(doc, Vector2(0.2, 0.5)))
	s.apply_fold_percent(0.5)  # -180 * 0.5 = -90
	s.update()
	var p: Vector3 = s.panel_transforms[s.hinge_child[0]] * OVCore.fold_to_godot(1.0, 0.5)
	check_vec_near(p, Vector3(0.5, -0.5, -0.5), 1e-5, "mountain folds down")


func test_flat_fold_thickness() -> void:
	var doc: OVFoldDocument = _strips([0.5])
	var s: OVHingeSolver = OVHingeSolver.new()
	s.thickness = 0.01
	s.build(doc, _face_with_point(doc, Vector2(0.2, 0.5)))
	s.set_angle(0, 180.0)
	s.update()
	var p: Vector3 = s.panel_transforms[s.hinge_child[0]] * OVCore.fold_to_godot(1.0, 0.5)
	check_vec_near(p, Vector3(0.0, 0.01, -0.5), 1e-5, "180 degree fold lands one thickness above")


func test_root_choice_symmetry() -> void:
	var doc: OVFoldDocument = _strips([0.5])
	var s: OVHingeSolver = OVHingeSolver.new()
	s.thickness = 0.0
	s.build(doc, _face_with_point(doc, Vector2(0.8, 0.5)))
	s.set_angle(0, 90.0)
	s.update()
	var p: Vector3 = s.panel_transforms[s.hinge_child[0]] * OVCore.fold_to_godot(0.0, 0.5)
	check_vec_near(p, Vector3(0.5, 0.5, -0.5), 1e-5, "valley is symmetric regardless of root")


func test_nested_u_shape() -> void:
	var doc: OVFoldDocument = _strips([1.0 / 3.0, 2.0 / 3.0])
	var s: OVHingeSolver = OVHingeSolver.new()
	s.thickness = 0.0
	s.build(doc, _face_with_point(doc, Vector2(0.5, 0.5)))
	check_eq(s.hinge_count(), 2, "two hinges")
	s.apply_fold_percent(0.5)
	s.update()
	var left: Vector3 = s.vertex_positions()[0]
	for vi in doc.vertex_count():
		var uv: Vector2 = OVCore.sheet_uv(doc.vertices[vi])
		if uv.is_equal_approx(Vector2(0, 0)):
			left = s.vertex_positions()[vi]
	check_vec_near(left, Vector3(1.0 / 3.0, 1.0 / 3.0, 0.0), 1e-5, "outer corner of U rises")


func test_chain_of_three_hinges() -> void:
	var doc: OVFoldDocument = _strips([0.25, 0.5, 0.75])
	var s: OVHingeSolver = OVHingeSolver.new()
	s.thickness = 0.0
	s.build(doc, _face_with_point(doc, Vector2(0.1, 0.5)))
	for h in s.hinge_count():
		s.set_angle(h, 90.0)
	s.update()
	# Four 90 degree valleys from the left strip close the strip into a square tube outline.
	var far: Vector3
	for vi in doc.vertex_count():
		if OVCore.sheet_uv(doc.vertices[vi]).is_equal_approx(Vector2(1, 0)):
			far = s.vertex_positions()[vi]
	check_vec_near(far, Vector3(0, 0, 0), 1e-4, "strip closes into a square loop")


func test_cycle_detected() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0.5, 0), Vector2(0.5, 1), A.VALLEY)
	cp.add_segment(Vector2(0, 0.5), Vector2(1, 0.5), A.VALLEY)
	var s: OVHingeSolver = OVHingeSolver.new()
	var r: Dictionary = s.build(cp.to_document())
	check(not r.ok, "four panels around a vertex form a loop")


func test_cut_separates_panels() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0.5, 0), Vector2(0.5, 0.5), A.CUT)
	cp.add_segment(Vector2(0.5, 0.5), Vector2(0.5, 1), A.VALLEY)
	cp.add_segment(Vector2(0, 0.5), Vector2(1, 0.5), A.VALLEY)
	var s: OVHingeSolver = OVHingeSolver.new()
	var r: Dictionary = s.build(cp.to_document())
	check(r.ok, "cut opens the loop: %s" % str(r.errors))
	check_eq(s.hinge_count(), 3, "three hinges in a tree")
