class_name OVFoldDocument
extends RefCounted
## In-memory FOLD 1.2 document (https://github.com/edemaine/fold/blob/main/doc/spec.md).
## Coordinates are stored in Godot space (see OVCore.fold_to_godot).

const A := OVCore.Assign

var vertices: PackedVector3Array = PackedVector3Array()
var edges: PackedInt32Array = PackedInt32Array()          ## 2 vertex indices per edge
var assignments: PackedByteArray = PackedByteArray()      ## OVCore.Assign per edge
var fold_angles: PackedFloat32Array = PackedFloat32Array()  ## degrees per edge, valley positive
var faces: Array[PackedInt32Array] = []
var meta: Dictionary = {}       ## file_* and frame_* scalar fields
var frames: Array = []          ## raw extra frames (file_frames)
var extra: Dictionary = {}      ## unknown / namespaced keys preserved on round trip
var is_3d: bool = false

var _edge_lookup: Dictionary = {}


func vertex_count() -> int:
	return vertices.size()


func edge_count() -> int:
	return assignments.size()


func face_count() -> int:
	return faces.size()


func edge_vertex(e: int, side: int) -> int:
	return edges[e * 2 + side]


func add_vertex(p: Vector3) -> int:
	vertices.append(p)
	return vertices.size() - 1


func add_edge(u: int, v: int, assignment: int, fold_angle: float = NAN) -> int:
	edges.append_array([u, v])
	assignments.append(assignment)
	fold_angles.append(OVCore.default_fold_angle(assignment) if is_nan(fold_angle) else fold_angle)
	_edge_lookup.clear()
	return assignments.size() - 1


func add_face(indices: PackedInt32Array) -> int:
	faces.append(indices)
	return faces.size() - 1


## Index of the edge joining u and v, or -1.
func find_edge(u: int, v: int) -> int:
	if _edge_lookup.is_empty() and edge_count() > 0:
		for e in edge_count():
			_edge_lookup[_key(edges[e * 2], edges[e * 2 + 1])] = e
	return _edge_lookup.get(_key(u, v), -1)


## Call after editing arrays directly.
func touch() -> void:
	_edge_lookup.clear()


func duplicate_document() -> OVFoldDocument:
	var d: OVFoldDocument = OVFoldDocument.new()
	d.vertices = vertices.duplicate()
	d.edges = edges.duplicate()
	d.assignments = assignments.duplicate()
	d.fold_angles = fold_angles.duplicate()
	for f in faces:
		d.faces.append(f.duplicate())
	d.meta = meta.duplicate(true)
	d.frames = frames.duplicate(true)
	d.extra = extra.duplicate(true)
	d.is_3d = is_3d
	return d


# ---------------------------------------------------------------- parsing


static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return OVCore.fail(PackedStringArray(["File is not a JSON object."]))
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> Dictionary:
	var doc: OVFoldDocument = OVFoldDocument.new()
	var errors: PackedStringArray = PackedStringArray()
	var coords: Variant = d.get("vertices_coords", [])
	if typeof(coords) != TYPE_ARRAY:
		return OVCore.fail(PackedStringArray(["vertices_coords must be an array."]))
	for c in coords:
		if typeof(c) != TYPE_ARRAY or c.size() < 2:
			return OVCore.fail(PackedStringArray(["Each vertex needs at least 2 coordinates."]))
		var z: float = float(c[2]) if c.size() > 2 else 0.0
		if c.size() > 2 and absf(z) > OVCore.EPS:
			doc.is_3d = true
		doc.vertices.append(OVCore.fold_to_godot(float(c[0]), float(c[1]), z))

	var ev: Variant = d.get("edges_vertices", [])
	var ea: Variant = d.get("edges_assignment", [])
	var efa: Variant = d.get("edges_foldAngle", [])
	if typeof(ev) == TYPE_ARRAY:
		for i in ev.size():
			var pair: Variant = ev[i]
			if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
				errors.append("edges_vertices[%d] must be a pair." % i)
				continue
			var a: int = OVCore.Assign.UNASSIGNED
			if typeof(ea) == TYPE_ARRAY and i < ea.size():
				a = OVCore.assign_from_letter(str(ea[i]))
			var angle: float = NAN
			if typeof(efa) == TYPE_ARRAY and i < efa.size() and efa[i] != null:
				angle = float(efa[i])
			doc.add_edge(int(pair[0]), int(pair[1]), a, angle)

	var fv: Variant = d.get("faces_vertices", [])
	if typeof(fv) == TYPE_ARRAY:
		for f in fv:
			if typeof(f) != TYPE_ARRAY:
				errors.append("faces_vertices entries must be arrays.")
				continue
			var face: PackedInt32Array = PackedInt32Array()
			for idx in f:
				face.append(int(idx))
			doc.faces.append(face)

	for key in d.keys():
		var k: String = str(key)
		if k in ["vertices_coords", "edges_vertices", "edges_assignment", "edges_foldAngle", "faces_vertices"]:
			continue
		if k == "file_frames":
			doc.frames = d[k] if typeof(d[k]) == TYPE_ARRAY else []
		elif k.begins_with("file_") or k.begins_with("frame_"):
			doc.meta[k] = d[k]
		else:
			doc.extra[k] = d[k]

	if not errors.is_empty():
		return OVCore.fail(errors)
	if doc.edge_count() == 0 and doc.face_count() > 0:
		doc.build_edges_from_faces()
	var problems: PackedStringArray = doc.validate()
	if not problems.is_empty():
		return OVCore.fail(problems)
	return OVCore.ok(doc)


