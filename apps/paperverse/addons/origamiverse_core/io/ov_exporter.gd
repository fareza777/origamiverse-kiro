class_name OVExporter
extends RefCounted
## Exports folded paper as FOLD, Wavefront OBJ (+MTL) and binary glTF (GLB).
## Exports are two-sided: front and back are separate surfaces so any viewer shows both paper colors.


## FOLD text: the crease pattern plus a "foldedForm" frame with 3D vertex positions.
static func fold_text(doc: OVFoldDocument, folded_vertices: PackedVector3Array, title: String = "") -> String:
	var d: OVFoldDocument = doc.duplicate_document()
	if title != "":
		d.meta["file_title"] = title
	return d.to_json(folded_vertices)


## Two-sided mesh from triangle corners (3 per triangle, Godot clockwise-front order as produced by OVPaperMesh).
static func two_sided_mesh(corners: PackedVector3Array, front: Color, back: Color) -> ArrayMesh:
	var m: ArrayMesh = ArrayMesh.new()
	for side in 2:
		var pos: PackedVector3Array = PackedVector3Array()
		var nrm: PackedVector3Array = PackedVector3Array()
		var offset: float = 0.0004 * (1.0 if side == 0 else -1.0)
		for t in range(0, corners.size(), 3):
			var a: Vector3 = corners[t]
			var b: Vector3 = corners[t + 1]
			var c: Vector3 = corners[t + 2]
			var n: Vector3 = (c - a).cross(b - a).normalized()
			if side == 0:
				pos.append_array([a + n * offset, b + n * offset, c + n * offset])
				nrm.append_array([n, n, n])
			else:
				pos.append_array([a + n * offset, c + n * offset, b + n * offset])
				nrm.append_array([-n, -n, -n])
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = front if side == 0 else back
		mat.roughness = 0.85
		mat.resource_name = "paper_front" if side == 0 else "paper_back"
		m.surface_set_material(side, mat)
		m.surface_set_name(side, mat.resource_name)
	return m


## Writes a GLB file. Returns OK or an error.
static func write_glb(path: String, corners: PackedVector3Array, front: Color, back: Color, name: String = "Origami") -> Error:
	var root: Node3D = Node3D.new()
	root.name = name.validate_node_name() if name != "" else "Origami"
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Paper"
	mi.mesh = two_sided_mesh(corners, front, back)
	root.add_child(mi)
	mi.owner = root
	var gltf: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var err: Error = gltf.append_from_scene(root, state)
	if err == OK:
		err = gltf.write_to_filesystem(state, path)
	root.free()
	return err


## GLB bytes (for share sheets / native save dialogs).
static func glb_bytes(corners: PackedVector3Array, front: Color, back: Color, name: String = "Origami") -> PackedByteArray:
	var root: Node3D = Node3D.new()
	root.name = name.validate_node_name() if name != "" else "Origami"
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Paper"
	mi.mesh = two_sided_mesh(corners, front, back)
	root.add_child(mi)
	mi.owner = root
	var gltf: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var bytes: PackedByteArray = PackedByteArray()
	if gltf.append_from_scene(root, state) == OK:
		bytes = gltf.generate_buffer(state)
	root.free()
	return bytes


## OBJ text referencing `mtl_name`. Godot units map 1:1 to OBJ units, Y up.
static func obj_text(corners: PackedVector3Array, mtl_name: String = "paper.mtl") -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Exported by %s" % OVCore.CREATOR)
	lines.append("mtllib %s" % mtl_name)
	lines.append("o Origami")
	for p in corners:
		lines.append("v %.6f %.6f %.6f" % [p.x, p.y, p.z])
	var tri_count: int = corners.size() / 3
	# OBJ is counter-clockwise-front; corners arrive clockwise-front (Godot), so front faces list (a, c, b).
	for t in tri_count:
		var a: Vector3 = corners[t * 3]
		var n: Vector3 = (corners[t * 3 + 2] - a).cross(corners[t * 3 + 1] - a).normalized()
		lines.append("vn %.5f %.5f %.5f" % [n.x, n.y, n.z])
	for t in tri_count:
		var n2: Vector3 = (corners[t * 3 + 2] - corners[t * 3]).cross(corners[t * 3 + 1] - corners[t * 3]).normalized()
		lines.append("vn %.5f %.5f %.5f" % [-n2.x, -n2.y, -n2.z])
	lines.append("usemtl paper_front")
	for t in tri_count:
		var i: int = t * 3 + 1
		lines.append("f %d//%d %d//%d %d//%d" % [i, t + 1, i + 2, t + 1, i + 1, t + 1])
	lines.append("usemtl paper_back")
	for t in tri_count:
		var i: int = t * 3 + 1
		var nb: int = tri_count + t + 1
		lines.append("f %d//%d %d//%d %d//%d" % [i, nb, i + 1, nb, i + 2, nb])
	return "\n".join(lines) + "\n"


static func mtl_text(front: Color, back: Color) -> String:
	return "# OrigamiVerse paper\nnewmtl paper_front\nKd %.4f %.4f %.4f\nNs 10\n\nnewmtl paper_back\nKd %.4f %.4f %.4f\nNs 10\n" % [
		front.r, front.g, front.b, back.r, back.g, back.b]
