class_name FSCatalog
extends RefCounted
## Chapters and level order.

const CHAPTERS: Array[Dictionary] = [
	{"id": 1, "title": "Paper Meadow", "subtitle": "Bridges, tucks and hidden cranes", "mood": "dawn", "preset": "meadow"},
	{"id": 2, "title": "Lantern Cliffs", "subtitle": "Walls you can walk on", "mood": "dusk", "preset": "cliffs"},
	{"id": 3, "title": "Ink Hollow", "subtitle": "Wax seals under a Kiroween moon", "mood": "night", "preset": "night"},
]

const LEVEL_IDS: PackedStringArray = [
	"c1_l1", "c1_l2", "c1_l3", "c1_l4", "c1_l5",
	"c2_l1", "c2_l2", "c2_l3", "c2_l4", "c2_l5",
	"c3_l1", "c3_l2", "c3_l3", "c3_l4", "c3_l5",
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
