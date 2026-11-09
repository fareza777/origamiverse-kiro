class_name FSPuzzle
extends RefCounted
## FoldShift rules. Pure logic on top of OVHingeSolver + OVSurfaceNavigator, shared by the game and the solver.

signal crane_collected(index: int)
signal seal_broken(index: int)

var level: FSLevelData
var docs: Array[OVFoldDocument] = []
var solvers: Array[OVHingeSolver] = []

## Tiles
var tile_island: PackedInt32Array = PackedInt32Array()
var tile_cell: Array[Vector2i] = []
var tile_faces: Array[PackedInt32Array] = []
var tile_rest: Array[PackedVector3Array] = []
var tile_flap: PackedInt32Array = PackedInt32Array()   ## flap index owning the tile's panel, -1 for base
var tile_of: Dictionary = {}                            ## Vector3i(island, r, c) -> tile

## Flaps
var flap_names: PackedStringArray = PackedStringArray()
var flap_island: PackedInt32Array = PackedInt32Array()
var flap_hinge: PackedInt32Array = PackedInt32Array()
var flap_panel: PackedInt32Array = PackedInt32Array()
var flap_angles: Array[PackedFloat32Array] = []
var flap_tiles: Array[PackedInt32Array] = []            ## tiles moved by the flap (its subtree)

## State
var indices: PackedInt32Array = PackedInt32Array()      ## current angle index per flap
var player_node: int = -1
var unlocked: PackedByteArray = PackedByteArray()       ## per flap: 1 = free to fold
var seal_broken_flags: PackedByteArray = PackedByteArray()
var collected: PackedByteArray = PackedByteArray()
var folds: int = 0
var nav: OVSurfaceNavigator

var _nav_cache: Dictionary = {}
var cache_navs: bool = true


func setup(L: FSLevelData) -> Dictionary:
	level = L
	var errors: PackedStringArray = PackedStringArray()
	for i in L.islands.size():
		var built: Dictionary = L.build_island_document(i)
		var doc: OVFoldDocument = built.doc
		var s: OVHingeSolver = OVHingeSolver.new()
		s.root_transform = Transform3D(Basis.IDENTITY, L.islands[i].origin)
		var r: Dictionary = s.build(doc, built.root_face)
		if not r.ok:
			for e in r.errors:
				errors.append("Island %d: %s" % [i, e])
		docs.append(doc)
		solvers.append(s)
		var keys: Array = built.cell_faces.keys()
		keys.sort()
		for cell in keys:
			var t: int = tile_island.size()
			var faces: PackedInt32Array = built.cell_faces[cell]
			tile_island.append(i)
			tile_cell.append(cell)
			tile_faces.append(faces)
			var f0: PackedInt32Array = doc.faces[faces[0]]
			var f1: PackedInt32Array = doc.faces[faces[1]]
			# Corner order c0, c1, c2, c3 (normal +Y): f0 = [c0, c1, c2], f1 = [c0, c2, c3].
			tile_rest.append(PackedVector3Array([doc.vertices[f0[0]], doc.vertices[f0[1]], doc.vertices[f0[2]], doc.vertices[f1[2]]]))
			tile_of[Vector3i(i, cell.x, cell.y)] = t
	if not errors.is_empty():
		return OVCore.fail(errors)
	tile_flap.resize(tile_island.size())
	tile_flap.fill(-1)
	for name in L.flap_order:
		var fi: int = flap_names.size()
		var island: int = -1
		var panel: int = -1
		for t in tile_island.size():
			var cell: Vector2i = tile_cell[t]
			if L.islands[tile_island[t]].cells[cell] == name:
				island = tile_island[t]
				panel = solvers[island].panel_of_face[tile_faces[t][0]]
				break
		if island < 0:
			errors.append("Flap %s has no cells." % name)
			continue
		var s: OVHingeSolver = solvers[island]
		var h: int = s.panel_parent_hinge[panel]
		if h < 0:
			errors.append("Flap %s is not hinged to its parent (check hinge side)." % name)
			continue
		flap_names.append(name)
		flap_island.append(island)
		flap_hinge.append(h)
		flap_panel.append(panel)
		flap_angles.append(L.flaps[name].angles)
		indices.append(L.flaps[name].angles.find(L.flaps[name].start))
	if not errors.is_empty():
		return OVCore.fail(errors)
	for t in tile_island.size():
		var panel_t: int = solvers[tile_island[t]].panel_of_face[tile_faces[t][0]]
		for fi in flap_names.size():
			if flap_island[fi] == tile_island[t] and flap_panel[fi] == panel_t:
				tile_flap[t] = fi
	for fi in flap_names.size():
		var sub: PackedInt32Array = solvers[flap_island[fi]].subtree(flap_panel[fi])
		var moved: PackedInt32Array = PackedInt32Array()
		for t in tile_island.size():
			if tile_island[t] == flap_island[fi] and sub.has(solvers[tile_island[t]].panel_of_face[tile_faces[t][0]]):
				moved.append(t)
		flap_tiles.append(moved)
	unlocked.resize(flap_names.size())
	unlocked.fill(1)
	for s in L.seals:
		for name in s.unlocks:
			var fi: int = flap_names.find(name)
			if fi >= 0:
				unlocked[fi] = 0
	seal_broken_flags.resize(L.seals.size())
	collected.resize(L.cranes.size())
	apply_indices(indices)
	nav = nav_for(indices)
	player_node = nav.best_node_for_tile(tile_of.get(L.start, -1))
	if player_node < 0:
		return OVCore.fail(PackedStringArray(["Start tile is not walkable."]))
	_visit(player_node)
	return OVCore.ok(self)


