class_name FSLevelData
extends RefCounted
## Parsed FoldShift level. Each island becomes a triangulated OVFoldDocument that OVHingeSolver can fold.

const SIDE_OFFSETS: Dictionary = {"N": Vector2i(-1, 0), "S": Vector2i(1, 0), "W": Vector2i(0, -1), "E": Vector2i(0, 1)}

var id: String = ""
var chapter: int = 1
var index: int = 1
var title: String = ""
var hint: String = ""
var par: int = -1
var islands: Array[Dictionary] = []   ## {"origin": Vector3, "cells": {Vector2i: String}}
var flaps: Dictionary = {}            ## letter -> {"hinge", "angles": PackedFloat32Array, "start": float, "parent": String}
var flap_order: PackedStringArray = PackedStringArray()
var start: Vector3i
var goal: Vector3i
var cranes: Array[Dictionary] = []    ## {"at": Vector3i, "side": 0|1}
var seals: Array[Dictionary] = []     ## {"at": Vector3i, "unlocks": PackedStringArray}
var camera: Dictionary = {}           ## optional {"yaw", "pitch", "distance"}


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return OVCore.fail(PackedStringArray(["Level file missing: " + path]))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return OVCore.fail(PackedStringArray(["Level is not valid JSON: " + path]))
	return parse(parsed)


static func parse(d: Dictionary) -> Dictionary:
	var L: FSLevelData = FSLevelData.new()
	var errors: PackedStringArray = PackedStringArray()
	L.id = str(d.get("id", ""))
	L.chapter = int(d.get("chapter", 1))
	L.index = int(d.get("index", 1))
	L.title = str(d.get("title", L.id))
	L.hint = str(d.get("hint", ""))
	L.par = int(d.get("par", -1))
	L.camera = d.get("camera", {})
	for isl in d.get("islands", []):
		var o: Array = isl.get("origin", [0, 0, 0])
		var cells: Dictionary = {}
		var rows: Array = isl.get("rows", [])
		for r in rows.size():
			var row: String = str(rows[r]).replace(" ", "")
			for c in row.length():
				var ch: String = row[c]
				if ch != "_":
					cells[Vector2i(r, c)] = ch
		L.islands.append({"origin": Vector3(float(o[0]), float(o[1]), float(o[2])), "cells": cells})
	var fl: Dictionary = d.get("flaps", {})
	var names: Array = fl.keys()
	names.sort()
	for name in names:
		var f: Dictionary = fl[name]
		var angles: PackedFloat32Array = PackedFloat32Array()
		for a in f.get("angles", [0, 180]):
			angles.append(float(a))
		var hinge: String = str(f.get("hinge", "W")).to_upper()
		if not SIDE_OFFSETS.has(hinge):
			errors.append("Flap %s has an invalid hinge side %s." % [name, hinge])
		var start_angle: float = float(f.get("start", angles[0]))
		if angles.find(start_angle) < 0:
			errors.append("Flap %s start angle %s is not one of its angles." % [name, str(start_angle)])
		L.flaps[str(name)] = {"hinge": hinge, "angles": angles, "start": start_angle, "parent": str(f.get("parent", "."))}
		L.flap_order.append(str(name))
	L.start = _v3i(d.get("start", [0, 0, 0]))
	L.goal = _v3i(d.get("goal", [0, 0, 0]))
	for cr in d.get("cranes", []):
		L.cranes.append({"at": _v3i(cr), "side": 1 if (cr.size() > 3 and str(cr[3]) == "back") else 0})
	for s in d.get("seals", []):
		var unl: PackedStringArray = PackedStringArray()
		var u: Variant = s.get("unlocks", [])
		if typeof(u) == TYPE_STRING:
			unl.append(u)
		else:
			for x in u:
				unl.append(str(x))
		L.seals.append({"at": _v3i(s.get("at", [0, 0, 0])), "unlocks": unl})
	for p in [L.start, L.goal]:
		if not L.has_cell(p):
			errors.append("Start/goal %s is not on a cell." % str(p))
	for cr in L.cranes:
		if not L.has_cell(cr.at):
			errors.append("Crane %s is not on a cell." % str(cr.at))
	for s in L.seals:
		if not L.has_cell(s.at):
			errors.append("Seal %s is not on a cell." % str(s.at))
		for name in s.unlocks:
			if not L.flaps.has(name):
				errors.append("Seal unlocks unknown flap %s." % name)
	for isl in L.islands:
		for cell in isl.cells.keys():
			var ch: String = isl.cells[cell]
			if ch != "." and not L.flaps.has(ch):
				errors.append("Cell %s uses undefined flap %s." % [str(cell), ch])
	if not errors.is_empty():
		return OVCore.fail(errors)
	return OVCore.ok(L)


