class_name FSEnvironment
extends Node3D
## Sky, light, fog, paper sea, island bases and decorative props for a chapter style.

const SEA_SHADER: Shader = preload("res://scripts/world/sea.gdshader")

var sun: DirectionalLight3D
var _clouds: Array[Node3D] = []
var env: Environment


func build(style: Dictionary, puzzle: FSPuzzle, bounds: AABB, rng_seed: int) -> void:
	var we: WorldEnvironment = WorldEnvironment.new()
	env = Environment.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = style.sky_top
	sky_mat.sky_horizon_color = style.sky_horizon
	sky_mat.ground_horizon_color = style.sky_horizon
	sky_mat.ground_bottom_color = style.ground
	sky_mat.sun_angle_max = 20.0
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = style.ambient
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = style.fog
	env.fog_density = style.fog_density
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = style.sun
	sun.light_energy = style.sun_energy
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_max_distance = maxf(30.0, bounds.size.length() * 2.5)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	add_child(sun)
	if Game.quality:
		Game.quality.register_light(sun)

	var center: Vector3 = bounds.get_center()
	var sea: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(260, 260)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	sea.mesh = plane
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = SEA_SHADER
	sm.set_shader_parameter("color_a", style.sea_a)
	sm.set_shader_parameter("color_b", style.sea_b)
	sm.set_shader_parameter("noise_tex", OVPaperMesh.grain_texture())
	sea.material_override = sm
	sea.position = Vector3(center.x, bounds.position.y - 5.0, center.z)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)

	_build_island_bases(style, puzzle)
	_scatter_props(style, bounds, rng_seed)


## Layered paper "cake" under the base cells so islands read as solid ground.
func _build_island_bases(style: Dictionary, puzzle: FSPuzzle) -> void:
	var layers: Array[Color] = [style.base.back, (style.base.back as Color).darkened(0.12), (style.base.back as Color).darkened(0.25)]
	for i in puzzle.level.islands.size():
		var isl: Dictionary = puzzle.level.islands[i]
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var depth: float = 0.0
		for li in layers.size():
			var top: float = -0.04 - depth
			var h: float = 0.22 - li * 0.03
			var inset: float = 0.05 + li * 0.07
			st.set_color(layers[li])
			for cell in isl.cells.keys():
				if isl.cells[cell] != ".":
					continue
				_cell_box(st, isl, cell, top, top - h, inset)
			depth += h
		st.generate_normals()
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		mi.position = isl.origin
		add_child(mi)


func _cell_box(st: SurfaceTool, isl: Dictionary, cell: Vector2i, y0: float, y1: float, inset: float) -> void:
	var cells: Dictionary = isl.cells
	var x0: float = cell.y
	var x1: float = cell.y + 1.0
	var z0: float = cell.x
	var z1: float = cell.x + 1.0
	# Inset only on island borders so neighboring columns merge into one mass.
	if not (cells.get(cell + Vector2i(0, -1), "_") == "."):
		x0 += inset
	if not (cells.get(cell + Vector2i(0, 1), "_") == "."):
		x1 -= inset
	if not (cells.get(cell + Vector2i(-1, 0), "_") == "."):
		z0 += inset
	if not (cells.get(cell + Vector2i(1, 0), "_") == "."):
		z1 -= inset
	var p: Array[Vector3] = [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1),
		Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
	var quads: Array = [[3, 2, 6, 7], [1, 0, 4, 5], [2, 1, 5, 6], [0, 3, 7, 4], [7, 6, 5, 4]]
	for q in quads:
		st.add_vertex(p[q[0]]); st.add_vertex(p[q[1]]); st.add_vertex(p[q[2]])
		st.add_vertex(p[q[0]]); st.add_vertex(p[q[2]]); st.add_vertex(p[q[3]])


func _scatter_props(style: Dictionary, bounds: AABB, rng_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed
	var center: Vector3 = bounds.get_center()
	var radius: float = maxf(bounds.size.x, bounds.size.z) * 0.5
	# Small decorative islets with props around the play area (never on playable tiles).
	var islets: int = 6
	for i in islets:
		var ang: float = TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / islets
		var dist: float = radius + rng.randf_range(3.0, 6.0)
		var pos: Vector3 = center + Vector3(cos(ang) * dist, rng.randf_range(-2.5, -0.5), sin(ang) * dist)
		var islet: Node3D = Node3D.new()
		islet.position = pos
		add_child(islet)
		var rock: Node3D = _model("rock")
		rock.scale = Vector3(3.2, 2.4, 3.2) * rng.randf_range(0.7, 1.1)
		rock.rotation.y = rng.randf() * TAU
		islet.add_child(rock)
		for k in rng.randi_range(1, 3):
			var prop: Node3D = _model(style.props[rng.randi() % style.props.size()])
			prop.position = Vector3(rng.randf_range(-0.6, 0.6), 0.7, rng.randf_range(-0.6, 0.6))
			prop.rotation.y = rng.randf() * TAU
			prop.scale = Vector3.ONE * rng.randf_range(0.9, 1.4)
			islet.add_child(prop)
	for i in 5:
		var m: Node3D = _model("mountain")
		var ang2: float = TAU * float(i) / 5.0 + rng.randf() * 0.5
		m.position = center + Vector3(cos(ang2), 0, sin(ang2)) * (radius + rng.randf_range(28.0, 40.0)) + Vector3(0, bounds.position.y - 6.0, 0)
		m.scale = Vector3.ONE * rng.randf_range(4.0, 7.0)
		m.rotation.y = rng.randf() * TAU
		add_child(m)
	for i in 7:
		var c: Node3D = _model("cloud")
		var ang3: float = rng.randf() * TAU
		c.position = center + Vector3(cos(ang3), 0, sin(ang3)) * (radius + rng.randf_range(6.0, 18.0)) + Vector3(0, rng.randf_range(3.0, 7.0), 0)
		c.scale = Vector3.ONE * rng.randf_range(1.2, 2.4)
		c.set_meta("drift", rng.randf_range(0.15, 0.35))
		_clouds.append(c)
		add_child(c)


func _model(name: String) -> Node3D:
	var scene: PackedScene = load("res://assets/models/%s.glb" % name)
	var n: Node3D = scene.instantiate()
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	if ap and ap.get_animation_list().size() > 0:
		var a: String = ap.get_animation_list()[0]
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		ap.play(a)
		ap.seek(randf() * 2.0)
	return n


func _process(dt: float) -> void:
	for c in _clouds:
		c.position.x += float(c.get_meta("drift")) * dt