## Derives edges from faces: edges used by one face become boundary, shared edges flat.
func build_edges_from_faces() -> void:
	var counts: Dictionary = {}
	var order: Array = []
	for f in faces:
		for i in f.size():
			var k: Vector2i = _key(f[i], f[(i + 1) % f.size()])
			if not counts.has(k):
				order.append(k)
				counts[k] = 0
			counts[k] += 1
	edges.clear(); assignments.clear(); fold_angles.clear()
	for k in order:
		add_edge(k.x, k.y, A.BOUNDARY if counts[k] == 1 else A.FLAT)


## Returns a list of problems; empty means valid.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var n: int = vertices.size()
	if edges.size() != assignments.size() * 2 or fold_angles.size() != assignments.size():
		problems.append("Edge arrays have mismatched lengths.")
		return problems
	for e in edge_count():
		var u: int = edges[e * 2]
		var v: int = edges[e * 2 + 1]
		if u < 0 or v < 0 or u >= n or v >= n:
			problems.append("Edge %d references a missing vertex." % e)
		elif u == v:
			problems.append("Edge %d is degenerate (both ends are vertex %d)." % [e, u])
		elif vertices[u].distance_squared_to(vertices[v]) < 1e-14:
			problems.append("Edge %d has zero length." % e)
		if is_nan(fold_angles[e]) or absf(fold_angles[e]) > 180.0 + OVCore.EPS:
			problems.append("Edge %d fold angle must be within [-180, 180]." % e)
	for fi in faces.size():
		var f: PackedInt32Array = faces[fi]
		if f.size() < 3:
			problems.append("Face %d has fewer than 3 vertices." % fi)
		for idx in f:
			if idx < 0 or idx >= n:
				problems.append("Face %d references a missing vertex." % fi)
				break
	return problems


# ---------------------------------------------------------------- serializing


func to_dict(include_folded_frame: PackedVector3Array = PackedVector3Array()) -> Dictionary:
	var d: Dictionary = {}
	d["file_spec"] = 1.2
	d["file_creator"] = OVCore.CREATOR
	for k in meta.keys():
		if k != "file_spec" and k != "file_creator":
			d[k] = meta[k]
	if not d.has("frame_classes"):
		d["frame_classes"] = ["creasePattern"]
	var coords: Array = []
	for p in vertices:
		var f: PackedFloat64Array = OVCore.godot_to_fold(p)
		coords.append([_r(f[0]), _r(f[1]), _r(f[2])] if is_3d else [_r(f[0]), _r(f[1])])
	d["vertices_coords"] = coords
	var ev: Array = []
	var ea: Array = []
	var efa: Array = []
	for e in edge_count():
		ev.append([edges[e * 2], edges[e * 2 + 1]])
		ea.append(OVCore.assign_to_letter(assignments[e]))
		efa.append(_r(fold_angles[e]))
	d["edges_vertices"] = ev
	d["edges_assignment"] = ea
	d["edges_foldAngle"] = efa
	var fv: Array = []
	for f in faces:
		fv.append(Array(f))
	d["faces_vertices"] = fv
	for k in extra.keys():
		d[k] = extra[k]
	var all_frames: Array = frames.duplicate(true)
	if not include_folded_frame.is_empty():
		var folded: Array = []
		for p in include_folded_frame:
			var f3: PackedFloat64Array = OVCore.godot_to_fold(p)
			folded.append([_r(f3[0]), _r(f3[1]), _r(f3[2])])
		all_frames.append({
			"frame_title": "Folded state",
			"frame_classes": ["foldedForm"],
			"frame_attributes": ["3D"],
			"frame_parent": 0,
			"frame_inherit": true,
			"vertices_coords": folded,
		})
	if not all_frames.is_empty():
		d["file_frames"] = all_frames
	return d


func to_json(include_folded_frame: PackedVector3Array = PackedVector3Array()) -> String:
	return JSON.stringify(to_dict(include_folded_frame), "  ", false)


