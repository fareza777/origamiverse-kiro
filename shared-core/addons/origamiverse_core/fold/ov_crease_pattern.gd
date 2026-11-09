class_name OVCreasePattern
extends RefCounted
## Editable crease pattern: a sheet outline plus crease segments in FOLD 2D coordinates.
## `to_document()` planarizes the segments into a triangulated OVFoldDocument.

signal changed

const MERGE_TOL: float = 1e-4

## Each segment: {"a": Vector2, "b": Vector2, "assign": int, "angle": float}
var segments: Array[Dictionary] = []
## Sheet outline as a closed polygon (CCW). Defaults to the unit square.
var outline: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])

var last_warnings: PackedStringArray = PackedStringArray()


static func make_segment(a: Vector2, b: Vector2, assign: int, angle: float = NAN) -> Dictionary:
	return {"a": a, "b": b, "assign": assign,
		"angle": OVCore.default_fold_angle(assign) if is_nan(angle) else angle}


func add_segment(a: Vector2, b: Vector2, assign: int, angle: float = NAN) -> int:
	if a.distance_to(b) < MERGE_TOL:
		return -1
	segments.append(make_segment(a, b, assign, angle))
	changed.emit()
	return segments.size() - 1


func insert_segment(index: int, seg: Dictionary) -> void:
	segments.insert(clampi(index, 0, segments.size()), seg.duplicate())
	changed.emit()


func remove_segment(index: int) -> Dictionary:
	if index < 0 or index >= segments.size():
		return {}
	var s: Dictionary = segments[index]
	segments.remove_at(index)
	changed.emit()
	return s


func set_segment(index: int, seg: Dictionary) -> void:
	segments[index] = seg.duplicate()
	changed.emit()


func clear() -> void:
	segments.clear()
	changed.emit()


func bounds() -> Rect2:
	var r: Rect2 = Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		r = r.expand(p)
	return r


## Index of the segment nearest to `p` within `radius`, or -1.
func pick_segment(p: Vector2, radius: float) -> int:
	var best: int = -1
	var best_d: float = radius
	for i in segments.size():
		var s: Dictionary = segments[i]
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, s.a, s.b)
		var d: float = q.distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## Snaps `p` to the most useful nearby point. `from` (optional) enables 22.5 degree angle snapping.
func snap(p: Vector2, grid_divisions: int, radius: float, from: Variant = null) -> Vector2:
	var candidates: Array[Vector2] = []
	for v in outline:
		candidates.append(v)
	for i in outline.size():
		candidates.append((outline[i] + outline[(i + 1) % outline.size()]) * 0.5)
	for s in segments:
		candidates.append(s.a)
		candidates.append(s.b)
		candidates.append((s.a + s.b) * 0.5)
	for i in segments.size():
		for j in range(i + 1, segments.size()):
			var x: Variant = Geometry2D.segment_intersects_segment(segments[i].a, segments[i].b, segments[j].a, segments[j].b)
			if x != null:
				candidates.append(x)
	var best: Vector2 = p
	var best_d: float = radius
	var found: bool = false
	for c in candidates:
		var d: float = c.distance_to(p)
		if d < best_d:
			best_d = d
			best = c
			found = true
	if found:
		return best
	if from != null:
		var origin: Vector2 = from
		var dir: Vector2 = p - origin
		if dir.length() > MERGE_TOL:
			var step: float = PI / 8.0
			var ang: float = roundf(dir.angle() / step) * step
			var len: float = dir.length()
			var snapped_point: Vector2 = origin + Vector2.from_angle(ang) * len
			if snapped_point.distance_to(p) < radius * 2.0:
				# Extend to the outline or the nearest segment along the snapped ray when close.
				var hit: Variant = _ray_hit(origin, Vector2.from_angle(ang), len, radius * 2.0)
				return hit if hit != null else snapped_point
	if grid_divisions > 0:
		var r: Rect2 = bounds()
		var cell: Vector2 = r.size / float(grid_divisions)
		var g: Vector2 = r.position + ((p - r.position) / cell).round() * cell
		if g.distance_to(p) < radius * 1.5:
			return g
	return p


