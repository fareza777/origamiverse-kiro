class_name OVPerfOverlay
extends CanvasLayer
## Small on-screen performance readout (FPS, GPU time, 3D scale, draw calls). Also logs to stdout
## (logcat on Android) every few seconds so device runs can be measured without a debugger.

var quality: OVRenderQuality
var log_interval: float = 3.0

var _label: Label
var _t: float = 0.0
var _log_t: float = 0.0


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15))
	_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _process(dt: float) -> void:
	_t += dt
	_log_t += dt
	if _t < 0.25:
		return
	_t = 0.0
	var text: String = "%d FPS · CPU %.1f ms · %d draws" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	if quality:
		text += "\n" + quality.summary()
	_label.text = text
	if _log_t >= log_interval:
		_log_t = 0.0
		print("[perf] ", text.replace("\n", " | "))
