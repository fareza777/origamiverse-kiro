class_name PVFoldView
extends Node3D
## Real-time 3D folding view. Lives inside a SubViewport so the studio can lay it out with Controls.

signal settled
signal stats_changed(text: String)

const MODEL_SCALE: float = 2.0
## Still frames before the soft solver sleeps: at its target pose, and when it rests short of the target.
const SLEEP_FRAMES: int = 20
const SLEEP_FRAMES_LONG: int = 60
## Camera fit for the folded paper's bounding sphere. 1.0 fits the whole sphere: folded paper can reach the full
## radius toward the camera, and anything tighter clipped tall bases at the bottom of the view.
const FIT_FILL: float = 1.0

var camera_rig: OVOrbitCamera
var doc: OVFoldDocument
var soft: OVBarHingeSolver
var rigid_solver: OVHingeSolver
var rigid: bool = false
var paper: OVPaperMesh = OVPaperMesh.new()
var material: ShaderMaterial
var fold_percent: float = 0.0
var spin_degrees: float = 0.0
var sleeping: bool = false

var _model_root: Node3D
var _mesh_instance: MeshInstance3D
var _pick_body: StaticBody3D
var _pick_shape: CollisionShape3D
var _ground: MeshInstance3D
var _ground_y: float = 0.0
var _still_frames: int = 0
var _last_positions: PackedVector3Array = PackedVector3Array()
var _budget_usec: int = 7000
var _pin_marker: MeshInstance3D
var _stats_timer: float = 0.0
var sun: DirectionalLight3D
## The pick shape (concave BVH) is rebuilt only when the paper is at rest, not every simulated frame.
var _pick_dirty: bool = true
## The paper moved since the camera was last fitted to it.
var _fit_pending: bool = false


func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("c9d3f2")
	sky_mat.sky_horizon_color = Color("f4f1ea")
	sky_mat.ground_horizon_color = Color("f4f1ea")
	sky_mat.ground_bottom_color = Color("d9d3c7")
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_COLOR
	# Cool blue-grey backdrop and a darker ground than any paper preset's light side, so a white sheet never
	# blends into the background (white-on-white was hard to read on phones).
	e.background_color = Color("cfd7ea")
	e.background_energy_multiplier = 1.0
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.2
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -30, 0)
	sun.light_energy = 1.15
	sun.light_color = Color("fff6e8")
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.8
	sun.directional_shadow_max_distance = 12.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("cfdcff")
	add_child(fill)

	_ground = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 9.0
	disc.bottom_radius = 9.0
	disc.height = 0.02
	disc.radial_segments = 64
	_ground.mesh = disc
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color("b9c2d8")
	gm.roughness = 0.95
	_ground.material_override = gm
	add_child(_ground)

	_model_root = Node3D.new()
	add_child(_model_root)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = paper.mesh
	_model_root.add_child(_mesh_instance)
	_pick_body = StaticBody3D.new()
	_pick_shape = CollisionShape3D.new()
	_pick_body.add_child(_pick_shape)
	_model_root.add_child(_pick_body)
	_pin_marker = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	_pin_marker.mesh = sm
	var pm: StandardMaterial3D = StandardMaterial3D.new()
	pm.albedo_color = Color("2b2640")
	pm.emission_enabled = true
	pm.emission = Color("ffb347")
	pm.emission_energy_multiplier = 0.6
	_pin_marker.material_override = pm
	_model_root.add_child(_pin_marker)
	material = OVPaperMesh.make_material(OVPaperPresets.PRESETS[0])
	material.set_shader_parameter("grain_scale", 22.0)
	# Darker sheet outline and creases so the paper's shape reads at a glance.
	material.set_shader_parameter("edge_strength", 0.6)
	material.set_shader_parameter("crease_strength", 0.45)
	camera_rig = OVOrbitCamera.new()
	camera_rig.min_pitch = -20.0
	add_child(camera_rig)


