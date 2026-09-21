extends SceneTree

## Headless simulation test runner.
##
## Discovers `res://tests/**/test_*.gd`, instantiates each one, runs every
## `test_*` method and reports results.  No rendering context is created, so
## the domain suite runs anywhere the engine runs.
##
##   godot --headless --script res://tests/runner.gd -- --filter=rail

const TEST_ROOT := "res://tests"
const PREFIX := "test_"
const METHOD_PREFIX := "test_"

var _filter: String = ""
var _files: PackedStringArray = PackedStringArray()
var _total_cases: int = 0
var _failed_cases: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_filter = _read_filter(OS.get_cmdline_user_args())
	var start_ms := Time.get_ticks_msec()
	_collect(TEST_ROOT)
	_files.sort()
	if _files.is_empty():
		print("runner: no test files found under " + TEST_ROOT)
		quit(1)
		return
	for file in _files:
		_run_file(file)
	var elapsed := Time.get_ticks_msec() - start_ms
	print("")
	for line in _failures:
		print(line)
	print("")
	print("────────────────────────────────────────────────────────────")
	print("ran %d cases in %d files over %d ms" % [_total_cases, _files.size(), elapsed])
	if _failed_cases == 0:
		print("PASS — all %d cases green" % _total_cases)
		quit(0)
	else:
		print("FAIL — %d of %d cases failed" % [_failed_cases, _total_cases])
		quit(1)


func _read_filter(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--filter="):
			return arg.trim_prefix("--filter=")
	return ""


func _collect(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if name != "." and name != "..":
				_collect(full)
		elif name.begins_with(PREFIX) and name.ends_with(".gd"):
			_files.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _run_file(path: String) -> void:
	if _filter != "" and not path.contains(_filter):
		return
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		_failed_cases += 1
		_failures.append("LOAD ERROR %s — script did not compile" % path)
		return
	var instance: Object = script.new()
	if instance == null:
		_failed_cases += 1
		_failures.append("LOAD ERROR %s — could not instantiate" % path)
		return
	var cases: PackedStringArray = []
	for method in instance.get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with(METHOD_PREFIX) and method_name != METHOD_PREFIX:
			cases.append(method_name)
	cases.sort()
	if cases.is_empty():
		_failed_cases += 1
		_failures.append("EMPTY SUITE %s — declares no test_* methods" % path)
		return
	var short := path.trim_prefix("res://")
	var passed := 0
	for case_name in cases:
		_total_cases += 1
		if instance.has_method("set_current_case"):
			instance.call("set_current_case", case_name)
		var before_ms := Time.get_ticks_msec()
		# A suite may build a fresh fixture per case; a case that reaches no
		# assertion at all aborted mid-flight and must never read as green.
		if instance.has_method("setup"):
			instance.call("setup")
		instance.call(case_name)
		if instance.has_method("teardown"):
			instance.call("teardown")
		var recorded: PackedStringArray = instance.get("failures")
		var assertions := 0
		if instance.has_method("assertion_count"):
			assertions = int(instance.call("assertion_count"))
		if assertions == 0 and recorded.is_empty():
			recorded = PackedStringArray(["case ran no assertion — it aborted before its first check"])
		if recorded.is_empty():
			passed += 1
		else:
			_failed_cases += 1
			var header := "FAIL %s :: %s" % [short, case_name]
			_failures.append(header)
			for line in recorded:
				_failures.append("  · " + line.replace("\n", "\n    "))
			_failures.append("  · took %d ms" % (Time.get_ticks_msec() - before_ms))
	if instance is RefCounted:
		instance = null
	print("%-62s %3d/%-3d %s" % [short, passed, cases.size(), "ok" if passed == cases.size() else "FAILED"])