## Returns a copy whose faces are all triangles. New diagonals are flat (F) edges.
func triangulated() -> OVFoldDocument:
	var d: OVFoldDocument = duplicate_document()
	d.faces = []
	for f in faces:
		if f.size() == 3:
			d.faces.append(f.duplicate())
			continue
		var pts: PackedVector3Array = PackedVector3Array()
		for idx in f:
			pts.append(vertices[idx])
		var tri: PackedInt32Array = OVTriangulator.triangulate(pts)
		for k in range(0, tri.size(), 3):
			var t: PackedInt32Array = PackedInt32Array([f[tri[k]], f[tri[k + 1]], f[tri[k + 2]]])
			d.faces.append(t)
			for s in 3:
				var u: int = t[s]
				var v: int = t[(s + 1) % 3]
				if d.find_edge(u, v) < 0:
					d.add_edge(u, v, A.FLAT, 0.0)
	return d


## Returns a copy where paper is actually separated along cut (C) edges: vertices on a cut get one copy per
## side, so simulations treat the two sides as free. Interior cut tips stay shared (the slit ends there).
func split_along_cuts() -> OVFoldDocument:
	var has_cut: bool = false
	for a in assignments:
		if a == OVCore.Assign.CUT:
			has_cut = true
			break
	if not has_cut:
		return duplicate_document()
	var d: OVFoldDocument = duplicate_document()
	var orig_of: PackedInt32Array = PackedInt32Array()
	orig_of.resize(d.vertex_count())
	for i in d.vertex_count():
		orig_of[i] = i
	var incident: Array = []
	incident.resize(vertex_count())
	for i in vertex_count():
		incident[i] = PackedInt32Array()
	for fi in faces.size():
		for v in faces[fi]:
			incident[v].append(fi)
	for v in vertex_count():
		var fs: PackedInt32Array = incident[v]
		if fs.size() < 2:
			continue
		# Union faces around v that share a non-cut edge through v.
		var comp: Dictionary = {}
		for f in fs:
			comp[f] = f
		var find := func(x: int) -> int:
			while comp[x] != x:
				x = comp[x]
			return x
		for i in fs.size():
			for j in range(i + 1, fs.size()):
				var fa: PackedInt32Array = faces[fs[i]]
				var fb: PackedInt32Array = faces[fs[j]]
				for w in fa:
					if w != v and fb.has(w):
						var e: int = find_edge(v, w)
						if e >= 0 and assignments[e] != OVCore.Assign.CUT:
							var ra: int = find.call(fs[i])
							var rb: int = find.call(fs[j])
							if ra != rb:
								comp[ra] = rb
		var roots: Dictionary = {}
		for f in fs:
			roots[find.call(f)] = true
		if roots.size() <= 1:
			continue
		var first: bool = true
		for r in roots.keys():
			if first:
				first = false
				continue
			var nv: int = d.add_vertex(d.vertices[v])
			orig_of.append(v)
			for f in fs:
				if find.call(f) == r:
					var face: PackedInt32Array = d.faces[f]
					for k in face.size():
						if face[k] == v:
							face[k] = nv
					d.faces[f] = face
	# Rebuild edges from faces, keeping each original edge's assignment and angle.
	var new_edges: Dictionary = {}
	var order: Array = []
	for f in d.faces:
		for k in f.size():
			var a2: int = f[k]
			var b2: int = f[(k + 1) % f.size()]
			var key: Vector2i = Vector2i(mini(a2, b2), maxi(a2, b2))
			if not new_edges.has(key):
				new_edges[key] = 0
				order.append(key)
			new_edges[key] += 1
	d.edges.clear()
	d.assignments.clear()
	d.fold_angles.clear()
	for key in order:
		var oe: int = find_edge(orig_of[key.x], orig_of[key.y])
		var asg: int = assignments[oe] if oe >= 0 else OVCore.Assign.FLAT
		var ang: float = fold_angles[oe] if oe >= 0 else 0.0
		if new_edges[key] == 1 and asg != OVCore.Assign.CUT:
			asg = OVCore.Assign.BOUNDARY
			ang = 0.0
		d.add_edge(key.x, key.y, asg, ang)
	d.touch()
	return d


## Bounding rectangle of the sheet in FOLD 2D space.
func sheet_rect() -> Rect2:
	if vertices.is_empty():
		return Rect2()
	var r: Rect2 = Rect2(OVCore.sheet_uv(vertices[0]), Vector2.ZERO)
	for p in vertices:
		r = r.expand(OVCore.sheet_uv(p))
	return r


static func _key(u: int, v: int) -> Vector2i:
	return Vector2i(mini(u, v), maxi(u, v))


static func _r(x: float) -> float:
	return snappedf(x, 0.000001)
