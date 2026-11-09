extends OVTestCase

const A := OVCore.Assign


func _count(doc: OVFoldDocument, a: int) -> int:
	var n: int = 0
	for x in doc.assignments:
		if x == a:
			n += 1
	return n


func test_single_diagonal() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0), Vector2(1, 1), A.VALLEY)
	var doc: OVFoldDocument = cp.to_document()
	check_eq(doc.vertex_count(), 4, "4 corners")
	check_eq(doc.face_count(), 2, "2 triangles")
	check_eq(_count(doc, A.BOUNDARY), 4, "4 boundary edges")
	check_eq(_count(doc, A.VALLEY), 1, "1 valley")
	check(doc.validate().is_empty(), "valid")


func test_crossing_diagonals_split() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0), Vector2(1, 1), A.VALLEY)
	cp.add_segment(Vector2(1, 0), Vector2(0, 1), A.MOUNTAIN)
	var doc: OVFoldDocument = cp.to_document()
	check_eq(doc.vertex_count(), 5, "center vertex created")
	check_eq(doc.face_count(), 4, "4 triangles")
	check_eq(_count(doc, A.VALLEY), 2, "valley split in 2")
	check_eq(_count(doc, A.MOUNTAIN), 2, "mountain split in 2")


func test_t_junction_and_grid() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0.5, 0), Vector2(0.5, 1), A.VALLEY)
	cp.add_segment(Vector2(0, 0.5), Vector2(0.5, 0.5), A.MOUNTAIN)
	var doc: OVFoldDocument = cp.to_document()
	# Faces: right half is a pentagon (the T vertex sits on its edge) -> 3 tris, plus two left quarters -> 2 each.
	check_eq(doc.face_count(), 7, "T junction faces")
	var area: float = 0.0
	for f in doc.faces:
		var a: Vector2 = OVCore.sheet_uv(doc.vertices[f[0]])
		area += (OVCore.sheet_uv(doc.vertices[f[1]]) - a).cross(OVCore.sheet_uv(doc.vertices[f[2]]) - a) * 0.5
	check_near(area, 1.0, 1e-5, "covers the sheet exactly")


func test_dangling_crease_ignored() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0.2, 0.2), Vector2(0.6, 0.6), A.VALLEY)
	var doc: OVFoldDocument = cp.to_document()
	check_eq(doc.face_count(), 2, "square only (fan of 2)")
	check(not cp.last_warnings.is_empty(), "warning reported")


func test_segment_clipped_to_sheet() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(-1, 0.5), Vector2(2, 0.5), A.VALLEY)
	var doc: OVFoldDocument = cp.to_document()
	check_eq(doc.face_count(), 4, "two rectangles")
	for p in doc.vertices:
		var uv: Vector2 = OVCore.sheet_uv(p)
		check(uv.x >= -1e-6 and uv.x <= 1.0 + 1e-6, "inside sheet")


func test_snap() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0), Vector2(1, 1), A.VALLEY)
	check_vec2(cp.snap(Vector2(0.98, 0.03), 8, 0.05), Vector2(1, 0), "corner snap")
	check_vec2(cp.snap(Vector2(0.51, 0.49), 8, 0.05), Vector2(0.5, 0.5), "midpoint snap")
	check_vec2(cp.snap(Vector2(0.26, 0.74), 4, 0.05), Vector2(0.25, 0.75), "grid snap")
	var s: Vector2 = cp.snap(Vector2(0.33, 0.13), 0, 0.03, Vector2(0, 0))
	check_near(rad_to_deg(s.angle()), 22.5, 0.01, "22.5 degree angle snap")


func check_vec2(a: Vector2, b: Vector2, msg: String) -> void:
	check(a.distance_to(b) < 1e-4, "%s (expected %s got %s)" % [msg, str(b), str(a)])


func test_serialize_round_trip() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0), Vector2(1, 1), A.VALLEY, 120.0)
	cp.add_segment(Vector2(0, 1), Vector2(1, 0), A.CUT)
	var cp2: OVCreasePattern = OVCreasePattern.from_dict(JSON.parse_string(JSON.stringify(cp.to_dict())))
	check_eq(cp2.segments.size(), 2, "segments kept")
	check_near(cp2.segments[0].angle, 120.0, 1e-6, "angle kept")
	check_eq(cp2.segments[1].assign, A.CUT, "assignment kept")


func test_from_document() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0.5, 0), Vector2(0.5, 1), A.MOUNTAIN)
	var doc: OVFoldDocument = cp.to_document()
	var back: OVCreasePattern = OVCreasePattern.from_document(doc)
	check_eq(back.outline.size(), 4, "square outline recovered")
	var creases: int = 0
	for s in back.segments:
		if s.assign == A.MOUNTAIN:
			creases += 1
	check_eq(creases, 1, "mountain recovered")
