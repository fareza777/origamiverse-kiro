extends OVTestCase

const A := OVCore.Assign


func _run(s: OVBarHingeSolver, frames: int) -> void:
	for i in frames:
		s.step(1.0 / 60.0)


func test_diagonal_valley_half() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0), Vector2(1, 1), A.VALLEY)
	var s: OVBarHingeSolver = OVBarHingeSolver.new()
	check(s.setup(cp.to_document(), 0).ok, "setup")
	s.fold_percent = 0.5
	_run(s, 90)
	check(s.is_finite_state(), "finite")
	var crease: int = s.hinge_is_crease.find(1)
	check_near(rad_to_deg(s.current_angle(crease)), 90.0, 3.0, "valley reaches 90 degrees")
	var maxy: float = -INF
	for p in s.positions:
		maxy = maxf(maxy, p.y)
	check(maxy > 0.3, "free wing rises (valley folds up), max y = %.3f" % maxy)
	check(s.strain < 0.01, "low strain %.5f" % s.strain)


func test_mountain_goes_down() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0), Vector2(1, 1), A.MOUNTAIN)
	var s: OVBarHingeSolver = OVBarHingeSolver.new()
	s.setup(cp.to_document(), 0)
	s.fold_percent = 0.5
	_run(s, 90)
	var miny: float = INF
	for p in s.positions:
		miny = minf(miny, p.y)
	check(miny < -0.3, "mountain wing goes down, min y = %.3f" % miny)


func test_near_flat_fold_is_stable() -> void:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0.5), Vector2(1, 0.5), A.VALLEY)
	var s: OVBarHingeSolver = OVBarHingeSolver.new()
	s.setup(cp.to_document())
	for i in 10:
		s.fold_percent = float(i + 1) / 10.0
		_run(s, 20)
	_run(s, 60)
	check(s.is_finite_state(), "finite at 100 %")
	check(s.crease_error_degrees() < 4.0, "reaches near-flat fold, error %.2f deg" % s.crease_error_degrees())


## Waterbomb base: both diagonals mountain, one midline valley (degree-6 vertex, Maekawa |M-V| = 2).
func _square_base() -> OVFoldDocument:
	var cp: OVCreasePattern = OVCreasePattern.new()
	cp.add_segment(Vector2(0, 0), Vector2(1, 1), A.MOUNTAIN)
	cp.add_segment(Vector2(1, 0), Vector2(0, 1), A.MOUNTAIN)
	cp.add_segment(Vector2(0, 0.5), Vector2(1, 0.5), A.VALLEY)
	return cp.to_document()


func test_square_base_converges() -> void:
	var s: OVBarHingeSolver = OVBarHingeSolver.new()
	s.setup(_square_base())
	for i in 6:
		s.fold_percent = 0.1 * (i + 1)
		_run(s, 30)
	_run(s, 60)
	check(s.is_finite_state(), "finite")
	check(s.strain < 0.01, "strain small %.4f" % s.strain)
	# A degree-6 vertex cannot follow uniformly scaled angles exactly; ~10 degrees of compromise is physical.
	check(s.crease_error_degrees() < 14.0, "creases near target, error %.2f" % s.crease_error_degrees())


func test_reset() -> void:
	var s: OVBarHingeSolver = OVBarHingeSolver.new()
	s.setup(_square_base())
	s.fold_percent = 0.5
	_run(s, 20)
	s.reset()
	check_eq(s.positions, s.doc.vertices, "reset restores flat sheet")


func test_performance_grid() -> void:
	# 10x10 grid of alternating creases = 200+ triangles, typical of a detailed template.
	var cp: OVCreasePattern = OVCreasePattern.new()
	for i in range(1, 10):
		var t: float = i / 10.0
		cp.add_segment(Vector2(t, 0), Vector2(t, 1), A.VALLEY if i % 2 == 0 else A.MOUNTAIN)
	for j in range(1, 6):
		var t2: float = j / 6.0
		cp.add_segment(Vector2(0, t2), Vector2(1, t2), A.FLAT)
	var doc: OVFoldDocument = cp.to_document()
	var s: OVBarHingeSolver = OVBarHingeSolver.new()
	s.setup(doc)
	s.fold_percent = 0.6
	var t0: int = Time.get_ticks_usec()
	_run(s, 30)
	var per_frame_ms: float = (Time.get_ticks_usec() - t0) / 1000.0 / 30.0
	print("    bar-hinge: %d tris, %d hinges, %.2f ms/frame (desktop)" % [doc.face_count(), s.hinge_a.size(), per_frame_ms])
	check(s.is_finite_state(), "finite")
	check(per_frame_ms < 16.0, "fits a 60 FPS frame on desktop")
