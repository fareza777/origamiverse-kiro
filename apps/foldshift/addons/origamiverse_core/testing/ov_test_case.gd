class_name OVTestCase
extends RefCounted
## Base class for headless tests. Methods named test_* are run by OVTestRunner.

var failures: PackedStringArray = PackedStringArray()
var checks: int = 0
var tree: SceneTree
var _current: String = ""


func check(cond: bool, message: String) -> bool:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [_current, message])
	return cond


func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func check_near(actual: float, expected: float, tol: float, message: String) -> bool:
	return check(absf(actual - expected) <= tol, "%s (expected %.5f +- %.5f, got %.5f)" % [message, expected, tol, actual])


func check_vec_near(actual: Vector3, expected: Vector3, tol: float, message: String) -> bool:
	return check(actual.distance_to(expected) <= tol, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])
