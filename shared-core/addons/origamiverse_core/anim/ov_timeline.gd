class_name OVTimeline
extends RefCounted
## Keyframed float channels with per-key easing. Keys are kept sorted by time.

signal changed

enum Ease { LINEAR, SMOOTH, EASE_IN, EASE_OUT, HOLD, BACK }
const EASE_NAMES: PackedStringArray = ["Linear", "Smooth", "Ease in", "Ease out", "Hold", "Overshoot"]

## channel name -> Array of {"t": float, "v": float, "ease": int}
var channels: Dictionary = {}
var duration: float = 4.0


func set_key(channel: String, t: float, value: float, ease: int = Ease.SMOOTH) -> void:
	var keys: Array = channels.get(channel, [])
	for k in keys:
		if absf(k.t - t) < 1e-4:
			k.v = value
			k.ease = ease
			channels[channel] = keys
			changed.emit()
			return
	keys.append({"t": t, "v": value, "ease": ease})
	keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	channels[channel] = keys
	duration = maxf(duration, t)
	changed.emit()


func remove_key(channel: String, t: float) -> bool:
	var keys: Array = channels.get(channel, [])
	for i in keys.size():
		if absf(keys[i].t - t) < 1e-4:
			keys.remove_at(i)
			changed.emit()
			return true
	return false


func keys(channel: String) -> Array:
	return channels.get(channel, [])


func has_keys(channel: String) -> bool:
	return not keys(channel).is_empty()


## Interpolated value at time t; `fallback` when the channel has no keys.
func sample(channel: String, t: float, fallback: float = 0.0) -> float:
	var ks: Array = channels.get(channel, [])
	if ks.is_empty():
		return fallback
	if t <= ks[0].t:
		return ks[0].v
	if t >= ks[ks.size() - 1].t:
		return ks[ks.size() - 1].v
	for i in range(1, ks.size()):
		var b: Dictionary = ks[i]
		if t <= b.t:
			var a: Dictionary = ks[i - 1]
			var span: float = maxf(b.t - a.t, 1e-6)
			var x: float = (t - a.t) / span
			return lerpf(a.v, b.v, apply_ease(a.ease, x))
	return ks[ks.size() - 1].v


static func apply_ease(ease: int, x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	match ease:
		Ease.LINEAR: return x
		Ease.SMOOTH: return x * x * (3.0 - 2.0 * x)
		Ease.EASE_IN: return x * x * x
		Ease.EASE_OUT: return 1.0 - pow(1.0 - x, 3.0)
		Ease.HOLD: return 0.0 if x < 1.0 else 1.0
		Ease.BACK:
			var c1: float = 1.70158
			var c3: float = c1 + 1.0
			return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
	return x


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for name in channels.keys():
		var arr: Array = []
		for k in channels[name]:
			arr.append([k.t, k.v, k.ease])
		out[name] = arr
	return {"duration": duration, "channels": out}


static func from_dict(d: Dictionary) -> OVTimeline:
	var tl: OVTimeline = OVTimeline.new()
	tl.duration = float(d.get("duration", 4.0))
	var ch: Dictionary = d.get("channels", {})
	for name in ch.keys():
		var arr: Array = []
		for k in ch[name]:
			arr.append({"t": float(k[0]), "v": float(k[1]), "ease": int(k[2])})
		arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
		tl.channels[str(name)] = arr
	return tl
