extends TestCase
## Settings load, save and clean their values (spec §4.10).

const SettingsScript := preload("res://src/core/settings.gd")
const TEMP_PATH := "user://test_settings.cfg"

var _made: Array[Node] = []


func after_each() -> void:
	for node in _made:
		node.free()
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


## A Settings instance outside the tree, so it neither loads nor applies the real file.
func fresh() -> SettingsScript:
	var settings := SettingsScript.new()
	_made.append(settings)
	return settings


func write_temp(text: String) -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_missing_file_keeps_defaults() -> void:
	var settings := fresh()
	settings.load_from("user://no_such_settings.cfg")
	assert_eq(settings.player_name, "Captain")
	assert_eq(settings.master_volume, 0.8)
	assert_eq(settings.vsync, true)
	assert_eq(settings.last_address, "127.0.0.1")


func test_saved_settings_load_back_unchanged() -> void:
	var saved := fresh()
	saved.player_name = "Ann"
	saved.fullscreen = true
	saved.vsync = false
	saved.master_volume = 0.35
	saved.mouse_sensitivity = 2.25
	saved.last_address = "10.0.0.7:4000"
	assert_eq(saved.save_to(TEMP_PATH), OK)
	var loaded := fresh()
	loaded.load_from(TEMP_PATH)
	assert_eq(loaded.player_name, "Ann")
	assert_eq(loaded.fullscreen, true)
	assert_eq(loaded.vsync, false)
	assert_eq(loaded.master_volume, 0.35)
	assert_eq(loaded.mouse_sensitivity, 2.25)
	assert_eq(loaded.last_address, "10.0.0.7:4000")


func test_out_of_range_numbers_are_clamped() -> void:
	write_temp("[audio]\nmaster_volume=5.0\n[controls]\nmouse_sensitivity=-2\n")
	var settings := fresh()
	settings.load_from(TEMP_PATH)
	assert_eq(settings.master_volume, 1.0)
	assert_eq(settings.mouse_sensitivity, 0.1)


func test_wrong_types_fall_back_to_defaults() -> void:
	write_temp("[display]\nfullscreen=\"yes\"\n[audio]\nmaster_volume=\"loud\"\n[player]\nname=42\nlast_address=\"   \"\n")
	var settings := fresh()
	settings.load_from(TEMP_PATH)
	assert_eq(settings.fullscreen, false)
	assert_eq(settings.master_volume, 0.8)
	assert_eq(settings.player_name, "42")
	assert_eq(settings.last_address, "127.0.0.1")


func test_unreadable_file_keeps_defaults() -> void:
	allowed_engine_errors = 1  # ConfigFile reports the parse error.
	write_temp("[[[ this is not a config file")
	var settings := fresh()
	settings.load_from(TEMP_PATH)
	assert_eq(settings.player_name, "Captain")
	assert_eq(settings.master_volume, 0.8)


func test_clean_name_is_fast_on_huge_input() -> void:
	# A modified client can send any name; cleaning it must not stall the host.
	var huge := "x".repeat(200000)
	var started := Time.get_ticks_usec()
	var cleaned := SettingsScript.clean_name(huge)
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	assert_eq(cleaned.length(), 24)
	assert_true(elapsed_ms < 50.0, "took %.0f ms" % elapsed_ms)


func test_names_are_cleaned() -> void:
	assert_eq(SettingsScript.clean_name("  Ann  "), "Ann")
	assert_eq(SettingsScript.clean_name("   "), "Captain")
	assert_eq(SettingsScript.clean_name("Ann\nBob\t"), "Ann Bob")
	assert_eq(SettingsScript.clean_name("x".repeat(40)).length(), 24)
