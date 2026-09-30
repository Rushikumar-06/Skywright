extends TestCase
## Command-line options after "--" (used for two-copy testing and servers).


func test_reads_host_join_name_and_port() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--host", "--name=Ann", "--port=4000"])), {"host": true, "name": "Ann", "port": 4000})
	assert_eq(LaunchOptions.parse(PackedStringArray(["--join=10.0.0.2:4000"])), {"join": "10.0.0.2:4000"})


func test_reads_solo() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--solo", "--name=Ann"])), {"solo": true, "name": "Ann"})


func test_ignores_unknown_and_malformed_options() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--fly", "--port=abc", "--port=70000", "host"])), {})


func test_reads_server() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--server", "--port=4000", "--name=Skyport"])), {"server": true, "port": 4000, "name": "Skyport"})
