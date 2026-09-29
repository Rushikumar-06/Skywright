class_name TestCase
extends Node
## Base class for tests. The runner makes a fresh instance for each test_* method,
## adds it to the scene tree, awaits the method, awaits after_each(), then frees it.

## Assertion failures recorded while the current test runs.
var failures: PackedStringArray = []
## Engine errors this test may log on purpose (for example when it loads a broken
## file). More errors than this fail the test.
var allowed_engine_errors := 0


## Override to clean up after each test: close sockets, delete temp files.
func after_each() -> void:
	pass


func assert_true(value: bool, message := "") -> void:
	if not value:
		_fail("expected true", message)


func assert_false(value: bool, message := "") -> void:
	if value:
		_fail("expected false", message)


## Passes when both values have the same type and compare equal.
func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("expected %s, got %s" % [var_to_str(expected), var_to_str(actual)], message)


func assert_near(actual: float, expected: float, tolerance: float, message := "") -> void:
	if not absf(actual - expected) <= tolerance:
		_fail("expected %s ± %s, got %s" % [expected, tolerance, actual], message)


## Waits a frame at a time until condition returns true or timeout seconds pass,
## and returns whether it came true. Use it as: await wait_until(...)
func wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


func _fail(what: String, message: String) -> void:
	failures.append(what if message.is_empty() else "%s: %s" % [message, what])
