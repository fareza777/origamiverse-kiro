extends Node
## FoldShift global state (autoload "Game"): save data, settings, achievements, audio, theme and scene flow.

signal achievement_unlocked(id: String)
signal settings_changed

const SAVE_PATH: String = "user://foldshift_save.json"
const SCHEMA: int = 1

const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "first_fold", "title": "First Crease", "desc": "Fold the world for the first time."},
	{"id": "chapter_1", "title": "Bridge Builder", "desc": "Clear Paper Meadow."},
	{"id": "wall_walker", "title": "Wall Walker", "desc": "Walk Kami up a folded wall."},
	{"id": "chapter_2", "title": "Cliff Climber", "desc": "Clear Lantern Cliffs."},
	{"id": "seal_breaker", "title": "Seal Breaker", "desc": "Break a wax seal."},
	{"id": "chapter_3", "title": "Night Folder", "desc": "Clear Ink Hollow."},
	{"id": "secret_keeper", "title": "Secret Keeper", "desc": "Find a crane hidden on the back of a flap."},
	{"id": "flock", "title": "A Small Flock", "desc": "Collect 10 paper cranes."},
	{"id": "thousand", "title": "Senbazuru", "desc": "Collect every paper crane."},
	{"id": "on_par", "title": "On Par", "desc": "Finish a level in the minimum number of folds."},
	{"id": "perfectionist", "title": "Perfect Fold", "desc": "Earn 3 stars on every level."},
	{"id": "no_regrets", "title": "No Regrets", "desc": "Clear an Ink Hollow level without using undo."},
	{"id": "paper_master", "title": "Paper Master", "desc": "Make 100 folds in total."},
]

var data: Dictionary = {}
var audio: OVPaperAudio
var theme: Theme
var ui_scale: float = 1.0
var palette: Dictionary = {
	"bg": Color("f7f2e8"), "card": Color("fffaf0"), "ink": Color("2b2640"), "muted": Color("8a8399"),
	"accent": Color("e8604c"), "accent_ink": Color("ffffff"), "gold": Color("f2b440"),
}
var _levels_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)
	audio = OVPaperAudio.new()
	add_child(audio)
	load_save()
	apply_settings()
	ui_scale = OVThemeFactory.ui_scale_for(get_viewport().get_visible_rect().size)
	theme = OVThemeFactory.build(palette, ui_scale)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		var main: Node = get_tree().current_scene
		if main and main.has_method("capture_resume"):
			main.capture_resume()
		save()
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var main2: Node = get_tree().current_scene
		if main2 and main2.has_method("go_back"):
			main2.go_back()


# ------------------------------------------------------------ persistence


func default_data() -> Dictionary:
	return {
		"levels": {},
		"achievements": {},
		"settings": {"music": 0.7, "sfx": 0.9, "haptics": true, "reduce_motion": false},
		"stats": {"folds": 0, "steps": 0, "cranes": 0},
		"resume": {},
		"seen_tutorial": false,
	}


func load_save() -> void:
	var d: Dictionary = OVSaveStore.read_json(SAVE_PATH, default_data())
	var base: Dictionary = default_data()
	for k in base.keys():
		if not d.has(k) or typeof(d[k]) != typeof(base[k]):
			d[k] = base[k]
	for k in base.settings.keys():
		if not d.settings.has(k):
			d.settings[k] = base.settings[k]
	for k in base.stats.keys():
		if not d.stats.has(k):
			d.stats[k] = base.stats[k]
	data = d


func save() -> void:
	OVSaveStore.write_json(SAVE_PATH, data, SCHEMA)


func reset_progress() -> void:
	var settings: Dictionary = data.settings.duplicate()
	data = default_data()
	data.settings = settings
	save()


func apply_settings() -> void:
	OVPaperAudio.set_bus_volume("Music", float(data.settings.music))
	OVPaperAudio.set_bus_volume("SFX", float(data.settings.sfx))
	audio.haptics_enabled = bool(data.settings.haptics)
	settings_changed.emit()


func set_setting(key: String, value: Variant) -> void:
	data.settings[key] = value
	apply_settings()
	save()


# ------------------------------------------------------------ levels and progress


func level_data(id: String) -> FSLevelData:
	if not _levels_cache.has(id):
		var r: Dictionary = FSLevelData.load_file(FSCatalog.level_path(id))
		if not r.ok:
			push_error("Level %s failed: %s" % [id, str(r.errors)])
			return null
		_levels_cache[id] = r.value
	return _levels_cache[id]


