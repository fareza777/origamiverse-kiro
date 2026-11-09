class_name OVHingeSolver
extends RefCounted
## Exact rigid folding for crease patterns whose panels form a tree of straight hinges.
## Used by FoldShift for world panels and by PaperVerse for its "rigid" preview mode.

var doc: OVFoldDocument
var thickness: float = OVCore.PAPER_THICKNESS
var root_transform: Transform3D = Transform3D.IDENTITY

var panel_of_face: PackedInt32Array = PackedInt32Array()
var panel_faces: Array[PackedInt32Array] = []
var panel_transforms: Array[Transform3D] = []
var panel_parent_hinge: PackedInt32Array = PackedInt32Array()   ## -1 for the root
var panel_order: PackedInt32Array = PackedInt32Array()          ## parents before children
var root_panel: int = 0

## Per hinge data.
var hinge_parent: PackedInt32Array = PackedInt32Array()
var hinge_child: PackedInt32Array = PackedInt32Array()
var hinge_pivot: PackedVector3Array = PackedVector3Array()
var hinge_axis: PackedVector3Array = PackedVector3Array()
var hinge_angle: PackedFloat32Array = PackedFloat32Array()       ## current, degrees
var hinge_fold_angle: PackedFloat32Array = PackedFloat32Array()  ## FOLD target, degrees
var hinge_edges: Array[PackedInt32Array] = []
var edge_hinge: PackedInt32Array = PackedInt32Array()            ## doc edge -> hinge or -1

var _dirty: bool = true


## Builds panels and the hinge tree. Returns OVCore.ok()/fail().
func build(document: OVFoldDocument, root_face: int = 0) -> Dictionary:
	doc = document
	var errors: PackedStringArray = PackedStringArray()
	if doc.is_3d:
		return OVCore.fail(PackedStringArray(["Rigid folding needs a flat crease pattern."]))
	var nf: int = doc.face_count()
	if nf == 0:
		return OVCore.fail(PackedStringArray(["Document has no faces."]))

	# Edge -> faces.
	var edge_faces: Array = []
	edge_faces.resize(doc.edge_count())
	for e in doc.edge_count():
		edge_faces[e] = PackedInt32Array()
	for fi in nf:
		var f: PackedInt32Array = doc.faces[fi]
		for i in f.size():
			var e: int = doc.find_edge(f[i], f[(i + 1) % f.size()])
			if e >= 0:
				edge_faces[e].append(fi)

	# Union-find faces across non-hinge, non-cut edges.
	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(nf)
	for i in nf:
		parent[i] = i
	for e in doc.edge_count():
		var a: int = doc.assignments[e]
		if OVCore.is_crease(a) or a == OVCore.Assign.CUT or a == OVCore.Assign.BOUNDARY:
			continue
		var ef: PackedInt32Array = edge_faces[e]
		if ef.size() == 2:
			_union(parent, ef[0], ef[1])
	var panel_id: Dictionary = {}
	panel_of_face.resize(nf)
	panel_faces = []
	for fi in nf:
		var r: int = _find(parent, fi)
		if not panel_id.has(r):
			panel_id[r] = panel_faces.size()
			panel_faces.append(PackedInt32Array())
		panel_of_face[fi] = panel_id[r]
		panel_faces[panel_id[r]].append(fi)
	var np: int = panel_faces.size()

	# Group crease edges by panel pair.
	var pair_edges: Dictionary = {}
	edge_hinge.resize(doc.edge_count())
	edge_hinge.fill(-1)
	for e in doc.edge_count():
		if not OVCore.is_crease(doc.assignments[e]):
			continue
		var ef: PackedInt32Array = edge_faces[e]
		if ef.size() != 2:
			continue
		var p0: int = panel_of_face[ef[0]]
		var p1: int = panel_of_face[ef[1]]
		if p0 == p1:
			errors.append("Crease edge %d lies inside a single rigid panel; it needs a cut or more creases to fold." % e)
			continue
		var key: Vector2i = Vector2i(mini(p0, p1), maxi(p0, p1))
		if not pair_edges.has(key):
			pair_edges[key] = PackedInt32Array()
		pair_edges[key].append(e)

	# BFS spanning tree from the root panel.
	root_panel = panel_of_face[clampi(root_face, 0, nf - 1)]
	var adjacency: Array = []
	adjacency.resize(np)
	for i in np:
		adjacency[i] = []
	for key in pair_edges.keys():
		adjacency[key.x].append(key)
		adjacency[key.y].append(key)
	panel_parent_hinge.resize(np)
	panel_parent_hinge.fill(-1)
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(np)
	seen[root_panel] = 1
	panel_order = PackedInt32Array([root_panel])
	var used_pairs: Dictionary = {}
	_clear_hinges()
	var head: int = 0
	while head < panel_order.size():
		var p: int = panel_order[head]
		head += 1
		for key in adjacency[p]:
			if used_pairs.has(key):
				continue
			var other: int = key.y if key.x == p else key.x
			if seen[other] == 1:
				errors.append("Panels %d and %d are joined twice (closed loop of hinges); rigid folding cannot solve loops." % [key.x, key.y])
				used_pairs[key] = true
				continue
			used_pairs[key] = true
			seen[other] = 1
			var h: Variant = _make_hinge(p, other, pair_edges[key])
			if h is String:
				errors.append(h)
				continue
			panel_parent_hinge[other] = h
			panel_order.append(other)
	for i in np:
		if seen[i] == 0:
			# Disconnected panel (separated by cuts): it stays attached to the root frame.
			panel_order.append(i)
	panel_transforms.resize(np)
	_dirty = true
	if not errors.is_empty():
		return OVCore.fail(errors)
	update()
	return OVCore.ok(self)


