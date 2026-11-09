class_name OVCollisionSync
extends RefCounted
## Keeps physics shapes aligned with folded paper so ray picking and physics props follow the fold.


## Transform whose basis spans a quad tile: X along corner0->corner1, Y = tile normal, Z completes.
static func tile_transform(c: PackedVector3Array) -> Transform3D:
	var center: Vector3 = (c[0] + c[1] + c[2] + c[3]) * 0.25
	var x: Vector3 = (c[1] - c[0]).normalized()
	var y: Vector3 = (c[1] - c[0]).cross(c[3] - c[0]).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), center)


## Creates a thin static box for one tile. Metadata "tile_id" lets ray hits map back to the tile.
static func make_tile_body(tile_id: int, size: float = 1.0, thickness: float = 0.04, layer: int = 1) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.set_meta("tile_id", tile_id)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(size * 0.98, thickness, size * 0.98)
	shape.shape = box
	body.add_child(shape)
	return body


static func sync_tile_body(body: StaticBody3D, corners: PackedVector3Array) -> void:
	body.transform = tile_transform(corners)


## Updates (or creates) a two-sided concave shape from triangle corners.
static func sync_concave(shape_node: CollisionShape3D, corners: PackedVector3Array) -> void:
	var shape: ConcavePolygonShape3D = shape_node.shape as ConcavePolygonShape3D
	if shape == null:
		shape = ConcavePolygonShape3D.new()
		shape_node.shape = shape
	shape.backface_collision = true
	shape.set_faces(corners)


## Ray pick against physics in `world` from a camera and screen point. Returns the hit dictionary or {}.
static func pick(camera: Camera3D, screen_pos: Vector2, mask: int = 0xFFFFFFFF, length: float = 200.0) -> Dictionary:
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * length
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask)
	query.hit_back_faces = true
	return camera.get_world_3d().direct_space_state.intersect_ray(query)
