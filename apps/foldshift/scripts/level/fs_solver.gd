class_name FSSolver
extends RefCounted
## Exhaustive 0-1 BFS over FoldShift states. Walking is free, each fold costs 1.
## Proves solvability, computes par and a reference solution, and finds which cranes are collectible.
##
## State = (flap angle indices, walk component, unlocked flaps). Walking never hurts (seals only unlock),
## so on entering a component every seal inside it is broken and any node in it can be the next fold spot.

var puzzle: FSPuzzle
var max_states: int = 200000

var par: int = -1
var solution: Array[Dictionary] = []   ## [{"flap": name, "angle": deg, "stand": tile}]
var collectible_cranes: PackedByteArray = PackedByteArray()
var states_explored: int = 0


func solve(p: FSPuzzle) -> bool:
	puzzle = p
	var goal_tile: int = p.tile_of.get(p.level.goal, -1)
	collectible_cranes = PackedByteArray()
	collectible_cranes.resize(p.level.cranes.size())
	var start_idx: PackedInt32Array = p.indices.duplicate()
	var start_unl: PackedByteArray = p.unlocked.duplicate()
	var start: Dictionary = _canon(start_idx, p.player_node, start_unl)
	var dist: Dictionary = {start.key: 0}
	var parent: Dictionary = {start.key: null}
	var deque: Array[Dictionary] = [start]
	var found_key: String = ""
	var head: int = 0
	# Deque implemented as array with front insertions for 0-cost edges (none remain after canonicalization,
	# so this is a plain BFS over folds).
	while head < deque.size():
		var st: Dictionary = deque[head]
		head += 1
		states_explored += 1
		if states_explored > max_states:
			break
		_mark_cranes(st)
		if found_key == "" and _component_has_tile(st, goal_tile):
			found_key = st.key
			par = dist[st.key]
		var d: int = dist[st.key]
		for node in st.component:
			for fi in p.flap_count():
				if st.unl[fi] == 0:
					continue
				for j in p.flap_angles[fi].size():
					if j == st.idx[fi]:
						continue
					var next_idx: PackedInt32Array = st.idx.duplicate()
					next_idx[fi] = j
					var n2: OVSurfaceNavigator = p.nav_for(next_idx)
					if not n2.is_walkable(node):
						continue
					var nxt: Dictionary = _canon(next_idx, node, st.unl)
					if dist.has(nxt.key):
						continue
					dist[nxt.key] = d + 1
					parent[nxt.key] = {"from": st.key, "flap": p.flap_names[fi], "angle": p.flap_angles[fi][j], "stand": node / 2}
					deque.append(nxt)
	p.apply_indices(p.indices)
	if found_key == "":
		return false
	solution = []
	var k: Variant = found_key
	while parent[k] != null:
		var step: Dictionary = parent[k]
		solution.push_front({"flap": step.flap, "angle": step.angle, "stand": step.stand})
		k = step.from
	return true


func _canon(idx: PackedInt32Array, node: int, unl_in: PackedByteArray) -> Dictionary:
	var n: OVSurfaceNavigator = puzzle.nav_for(idx)
	var comp: PackedInt32Array = n.reachable(node)
	var unl: PackedByteArray = unl_in.duplicate()
	var changed: bool = true
	# Break every seal reachable in this component.
	while changed:
		changed = false
		for i in puzzle.level.seals.size():
			var seal_tile: int = puzzle.tile_of.get(puzzle.level.seals[i].at, -1)
			for side in 2:
				if comp.has(seal_tile * 2 + side):
					for name in puzzle.level.seals[i].unlocks:
						var fi: int = puzzle.flap_names.find(name)
						if fi >= 0 and unl[fi] == 0:
							unl[fi] = 1
							changed = true
	var rep: int = node
	for c in comp:
		rep = mini(rep, c)
	var key: String = "%s|%d|%s" % [puzzle.config_key(idx), rep, unl.hex_encode()]
	return {"key": key, "idx": idx, "component": comp, "unl": unl}


func _component_has_tile(st: Dictionary, tile: int) -> bool:
	return st.component.has(tile * 2) or st.component.has(tile * 2 + 1)


func _mark_cranes(st: Dictionary) -> void:
	for i in puzzle.level.cranes.size():
		var cr: Dictionary = puzzle.level.cranes[i]
		var t: int = puzzle.tile_of.get(cr.at, -1)
		if st.component.has(t * 2 + int(cr.side)):
			collectible_cranes[i] = 1


func all_cranes_collectible() -> bool:
	for c in collectible_cranes:
		if c == 0:
			return false
	return true
