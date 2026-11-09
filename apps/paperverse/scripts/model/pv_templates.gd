class_name PVTemplates
extends RefCounted
## Built-in crease pattern templates: procedural ones plus classic patterns converted from the
## MIT-licensed Origami Simulator examples (see tools/svg_to_templates.py).

const A := OVCore.Assign
const DIR: String = "res://templates"

const PROCEDURAL: Array[Dictionary] = [
	{"id": "blank", "title": "Blank Sheet", "description": "Start from an empty square.", "fold_percent": 0.0},
	{"id": "half_fold", "title": "Half Fold", "description": "One valley fold. The first fold anyone learns.", "fold_percent": 0.9},
	{"id": "accordion", "title": "Accordion Fan", "description": "Alternating mountains and valleys.", "fold_percent": 0.85},
	{"id": "kite", "title": "Kite Base", "description": "Two edges folded to the diagonal: the start of fish, swan and many birds.", "fold_percent": 0.95},
	{"id": "miura", "title": "Miura-ori", "description": "Rigid-foldable map fold used for space solar arrays.", "fold_percent": 0.8},
	{"id": "box_tray", "title": "Tray (Cuts)", "description": "Cut corners and four walls: a rigid fold you can also try in Rigid mode.", "fold_percent": 0.5},
]


static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in PROCEDURAL:
		out.append(t)
	var idx_path: String = DIR.path_join("index.json")
	if FileAccess.file_exists(idx_path):
		var ids: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx_path))
		if typeof(ids) == TYPE_ARRAY:
			for id in ids:
				var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join("%s.json" % id)))
				if typeof(d) == TYPE_DICTIONARY:
					out.append({"id": d.id, "title": d.title, "description": d.description,
						"fold_percent": float(d.get("fold_percent", 0.9)), "source": d.get("source", ""), "pattern": d.pattern})
	return out


static func by_id(id: String) -> Dictionary:
	for t in all():
		if t.id == id:
			return t
	return PROCEDURAL[0]


static func make_pattern(t: Dictionary) -> OVCreasePattern:
	if t.has("pattern"):
		return OVCreasePattern.from_dict(t.pattern)
	var cp: OVCreasePattern = OVCreasePattern.new()
	match str(t.id):
		"half_fold":
			cp.add_segment(Vector2(0.5, 0), Vector2(0.5, 1), A.VALLEY)
		"accordion":
			for i in range(1, 8):
				var x: float = i / 8.0
				cp.add_segment(Vector2(x, 0), Vector2(x, 1), A.VALLEY if i % 2 == 1 else A.MOUNTAIN)
		"kite":
			cp.add_segment(Vector2(0, 0), Vector2(1, 1), A.MOUNTAIN)
			var t225: float = tan(deg_to_rad(22.5))
			cp.add_segment(Vector2(0, 0), Vector2(1, t225), A.VALLEY)
			cp.add_segment(Vector2(0, 0), Vector2(t225, 1), A.VALLEY)
		"miura":
			_miura(cp, 5, 4, 0.1)
		"box_tray":
			var q: float = 0.25
			for x in [q, 1.0 - q]:
				cp.add_segment(Vector2(x, q), Vector2(x, 1.0 - q), A.VALLEY, 90.0)
			for y in [q, 1.0 - q]:
				cp.add_segment(Vector2(q, y), Vector2(1.0 - q, y), A.VALLEY, 90.0)
			# Cut between each corner square and the side wall so the walls can rise; the corners ride along
			# with the top and bottom walls as tabs.
			for corner in [Vector2(q, q), Vector2(1.0 - q, q), Vector2(1.0 - q, 1.0 - q), Vector2(q, 1.0 - q)]:
				var ex: Vector2 = Vector2(0.0 if corner.x < 0.5 else 1.0, corner.y)
				cp.add_segment(corner, ex, A.CUT)
	return cp


## Miura-ori: `cols` x `rows` parallelograms, zigzag offset `shift` (fraction of the sheet).
static func _miura(cp: OVCreasePattern, cols: int, rows: int, shift: float) -> void:
	var w: float = 1.0 / cols
	var h: float = 1.0 / rows
	# Zigzag lines running across x (horizontal pleats), alternating mountain/valley per row.
	for j in range(1, rows):
		var y: float = j * h
		for i in cols:
			var x0: float = i * w
			var x1: float = (i + 1) * w
			var y0: float = y + (shift if i % 2 == 0 else -shift) * 0.5
			var y1: float = y + (-shift if i % 2 == 0 else shift) * 0.5
			cp.add_segment(Vector2(x0, y0), Vector2(x1, y1), A.MOUNTAIN if j % 2 == 0 else A.VALLEY)
	# Vertical lines: segments alternate along the line and between neighboring lines, so every degree-4 vertex
	# is a valid Miura vertex (3 creases of one kind, 1 of the other, with the odd one on the straight line).
	for i in range(1, cols):
		var x: float = i * w
		for j in rows:
			var ya: float = 0.0 if j == 0 else j * h + (shift if i % 2 == 0 else -shift) * 0.5
			var yb: float = 1.0 if j == rows - 1 else (j + 1) * h + (shift if i % 2 == 0 else -shift) * 0.5
			cp.add_segment(Vector2(x, ya), Vector2(x, yb), A.VALLEY if (j + i - 1) % 2 == 0 else A.MOUNTAIN)