func flap_count() -> int:
	return flap_names.size()


func tile_count() -> int:
	return tile_island.size()


func flap_index_by_name(name: String) -> int:
	return flap_names.find(name)


func current_angle(fi: int) -> float:
	return flap_angles[fi][indices[fi]]


# ------------------------------------------------------------ geometry


func apply_indices(idx: PackedInt32Array) -> void:
	for fi in flap_names.size():
		solvers[flap_island[fi]].set_angle(flap_hinge[fi], flap_angles[fi][idx[fi]])
	for s in solvers:
		s.update()


## Live (non-committed) angle while the player drags a flap.
func set_live_angle(fi: int, degrees: float) -> void:
	var s: OVHingeSolver = solvers[flap_island[fi]]
	s.set_angle(flap_hinge[fi], degrees)
	s.update()


func tile_corners(t: int) -> PackedVector3Array:
	var s: OVHingeSolver = solvers[tile_island[t]]
	var xf: Transform3D = s.panel_transforms[s.panel_of_face[tile_faces[t][0]]]
	var rest: PackedVector3Array = tile_rest[t]
	return PackedVector3Array([xf * rest[0], xf * rest[1], xf * rest[2], xf * rest[3]])


func tile_center(t: int) -> Vector3:
	var c: PackedVector3Array = tile_corners(t)
	return (c[0] + c[1] + c[2] + c[3]) * 0.25


func config_key(idx: PackedInt32Array) -> String:
	return ",".join(Array(idx).map(func(x: int) -> String: return str(x)))


## Navigation graph for an angle configuration (cached). Leaves geometry at `idx`.
func nav_for(idx: PackedInt32Array) -> OVSurfaceNavigator:
	var key: String = config_key(idx)
	apply_indices(idx)
	if cache_navs and _nav_cache.has(key):
		return _nav_cache[key]
	var tiles: Array = []
	for t in tile_island.size():
		tiles.append({"id": t, "corners": tile_corners(t)})
	var n: OVSurfaceNavigator = OVSurfaceNavigator.new()
	n.build(tiles)
	if cache_navs:
		_nav_cache[key] = n
	return n


