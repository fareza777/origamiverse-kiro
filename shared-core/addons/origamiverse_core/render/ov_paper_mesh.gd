class_name OVPaperMesh
extends RefCounted
## Builds flat-shaded paper meshes that follow the paper shader's attribute contract.
## Static attributes (sheet UV, barycentrics, crease codes) are computed once; positions update per frame.

const SHADER: Shader = preload("res://addons/origamiverse_core/render/paper.gdshader")

const CODE_NONE: float = 0.0
const CODE_FACET: float = 0.25
const CODE_VALLEY: float = 0.5
const CODE_MOUNTAIN: float = 0.75
const CODE_EDGE: float = 1.0

var mesh: ArrayMesh = ArrayMesh.new()
var doc: OVFoldDocument
var triangle_count: int = 0
## Triangle -> source face index (identity for triangulated docs).
var tri_face: PackedInt32Array = PackedInt32Array()
## Corner -> doc vertex index (3 per triangle).
var corner_vertex: PackedInt32Array = PackedInt32Array()

var _uv: PackedVector2Array = PackedVector2Array()
var _uv2: PackedVector2Array = PackedVector2Array()
var _colors: PackedColorArray = PackedColorArray()
var _positions: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _material: Material

static var _grain: NoiseTexture2D


## Drops shared static resources. Autoloads call this on exit so Godot does not report them as leaked.
static func release_shared() -> void:
	_grain = null


## Shared tileable grain texture: 256 px value noise with 16 cells across, seamless, mipmapped.
## Generated once by the engine (C++, threaded), so no asset file and no per-pixel hashing.
static func grain_texture() -> NoiseTexture2D:
	if _grain == null:
		var n: FastNoiseLite = FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
		n.frequency = 16.0 / 256.0
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		n.seed = 7
		_grain = NoiseTexture2D.new()
		_grain.width = 256
		_grain.height = 256
		_grain.seamless = true
		_grain.generate_mipmaps = true
		_grain.normalize = true
		_grain.noise = n
	return _grain


static func make_material(preset: Dictionary = {}) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("grain_tex", grain_texture())
	if not preset.is_empty():
		OVPaperPresets.apply(m, preset)
	return m


func setup(document: OVFoldDocument, material: Material = null, face_filter: PackedInt32Array = PackedInt32Array()) -> void:
	doc = document
	_material = material
	corner_vertex = PackedInt32Array()
	tri_face = PackedInt32Array()
	_uv = PackedVector2Array(); _uv2 = PackedVector2Array(); _colors = PackedColorArray()
	var face_list: PackedInt32Array = face_filter
	if face_list.is_empty():
		face_list.resize(doc.face_count())
		for i in doc.face_count():
			face_list[i] = i
	for fi in face_list:
		var f: PackedInt32Array = doc.faces[fi]
		var tri: PackedInt32Array = PackedInt32Array([0, 1, 2]) if f.size() == 3 else _fan(f.size())
		for k in range(0, tri.size(), 3):
			# FOLD faces are counter-clockwise seen from the front; Godot treats clockwise as front-facing,
			# so corners are emitted as (c0, c2, c1).
			var c: PackedInt32Array = PackedInt32Array([f[tri[k]], f[tri[k + 2]], f[tri[k + 1]]])
			var codes: Color = Color(
				_code(c[1], c[2], f), _code(c[2], c[0], f), _code(c[0], c[1], f), 1.0)
			for s in 3:
				corner_vertex.append(c[s])
				_uv.append(OVCore.sheet_uv(doc.vertices[c[s]]))
				_colors.append(codes)
			_uv2.append_array([Vector2(1, 0), Vector2(0, 1), Vector2(0, 0)])
			tri_face.append(fi)
	triangle_count = tri_face.size()
	_positions.resize(corner_vertex.size())
	_normals.resize(corner_vertex.size())
	update_from_vertices(doc.vertices)


static func _fan(n: int) -> PackedInt32Array:
	var t: PackedInt32Array = PackedInt32Array()
	for i in range(1, n - 1):
		t.append_array([0, i, i + 1])
	return t


func _code(u: int, v: int, face: PackedInt32Array) -> float:
	var e: int = doc.find_edge(u, v)
	if e < 0:
		# Internal fan diagonal of a polygon face.
		return CODE_NONE
	match doc.assignments[e]:
		OVCore.Assign.VALLEY: return CODE_VALLEY
		OVCore.Assign.MOUNTAIN: return CODE_MOUNTAIN
		OVCore.Assign.BOUNDARY, OVCore.Assign.CUT: return CODE_EDGE
	return CODE_NONE


## Positions given per document vertex (bar-hinge solver output).
func update_from_vertices(vertex_positions: PackedVector3Array) -> void:
	for i in corner_vertex.size():
		_positions[i] = vertex_positions[corner_vertex[i]]
	_commit()


## Positions given per corner (3 per triangle, hinge solver output where panels may not share vertices).
func update_from_corners(corner_positions: PackedVector3Array) -> void:
	_positions = corner_positions.duplicate()
	_commit()


## Positions from a hinge solver: each corner uses its face's panel transform.
func update_from_hinge_solver(solver: OVHingeSolver) -> void:
	for t in triangle_count:
		var xf: Transform3D = solver.panel_transforms[solver.panel_of_face[tri_face[t]]]
		for s in 3:
			var i: int = t * 3 + s
			_positions[i] = xf * doc.vertices[corner_vertex[i]]
	_commit()


func _commit() -> void:
	if triangle_count == 0:
		mesh.clear_surfaces()
		return
	for t in triangle_count:
		var i: int = t * 3
		# Corners are in Godot (clockwise-front) order, so the front normal is (p2 - p0) x (p1 - p0).
		var n: Vector3 = (_positions[i + 2] - _positions[i]).cross(_positions[i + 1] - _positions[i])
		n = n.normalized() if n.length_squared() > 1e-20 else Vector3.UP
		_normals[i] = n
		_normals[i + 1] = n
		_normals[i + 2] = n
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _positions
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_COLOR] = _colors
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _material != null:
		mesh.surface_set_material(0, _material)


func set_material(material: Material) -> void:
	_material = material
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)


func corner_positions() -> PackedVector3Array:
	return _positions


## Triangle soup for ConcavePolygonShape3D (two-sided collision for ray picking).
func collision_faces() -> PackedVector3Array:
	return _positions


func aabb() -> AABB:
	if _positions.is_empty():
		return AABB()
	var box: AABB = AABB(_positions[0], Vector3.ZERO)
	for p in _positions:
		box = box.expand(p)
	return box
