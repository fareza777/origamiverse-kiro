extends OVTestCase
## Every shipped level must parse, build a valid hinge tree, be solvable, match its stored par,
## and have every crane collectible.


func _level_paths() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f in DirAccess.get_files_at("res://levels"):
		if f.ends_with(".json"):
			out.append("res://levels/" + f)
	out.sort()
	return out


func test_level_count() -> void:
	check_eq(_level_paths().size(), FSCatalog.LEVEL_IDS.size(), "every catalog level has a file")
	for id in FSCatalog.LEVEL_IDS:
		check(FileAccess.file_exists("res://levels/%s.json" % id), "%s exists" % id)


func test_levels_solvable_with_par() -> void:
	for path in _level_paths():
		var r: Dictionary = FSLevelData.load_file(path)
		if not check(r.ok, "%s parses: %s" % [path, str(r.errors)]):
			continue
		var L: FSLevelData = r.value
		var p: FSPuzzle = FSPuzzle.new()
		var pr: Dictionary = p.setup(L)
		if not check(pr.ok, "%s builds: %s" % [path, str(pr.errors)]):
			continue
		var t0: int = Time.get_ticks_msec()
		var s: FSSolver = FSSolver.new()
		var ok: bool = s.solve(p)
		var moves: Array = s.solution.map(func(m: Dictionary) -> String: return "%s->%d@%d" % [m.flap, int(m.angle), m.stand])
		print("    %s  par=%d (file %d)  states=%d  %d ms  %s" % [L.id, s.par, L.par, s.states_explored, Time.get_ticks_msec() - t0, " ".join(moves)])
		check(ok, "%s is solvable" % L.id)
		check_eq(s.par, L.par, "%s par matches solver" % L.id)
		check(s.par >= 1, "%s needs at least one fold" % L.id)
		check(s.all_cranes_collectible(), "%s all cranes collectible %s" % [L.id, str(s.collectible_cranes)])


func test_replay_solution_in_puzzle() -> void:
	# Replays the solver's moves through the same API the game uses.
	for path in _level_paths():
		var L: FSLevelData = FSLevelData.load_file(path).value
		var p: FSPuzzle = FSPuzzle.new()
		p.setup(L)
		var s: FSSolver = FSSolver.new()
		if not s.solve(p):
			continue
		var p2: FSPuzzle = FSPuzzle.new()
		p2.setup(L)
		for m in s.solution:
			_break_reachable_seals(p2)
			var tile: int = m.stand
			var walk: PackedInt32Array = p2.path_to_tile(tile)
			if p2.player_node / 2 != tile:
				check(not walk.is_empty(), "%s: can walk to fold spot %d" % [L.id, tile])
				p2.walk(walk)
			var fi: int = p2.flap_index_by_name(m.flap)
			var res: Dictionary = p2.try_fold(fi, p2.flap_angles[fi].find(m.angle))
			check(res.ok, "%s: fold %s accepted (%s)" % [L.id, m.flap, res.reason])
		var goal_tile: int = p2.tile_of[L.goal]
		var final: PackedInt32Array = p2.path_to_tile(goal_tile)
		check(not final.is_empty() or p2.is_won(), "%s: goal reachable after solution" % L.id)
		p2.walk(final)
		check(p2.is_won(), "%s: won" % L.id)
		check_eq(p2.folds, s.par, "%s: fold count equals par" % L.id)


## Walks to every reachable unbroken seal (seals only ever help, mirroring the solver).
func _break_reachable_seals(p: FSPuzzle) -> void:
	for i in p.level.seals.size():
		if p.seal_broken_flags[i] == 0:
			var path: PackedInt32Array = p.path_to_tile(p.tile_of[p.level.seals[i].at])
			if not path.is_empty():
				p.walk(path)


func test_rules_on_first_level() -> void:
	var L: FSLevelData = FSLevelData.load_file("res://levels/c1_l1.json").value
	var p: FSPuzzle = FSPuzzle.new()
	p.setup(L)
	var goal: int = p.tile_of[L.goal]
	check(p.path_to_tile(goal).is_empty(), "goal unreachable before folding")
	# Walk onto the folded strip and try to unfold while riding it: Kami would end up underneath.
	var strip_tile: int = p.tile_of[Vector3i(0, 1, 3)]
	var onto: PackedInt32Array = p.path_to_tile(strip_tile)
	check(not onto.is_empty(), "can step onto the folded strip")
	p.walk(onto)
	check_eq(p.cranes_collected(), 0, "crane is on the other cell")
	var crane_tile: int = p.tile_of[Vector3i(0, 0, 3)]
	p.walk(p.path_to_tile(crane_tile))
	check_eq(p.cranes_collected(), 1, "secret crane collected from the strip's back")
	var res: Dictionary = p.try_fold(0, 1)
	check(not res.ok, "cannot unfold while standing on the strip")
	p.walk(p.path_to_tile(p.tile_of[Vector3i(0, 1, 0)]))
	check(p.try_fold(0, 1).ok, "unfold from solid ground")
	check(not p.path_to_tile(goal).is_empty(), "bridge connects to the goal")
	var snap: Dictionary = p.snapshot()
	var p3: FSPuzzle = FSPuzzle.new()
	p3.setup(L)
	p3.restore(JSON.parse_string(JSON.stringify(snap)))
	check_eq(p3.folds, 1, "snapshot restores folds")
	check(not p3.path_to_tile(goal).is_empty(), "snapshot restores geometry")