# ------------------------------------------------------------ rules


func is_locked(fi: int) -> bool:
	return unlocked[fi] == 0


func is_riding(fi: int, node: int = -1) -> bool:
	var n: int = player_node if node < 0 else node
	return flap_tiles[fi].has(n / 2)


## Checks a fold without applying it. Returns {"ok": bool, "reason": String}.
func check_fold(fi: int, new_index: int) -> Dictionary:
	if new_index == indices[fi]:
		return {"ok": false, "reason": ""}
	if is_locked(fi):
		return {"ok": false, "reason": "Sealed. Find the matching wax seal."}
	var next: PackedInt32Array = indices.duplicate()
	next[fi] = new_index
	var riding: bool = is_riding(fi)
	var n: OVSurfaceNavigator = nav_for(next)
	apply_indices(indices)
	if not n.is_walkable(player_node):
		if riding:
			return {"ok": false, "reason": "Kami would be left hanging upside down."}
		return {"ok": false, "reason": "That fold would squash Kami."}
	return {"ok": true, "reason": "", "riding": riding}


## Applies a fold if allowed. Returns the check result.
func try_fold(fi: int, new_index: int) -> Dictionary:
	var res: Dictionary = check_fold(fi, new_index)
	if not res.ok:
		apply_indices(indices)
		return res
	indices[fi] = new_index
	folds += 1
	nav = nav_for(indices)
	return res


## Shortest path to the best node of `tile` (prefers the side reachable from Kami).
func path_to_tile(tile: int) -> PackedInt32Array:
	var best: PackedInt32Array = PackedInt32Array()
	for side in 2:
		var target: int = tile * 2 + side
		if not nav.is_walkable(target):
			continue
		var p: PackedInt32Array = nav.path(player_node, target)
		if not p.is_empty() and (best.is_empty() or p.size() < best.size()):
			best = p
	return best


## Moves Kami along a path, applying seals and cranes in order.
func walk(path: PackedInt32Array) -> void:
	for node in path:
		player_node = node
		_visit(node)


func _visit(node: int) -> void:
	var t: int = node / 2
	var side: int = node % 2
	for i in level.seals.size():
		if seal_broken_flags[i] == 0 and tile_of.get(level.seals[i].at, -2) == t:
			seal_broken_flags[i] = 1
			for name in level.seals[i].unlocks:
				var fi: int = flap_names.find(name)
				if fi >= 0:
					unlocked[fi] = 1
			seal_broken.emit(i)
	for i in level.cranes.size():
		if collected[i] == 0 and tile_of.get(level.cranes[i].at, -2) == t and level.cranes[i].side == side:
			collected[i] = 1
			crane_collected.emit(i)


func is_won() -> bool:
	return player_node >= 0 and player_node / 2 == tile_of.get(level.goal, -2)


func cranes_collected() -> int:
	var n: int = 0
	for c in collected:
		n += c
	return n


## Which side of the tile is "up" for markers printed on the given side.
func side_normal(t: int, side: int) -> Vector3:
	var c: PackedVector3Array = tile_corners(t)
	var n: Vector3 = (c[1] - c[0]).cross(c[3] - c[0]).normalized()
	return n if side == 0 else -n


# ------------------------------------------------------------ snapshots (undo, resume)


func snapshot() -> Dictionary:
	return {"indices": Array(indices), "player": player_node, "unlocked": Array(unlocked),
		"seals": Array(seal_broken_flags), "cranes": Array(collected), "folds": folds}


func restore(s: Dictionary) -> void:
	indices = PackedInt32Array(s.indices)
	player_node = int(s.player)
	unlocked = PackedByteArray(s.unlocked)
	seal_broken_flags = PackedByteArray(s.seals)
	collected = PackedByteArray(s.cranes)
	folds = int(s.folds)
	nav = nav_for(indices)
