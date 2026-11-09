extends OVTestCase

const DIR: String = "user://ov_tests"


func test_save_and_backup() -> void:
	var path: String = DIR.path_join("save.json")
	OVSaveStore.delete(path)
	check_eq(OVSaveStore.write_json(path, {"level": 3}, 2), OK, "first write")
	check_eq(OVSaveStore.write_json(path, {"level": 4}, 2), OK, "second write")
	var d: Dictionary = OVSaveStore.read_json(path)
	check_eq(int(d.level), 4, "latest value")
	check_eq(int(d.schema), 2, "schema stored")
	# Corrupt the primary file: the backup (level 3) must be used.
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	var d2: Dictionary = OVSaveStore.read_json(path)
	check_eq(int(d2.get("level", -1)), 3, "falls back to backup")
	OVSaveStore.delete(path)
	var d3: Dictionary = OVSaveStore.read_json(path, {"level": 0})
	check_eq(int(d3.level), 0, "defaults when nothing exists")


func _folded_corners() -> PackedVector3Array:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0.5, 0), Vector2(0.5, 1), OVCore.Assign.VALLEY)
	var doc: OVFoldDocument = cp.to_document()
	var s: OVHingeSolver = OVHingeSolver.new()
	s.build(doc)
	s.set_angle(0, 120.0)
	s.update()
	var pm: OVPaperMesh = OVPaperMesh.new()
	pm.setup(doc)
	pm.update_from_hinge_solver(s)
	return pm.corner_positions()


func test_obj_export() -> void:
	var corners: PackedVector3Array = _folded_corners()
	var text: String = OVExporter.obj_text(corners)
	var v: int = 0
	var f: int = 0
	for line in text.split("\n"):
		if line.begins_with("v "):
			v += 1
		elif line.begins_with("f "):
			f += 1
	check_eq(v, corners.size(), "one vertex per corner")
	check_eq(f, corners.size() / 3 * 2, "front and back faces")
	check(OVExporter.mtl_text(Color.WHITE, Color.RED).contains("paper_back"), "mtl has back material")


func test_glb_export() -> void:
	var corners: PackedVector3Array = _folded_corners()
	var path: String = DIR.path_join("model.glb")
	DirAccess.make_dir_recursive_absolute(DIR)
	var err: Error = OVExporter.write_glb(path, corners, Color.WHITE, Color.RED, "Test Fold")
	check_eq(err, OK, "glb written")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(bytes.size() > 200, "glb has content (%d bytes)" % bytes.size())
	check_eq(bytes.slice(0, 4).get_string_from_ascii(), "glTF", "glb magic")
	var mem: PackedByteArray = OVExporter.glb_bytes(corners, Color.WHITE, Color.RED)
	check(mem.size() > 200, "in-memory glb")


func test_fold_export_has_folded_frame() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0), Vector2(1, 1), OVCore.Assign.VALLEY)
	var doc: OVFoldDocument = cp.to_document()
	var folded: PackedVector3Array = doc.vertices.duplicate()
	folded[0].y = 0.5
	var text: String = OVExporter.fold_text(doc, folded, "My fold")
	var r: Dictionary = OVFoldDocument.from_json(text)
	check(r.ok, "exported FOLD re-imports")
	check_eq((r.value as OVFoldDocument).meta.get("file_title"), "My fold", "title")
	check_eq((r.value as OVFoldDocument).frames.size(), 1, "folded frame present")


func test_feature_gate() -> void:
	check(OVFeatureGate.is_unlocked("any.feature"), "everything unlocked in this release")
	OVFeatureGate.unlock_all = false
	check(not OVFeatureGate.is_unlocked("pro.export"), "locked when gate enabled")
	OVFeatureGate.grant("pro.export")
	check(OVFeatureGate.is_unlocked("pro.export"), "granted")
	OVFeatureGate.unlock_all = true
