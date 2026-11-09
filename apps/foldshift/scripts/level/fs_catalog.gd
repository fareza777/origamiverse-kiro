class_name FSCatalog
extends RefCounted
## Chapters and level order.

const CHAPTERS: Array[Dictionary] = [
	{"id": 1, "title": "Paper Meadow", "subtitle": "Bridges and secrets", "mood": "dawn", "preset": "meadow"},
]

const LEVEL_IDS: PackedStringArray = [
	"c1_l1",
]


static func levels_in_chapter(chapter: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id in LEVEL_IDS:
		if id.begins_with("c%d_" % chapter):
			out.append(id)
	return out


static func chapter(chapter_id: int) -> Dictionary:
	for c in CHAPTERS:
		if c.id == chapter_id:
			return c
	return CHAPTERS[0]


static func next_level(id: String) -> String:
	var i: int = LEVEL_IDS.find(id)
	return LEVEL_IDS[i + 1] if i >= 0 and i + 1 < LEVEL_IDS.size() else ""


static func level_path(id: String) -> String:
	return "res://levels/%s.json" % id
