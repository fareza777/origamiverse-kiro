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
## Point the camera looks at after recenter().
var home_focus: Vector3 = Vector3.ZERO
## Set when the user orbits, zooms or twists; cleared by recenter(). refit() leaves the view alone while it is set.
var user_moved: bool = false
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
	home_focus = focus_target
	var fit: float = _fit_distance(maxf(box.size.length() * 0.5, 0.1), viewport_aspect, fill)
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


## Re-frames a subject that changed shape (a sphere around `center`), keeping the current yaw and pitch.
## The camera glides there unless the user has moved it since the last recenter(); either way recenter() uses it.
func refit(center: Vector3, radius: float, viewport_aspect: float = 0.5625, fill: float = 1.0) -> void:
	home_focus = center
	home.distance = _fit_distance(maxf(radius, 0.1), viewport_aspect, fill)
	min_distance = home.distance * 0.35
	max_distance = home.distance * 2.0
	if not user_moved:
		focus_target = home_focus
		distance.target = home.distance


## Distance at which a sphere of `radius` fits the narrower field of view; fill < 1 moves closer.
func _fit_distance(radius: float, viewport_aspect: float, fill: float) -> float:
	var vfov: float = deg_to_rad(fov)
	var hfov: float = 2.0 * atan(tan(vfov * 0.5) * viewport_aspect)
	var limiting: float = minf(vfov, hfov)
	return radius / sin(limiting * 0.5) * fill


func recenter() -> void:
	user_moved = false
	focus_target = home_focus
	yaw.target = home.yaw
	pitch.target = home.pitch
	distance.target = home.distance


func orbit(rel: Vector2) -> void:
	user_moved = true
	yaw.target -= rel.x * 0.25 * sensitivity
	pitch.target = clampf(pitch.target + rel.y * 0.2 * sensitivity, min_pitch, max_pitch)


func zoom(factor: float) -> void:
	user_moved = true
	distance.target = clampf(distance.target / factor, min_distance, max_distance)


func twist(radians: float) -> void:
	user_moved = true
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