func level_record(id: String) -> Dictionary:
	return data.levels.get(id, {})


func is_level_done(id: String) -> bool:
	return bool(level_record(id).get("done", false))


func is_level_unlocked(id: String) -> bool:
	var i: int = FSCatalog.LEVEL_IDS.find(id)
	if i <= 0:
		return true
	var L: FSLevelData = level_data(id)
	if L and L.index == 1:
		return is_chapter_unlocked(L.chapter)
	return is_level_done(FSCatalog.LEVEL_IDS[i - 1])


func is_chapter_unlocked(chapter: int) -> bool:
	if chapter <= 1:
		return true
	for id in FSCatalog.levels_in_chapter(chapter - 1):
		if not is_level_done(id):
			return false
	return true


func chapter_stats(chapter: int) -> Dictionary:
	var stars: int = 0
	var cranes: int = 0
	var crane_total: int = 0
	var done: int = 0
	var ids: PackedStringArray = FSCatalog.levels_in_chapter(chapter)
	for id in ids:
		var rec: Dictionary = level_record(id)
		stars += int(rec.get("stars", 0))
		done += 1 if rec.get("done", false) else 0
		var L: FSLevelData = level_data(id)
		if L:
			crane_total += L.cranes.size()
		for c in rec.get("cranes", []):
			cranes += 1 if c else 0
	return {"stars": stars, "max_stars": ids.size() * 3, "cranes": cranes, "crane_total": crane_total, "done": done, "count": ids.size()}


static func stars_for(folds: int, par: int) -> int:
	if folds <= par:
		return 3
	if folds <= par + 2:
		return 2
	return 1


## Records a cleared level. Returns {"stars", "best", "new_best"}.
func record_clear(id: String, folds: int, cranes: PackedByteArray, used_undo: bool) -> Dictionary:
	var L: FSLevelData = level_data(id)
	var rec: Dictionary = level_record(id).duplicate(true)
	var stars: int = stars_for(folds, L.par)
	var prev_best: int = int(rec.get("best", 9999))
	rec["done"] = true
	rec["best"] = mini(prev_best, folds)
	rec["stars"] = maxi(int(rec.get("stars", 0)), stars)
	var merged: Array = []
	var old: Array = rec.get("cranes", [])
	for i in cranes.size():
		merged.append(cranes[i] == 1 or (i < old.size() and bool(old[i])))
	rec["cranes"] = merged
	data.levels[id] = rec
	data.resume = {}
	if folds <= L.par:
		unlock("on_par")
	if L.chapter == 3 and not used_undo:
		unlock("no_regrets")
	for ch in FSCatalog.CHAPTERS:
		var st: Dictionary = chapter_stats(ch.id)
		if st.done == st.count and st.count > 0:
			unlock("chapter_%d" % ch.id)
	var total_cranes: int = 0
	var all_cranes: int = 0
	var all_three: bool = true
	for lid in FSCatalog.LEVEL_IDS:
		var r2: Dictionary = level_record(lid)
		for c in r2.get("cranes", []):
			total_cranes += 1 if c else 0
		var L2: FSLevelData = level_data(lid)
		if L2:
			all_cranes += L2.cranes.size()
		if int(r2.get("stars", 0)) < 3:
			all_three = false
	if total_cranes >= 10:
		unlock("flock")
	if total_cranes >= all_cranes and all_cranes > 0:
		unlock("thousand")
	if all_three:
		unlock("perfectionist")
	save()
	return {"stars": stars, "best": rec.best, "new_best": folds < prev_best}


func add_stat(key: String, amount: int = 1) -> void:
	data.stats[key] = int(data.stats.get(key, 0)) + amount
	if key == "folds":
		if int(data.stats.folds) >= 1:
			unlock("first_fold")
		if int(data.stats.folds) >= 100:
			unlock("paper_master")


func unlock(id: String) -> void:
	if data.achievements.has(id):
		return
	data.achievements[id] = int(Time.get_unix_time_from_system())
	save()
	achievement_unlocked.emit(id)


func achievement(id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a.id == id:
			return a
	return {}


func total_stars() -> int:
	var s: int = 0
	for id in FSCatalog.LEVEL_IDS:
		s += int(level_record(id).get("stars", 0))
	return s
