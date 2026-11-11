class_name OVOrbitCamera
extends Node3D
## Spring-smoothed orbit camera used by both apps. Yaw/pitch in degrees, distance in world units.

var camera: Camera3D
var yaw: OVSpring = OVSpring.new(35.0, 3.0, 0.9)
var pitch: OVSpring = OVSpring.new(42.0, 3.0, 0.9)
var distance: OVSpring = OVSpring.new(12.0, 2.5, 0.95)
var focus: Vector3 = Vector3.ZERO
var focus_target: Vector3 = Vector3.ZERO
var home: Dictionary = {"yaw": 35.0, "pitch": 42.0, "distance": 12.0}
var min_distance: float = 2.0
var max_distance: float = 40.0
var min_pitch: float = 8.0
var max_pitch: float = 88.0
var fov: float = 38.0
## Multiplier for drag orbit speed (settings: camera sensitivity).
var sensitivity: float = 1.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.05
	camera.far = 400.0
	add_child(camera)
	camera.current = true


## Frames an AABB for a viewport aspect (width / height). `preset` may override yaw/pitch/distance.
func frame_bounds(box: AABB, preset: Dictionary = {}, viewport_aspect: float = 0.5625, fill: float = 0.8, intro: bool = true) -> void:
	focus_target = box.get_center()
	focus = focus_target
	var radius: float = maxf(box.size.length() * 0.5, 0.1)
	var vfov: float = deg_to_rad(fov)
	var hfov: float = 2.0 * atan(tan(vfov * 0.5) * viewport_aspect)
	var limiting: float = minf(vfov, hfov)
	var fit: float = radius / sin(limiting * 0.5) * fill
	home = {
		"yaw": float(preset.get("yaw", home.yaw)),
		"pitch": float(preset.get("pitch", home.pitch)),
		"distance": float(preset.get("distance", fit)),
	}
	min_distance = home.distance * 0.35
	max_distance = home.distance * 2.0
	if intro:
		yaw.snap(home.yaw + 40.0)
		pitch.snap(home.pitch + 12.0)
		distance.snap(home.distance * 1.35)
	recenter()


func recenter() -> void:
	yaw.target = home.yaw
	pitch.target = home.pitch
	distance.target = home.distance


func orbit(rel: Vector2) -> void:
	yaw.target -= rel.x * 0.25 * sensitivity
	pitch.target = clampf(pitch.target + rel.y * 0.2 * sensitivity, min_pitch, max_pitch)


func zoom(factor: float) -> void:
	distance.target = clampf(distance.target / factor, min_distance, max_distance)


func twist(radians: float) -> void:
	yaw.target -= rad_to_deg(radians)


func _process(dt: float) -> void:
	yaw.step(dt)
	pitch.step(dt)
	distance.step(dt)
	focus = focus.lerp(focus_target, 1.0 - exp(-dt * 4.0))
	var y: float = deg_to_rad(yaw.value)
	var p: float = deg_to_rad(pitch.value)
	var offset: Vector3 = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * distance.value
	camera.global_position = focus + offset
	camera.look_at(focus, Vector3.UP)