func _ray_hit(origin: Vector2, dir: Vector2, len: float, tol: float) -> Variant:
	var far: Vector2 = origin + dir * 10.0
	var best: Variant = null
	var best_t: float = INF
	var lines: Array = []
	for i in outline.size():
		lines.append([outline[i], outline[(i + 1) % outline.size()]])
	for s in segments:
		lines.append([s.a, s.b])
	for l in lines:
		var x: Variant = Geometry2D.segment_intersects_segment(origin + dir * MERGE_TOL * 10.0, far, l[0], l[1])
		if x != null:
			var t: float = (x - origin).length()
			if absf(t - len) < tol and t < best_t:
				best_t = t
				best = x
	return best


# ---------------------------------------------------------------- planarization


## Builds a triangulated FOLD document. Warnings (dropped dangling creases) go to `last_warnings`.
func to_document() -> OVFoldDocument:
	last_warnings = PackedStringArray()
	var lines: Array[Dictionary] = []
	for i in outline.size():
		lines.append(make_segment(outline[i], outline[(i + 1) % outline.size()], OVCore.Assign.BOUNDARY, 0.0))
	for s in segments:
		var clipped: Variant = _clip_to_outline(s.a, s.b)
		if clipped != null:
			var c: Dictionary = s.duplicate()
			c.a = clipped[0]
			c.b = clipped[1]
			lines.append(c)

	# 1. Split parameters for every line.
	var splits: Array = []
	for i in lines.size():
		splits.append(PackedFloat32Array([0.0, 1.0]))
	for i in lines.size():
		var a1: Vector2 = lines[i].a
		var b1: Vector2 = lines[i].b
		for j in range(i + 1, lines.size()):
			var a2: Vector2 = lines[j].a
			var b2: Vector2 = lines[j].b
			var x: Variant = Geometry2D.segment_intersects_segment(a1, b1, a2, b2)
			if x != null:
				splits[i].append(_param(a1, b1, x))
				splits[j].append(_param(a2, b2, x))
			# Endpoints touching the other line (T junctions and collinear overlaps).
			for pair in [[a2, i], [b2, i], [a1, j], [b1, j]]:
				var p: Vector2 = pair[0]
				var k: int = pair[1]
				var la: Vector2 = lines[k].a
				var lb: Vector2 = lines[k].b
				var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, la, lb)
				if q.distance_to(p) < MERGE_TOL:
					splits[k].append(_param(la, lb, q))

	# 2. Vertices (merged) and sub-edges.
	var points: PackedVector2Array = PackedVector2Array()
	var edge_map: Dictionary = {}   # Vector2i -> [assign, angle]
	for i in lines.size():
		var ts: PackedFloat32Array = splits[i]
		ts.sort()
		var prev: int = -1
		var prev_t: float = -1.0
		for t in ts:
			if prev >= 0 and t - prev_t < 1e-7:
				continue
			var p: Vector2 = lines[i].a.lerp(lines[i].b, t)
			var vi: int = _merge_point(points, p)
			if prev >= 0 and prev != vi:
				var key: Vector2i = Vector2i(mini(prev, vi), maxi(prev, vi))
				var assign: int = lines[i].assign
				if not edge_map.has(key) or _priority(assign) > _priority(edge_map[key][0]):
					edge_map[key] = [assign, lines[i].angle]
			prev = vi
			prev_t = t

	# 3. Drop dangling edges (degree-1 vertices) since they cannot bound a face.
	var degree: PackedInt32Array = PackedInt32Array()
	degree.resize(points.size())
	for key in edge_map.keys():
		degree[key.x] += 1
		degree[key.y] += 1
	var removed: int = 0
	var changed_any: bool = true
	while changed_any:
		changed_any = false
		for key in edge_map.keys():
			if degree[key.x] <= 1 or degree[key.y] <= 1:
				degree[key.x] -= 1
				degree[key.y] -= 1
				edge_map.erase(key)
				removed += 1
				changed_any = true
	if removed > 0:
		last_warnings.append("%d dangling crease piece(s) were ignored because they do not split the paper." % removed)

	# 4. Build document with compact vertex indices.
	var doc: OVFoldDocument = OVFoldDocument.new()
	var remap: PackedInt32Array = PackedInt32Array()
	remap.resize(points.size())
	remap.fill(-1)
	for key in edge_map.keys():
		for vi in [key.x, key.y]:
			if remap[vi] < 0:
				remap[vi] = doc.add_vertex(OVCore.fold_to_godot(points[vi].x, points[vi].y))
	for key in edge_map.keys():
		var info: Array = edge_map[key]
		var ang: float = info[1] if OVCore.is_crease(info[0]) else 0.0
		doc.add_edge(remap[key.x], remap[key.y], info[0], ang)

	# 5. Faces via half-edge traversal.
	_extract_faces(doc)
	doc.meta["file_classes"] = ["singleModel"]
	return doc.triangulated()


