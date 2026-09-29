extends TestCase
## A test that passes, unless SKYWRIGHT_FIXTURE asks it to log an error from _ready
## or _exit_tree. test_runner.gd uses it to check the runner counts those errors.


func _ready() -> void:
	if OS.get_environment("SKYWRIGHT_FIXTURE") == "ready":
		push_error("an error in _ready")


func _exit_tree() -> void:
	if OS.get_environment("SKYWRIGHT_FIXTURE") == "exit":
		push_error("an error in _exit_tree")


func test_nothing() -> void:
	pass
