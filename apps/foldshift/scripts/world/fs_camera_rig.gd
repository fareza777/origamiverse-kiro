class_name FSCameraRig
extends Node3D
## Orbit camera with spring smoothing. Yaw/pitch in degrees, distance in world units.

var camera: Camera3D
var yaw: OVSpring = OVSpring.new(35.0, 3.0, 0.9)
var pitch: OVSpring = OVSpring.new(52.0, 3.0, 0.9)
var distance: OVSpring = OVSpring.new(12.0, 2.5, 0.95)
var focus: Vector3 = Vector3.ZERO
var focus_target: Vector3 = Vector3.ZERO
var home: Dictionary = {"yaw": 35.0, "pitch": 52.0, "distance": 12.0}
var min_distance: float = 5.0
var max_distance: float = 30.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)
	camera.current = true


func frame_bounds(box: AABB, preset: Dictionary = {}, viewport_aspect: float = 0.5625) -> void:
	focus_target = box.get_center()
	focus = focus_target
	var radius: float = box.size.length() * 0.5
	# Fit for the narrow (horizontal) FOV on portrait screens.
	var hfov: float = 2.0 * atan(tan(deg_to_rad(camera.fov) * 0.5) * viewport_aspect)
	var fit: float = radius / sin(hfov * 0.5) * 0.8
	home = {
		"yaw": float(preset.get("yaw", 35.0)),
		"pitch": float(preset.get("pitch", 42.0)),
		"distance": clampf(float(preset.get("distance", fit)), 5.0, 40.0),
	}
	min_distance = home.distance * 0.45
	max_distance = home.distance * 1.8
	yaw.snap(home.yaw + 40.0)
	pitch.snap(home.pitch + 12.0)
	distance.snap(home.distance * 1.35)
	recenter()


func recenter() -> void:
	yaw.target = home.yaw
	pitch.target = home.pitch
	distance.target = home.distance
	focus_target = focus_target


func orbit(rel: Vector2) -> void:
	yaw.target -= rel.x * 0.25
	pitch.target = clampf(pitch.target + rel.y * 0.2, 12.0, 85.0)


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