## Loads a document. Returns {"ok": bool, "message": String}.
func load_document(d: OVFoldDocument, pin_face: int, want_rigid: bool) -> Dictionary:
	doc = d
	var message: String = ""
	if doc.face_count() == 0:
		return {"ok": false, "message": "The pattern has no faces."}
	# Center the sheet on the origin and scale it to a comfortable size.
	var r: Rect2 = doc.sheet_rect()
	var c: Vector2 = r.get_center()
	var s: float = MODEL_SCALE / maxf(maxf(r.size.x, r.size.y), 1e-6)
	for i in doc.vertex_count():
		var uv: Vector2 = (OVCore.sheet_uv(doc.vertices[i]) - c) * s
		doc.vertices[i] = OVCore.fold_to_godot(uv.x, uv.y)
	paper.setup(doc, material)
	_mesh_instance.mesh = paper.mesh
	soft = OVBarHingeSolver.new()
	var pin: int = pin_face if pin_face >= 0 and pin_face < doc.face_count() else -1
	soft.setup(doc, pin)
	rigid = false
	rigid_solver = null
	if want_rigid:
		var rs: OVHingeSolver = OVHingeSolver.new()
		rs.thickness = 0.004
		var res: Dictionary = rs.build(doc, soft.pinned_face)
		if res.ok:
			rigid = true
			rigid_solver = rs
		else:
			message = "Rigid mode needs a tree of straight hinges. Using soft simulation: " + str(res.errors[0])
	camera_rig.frame_bounds(AABB(Vector3(-1.2, -0.6, -1.2), Vector3(2.4, 1.2, 2.4)), {"yaw": 30.0, "pitch": 48.0}, 1.0, 0.62, false)
	wake()
	_update_mesh()
	_fit_camera()
	return {"ok": true, "message": message}


func pinned_face() -> int:
	return soft.pinned_face if soft else -1


func set_pinned_face(fi: int) -> void:
	if soft == null or fi < 0 or fi >= doc.face_count():
		return
	soft.set_pinned_face(fi)
	if rigid and rigid_solver:
		rigid_solver.build(doc, fi)
	wake()


func set_fold(p: float) -> void:
	if absf(p - fold_percent) > 1e-5:
		fold_percent = p
		wake()


func set_spin(deg: float) -> void:
	spin_degrees = deg
	_model_root.rotation.y = deg_to_rad(deg)


func set_preset(p: Dictionary) -> void:
	OVPaperPresets.apply(material, p)


func set_show_assignment(on: bool) -> void:
	material.set_shader_parameter("show_assignment", 1.0 if on else 0.0)


func wake() -> void:
	sleeping = false
	_still_frames = 0


func reset_shape() -> void:
	if soft:
		soft.reset()
	wake()


func _process(dt: float) -> void:
	if doc == null:
		return
	if not sleeping:
		_fit_pending = true
		if rigid and rigid_solver:
			rigid_solver.apply_fold_percent(fold_percent)
			rigid_solver.update()
			_update_mesh()
			sleeping = true
			settled.emit()
		else:
			_step_soft(dt)
	if sleeping and _pick_dirty:
		_pick_dirty = false
		OVCollisionSync.sync_concave(_pick_shape, paper.collision_faces())
	_ground_y = lerpf(_ground_y, _lowest_y() - 0.03, 1.0 - exp(-dt * 6.0))
	_ground.position.y = _ground_y - 0.01
	_stats_timer -= dt
	var tick: bool = _stats_timer <= 0.0
	if tick:
		_stats_timer = 0.5
		stats_changed.emit(stats_text())
	# Follow the paper's changing shape twice a second while it moves, and once more when it comes to rest.
	if _fit_pending and (tick or sleeping):
		_fit_pending = false
		_fit_camera()


