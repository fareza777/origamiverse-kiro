class_name OVSaveStore
extends RefCounted
## Atomic, versioned JSON persistence in user://. Keeps one backup of the previous good save.


## Writes `data` (with "schema" added) to `path`. Returns OK or an Error code.
static func write_json(path: String, data: Dictionary, schema: int = 1) -> Error:
	var payload: Dictionary = data.duplicate(true)
	payload["schema"] = schema
	var text: String = JSON.stringify(payload, "\t")
	return write_text(path, text)


static func write_text(path: String, text: String) -> Error:
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			return mk
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.file_exists(path):
		var bak: String = path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	return DirAccess.rename_absolute(tmp, path)


## Reads a JSON dictionary, falling back to the backup, then to `defaults`.
static func read_json(path: String, defaults: Dictionary = {}) -> Dictionary:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var text: String = FileAccess.get_file_as_string(candidate)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return defaults.duplicate(true)


static func delete(path: String) -> void:
	for candidate in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


## Lists files in a user:// folder with the given extension, newest first.
static func list_files(dir_path: String, extension: String) -> PackedStringArray:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return PackedStringArray()
	for file in dir.get_files():
		if file.get_extension() == extension:
			var full: String = dir_path.path_join(file)
			out.append([FileAccess.get_modified_time(full), full])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var names: PackedStringArray = PackedStringArray()
	for item in out:
		names.append(item[1])
	return names
