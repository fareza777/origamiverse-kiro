class_name FSCharacter
extends Node3D
## Kami the paper fox. Walks a list of surface points, aligning her up axis to the paper normal.

signal stepped(index: int)
signal arrived

const MODEL: PackedScene = preload("res://assets/models/kami.glb")
const HOP_TIME: float = 0.24

var model: Node3D
var anim: AnimationPlayer
var walking: bool = false
var facing: Vector3 = Vector3.FORWARD

var _points: Array = []      # [{"pos": Vector3, "normal": Vector3}]
var _seg: int = 0
var _t: float = 0.0
var _up: Vector3 = Vector3.UP
var _squash: float = 0.0


func _ready() -> void:
	model = MODEL.instantiate()
	add_child(model)
	model.scale = Vector3.ONE * 1.6
	anim = _find_anim(model)
	if anim:
		for name in anim.get_animation_list():
			anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
		if anim.has_animation("idle"):
			anim.play("idle")


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a: AnimationPlayer = _find_anim(c)
		if a:
			return a
	return null


## Places Kami on a surface point (used while idle so she rides moving paper).
func place(pos: Vector3, normal: Vector3) -> void:
	_up = normal
	global_transform = Transform3D(_basis(normal, facing), pos)


func walk(points: Array) -> void:
	if points.size() < 2:
		arrived.emit()
		return
	_points = points
	_seg = 0
	_t = 0.0
	walking = true


func stop() -> void:
	walking = false


func _process(dt: float) -> void:
	_squash = maxf(0.0, _squash - dt * 4.0)
	if model:
		var s: float = 1.0 - 0.12 * sin(_squash * PI)
		model.scale = Vector3(1.6 / sqrt(s), 1.6 * s, 1.6 / sqrt(s))
	if not walking:
		return
	_t += dt / HOP_TIME
	while _t >= 1.0 and walking:
		_t -= 1.0
		_seg += 1
		stepped.emit(_seg)
		_squash = 1.0
		if _seg >= _points.size() - 1:
			walking = false
			var last: Dictionary = _points[_points.size() - 1]
			place(last.pos, last.normal)
			arrived.emit()
			return
	var a: Dictionary = _points[_seg]
	var b: Dictionary = _points[_seg + 1]
	var na: Vector3 = a.normal
	var nb: Vector3 = b.normal
	var t: float = _t
	var pos: Vector3
	var up: Vector3
	if na.dot(nb) > 0.95:
		pos = a.pos.lerp(b.pos, t) + na * (sin(t * PI) * 0.18)
		up = na
	else:
		# Corner (wall or ledge): go through the shared edge so Kami never cuts through paper.
		var edge: Vector3 = _edge_point(a.pos, na, b.pos, nb)
		var bend: Vector3 = (na + nb).normalized() * 0.05
		if t < 0.5:
			pos = a.pos.lerp(edge + bend, t * 2.0)
		else:
			pos = (edge + bend).lerp(b.pos, (t - 0.5) * 2.0)
		up = na.slerp(nb, smoothstep(0.25, 0.75, t)).normalized()
	var dir: Vector3 = (b.pos - a.pos)
	var tangent: Vector3 = dir - up * dir.dot(up)
	if tangent.length_squared() > 1e-6:
		facing = facing.slerp(tangent.normalized(), minf(1.0, dt * 14.0)).normalized()
	global_transform = Transform3D(_basis(up, facing), pos)


static func _edge_point(pa: Vector3, na: Vector3, pb: Vector3, nb: Vector3) -> Vector3:
	# Walk from A within its plane toward B until reaching B's plane.
	var d: Vector3 = pb - pa
	d = (d - na * d.dot(na))
	if d.length_squared() < 1e-8:
		return (pa + pb) * 0.5
	d = d.normalized()
	var denom: float = d.dot(nb)
	if absf(denom) < 1e-4:
		return (pa + pb) * 0.5
	var s: float = (pb - pa).dot(nb) / denom
	return pa + d * clampf(s, 0.0, 1.0)


func _basis(up: Vector3, fwd: Vector3) -> Basis:
	var f: Vector3 = fwd - up * fwd.dot(up)
	if f.length_squared() < 1e-6:
		f = up.cross(Vector3.RIGHT)
		if f.length_squared() < 1e-6:
			f = up.cross(Vector3.FORWARD)
	f = f.normalized()
	var z: Vector3 = -f
	var x: Vector3 = up.cross(z).normalized()
	return Basis(x, up, z)
