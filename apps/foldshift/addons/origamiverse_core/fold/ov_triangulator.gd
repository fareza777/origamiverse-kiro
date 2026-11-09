class_name OVTriangulator
extends RefCounted
## Triangulates planar polygons (convex or concave) given in 3D.


## Newell normal of a polygon. Robust for concave and slightly non-planar input.
static func polygon_normal(points: PackedVector3Array) -> Vector3:
	var n: Vector3 = Vector3.ZERO
	var count: int = points.size()
	for i in count:
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % count]
		n.x += (a.y - b.y) * (a.z + b.z)
		n.y += (a.z - b.z) * (a.x + b.x)
		n.z += (a.x - b.x) * (a.y + b.y)
	return n.normalized() if n.length_squared() > 1e-18 else Vector3.UP


## Returns triangle corner indices into `points` (3 per triangle), preserving winding.
static func triangulate(points: PackedVector3Array) -> PackedInt32Array:
	var count: int = points.size()
	if count < 3:
		return PackedInt32Array()
	if count == 3:
		return PackedInt32Array([0, 1, 2])
	var n: Vector3 = polygon_normal(points)
	# Build an orthonormal basis (t, b) with t x b = n so projected winding matches 3D winding.
	var t: Vector3 = (points[1] - points[0])
	t = (t - n * t.dot(n))
	if t.length_squared() < 1e-18:
		t = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD)
	t = t.normalized()
	var b: Vector3 = n.cross(t)
	var flat: PackedVector2Array = PackedVector2Array()
	flat.resize(count)
	for i in count:
		var p: Vector3 = points[i] - points[0]
		flat[i] = Vector2(p.dot(t), p.dot(b))
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(flat)
	if tri.is_empty():
		# Degenerate or self-intersecting polygon: fall back to a fan so we never lose the face.
		tri = PackedInt32Array()
		for i in range(1, count - 1):
			tri.append_array([0, i, i + 1])
		return tri
	# Geometry2D returns triangles in its own winding; force them to match the polygon's winding.
	var area: float = 0.0
	for i in count:
		area += flat[i].cross(flat[(i + 1) % count])
	for k in range(0, tri.size(), 3):
		var ta: Vector2 = flat[tri[k]]
		var tb: Vector2 = flat[tri[k + 1]]
		var tc: Vector2 = flat[tri[k + 2]]
		var tri_area: float = (tb - ta).cross(tc - ta)
		if signf(tri_area) != signf(area):
			var tmp: int = tri[k + 1]
			tri[k + 1] = tri[k + 2]
			tri[k + 2] = tmp
	return tri