func _extract_faces(doc: OVFoldDocument) -> void:
	var n: int = doc.vertex_count()
	var out: Array = []
	out.resize(n)
	for i in n:
		out[i] = []
	for e in doc.edge_count():
		var u: int = doc.edges[e * 2]
		var v: int = doc.edges[e * 2 + 1]
		out[u].append(v)
		out[v].append(u)
	var pos: PackedVector2Array = PackedVector2Array()
	for p in doc.vertices:
		pos.append(OVCore.sheet_uv(p))
	for i in n:
		var origin: Vector2 = pos[i]
		out[i].sort_custom(func(a: int, b: int) -> bool:
			return (pos[a] - origin).angle() < (pos[b] - origin).angle())
	var visited: Dictionary = {}
	for u in n:
		for v in out[u]:
			var start: Vector2i = Vector2i(u, v)
			if visited.has(start):
				continue
			var loop: PackedInt32Array = PackedInt32Array()
			var cur: Vector2i = start
			var guard: int = 0
			while not visited.has(cur) and guard < 100000:
				visited[cur] = true
				loop.append(cur.x)
				var around: Array = out[cur.y]
				var idx: int = around.find(cur.x)
				# Next clockwise from the twin keeps the face on the left (CCW traversal).
				var nxt: int = around[(idx - 1 + around.size()) % around.size()]
				cur = Vector2i(cur.y, nxt)
				guard += 1
			if loop.size() < 3:
				continue
			var area: float = 0.0
			for k in loop.size():
				area += pos[loop[k]].cross(pos[loop[(k + 1) % loop.size()]])
			if area > 1e-10:
				doc.add_face(loop)


func _clip_to_outline(a: Vector2, b: Vector2) -> Variant:
	var inside_a: bool = Geometry2D.is_point_in_polygon(a, outline) or _on_outline(a)
	var inside_b: bool = Geometry2D.is_point_in_polygon(b, outline) or _on_outline(b)
	if inside_a and inside_b:
		return [a, b]
	var hits: Array[Vector2] = []
	for i in outline.size():
		var x: Variant = Geometry2D.segment_intersects_segment(a, b, outline[i], outline[(i + 1) % outline.size()])
		if x != null:
			hits.append(x)
	if inside_a and not hits.is_empty():
		return [a, hits[0]]
	if inside_b and not hits.is_empty():
		return [hits[0], b]
	if hits.size() >= 2:
		return [hits[0], hits[1]]
	return null


func _on_outline(p: Vector2) -> bool:
	for i in outline.size():
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, outline[i], outline[(i + 1) % outline.size()])
		if q.distance_to(p) < MERGE_TOL:
			return true
	return false


static func _param(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab: Vector2 = b - a
	return clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)


static func _merge_point(points: PackedVector2Array, p: Vector2) -> int:
	for i in points.size():
		if points[i].distance_to(p) < MERGE_TOL:
			return i
	points.append(p)
	return points.size() - 1


