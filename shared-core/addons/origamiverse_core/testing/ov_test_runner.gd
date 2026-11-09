extends SceneTree
## Minimal headless test runner shared by the core and both apps.
## Usage: godot --headless --path <project> -s res://tests/run_tests.gd [-- --filter=name]
## Exit code = number of failed checks (0 = green).

var test_dir: String = "res://tests"


func _initialize() -> void:
	var filter: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var files: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(test_dir)
	if dir == null:
		printerr("No test directory at ", test_dir)
		quit(1)
		return
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var total_fail: int = 0
	var total_checks: int = 0
	var total_tests: int = 0
	var started: int = Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load(test_dir.path_join(f))
		if script == null:
			printerr("FAILED TO LOAD ", f)
			total_fail += 1
			continue
		var inst: Object = script.new()
		if not (inst is OVTestCase):
			continue
		var tc: OVTestCase = inst
		tc.tree = self
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (f + "." + name).contains(filter):
				continue
			tc._current = f.get_basename() + "." + name
			var before: int = tc.failures.size()
			var t0: int = Time.get_ticks_msec()
			tc.call(name)
			total_tests += 1
			var ms: int = Time.get_ticks_msec() - t0
			var status: String = "ok" if tc.failures.size() == before else "FAIL"
			print("  [%s] %s (%d ms)" % [status, tc._current, ms])
		for msg in tc.failures:
			printerr("    - ", msg)
		total_fail += tc.failures.size()
		total_checks += tc.checks
	print("\n%d tests, %d checks, %d failures in %d ms" % [total_tests, total_checks, total_fail, Time.get_ticks_msec() - started])
	quit(mini(total_fail, 125))
