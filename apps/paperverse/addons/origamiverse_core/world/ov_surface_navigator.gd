class_name OVSurfaceNavigator
extends RefCounted
## Walk graph over folded paper tiles. Gravity follows the paper: walkers may cross flat seams,
## climb from a floor onto a wall (concave) and step over a ledge (convex). Ceilings are never walkable.

var up: Vector3 = Vector3.UP
var thickness: float = OVCore.PAPER_THICKNESS
var edge_tolerance: float = 0.035
var min_up_dot: float = -0.25
var tile_half_extent: float = 0.5

## Per tile
var tile_ids: PackedInt32Array = PackedInt32Array()
var centers: PackedVector3Array = PackedVector3Array()
var normals: PackedVector3Array = PackedVector3Array()
var corners: Array[PackedVector3Array] = []
## Per node (node = tile * 2 + side, side 0 = front, 1 = back)
var walkable: PackedByteArray = PackedByteArray()
var adjacency: Array[PackedInt32Array] = []

var _astar: AStar3D = AStar3D.new()
var _index_of_id: Dictionary = {}


## tiles: Array of {"id": int, "corners": PackedVector3Array (4, CCW seen from the front), "blocked": bool}
func build(tiles: Array) -> void:
	var n: int = tiles.size()
	tile_ids = PackedInt32Array(); centers = PackedVector3Array(); normals = PackedVector3Array()
	corners = []
	_index_of_id.clear()
	for i in n:
		var t: Dictionary = tiles[i]
		var c: PackedVector3Array = t.corners
		corners.append(c)
		tile_ids.append(int(t.id))
		_index_of_id[int(t.id)] = i
		centers.append((c[0] + c[1] + c[2] + c[3]) * 0.25)
		normals.append((c[1] - c[0]).cross(c[3] - c[0]).normalized())
	walkable = PackedByteArray()
	walkable.resize(n * 2)
	for i in n:
		var blocked: bool = bool(tiles[i].get("blocked", false))
		for side in 2:
			var nrm: Vector3 = normals[i] * (1.0 if side == 0 else -1.0)
			var ok: bool = not blocked and nrm.dot(up) > min_up_dot and not _is_covered(i, nrm)
			walkable[i * 2 + side] = 1 if ok else 0
	_build_adjacency()
	_build_astar()


func _is_covered(i: int, nrm: Vector3) -> bool:
	var c: Vector3 = centers[i]
	for j in centers.size():
		if j == i:
			continue
		if absf(normals[j].dot(nrm)) < 0.95:
			continue
		var d: Vector3 = centers[j] - c
		var h: float = d.dot(nrm)
		if h > thickness * 0.25 and h < thickness * 3.0 + 0.01:
			var lateral: Vector3 = d - nrm * h
			if lateral.length() < tile_half_extent * 0.9:
				return true
	return false


func _build_adjacency() -> void:
	var n: int = centers.size()
	adjacency = []
	adjacency.resize(n * 2)
	for k in n * 2:
		adjacency[k] = PackedInt32Array()
	# Bucket tile edges by quantized midpoint.
	var buckets: Dictionary = {}
	var q: float = 0.25
	for i in n:
		for e in 4:
			var a: Vector3 = corners[i][e]
			var b: Vector3 = corners[i][(e + 1) % 4]
			var m: Vector3 = (a + b) * 0.5
			var key: Vector3i = Vector3i(roundi(m.x / q), roundi(m.y / q), roundi(m.z / q))
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append([i, a, b, m])
	var seen: Dictionary = {}
	for key in buckets.keys():
		# Look in neighbor buckets too so midpoints near a cell border still match.
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var other: Vector3i = key + Vector3i(dx, dy, dz)
					if not buckets.has(other):
						continue
					for ea in buckets[key]:
						for eb in buckets[other]:
							var ta: int = ea[0]
							var tb: int = eb[0]
							if ta >= tb:
								continue
							var pair: Vector3i = Vector3i(ta, tb, 0)
							if (ea[3] as Vector3).distance_to(eb[3]) > edge_tolerance:
								continue
							var same: bool = (ea[1] as Vector3).distance_to(eb[1]) < edge_tolerance * 2.0 and (ea[2] as Vector3).distance_to(eb[2]) < edge_tolerance * 2.0
							var flipped: bool = (ea[1] as Vector3).distance_to(eb[2]) < edge_tolerance * 2.0 and (ea[2] as Vector3).distance_to(eb[1]) < edge_tolerance * 2.0
							if not (same or flipped):
								continue
							var mkey: String = "%d_%d_%s" % [ta, tb, str(Vector3i((ea[3] as Vector3) * 100.0))]
							if seen.has(mkey):
								continue
							seen[mkey] = true
							_connect_tiles(ta, tb, ea[3])