func _clear_hinges() -> void:
	hinge_parent = PackedInt32Array(); hinge_child = PackedInt32Array()
	hinge_pivot = PackedVector3Array(); hinge_axis = PackedVector3Array()
	hinge_angle = PackedFloat32Array(); hinge_fold_angle = PackedFloat32Array()
	hinge_edges = []


func _make_hinge(parent_panel: int, child_panel: int, edge_list: PackedInt32Array) -> Variant:
	# All edges must be collinear.
	var a: Vector3 = doc.vertices[doc.edges[edge_list[0] * 2]]
	var b: Vector3 = doc.vertices[doc.edges[edge_list[0] * 2 + 1]]
	var u: Vector3 = (b - a).normalized()
	for e in edge_list:
		for s in 2:
			var p: Vector3 = doc.vertices[doc.edges[e * 2 + s]]
			if (p - a).cross(u).length() > 1e-4:
				return "Hinge between panels %d and %d is not a straight line." % [parent_panel, child_panel]
	# Orient the axis so that +angle turns the child toward the parent's front (+Y in sheet space).
	var centroid: Vector3 = _panel_centroid(child_panel)
	var d: Vector3 = centroid - a
	d = (d - u * d.dot(u))
	if u.cross(d).dot(Vector3.UP) < 0.0:
		u = -u
	var h: int = hinge_parent.size()
	hinge_parent.append(parent_panel)
	hinge_child.append(child_panel)
	hinge_pivot.append(a)
	hinge_axis.append(u)
	hinge_angle.append(0.0)
	hinge_fold_angle.append(doc.fold_angles[edge_list[0]])
	hinge_edges.append(edge_list)
	for e in edge_list:
		edge_hinge[e] = h
	return h


func _panel_centroid(panel: int) -> Vector3:
	var c: Vector3 = Vector3.ZERO
	var count: int = 0
	for fi in panel_faces[panel]:
		for vi in doc.faces[fi]:
			c += doc.vertices[vi]
			count += 1
	return c / float(maxi(count, 1))


func hinge_count() -> int:
	return hinge_parent.size()


func panel_count() -> int:
	return panel_faces.size()


func set_angle(hinge: int, degrees: float) -> void:
	hinge_angle[hinge] = clampf(degrees, -180.0, 180.0)
	_dirty = true


func get_angle(hinge: int) -> float:
	return hinge_angle[hinge]


## Sets every hinge to its FOLD fold angle scaled by `percent` (0..1).
func apply_fold_percent(percent: float) -> void:
	for h in hinge_count():
		hinge_angle[h] = hinge_fold_angle[h] * percent
	_dirty = true


## Local transform of a hinge rotation in its parent's frame.
func hinge_local_transform(h: int) -> Transform3D:
	var theta: float = deg_to_rad(hinge_angle[h])
	if absf(theta) < 1e-7:
		return Transform3D.IDENTITY
	var pivot: Vector3 = hinge_pivot[h] + Vector3.UP * (signf(theta) * thickness * 0.5)
	var basis: Basis = Basis(hinge_axis[h], theta)
	return Transform3D(basis, pivot - basis * pivot)


## Recomputes all panel transforms (sheet space -> world space).
func update() -> void:
	if not _dirty:
		return
	for p in panel_order:
		var h: int = panel_parent_hinge[p]
		if h < 0:
			panel_transforms[p] = root_transform
		else:
			panel_transforms[p] = panel_transforms[hinge_parent[h]] * hinge_local_transform(h)
	_dirty = false


func mark_dirty() -> void:
	_dirty = true


## World positions of a face's corners.
func face_points(fi: int) -> PackedVector3Array:
	var t: Transform3D = panel_transforms[panel_of_face[fi]]
	var out: PackedVector3Array = PackedVector3Array()
	for vi in doc.faces[fi]:
		out.append(t * doc.vertices[vi])
	return out


## One world position per document vertex (vertices shared by panels use the first panel found).
func vertex_positions() -> PackedVector3Array:
	var out: PackedVector3Array = doc.vertices.duplicate()
	var done: PackedByteArray = PackedByteArray()
	done.resize(out.size())
	for p in panel_order:
		var t: Transform3D = panel_transforms[p]
		for fi in panel_faces[p]:
			for vi in doc.faces[fi]:
				if done[vi] == 0:
					out[vi] = t * doc.vertices[vi]
					done[vi] = 1
	return out


## Panels in the subtree rooted at `panel` (inclusive).
func subtree(panel: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array([panel])
	var i: int = 0
	while i < out.size():
		var p: int = out[i]
		i += 1
		for h in hinge_count():
			if hinge_parent[h] == p:
				out.append(hinge_child[h])
	return out


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra != rb:
		parent[ra] = rb