func _step_soft(dt: float) -> void:
	soft.fold_percent = fold_percent
	var t0: int = Time.get_ticks_usec()
	soft.step(dt)
	var used: int = Time.get_ticks_usec() - t0
	# Adapt substeps so the solver stays inside its frame budget on slower phones.
	if used > _budget_usec and soft.substeps > 3:
		soft.substeps -= 1
	elif used < _budget_usec / 2 and soft.substeps < 12:
		soft.substeps += 1
	if not soft.is_finite_state():
		soft.reset()
	_update_mesh()
	var moved: float = 0.0
	if _last_positions.size() == soft.positions.size():
		for i in range(0, soft.positions.size(), 3):
			moved = maxf(moved, soft.positions[i].distance_squared_to(_last_positions[i]))
	_last_positions = soft.positions.duplicate()
	if moved < 1e-9:
		_still_frames += 1
	else:
		_still_frames = 0
	# Sleep once the paper stops moving. Usually it has reached its pose by then; patterns that cannot reach every
	# crease angle without collisions (bird base, twists, Miura at high percents) rest a little short of it, so after
	# a longer still spell they sleep anyway instead of simulating forever and draining the battery.
	if _still_frames > SLEEP_FRAMES_LONG or (_still_frames > SLEEP_FRAMES and soft.crease_error_degrees() < 2.0):
		sleeping = true
		settled.emit()


func _update_mesh() -> void:
	if rigid and rigid_solver:
		paper.update_from_hinge_solver(rigid_solver)
	else:
		paper.update_from_vertices(soft.positions)
	_pick_dirty = true
	var pin_face_index: int = soft.pinned_face
	if pin_face_index >= 0:
		var f: PackedInt32Array = doc.faces[pin_face_index]
		var pos: PackedVector3Array = soft.positions if not rigid else rigid_solver.vertex_positions()
		_pin_marker.position = (pos[f[0]] + pos[f[1]] + pos[f[2]]) / 3.0 + Vector3.UP * 0.03


## Frames the folded paper. Uses a sphere around the spin axis so turntable animation never leaves the frame.
## While the user has moved the camera, only the Recenter target is updated.
func _fit_camera() -> void:
	if doc == null or camera_rig == null or camera_rig.camera == null:
		return
	var pos: PackedVector3Array = folded_vertices()
	if pos.is_empty():
		return
	var lo: float = INF
	var hi: float = -INF
	var reach: float = 0.0
	for p in pos:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		reach = maxf(reach, p.x * p.x + p.z * p.z)
	var half_h: float = (hi - lo) * 0.5
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = vs.x / maxf(vs.y, 1.0) if vs.y > 0.0 else 1.0
	camera_rig.refit(Vector3(0.0, (lo + hi) * 0.5, 0.0), sqrt(reach + half_h * half_h), aspect, FIT_FILL)


func _lowest_y() -> float:
	var lo: float = 0.0
	var first: bool = true
	for p in paper.corner_positions():
		if first or p.y < lo:
			lo = p.y
			first = false
	return lo


## Face index under a screen point of the SubViewport, or -1.
func pick_face(screen: Vector2) -> int:
	if _pick_dirty:
		_pick_dirty = false
		OVCollisionSync.sync_concave(_pick_shape, paper.collision_faces())
	var hit: Dictionary = OVCollisionSync.pick(camera_rig.camera, screen)
	if hit.is_empty() or not hit.has("face_index"):
		return -1
	var tri: int = int(hit.face_index)
	if tri < 0 or tri >= paper.tri_face.size():
		return -1
	return paper.tri_face[tri]


func folded_vertices() -> PackedVector3Array:
	if rigid and rigid_solver:
		return rigid_solver.vertex_positions()
	return soft.positions


## Corners in world space (spin applied) for exports.
func export_corners() -> PackedVector3Array:
	var out: PackedVector3Array = paper.corner_positions().duplicate()
	var xf: Transform3D = _model_root.transform
	for i in out.size():
		out[i] = xf * out[i]
	return out


func stats_text() -> String:
	if doc == null:
		return ""
	if rigid:
		return "%d triangles · rigid hinges" % doc.face_count()
	return "%d triangles · strain %.2f%% · %s" % [doc.face_count(), soft.strain * 100.0, "settled" if sleeping else "folding"]


func max_strain() -> float:
	return 0.0 if rigid else soft.strain
