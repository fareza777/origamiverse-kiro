class_name OVSpring
extends RefCounted
## Critically damped spring for snappy, physical-feeling angle and camera motion.

var value: float = 0.0
var velocity: float = 0.0
var target: float = 0.0
var frequency: float = 6.0   ## Hz-like stiffness; higher = faster
var damping_ratio: float = 0.75


func _init(start: float = 0.0, freq: float = 6.0, zeta: float = 0.75) -> void:
	value = start
	target = start
	frequency = freq
	damping_ratio = zeta


func step(dt: float) -> float:
	# Semi-implicit integration with substeps for stability at low frame rates.
	var steps: int = maxi(1, ceili(dt * 240.0))
	var h: float = dt / float(steps)
	var w: float = TAU * frequency
	for _i in steps:
		var acc: float = w * w * (target - value) - 2.0 * damping_ratio * w * velocity
		velocity += acc * h
		value += velocity * h
	return value


func is_settled(tol: float = 0.05) -> bool:
	return absf(target - value) < tol and absf(velocity) < tol * 4.0


func snap(v: float) -> void:
	value = v
	target = v
	velocity = 0.0
