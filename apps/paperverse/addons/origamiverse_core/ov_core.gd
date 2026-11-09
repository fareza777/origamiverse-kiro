class_name OVCore
extends RefCounted
## Constants and helpers shared by every OrigamiVerse Core module.

const VERSION: String = "1.0.0"
const CREATOR: String = "OrigamiVerse Core " + VERSION + " (F7 Developer)"

## Edge assignments from the FOLD 1.2 spec.
enum Assign { BOUNDARY, MOUNTAIN, VALLEY, FLAT, UNASSIGNED, CUT, JOIN }

const ASSIGN_LETTERS: PackedStringArray = ["B", "M", "V", "F", "U", "C", "J"]

## Default paper thickness in world units (one unit = one grid tile in FoldShift).
const PAPER_THICKNESS: float = 0.012

const EPS: float = 1e-5


static func assign_from_letter(letter: String) -> int:
	var i: int = ASSIGN_LETTERS.find(letter.to_upper())
	return i if i >= 0 else Assign.UNASSIGNED


static func assign_to_letter(a: int) -> String:
	return ASSIGN_LETTERS[a] if a >= 0 and a < ASSIGN_LETTERS.size() else "U"


## Default FOLD fold angle (degrees) for an assignment when edges_foldAngle is absent.
static func default_fold_angle(a: int) -> float:
	match a:
		Assign.VALLEY: return 180.0
		Assign.MOUNTAIN: return -180.0
	return 0.0


## True for assignments that act as hinges between faces.
static func is_crease(a: int) -> bool:
	return a == Assign.MOUNTAIN or a == Assign.VALLEY


## FOLD (x, y, z) -> Godot (x, z, -y). A proper rotation, so CCW faces keep their front facing +Y.
static func fold_to_godot(x: float, y: float, z: float = 0.0) -> Vector3:
	return Vector3(x, z, -y)


static func godot_to_fold(p: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([p.x, -p.z, p.y])


## Sheet (2D) coordinates of a Godot-space point lying on the flat sheet.
static func sheet_uv(p: Vector3) -> Vector2:
	return Vector2(p.x, -p.z)


## Result dictionary used by fallible operations.
static func ok(value: Variant = null) -> Dictionary:
	return {"ok": true, "errors": PackedStringArray(), "value": value}


static func fail(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors, "value": null}
