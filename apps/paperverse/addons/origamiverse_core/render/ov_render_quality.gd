class_name OVRenderQuality
extends Node
## Graphics quality for one 3D viewport. Fixed tiers set the 3D render scale, MSAA and shadows. AUTO runs
## dynamic resolution: it measures GPU time per frame and scales the 3D buffer so the frame fits the budget.
## Low-end phones are fill-rate bound at native resolution (Adreno 610: ~68 ms GPU at 1080x2400), so the
## render scale is the knob that matters most. 2D UI keeps native resolution.

signal changed

enum Mode { AUTO, HIGH, BALANCED, BATTERY }

const MODE_NAMES: PackedStringArray = ["Auto", "High", "Balanced", "Battery"]

## GPU budget per frame for AUTO, in milliseconds (60 FPS leaves headroom for CPU and compositor).
@export var target_gpu_ms: float = 13.0
@export var min_scale: float = 0.5
@export var max_scale: float = 1.0
## Seconds per measurement window.
@export var window: float = 0.5

var mode: int = -1
var scale: float = 1.0
var shadows: bool = true
var msaa: int = Viewport.MSAA_2X
## Average GPU (or frame) time of the last window, in ms.
var last_gpu_ms: float = 0.0
var gpu_timing: bool = false

var _viewport: Viewport
var _lights: Array[Light3D] = []
var _acc_ms: float = 0.0
var _acc_frames: int = 0
var _acc_time: float = 0.0
var _low_windows: int = 0
var _warmup: int = 2


## Takes control of `vp`. Call again after replacing the viewport.
func attach(vp: Viewport) -> void:
	_viewport = vp
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	_reset_measure()
	_apply()


## Lights whose shadows follow the quality tier.
func register_light(light: Light3D) -> void:
	if light == null:
		return
	if not _lights.has(light):
		_lights.append(light)
	light.shadow_enabled = shadows
	light.tree_exiting.connect(func() -> void: _lights.erase(light), CONNECT_ONE_SHOT)


func set_mode(m: int) -> void:
	mode = clampi(m, 0, Mode.size() - 1)
	match mode:
		Mode.HIGH:
			scale = 1.0; msaa = Viewport.MSAA_2X; shadows = true
		Mode.BALANCED:
			scale = 0.75; msaa = Viewport.MSAA_2X; shadows = true
		Mode.BATTERY:
			scale = 0.55; msaa = Viewport.MSAA_DISABLED; shadows = false
		Mode.AUTO:
			# Start low so the first seconds are smooth, then grow while the GPU has headroom.
			scale = 0.7; msaa = Viewport.MSAA_2X; shadows = true
	_low_windows = 0
	_warmup = 2
	_reset_measure()
	_apply()


func _apply() -> void:
	if _viewport == null:
		return
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_viewport.scaling_3d_scale = scale
	_viewport.msaa_3d = msaa
	for l in _lights:
		if is_instance_valid(l):
			l.shadow_enabled = shadows
	changed.emit()


func _reset_measure() -> void:
	_acc_ms = 0.0
	_acc_frames = 0
	_acc_time = 0.0


func _process(dt: float) -> void:
	if _viewport == null or not is_instance_valid(_viewport):
		return
	var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(_viewport.get_viewport_rid())
	gpu_timing = gpu > 0.0
	# Compatibility renderer reports no GPU time; fall back to the frame time (an upper bound).
	_acc_ms += gpu if gpu_timing else dt * 1000.0
	_acc_frames += 1
	_acc_time += dt
	if _acc_time < window:
		return
	last_gpu_ms = _acc_ms / float(maxi(_acc_frames, 1))
	_reset_measure()
	if _warmup > 0:
		_warmup -= 1
		return
	if mode == Mode.AUTO:
		_adapt(last_gpu_ms)


## Fill cost grows with pixel count (scale squared), so the scale moves by the square root of the ratio.
func _adapt(ms: float) -> void:
	var budget: float = target_gpu_ms if gpu_timing else 1000.0 / 58.0
	var next: float = scale
	if ms > budget * 1.08:
		next = scale * clampf(sqrt(budget / ms), 0.75, 0.97)
		_low_windows = 0
	elif ms < budget * 0.72:
		_low_windows += 1
		# Grow slowly and only after sustained headroom, so the scale does not oscillate.
		if _low_windows >= 3:
			next = scale + 0.05
			_low_windows = 0
	else:
		_low_windows = 0
	next = clampf(snappedf(next, 0.05), min_scale, max_scale)
	if not is_equal_approx(next, scale):
		scale = next
		_apply()


func summary() -> String:
	var name: String = MODE_NAMES[mode] if mode >= 0 else "Default"
	return "%s · 3D %d%% · %s %.1f ms" % [name, roundi(scale * 100.0), "GPU" if gpu_timing else "frame", last_gpu_ms]
