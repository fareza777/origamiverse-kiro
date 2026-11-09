extends OVTestCase
## Every template must planarize into a valid document and fold without NaN or runaway strain.


func test_template_count() -> void:
	check(PVTemplates.all().size() >= 13, "at least 12 templates plus blank (got %d)" % PVTemplates.all().size())


func test_templates_fold() -> void:
	for t in PVTemplates.all():
		if t.id == "blank":
			continue
		var cp: OVCreasePattern = PVTemplates.make_pattern(t)
		var doc: OVFoldDocument = cp.to_document()
		check(doc.validate().is_empty(), "%s valid" % t.id)
		check(doc.face_count() > 0, "%s has faces" % t.id)
		var s: OVBarHingeSolver = OVBarHingeSolver.new()
		if not check(s.setup(doc).ok, "%s solver setup" % t.id):
			continue
		var target: float = float(t.fold_percent)
		var t0: int = Time.get_ticks_usec()
		var frames: int = 0
		for i in 8:
			s.fold_percent = target * float(i + 1) / 8.0
			for k in 15:
				s.step()
				frames += 1
		for k in 60:
			s.step()
			frames += 1
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0 / frames
		print("    %-18s tris=%3d  strain=%.3f%%  err=%5.1f deg  %.2f ms/frame" % [t.id, doc.face_count(), s.strain * 100.0, s.crease_error_degrees(), ms])
		check(s.is_finite_state(), "%s finite" % t.id)
		check(s.strain < 0.03, "%s strain under 3%% (%.4f)" % [t.id, s.strain])
		check(doc.face_count() <= 400, "%s within the 400-triangle mobile budget" % t.id)


func test_tray_is_rigid_foldable() -> void:
	var doc: OVFoldDocument = PVTemplates.make_pattern(PVTemplates.by_id("box_tray")).to_document()
	var h: OVHingeSolver = OVHingeSolver.new()
	var r: Dictionary = h.build(doc, 0)
	check(r.ok, "tray builds as a hinge tree: %s" % str(r.errors))
	check_eq(h.hinge_count(), 4, "four walls")


func test_project_round_trip() -> void:
	var p: PVProject = PVProject.from_template(PVTemplates.by_id("waterbomb_base"))
	p.name = "Round trip"
	p.material = OVPaperPresets.by_id("gold_foil").duplicate()
	p.fold_percent = 0.42
	p.pin_face = 2
	var text: String = p.to_fold_text()
	var r: Dictionary = PVProject.from_fold_text(text)
	check(r.ok, "re-imports")
	var q: PVProject = r.value
	check_eq(q.name, "Round trip", "name")
	check_eq(q.pattern.segments.size(), p.pattern.segments.size(), "segments")
	check_near(q.fold_percent, 0.42, 1e-6, "fold percent")
	check_eq(q.pin_face, 2, "pin")
	check((q.material.back as Color).is_equal_approx(p.material.back), "material")
	check(q.timeline.has_keys("fold"), "timeline")
	# Plain FOLD (no PaperVerse keys) imports through the crease-pattern reconstruction.
	var plain: OVFoldDocument = p.build_document()
	var r2: Dictionary = PVProject.from_fold_text(plain.to_json(), "Plain")
	check(r2.ok, "plain FOLD imports")
	var creases: int = 0
	for s in (r2.value as PVProject).pattern.segments:
		if OVCore.is_crease(s.assign):
			creases += 1
	check(creases >= 4, "creases recovered from plain FOLD (%d)" % creases)


func test_store() -> void:
	var p: PVProject = PVProject.from_template(PVTemplates.by_id("half_fold"))
	check_eq(PVProjectStore.save(p), OK, "saved")
	var found: bool = false
	for info in PVProjectStore.list():
		if info.id == p.id:
			found = true
	check(found, "listed")
	var copy_id: String = PVProjectStore.duplicate_project(p.id)
	check(copy_id != "" and PVProjectStore.load_project(copy_id).ok, "duplicate loads")
	PVProjectStore.delete(p.id)
	PVProjectStore.delete(copy_id)
	check(not PVProjectStore.load_project(p.id).ok, "deleted")