static func _priority(a: int) -> int:
	match a:
		OVCore.Assign.BOUNDARY: return 4
		OVCore.Assign.CUT: return 3
		OVCore.Assign.MOUNTAIN, OVCore.Assign.VALLEY: return 2
	return 1


# ---------------------------------------------------------------- persistence


func to_dict() -> Dictionary:
	var segs: Array = []
	for s in segments:
		segs.append([s.a.x, s.a.y, s.b.x, s.b.y, OVCore.assign_to_letter(s.assign), s.angle])
	var o: Array = []
	for p in outline:
		o.append([p.x, p.y])
	return {"outline": o, "segments": segs}


static func from_dict(d: Dictionary) -> OVCreasePattern:
	var cp: OVCreasePattern = OVCreasePattern.new()
	var o: Array = d.get("outline", [])
	if o.size() >= 3:
		cp.outline = PackedVector2Array()
		for p in o:
			cp.outline.append(Vector2(float(p[0]), float(p[1])))
	for s in d.get("segments", []):
		if typeof(s) == TYPE_ARRAY and s.size() >= 6:
			cp.segments.append(make_segment(Vector2(float(s[0]), float(s[1])), Vector2(float(s[2]), float(s[3])),
				OVCore.assign_from_letter(str(s[4])), float(s[5])))
	return cp


## Rebuilds an editable pattern from any flat FOLD document (boundary edges become the outline).
static func from_document(doc: OVFoldDocument) -> OVCreasePattern:
	var cp: OVCreasePattern = OVCreasePattern.new()
	var r: Rect2 = doc.sheet_rect()
	var scale: float = 1.0 / maxf(r.size.x, r.size.y) if maxf(r.size.x, r.size.y) > 0.0 else 1.0
	var to_cp := func(p: Vector3) -> Vector2:
		return (OVCore.sheet_uv(p) - r.position) * scale
	var boundary_next: Dictionary = {}
	for e in doc.edge_count():
		var u: int = doc.edges[e * 2]
		var v: int = doc.edges[e * 2 + 1]
		var a: int = doc.assignments[e]
		if a == OVCore.Assign.BOUNDARY:
			boundary_next[u] = boundary_next.get(u, []) + [v]
			boundary_next[v] = boundary_next.get(v, []) + [u]
		elif a == OVCore.Assign.FLAT and is_zero_approx(doc.fold_angles[e]):
			# Flat facet edges usually come from triangulation; the editor regenerates them.
			continue
		else:
			cp.segments.append(make_segment(to_cp.call(doc.vertices[u]), to_cp.call(doc.vertices[v]),
				OVCore.Assign.FLAT if a == OVCore.Assign.UNASSIGNED else a, doc.fold_angles[e]))
	# Walk the boundary loop if it is a simple cycle; otherwise keep the bounding square.
	if not boundary_next.is_empty():
		var start: int = boundary_next.keys()[0]
		var loop: PackedVector2Array = PackedVector2Array([to_cp.call(doc.vertices[start])])
		var prev: int = -1
		var cur: int = start
		var ok: bool = true
		for _i in boundary_next.size():
			var nbrs: Array = boundary_next[cur]
			if nbrs.size() != 2:
				ok = false
				break
			var nxt: int = nbrs[0] if nbrs[0] != prev else nbrs[1]
			if nxt == start:
				break
			loop.append(to_cp.call(doc.vertices[nxt]))
			prev = cur
			cur = nxt
		if ok and loop.size() >= 3:
			var area: float = 0.0
			for k in loop.size():
				area += loop[k].cross(loop[(k + 1) % loop.size()])
			if area < 0.0:
				loop.reverse()
			cp.outline = _simplify(loop)
	return cp


static func _simplify(loop: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = loop.size()
	for i in n:
		var a: Vector2 = loop[(i - 1 + n) % n]
		var b: Vector2 = loop[i]
		var c: Vector2 = loop[(i + 1) % n]
		if absf((b - a).cross(c - b)) > 1e-9:
			out.append(b)
	return out
