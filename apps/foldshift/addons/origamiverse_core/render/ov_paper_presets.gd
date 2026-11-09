class_name OVPaperPresets
extends RefCounted
## Paper material presets shared by both apps.

const PRESETS: Array[Dictionary] = [
	{"id": "kami_coral", "name": "Kami Coral", "front": Color("f6f1e6"), "back": Color("e0594b"),
		"grain": 0.08, "fiber": 0.05, "rough": 0.82, "spec": 0.25, "metal": 0.0, "sheen": 0.12},
	{"id": "washi_indigo", "name": "Washi Indigo", "front": Color("efe8d8"), "back": Color("2f3f8f"),
		"grain": 0.14, "fiber": 0.12, "rough": 0.9, "spec": 0.15, "metal": 0.0, "sheen": 0.18},
	{"id": "kraft", "name": "Kraft", "front": Color("c49a6c"), "back": Color("b58a5c"),
		"grain": 0.16, "fiber": 0.10, "rough": 0.95, "spec": 0.1, "metal": 0.0, "sheen": 0.06},
	{"id": "mint_duo", "name": "Mint Duo", "front": Color("f3f7f2"), "back": Color("3fb59a"),
		"grain": 0.07, "fiber": 0.04, "rough": 0.8, "spec": 0.3, "metal": 0.0, "sheen": 0.12},
	{"id": "gold_foil", "name": "Gold Foil", "front": Color("e8c56a"), "back": Color("f4efe3"),
		"grain": 0.03, "fiber": 0.0, "rough": 0.35, "spec": 0.6, "metal": 0.75, "sheen": 0.05},
	{"id": "midnight", "name": "Midnight", "front": Color("2a2d43"), "back": Color("f2b440"),
		"grain": 0.1, "fiber": 0.06, "rough": 0.85, "spec": 0.2, "metal": 0.0, "sheen": 0.2},
	{"id": "sakura", "name": "Sakura", "front": Color("fbe6ec"), "back": Color("e4799b"),
		"grain": 0.09, "fiber": 0.07, "rough": 0.85, "spec": 0.22, "metal": 0.0, "sheen": 0.15},
	{"id": "pumpkin", "name": "Pumpkin Night", "front": Color("f28c28"), "back": Color("231a2e"),
		"grain": 0.1, "fiber": 0.05, "rough": 0.85, "spec": 0.2, "metal": 0.0, "sheen": 0.14},
]


static func by_id(id: String) -> Dictionary:
	for p in PRESETS:
		if p.id == id:
			return p
	return PRESETS[0]


static func apply(m: ShaderMaterial, p: Dictionary) -> void:
	m.set_shader_parameter("front_color", p.get("front", Color.WHITE))
	m.set_shader_parameter("back_color", p.get("back", Color.WHITE))
	m.set_shader_parameter("grain_strength", p.get("grain", 0.08))
	m.set_shader_parameter("fiber_strength", p.get("fiber", 0.05))
	m.set_shader_parameter("paper_roughness", p.get("rough", 0.82))
	m.set_shader_parameter("paper_specular", p.get("spec", 0.25))
	m.set_shader_parameter("metallic_amount", p.get("metal", 0.0))
	m.set_shader_parameter("sheen", p.get("sheen", 0.12))


## Serializable form for saves (colors as HTML strings).
static func to_dict(p: Dictionary) -> Dictionary:
	var d: Dictionary = p.duplicate()
	d.front = (p.front as Color).to_html(false)
	d.back = (p.back as Color).to_html(false)
	return d


static func from_dict(d: Dictionary) -> Dictionary:
	var p: Dictionary = by_id(str(d.get("id", ""))).duplicate()
	for k in d.keys():
		p[k] = d[k]
	p.front = Color(str(d.get("front", "ffffff")))
	p.back = Color(str(d.get("back", "ffffff")))
	return p
