extends TestCase
## The settings panel saves each change as it's made, so leaving it any way (Back,
## Esc, closing the window) keeps the change.

const TEMP_PATH := "user://test_panel_settings.cfg"

var _real_path := ""
var _real_volume := 0.0


func after_each() -> void:
	Settings.path = _real_path
	Settings.master_volume = _real_volume
	Settings.apply()
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_changes_are_saved_straight_away() -> void:
	_real_path = Settings.path
	_real_volume = Settings.master_volume
	Settings.path = TEMP_PATH
	var panel := SettingsPanel.new()
	add_child(panel)
	var volume := panel.find_children("*", "HSlider", true, false)[0] as HSlider
	volume.value = 0.25
	var saved := ConfigFile.new()
	assert_eq(saved.load(TEMP_PATH), OK, "a settings file was written")
	assert_eq(saved.get_value("audio", "master_volume", -1.0), 0.25)
