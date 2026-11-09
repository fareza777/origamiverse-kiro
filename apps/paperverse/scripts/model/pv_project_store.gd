class_name PVProjectStore
extends RefCounted
## Project files in user://projects/<id>.fold with a <id>.png thumbnail.

const DIR: String = "user://projects"


static func path_for(id: String) -> String:
	return DIR.path_join(id + ".fold")


static func thumb_for(id: String) -> String:
	return DIR.path_join(id + ".png")


static func save(p: PVProject, folded: PackedVector3Array = PackedVector3Array()) -> Error:
	p.modified = int(Time.get_unix_time_from_system())
	return OVSaveStore.write_text(path_for(p.id), p.to_fold_text(folded))


static func load_project(id: String) -> Dictionary:
	var path: String = path_for(id)
	if not FileAccess.file_exists(path):
		return OVCore.fail(PackedStringArray(["Project not found."]))
	var r: Dictionary = PVProject.from_fold_text(FileAccess.get_file_as_string(path))
	if r.ok:
		(r.value as PVProject).id = id
		(r.value as PVProject).modified = FileAccess.get_modified_time(path)
	return r


## [{"id", "name", "modified"}] newest first.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in OVSaveStore.list_files(DIR, "fold"):
		var id: String = path.get_file().get_basename()
		var name: String = id
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			name = str(parsed.get("paperverse:name", parsed.get("file_title", id)))
		out.append({"id": id, "name": name, "modified": FileAccess.get_modified_time(path)})
	return out


static func delete(id: String) -> void:
	OVSaveStore.delete(path_for(id))
	if FileAccess.file_exists(thumb_for(id)):
		DirAccess.remove_absolute(thumb_for(id))


static func duplicate_project(id: String) -> String:
	var r: Dictionary = load_project(id)
	if not r.ok:
		return ""
	var p: PVProject = r.value
	var old_thumb: String = thumb_for(id)
	p.id = PVProject.new_id()
	p.name = p.name + " copy"
	save(p)
	if FileAccess.file_exists(old_thumb):
		DirAccess.copy_absolute(old_thumb, thumb_for(p.id))
	return p.id


static func save_thumbnail(id: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var copy: Image = img.duplicate()
	var s: int = mini(copy.get_width(), copy.get_height())
	copy = copy.get_region(Rect2i((copy.get_width() - s) / 2, (copy.get_height() - s) / 2, s, s))
	copy.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	copy.save_png(thumb_for(id))
