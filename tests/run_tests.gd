extends SceneTree
## Runs every tests/**/test_*.gd headless and exits 0 when all pass, 1 otherwise.
## Run it through ./run_tests.sh, which imports the project first so class_name
## scripts resolve on a fresh checkout. An optional argument after "--" keeps only
## test files whose name contains it. A test fails when an assert fails or when the
## engine logs more errors during it than the test allows.

const TEST_ROOT := "res://tests"


## Counts engine and script errors so a crash inside a test can't pass silently.
class ErrorCounter extends Logger:
	var count := 0
	var last := ""
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		count += 1
		last = "%s (%s:%d, %s)" % [rationale if rationale else code, file, line, function]
		_lock.unlock()


var _errors := ErrorCounter.new()


func _initialize() -> void:
	OS.add_logger(_errors)
	Engine.max_fps = 60
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var filter := args[0] if not args.is_empty() else ""
	var passed := 0
	var failed := 0
	for path in _find_tests(TEST_ROOT):
		if not filter.is_empty() and not path.get_file().contains(filter):
			continue  # note: contains("") is false in Godot, hence the is_empty check
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL  %s: could not load" % path)
			continue
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			var problems := await _run_one(script, test_name)
			var label := "%s :: %s" % [path.get_file().get_basename(), test_name]
			if problems.is_empty():
				passed += 1
				print("  ok    ", label)
			else:
				failed += 1
				print("  FAIL  ", label)
				for problem in problems:
					print("        ", problem)
	print("\n%d passed, %d failed" % [passed, failed])
	OS.remove_logger(_errors)
	quit(0 if failed == 0 and passed > 0 else 1)


func _run_one(script: GDScript, test_name: String) -> PackedStringArray:
	var instance: Object = script.new()
	if not instance is TestCase:
		return PackedStringArray(["does not extend TestCase"])
	var test := instance as TestCase
	var errors_before := _errors.count  # before add_child, so errors in _ready count
	root.add_child(test)
	await test.call(test_name)
	await test.after_each()
	var problems := test.failures.duplicate()
	var allowed := test.allowed_engine_errors
	test.queue_free()
	await process_frame  # _exit_tree runs, and its errors count too
	var new_errors := _errors.count - errors_before
	if new_errors > allowed:
		problems.append("engine logged %d error(s), last: %s" % [new_errors, _errors.last])
	return problems


func _find_tests(dir: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_find_tests(dir.path_join(sub)))
	found.sort()
	return found
