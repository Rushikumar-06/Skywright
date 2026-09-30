extends TestCase
## Blueprint files: plain JSON that players share, so every byte of them is
## untrusted (spec §4.10).

var dir := "user://test_blueprints_%d" % randi()


func after_each() -> void:
	for file in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func text_of(blocks: String, extra := "") -> String:
	return '{"format": "skywright-blueprint", "version": 1, "name": "T", "blocks": %s%s}' % [blocks, extra]


func test_a_blueprint_round_trips() -> void:
	var grid := StarterShip.build()
	var propeller := grid.cells_of("propeller")[0]
	grid.set_block(propeller, "propeller", 4)
	grid.paint = {"balloon": Color.RED}
	assert_eq(Blueprint.save(grid, "Stormchaser", dir), OK)
	var loaded := Blueprint.load_file(Blueprint.path_for("Stormchaser", dir))
	assert_eq(loaded.get("problem"), null)
	assert_eq(loaded["name"], "Stormchaser")
	assert_eq(loaded["grid"].blocks, grid.blocks)
	assert_eq(loaded["grid"].paint, {"balloon": Color.RED})


func test_blueprints_are_plain_json() -> void:
	var text := Blueprint.to_text(StarterShip.build(), "Plain")
	var data: Variant = JSON.parse_string(text)
	assert_true(data is Dictionary)
	assert_eq(data.keys().size(), 5)
	for key in ["format", "version", "name", "blocks", "paint"]:
		assert_true(data.has(key), key)
	assert_true(text.contains("[-2,0,-5,"), "whole numbers are written as ints")
	assert_false(text.contains(".0"), "no floats")
	for block: Array in data["blocks"]:
		assert_eq(block.size(), 5)


func test_bad_blueprints_are_refused_with_the_first_problem() -> void:
	var not_bp := "This isn't a Skywright blueprint."
	var helm := "[0, 0, 0, \"helm\", 0]"
	var cases := [
		["not json", not_bp],
		["[]", not_bp],
		['{"format": "other"}', not_bp],
		['{"format": "skywright-blueprint", "version": 2, "blocks": []}', "This blueprint is version 2; this game reads version 1."],
		['{"format": "skywright-blueprint", "version": 1}', "The ship has no blocks."],
		[text_of('"x"'), "The ship has no blocks."],
		[text_of("[[1e400, 0, 0, \"helm\", 0]]"), "Block 1 has a number that isn't a whole number."],
		[text_of("[[0.5, 0, 0, \"helm\", 0]]"), "Block 1 has a number that isn't a whole number."],
		[text_of("[[0, 0, 0, \"gold\", 0]]"), "Block 1 is an unknown type, \"gold\"."],
		[text_of("[[0, 0, 0, \"helm\", 24]]"), "Block 1 has rotation 24; rotations go from 0 to 23."],
		[text_of("[%s, [0, 0, 0, \"frame\", 0]]" % helm), "Block 2 is in the same place as another block."],
		[text_of("[[0, 0, 0, \"frame\", 0]]"), "Every ship needs a helm."],
		[text_of("[%s]" % helm, ', "paint": {"balloon": "zzz"}'), "The paint colours aren't valid."],
	]
	for item: Array in cases:
		assert_eq(Blueprint.parse(item[0]).get("problem"), item[1], item[0])
	assert_eq(Blueprint.parse(text_of("[%s]" % helm))["name"], "T")
	assert_eq(Blueprint.parse(text_of("[%s]" % helm).replace('"T"', "5"))["name"], "Untitled ship")


func test_a_huge_file_is_refused_before_it_is_read() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("huge.skyship.json"), FileAccess.WRITE)
	file.store_buffer("x".repeat(1536 * 1024).to_utf8_buffer())
	file.close()
	assert_eq(Blueprint.load_file(dir.path_join("huge.skyship.json")).get("problem"), '"huge.skyship.json" is too big to be a blueprint.')
	assert_eq(Blueprint.load_file(dir.path_join("nope.skyship.json")).get("problem"), 'Couldn\'t open "nope.skyship.json".')


func test_file_names_come_from_the_ship_name() -> void:
	assert_true(Blueprint.path_for("Storm/chaser: v2?", dir).ends_with("/Storm_chaser_ v2_.skyship.json"))
	var sneaky := Blueprint.path_for("../../etc", dir)
	assert_eq(sneaky.get_base_dir(), dir)
	assert_false(sneaky.get_file().begins_with("."))
	assert_true(Blueprint.path_for("", dir).ends_with("/Untitled ship.skyship.json"))
	assert_true(Blueprint.path_for("x".repeat(40), dir).ends_with("/" + "x".repeat(32) + ".skyship.json"))
	assert_eq(Blueprint.path_for("...", dir), dir + "/ship.skyship.json")


func test_the_list_shows_saved_blueprints() -> void:
	assert_eq(Blueprint.list(dir), PackedStringArray())
	var grid := StarterShip.build()
	Blueprint.save(grid, "B ship", dir)
	Blueprint.save(grid, "A ship", dir)
	FileAccess.open(dir.path_join("notes.txt"), FileAccess.WRITE).close()
	assert_eq(Blueprint.list(dir), PackedStringArray([Blueprint.path_for("A ship", dir), Blueprint.path_for("B ship", dir)]))
	DirAccess.remove_absolute(dir.path_join("notes.txt"))