func _connect_tiles(ta: int, tb: int, mid: Vector3) -> void:
	var da: Vector3 = _inward(ta, mid)
	var db: Vector3 = _inward(tb, mid)
	for sa in 2:
		var na: Vector3 = normals[ta] * (1.0 if sa == 0 else -1.0)
		for sb in 2:
			var nb: Vector3 = normals[tb] * (1.0 if sb == 0 else -1.0)
			var linked: bool = false
			if na.dot(nb) > 0.9 and da.dot(db) < -0.9:
				linked = true   # flat seam
			elif nb.dot(da) > 0.9 and na.dot(db) > 0.9:
				linked = true   # concave: floor to rising wall
			elif nb.dot(da) < -0.9 and na.dot(db) < -0.9:
				linked = true   # convex: over a ledge
			if linked:
				var a_node: int = ta * 2 + sa
				var b_node: int = tb * 2 + sb
				if walkable[a_node] == 1 and walkable[b_node] == 1:
					adjacency[a_node].append(b_node)
					adjacency[b_node].append(a_node)


func _inward(t: int, mid: Vector3) -> Vector3:
	var d: Vector3 = centers[t] - mid
	d -= normals[t] * d.dot(normals[t])
	return d.normalized()


func _build_astar() -> void:
	_astar.clear()
	for node in walkable.size():
		if walkable[node] == 1:
			_astar.add_point(node, node_position(node))
	for node in adjacency.size():
		for other in adjacency[node]:
			if other > node:
				_astar.connect_points(node, other, true)


func index_of(tile_id: int) -> int:
	return _index_of_id.get(tile_id, -1)


func node_of(tile_id: int, side: int) -> int:
	var i: int = index_of(tile_id)
	return -1 if i < 0 else i * 2 + side


func node_tile_id(node: int) -> int:
	return tile_ids[node / 2]


func node_side(node: int) -> int:
	return node % 2


func is_walkable(node: int) -> bool:
	return node >= 0 and node < walkable.size() and walkable[node] == 1


func node_normal(node: int) -> Vector3:
	return normals[node / 2] * (1.0 if node % 2 == 0 else -1.0)


## Surface point a walker stands on (lifted half a thickness off the paper).
func node_position(node: int) -> Vector3:
	return centers[node / 2] + node_normal(node) * (thickness * 0.5)


## Best walkable node for a tile when the side is unknown: the side whose normal faces `up` the most.
func best_node_for_tile(tile_id: int) -> int:
	var i: int = index_of(tile_id)
	if i < 0:
		return -1
	var front: int = i * 2
	var back: int = i * 2 + 1
	var fw: bool = walkable[front] == 1
	var bw: bool = walkable[back] == 1
	if fw and bw:
		return front if normals[i].dot(up) >= 0.0 else back
	if fw:
		return front
	if bw:
		return back
	return -1


func path(from_node: int, to_node: int) -> PackedInt32Array:
	if not is_walkable(from_node) or not is_walkable(to_node):
		return PackedInt32Array()
	if from_node == to_node:
		return PackedInt32Array([from_node])
	var ids: PackedInt64Array = _astar.get_id_path(from_node, to_node)
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(ids.size())
	for i in ids.size():
		out[i] = int(ids[i])
	return out


## All nodes reachable from `from_node` (including it).
func reachable(from_node: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if not is_walkable(from_node):
		return out
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(walkable.size())
	out.append(from_node)
	seen[from_node] = 1
	var i: int = 0
	while i < out.size():
		var node: int = out[i]
		i += 1
		for other in adjacency[node]:
			if seen[other] == 0:
				seen[other] = 1
				out.append(other)
	return out
