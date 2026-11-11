class_name FSStyles
extends RefCounted
## Per-chapter look: paper presets, sky, light, fog and props.

const STYLES: Dictionary = {
	"meadow": {
		"base": {"id": "meadow_base", "front": Color("efe4cf"), "back": Color("d9c39c"), "grain": 0.09, "fiber": 0.06, "rough": 0.85, "spec": 0.22, "metal": 0.0, "sheen": 0.12},
		"flap": {"id": "meadow_flap", "front": Color("f4b8a6"), "back": Color("e8604c"), "grain": 0.08, "fiber": 0.05, "rough": 0.82, "spec": 0.25, "metal": 0.0, "sheen": 0.14},
		"sky_top": Color("8ec5e8"), "sky_horizon": Color("fde7c8"), "ground": Color("b9d7a8"),
		"sun": Color("fff1d6"), "sun_energy": 1.05, "ambient": 0.38, "fog": Color("fbe6cd"), "fog_density": 0.0035,
		"sea_a": Color("4a9fc2"), "sea_b": Color("8ccbdc"),
		"props": ["tree_round", "tree_pine", "flowers", "rock"], "far": ["mountain", "cloud"], "mood": "dawn",
	},
	"cliffs": {
		"base": {"id": "cliff_base", "front": Color("f3e6d4"), "back": Color("cfa98a"), "grain": 0.12, "fiber": 0.08, "rough": 0.9, "spec": 0.18, "metal": 0.0, "sheen": 0.12},
		"flap": {"id": "cliff_flap", "front": Color("a9c8ec"), "back": Color("3f7fbf"), "grain": 0.1, "fiber": 0.06, "rough": 0.85, "spec": 0.22, "metal": 0.0, "sheen": 0.14},
		"sky_top": Color("6b78c2"), "sky_horizon": Color("f6b38a"), "ground": Color("9a7aa0"),
		"sun": Color("ffcf9e"), "sun_energy": 1.15, "ambient": 0.5, "fog": Color("f2b89a"), "fog_density": 0.008,
		"sea_a": Color("8e86c9"), "sea_b": Color("f3c3b0"),
		"props": ["tree_pine", "rock", "lantern", "tree_blossom"], "far": ["mountain", "cloud"], "mood": "dusk",
	},
	"night": {
		"base": {"id": "night_base", "front": Color("e9e4f2"), "back": Color("3a335a"), "grain": 0.1, "fiber": 0.06, "rough": 0.85, "spec": 0.25, "metal": 0.0, "sheen": 0.22},
		"flap": {"id": "night_flap", "front": Color("f9c98f"), "back": Color("f28c28"), "grain": 0.1, "fiber": 0.05, "rough": 0.82, "spec": 0.25, "metal": 0.0, "sheen": 0.2},
		"sky_top": Color("141633"), "sky_horizon": Color("4b3f78"), "ground": Color("2a2244"),
		"sun": Color("b9c6ff"), "sun_energy": 0.75, "ambient": 0.6, "fog": Color("3b2f63"), "fog_density": 0.012,
		"sea_a": Color("2b2a5c"), "sea_b": Color("6a5aa8"),
		"props": ["pumpkin", "ghost", "tree_pine", "lantern"], "far": ["mountain", "cloud"], "mood": "night",
	},
}

## Seal colors (wax) by unlock order, readable on every chapter palette.
const SEAL_COLORS: Array[Color] = [Color("d6453d"), Color("3f7fd6"), Color("3faa6a"), Color("9a4fd0")]


static func get_style(id: String) -> Dictionary:
	return STYLES.get(id, STYLES["meadow"])
