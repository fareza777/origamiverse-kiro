class_name OVFeatureGate
extends RefCounted
## Entitlement checks for future optional purchases. This release unlocks everything.
## A store integration later only needs to replace `_entitlements` loading; callers stay unchanged.

static var _entitlements: Dictionary = {}
static var unlock_all: bool = true


static func is_unlocked(feature_id: String) -> bool:
	return unlock_all or bool(_entitlements.get(feature_id, false))


static func grant(feature_id: String) -> void:
	_entitlements[feature_id] = true
