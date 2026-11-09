class_name PVProject
extends RefCounted
## A PaperVerse project. Persisted as a FOLD 1.2 file with "paperverse:*" extension keys.

var id: String = ""
var name: String = "Untitled"
var pattern: OVCreasePattern = OVCreasePattern.new()
var timeline: OVTimeline = OVTimeline.new()
var material: Dictionary = OVPaperPresets.by_id("kami_coral").duplicate()
var fold_percent: float = 0.0
var pin_face: int = -1
var rigid: bool = false
var show_assignment: bool = true
var template_id: String = ""
var modified: int = 0


static func new_id() -> String:
	return "p%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]


static func from_template(t: Dictionary) -> PVProject:
	var p: PVProject = PVProject.new()
	p.id = new_id()
	p.name = str(t.title)
	p.template_id = str(t.id)
	p.pattern = PVTemplates.make_pattern(t)
	p.fold_percent = float(t.get("fold_percent", 0.9))
	p.timeline.set_key("fold", 0.0, 0.0, OVTimeline.Ease.SMOOTH)
	p.timeline.set_key("fold", 2.5, p.fold_percent, OVTimeline.Ease.SMOOTH)
	p.timeline.set_key("spin", 0.0, 0.0, OVTimeline.Ease.LINEAR)
	p.timeline.set_key("spin", 4.0, 90.0, OVTimeline.Ease.LINEAR)
	p.timeline.duration = 4.0
	return p


## Builds the triangulated FOLD document for the current pattern.
func build_document() -> OVFoldDocument:
	var doc: OVFoldDocument = pattern.to_document()
	doc.meta["file_title"] = name
	doc.meta["file_author"] = "PaperVerse user"
	doc.meta["file_classes"] = ["singleModel"]
	return doc


func to_fold_text(folded: PackedVector3Array = PackedVector3Array()) -> String:
	var doc: OVFoldDocument = build_document()
	doc.extra["paperverse:name"] = name
	doc.extra["paperverse:pattern"] = pattern.to_dict()
	doc.extra["paperverse:timeline"] = timeline.to_dict()
	doc.extra["paperverse:material"] = OVPaperPresets.to_dict(material)
	doc.extra["paperverse:view"] = {"fold_percent": fold_percent, "pin_face": pin_face, "rigid": rigid,
		"show_assignment": show_assignment, "template": template_id}
	return doc.to_json(folded)


## Loads a PaperVerse project or any plain FOLD file. Returns OVCore.ok(project) / fail().
static func from_fold_text(text: String, fallback_name: String = "Imported") -> Dictionary:
	var r: Dictionary = OVFoldDocument.from_json(text)
	if not r.ok:
		return r
	var doc: OVFoldDocument = r.value
	var p: PVProject = PVProject.new()
	p.id = new_id()
	if doc.extra.has("paperverse:pattern") and typeof(doc.extra["paperverse:pattern"]) == TYPE_DICTIONARY:
		p.pattern = OVCreasePattern.from_dict(doc.extra["paperverse:pattern"])
	else:
		if doc.is_3d:
			return OVCore.fail(PackedStringArray(["This FOLD file only contains a folded 3D shape, not a flat crease pattern."]))
		p.pattern = OVCreasePattern.from_document(doc)
	p.name = str(doc.extra.get("paperverse:name", doc.meta.get("file_title", fallback_name)))
	if doc.extra.has("paperverse:timeline"):
		p.timeline = OVTimeline.from_dict(doc.extra["paperverse:timeline"])
	else:
		p.timeline.set_key("fold", 0.0, 0.0)
		p.timeline.set_key("fold", 2.5, 0.9)
	if doc.extra.has("paperverse:material"):
		p.material = OVPaperPresets.from_dict(doc.extra["paperverse:material"])
	var view: Dictionary = doc.extra.get("paperverse:view", {})
	p.fold_percent = float(view.get("fold_percent", 0.5))
	p.pin_face = int(view.get("pin_face", -1))
	p.rigid = bool(view.get("rigid", false))
	p.show_assignment = bool(view.get("show_assignment", true))
	p.template_id = str(view.get("template", ""))
	return OVCore.ok(p)
