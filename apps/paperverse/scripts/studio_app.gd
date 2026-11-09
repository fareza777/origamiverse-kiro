extends Node
## PaperVerse global services (autoload "Studio"): theme, audio, settings and file dialogs.

const SETTINGS_PATH: String = "user://paperverse_settings.json"

var audio: OVPaperAudio
var theme: Theme
var ui_scale: float = 1.0
var settings: Dictionary = {"music": 0.35, "sfx": 0.8, "haptics": true, "grid": 8, "seen_intro": false}
var palette: Dictionary = {
	"bg": Color("f3f1ec"), "card": Color("fffdf8"), "ink": Color("23233a"), "muted": Color("85839a"),
	"accent": Color("4a5fd6"), "accent_ink": Color("ffffff"),
}


func _ready() -> void:
	audio = OVPaperAudio.new()
	add_child(audio)
	var loaded: Dictionary = OVSaveStore.read_json(SETTINGS_PATH, settings)
	for k in settings.keys():
		if loaded.has(k):
			settings[k] = loaded[k]
	apply_settings()
	ui_scale = OVThemeFactory.ui_scale_for(get_viewport().get_visible_rect().size)
	theme = OVThemeFactory.build(palette, ui_scale)
	OVUIKit.scale = ui_scale
	OVUIKit.on_click = func() -> void:
		audio.play("ui")
		audio.haptic(8, 0.25)
	audio.set_ambience("studio")


func apply_settings() -> void:
	OVPaperAudio.set_bus_volume("Music", float(settings.music))
	OVPaperAudio.set_bus_volume("SFX", float(settings.sfx))
	audio.haptics_enabled = bool(settings.haptics)


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	OVSaveStore.write_json(SETTINGS_PATH, settings)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		var main: Node = get_tree().current_scene
		if main and main.has_method("autosave"):
			main.autosave()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var main2: Node = get_tree().current_scene
		if main2 and main2.has_method("go_back"):
			main2.go_back()


# ------------------------------------------------------------ files


func has_native_dialogs() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)


## Asks where to save and writes `bytes`. `done` receives (ok: bool, where: String).
func save_bytes(file_name: String, filter: String, bytes: PackedByteArray, done: Callable) -> void:
	if has_native_dialogs():
		DisplayServer.file_dialog_show("Export", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), file_name, false,
			DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, PackedStringArray([filter]),
			func(status: bool, paths: PackedStringArray, _idx: int) -> void:
				if not status or paths.is_empty():
					done.call(false, "")
					return
				var f: FileAccess = FileAccess.open(paths[0], FileAccess.WRITE)
				if f == null:
					_fallback_save(file_name, bytes, done)
					return
				f.store_buffer(bytes)
				f.close()
				done.call(true, paths[0].get_file() if not paths[0].begins_with("content:") else file_name))
	else:
		_fallback_save(file_name, bytes, done)


func _fallback_save(file_name: String, bytes: PackedByteArray, done: Callable) -> void:
	DirAccess.make_dir_recursive_absolute("user://exports")
	var path: String = "user://exports".path_join(file_name)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		done.call(false, "")
		return
	f.store_buffer(bytes)
	f.close()
	done.call(true, ProjectSettings.globalize_path(path))


## Asks for a FOLD file to open. `done` receives (text: String, name: String); empty text = cancelled.
func open_text(filters: PackedStringArray, done: Callable) -> void:
	if not has_native_dialogs():
		done.call("", "")
		return
	DisplayServer.file_dialog_show("Import FOLD", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters,
		func(status: bool, paths: PackedStringArray, _idx: int) -> void:
			if not status or paths.is_empty():
				done.call("", "")
				return
			var f: FileAccess = FileAccess.open(paths[0], FileAccess.READ)
			if f == null:
				done.call("", "")
				return
			var text: String = f.get_as_text()
			f.close()
			done.call(text, paths[0].get_file().get_basename()))
