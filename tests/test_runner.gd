extends TestCase
## The runner itself: errors logged while a test is added or removed count against it.


func test_an_error_in_ready_fails_the_test() -> void:
	assert_eq(_run_fixture("ready"), 1, "the runner exits 1")


func test_an_error_in_exit_tree_fails_the_test() -> void:
	assert_eq(_run_fixture("exit"), 1, "the runner exits 1")


func test_the_fixture_passes_on_its_own() -> void:
	assert_eq(_run_fixture(""), 0, "the runner exits 0")


## Runs test_runner_fixture.gd in a fresh headless Godot and returns its exit code.
func _run_fixture(mode: String) -> int:
	OS.set_environment("SKYWRIGHT_FIXTURE", mode)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/run_tests.gd", "--", "runner_fixture"], output, true)
	OS.unset_environment("SKYWRIGHT_FIXTURE")
	return code