static func _v3i(a: Array) -> Vector3i:
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))


func has_cell(p: Vector3i) -> bool:
	return p.x >= 0 and p.x < islands.size() and islands[p.x].cells.has(Vector2i(p.y, p.z))


func cell_char(p: Vector3i) -> String:
	return islands[p.x].cells.get(Vector2i(p.y, p.z), "_")


## Builds the FOLD document for an island.
## Returns {"doc": OVFoldDocument, "cell_faces": {Vector2i: PackedInt32Array}, "root_face": int}
func build_island_document(island_index: int) -> Dictionary:
	var cells: Dictionary = islands[island_index].cells
	var doc: OVFoldDocument = OVFoldDocument.new()
	doc.meta["file_title"] = "%s island %d" % [id, island_index]
	doc.meta["file_creator_app"] = "FoldShift"
	var vid: Dictionary = {}
	var vert := func(gr: int, gc: int) -> int:
		var k: Vector2i = Vector2i(gr, gc)
		if not vid.has(k):
			vid[k] = doc.add_vertex(OVCore.fold_to_godot(float(gc), -float(gr)))
		return vid[k]
	var cell_faces: Dictionary = {}
	var keys: Array = cells.keys()
	keys.sort()
	var root_face: int = -1
	for cell in keys:
		var r: int = cell.x
		var c: int = cell.y
		var c0: int = vert.call(r + 1, c)
		var c1: int = vert.call(r + 1, c + 1)
		var c2: int = vert.call(r, c + 1)
		var c3: int = vert.call(r, c)
		var f0: int = doc.add_face(PackedInt32Array([c0, c1, c2]))
		var f1: int = doc.add_face(PackedInt32Array([c0, c2, c3]))
		cell_faces[cell] = PackedInt32Array([f0, f1])
		doc.add_edge(c0, c2, OVCore.Assign.FLAT, 0.0)
		if root_face < 0 and cells[cell] == ".":
			root_face = f0
	# Cell sides: S = between corner rows r+1 (c0-c1), E (c1-c2), N (c2-c3), W (c3-c0).
	for cell in keys:
		var r: int = cell.x
		var c: int = cell.y
		var sides: Dictionary = {
			"S": [Vector2i(r + 1, c), Vector2i(r + 1, c + 1)],
			"E": [Vector2i(r + 1, c + 1), Vector2i(r, c + 1)],
			"N": [Vector2i(r, c + 1), Vector2i(r, c)],
			"W": [Vector2i(r, c), Vector2i(r + 1, c)],
		}
		for side in sides.keys():
			var a: int = vid[sides[side][0]]
			var b: int = vid[sides[side][1]]
			if doc.find_edge(a, b) >= 0:
				continue
			var other: Vector2i = cell + SIDE_OFFSETS[side]
			var assign: int = OVCore.Assign.BOUNDARY
			if cells.has(other):
				assign = _edge_assign(cells[cell], side, cells[other])
			doc.add_edge(a, b, assign, 180.0 if assign == OVCore.Assign.VALLEY else 0.0)
	return {"doc": doc, "cell_faces": cell_faces, "root_face": maxi(root_face, 0)}


const OPPOSITE: Dictionary = {"N": "S", "S": "N", "E": "W", "W": "E"}


func _edge_assign(a: String, side_from_a: String, b: String) -> int:
	if a == b:
		return OVCore.Assign.FLAT
	if flaps.has(a) and flaps[a].hinge == side_from_a and flaps[a].parent == b:
		return OVCore.Assign.VALLEY
	if flaps.has(b) and flaps[b].hinge == OPPOSITE[side_from_a] and flaps[b].parent == a:
		return OVCore.Assign.VALLEY
	return OVCore.Assign.CUT
