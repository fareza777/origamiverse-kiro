extends OVTestCase


func _square_with_diagonal(assign: String = "V") -> String:
	return JSON.stringify({
		"file_spec": 1.2,
		"vertices_coords": [[0, 0], [1, 0], [1, 1], [0, 1]],
		"edges_vertices": [[0, 1], [1, 2], [2, 3], [3, 0], [0, 2]],
		"edges_assignment": ["B", "B", "B", "B", assign],
		"faces_vertices": [[0, 1, 2], [0, 2, 3]],
	})


func test_parse_basic() -> void:
	var r: Dictionary = OVFoldDocument.from_json(_square_with_diagonal())
	check(r.ok, "parses: %s" % str(r.errors))
	var doc: OVFoldDocument = r.value
	check_eq(doc.vertex_count(), 4, "vertex count")
	check_eq(doc.edge_count(), 5, "edge count")
	check_eq(doc.face_count(), 2, "face count")
	check_eq(doc.assignments[4], OVCore.Assign.VALLEY, "valley assignment")
	check_near(doc.fold_angles[4], 180.0, 1e-6, "valley angle derived")
	check_vec_near(doc.vertices[2], Vector3(1, 0, -1), 1e-6, "FOLD (1,1) maps to Godot (1,0,-1)")
	check(not doc.is_3d, "flat document")


func test_mountain_default_angle() -> void:
	var doc: OVFoldDocument = OVFoldDocument.from_json(_square_with_diagonal("M")).value
	check_near(doc.fold_angles[4], -180.0, 1e-6, "mountain angle derived")


func test_round_trip() -> void:
	var doc: OVFoldDocument = OVFoldDocument.from_json(_square_with_diagonal()).value
	doc.meta["file_title"] = "Diagonal"
	doc.extra["paperverse:note"] = "kept"
	var again: Dictionary = OVFoldDocument.from_json(doc.to_json())
	check(again.ok, "re-parses")
	var d2: OVFoldDocument = again.value
	check_eq(d2.vertices, doc.vertices, "vertices equal")
	check_eq(d2.edges, doc.edges, "edges equal")
	check_eq(d2.assignments, doc.assignments, "assignments equal")
	check_eq(d2.fold_angles, doc.fold_angles, "angles equal")
	check_eq(d2.meta.get("file_title"), "Diagonal", "title kept")
	check_eq(d2.extra.get("paperverse:note"), "kept", "namespaced key kept")
	var raw: Dictionary = JSON.parse_string(doc.to_json())
	check_eq(raw.file_spec, 1.2, "file_spec 1.2")
	check(str(raw.file_creator).begins_with("OrigamiVerse Core"), "creator set")


func test_folded_frame_export() -> void:
	var doc: OVFoldDocument = OVFoldDocument.from_json(_square_with_diagonal()).value
	var folded: PackedVector3Array = doc.vertices.duplicate()
	folded[1] = Vector3(0.5, 0.7, -0.5)
	var raw: Dictionary = JSON.parse_string(doc.to_json(folded))
	check(raw.has("file_frames"), "has frames")
	var frame: Dictionary = raw.file_frames[0]
	check(frame.frame_classes.has("foldedForm"), "folded frame class")
	check_near(float(frame.vertices_coords[1][2]), 0.7, 1e-6, "folded z = Godot y")


func test_validation_errors() -> void:
	var bad: String = JSON.stringify({
		"vertices_coords": [[0, 0], [1, 0]],
		"edges_vertices": [[0, 5], [1, 1]],
		"edges_assignment": ["B", "B"],
	})
	var r: Dictionary = OVFoldDocument.from_json(bad)
	check(not r.ok, "invalid doc rejected")
	check(r.errors.size() >= 2, "both problems reported: %s" % str(r.errors))
	check(not OVFoldDocument.from_json("not json").ok, "garbage rejected")
	check(not OVFoldDocument.from_json("[1,2]").ok, "non-object rejected")


func test_edges_from_faces() -> void:
	var r: Dictionary = OVFoldDocument.from_json(JSON.stringify({
		"vertices_coords": [[0, 0], [1, 0], [1, 1], [0, 1]],
		"faces_vertices": [[0, 1, 2], [0, 2, 3]],
	}))
	check(r.ok, "faces-only doc parses")
	var doc: OVFoldDocument = r.value
	check_eq(doc.edge_count(), 5, "edges derived")
	var diag: int = doc.find_edge(0, 2)
	check_eq(doc.assignments[diag], OVCore.Assign.FLAT, "shared edge is flat")
	check_eq(doc.assignments[doc.find_edge(0, 1)], OVCore.Assign.BOUNDARY, "outer edge is boundary")


func test_triangulate_polygon_faces() -> void:
	var r: Dictionary = OVFoldDocument.from_json(JSON.stringify({
		"vertices_coords": [[0, 0], [2, 0], [2, 1], [1, 0.4], [0, 1]],
		"edges_vertices": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]],
		"edges_assignment": ["B", "B", "B", "B", "B"],
		"faces_vertices": [[0, 1, 2, 3, 4]],
	}))
	var doc: OVFoldDocument = r.value
	var tri: OVFoldDocument = doc.triangulated()
	check_eq(tri.face_count(), 3, "concave pentagon -> 3 triangles")
	check_eq(tri.edge_count(), 7, "2 diagonals added")
	var area: float = 0.0
	for f in tri.faces:
		var a: Vector2 = OVCore.sheet_uv(tri.vertices[f[0]])
		var b: Vector2 = OVCore.sheet_uv(tri.vertices[f[1]])
		var c: Vector2 = OVCore.sheet_uv(tri.vertices[f[2]])
		var s: float = (b - a).cross(c - a) * 0.5
		check(s > 0.0, "triangle keeps CCW winding")
		area += s
	check_near(area, 2.0 - 0.6, 1e-5, "area preserved")


func test_reference_examples_parse() -> void:
	for name in ["simple.fold", "squaretwist.fold", "box.fold"]:
		var text: String = FileAccess.get_file_as_string("res://tests/data/" + name)
		var r: Dictionary = OVFoldDocument.from_json(text)
		check(r.ok, "%s parses: %s" % [name, str(r.errors)])
		if r.ok:
			var doc: OVFoldDocument = r.value
			check(doc.face_count() > 0, "%s has faces" % name)
			var again: Dictionary = OVFoldDocument.from_json(doc.to_json())
			check(again.ok and (again.value as OVFoldDocument).vertex_count() == doc.vertex_count(), "%s round trips" % name)
