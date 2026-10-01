extends TestCase
## Save files (spec §4.10): three JSON files a save, written whole or not at all,
## checked as untrusted input, three autosaves kept a slot, and a broken save falls
## back to the newest one that reads.

var dir := ""


func after_each() -> void:
	if not dir.is_empty():
		remove_tree(dir)
	SaveGame.dir = "user://saves"


## Points saves at a fresh folder for this test.
func fresh() -> void:
	dir = "user://test_saves_%d" % randi()
	SaveGame.dir = dir


static func remove_tree(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func exploration_text() -> String:
	var seen := Exploration.new()
	seen.reveal(Vector3(0, 900, 7000))
	return seen.to_text()


## A save as a game would make it: Ann's damaged ship with crates and two hands,
## Bo's helmless one, their accounts, two wrecks stripped and Ann's map.
func good_save(saved := 1790000000.0) -> Dictionary:
	var grid := StarterShip.build()
	grid.blocks[Vector3i(0, 0, 1)]["hp"] = 30
	grid.blocks.erase(Vector3i(-2, 1, 0))
	grid.cargo = {Vector3i(-1, 0, -2): {"good": "grain", "owner": "Ann"}, Vector3i(1, 0, 4): {"good": "mail", "owner": "Ann"}}
	var ann_ship := {"captain": "Ann", "at": [100.5, 880.25, 7000.0, 0.0, 0.258819, 0.0, 0.965926], "trim": 1.02, "anchored": false,
			"spares": 12, "blocks": grid.to_blocks(), "blueprint": StarterShip.build().to_blocks(), "paint": {"deck": "c0392b"},
			"cargo": grid.cargo_list(), "hands": [["Fenn", "gunner", -2, 1, 1, -1.0, 1.45, 1.0], ["Marta", "repairer", 0, 0, 0, 0.0, 3.45, 5.0]]}
	var wreck := StarterShip.build()
	wreck.blocks.erase(wreck.cells_of("helm")[0])
	var bo_ship := {"captain": "Bo", "at": [-300.0, 700.0, 6500.0, 0.0, 0.0, 0.0, 1.0], "trim": 1.0, "anchored": true, "spares": 0,
			"blocks": wreck.to_blocks(), "blueprint": StarterShip.build().to_blocks(), "paint": {}, "cargo": [], "hands": []}
	var ann := Economy.new_account()
	ann["money"] = 2340
	ann["unlocks"] = ["alloy"]
	ann["contracts"] = [{"id": 4, "kind": "scout", "title": "Scout Grey Arch", "reward": 180, "target": 0, "count": 1, "done": 0}]
	return {"world": {"seed": 7, "time": 1234.5, "salvaged": [2, 5], "exploration": exploration_text(), "host": "Ann", "saved": saved},
			"ships": [ann_ship, bo_ship], "players": {"Ann": ann, "Bo": Economy.new_account()}}


func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_a_save_round_trips() -> void:
	fresh()
	var save := good_save()
	var path := SaveGame.slot_path("1")
	assert_eq(SaveGame.write(path, save), OK)
	var read := SaveGame.read(path)
	assert_false(read.has("problem"), read.get("problem", ""))
	assert_eq(read.get("save"), save, "the same save, ints as ints")
	var ship := SaveGame.read_ship(save["ships"][0])
	assert_false(ship.has("problem"), ship.get("problem", ""))
	var grid: ShipGrid = ship["grid"]
	assert_eq(grid.to_blocks(), save["ships"][0]["blocks"], "her blocks and hit points")
	assert_eq(grid.cargo_list(), save["ships"][0]["cargo"], "her crates")
	assert_eq(grid.paint_names(), {"deck": "c0392b"})
	assert_eq((ship["blueprint"] as ShipGrid).to_blocks(), StarterShip.build().to_blocks(), "her blueprint")
	assert_eq(ship["hands"].map(func(hand: Dictionary) -> Array: return [hand["name"], hand["role"], hand["post"]]),
			[["Fenn", "gunner", Vector3i(-2, 1, 1)], ["Marta", "repairer", Vector3i.ZERO]])
	var at: Transform3D = ship["at"]
	assert_true(at.origin.is_equal_approx(Vector3(100.5, 880.25, 7000.0)), str(at.origin))
	assert_true(at.basis.get_rotation_quaternion().is_equal_approx(Quaternion(0.0, 0.258819, 0.0, 0.965926).normalized()))
	assert_false(SaveGame.read_ship(save["ships"][1]).has("problem"), "a helmless ship of yours keeps")


func test_saves_are_checked() -> void:
	fresh()
	var path := SaveGame.slot_path("1")
	var cases := [
		["missing", "This save is missing ships.json."],
		["damaged", "world.json is damaged."],
		["version", "This save is version 2; this game reads version 1."],
		["seed", "world.json"],
		["block", "ships.json: ship 1"],
		["crate", "ships.json: ship 1"],
		["money", "player.json"],
		["huge", "world.json is too big."],
	]
	for each: Array in cases:
		var save := good_save()
		match each[0]:
			"seed":
				save["world"]["seed"] = -1
			"block":
				save["ships"][0]["blocks"].append([100, 0, 0, "deck", 0, 80])
			"crate":
				save["ships"][0]["cargo"].append([0, 0, 0, "grain", "Ann"])
			"money":
				save["players"]["Bo"]["money"] = -5
			"huge":
				save["world"]["host"] = "x".repeat(SaveGame.MAX_FILE_SIZE + 1)
		assert_eq(SaveGame.write(path, save), OK)
		match each[0]:
			"missing":
				DirAccess.remove_absolute(path.path_join("ships.json"))
			"damaged":
				write_text(path.path_join("world.json"), "{")
			"version":
				write_text(path.path_join("world.json"), JSON.stringify({"version": 2, "world": save["world"]}))
		var problem: String = SaveGame.read(path).get("problem", "")
		assert_true(problem.begins_with(each[1]), "%s: %s" % [each[0], problem])


func test_a_broken_save_falls_back_to_the_previous_autosave() -> void:
	fresh()
	SaveGame.write(SaveGame.slot_path("1"), good_save(200.0))
	SaveGame.write(SaveGame.autosave_paths("1")[0], good_save(100.0))
	var loaded := SaveGame.load_slot("1")
	assert_eq(loaded["save"]["world"]["saved"], 200.0, "the newest")
	assert_eq(loaded.get("note", ""), "")
	write_text(SaveGame.slot_path("1").path_join("ships.json"), "{")
	loaded = SaveGame.load_slot("1")
	assert_eq(loaded.get("save", {}).get("world", {}).get("saved"), 100.0, "the autosave")
	assert_eq(loaded.get("note", ""), "The latest save in slot 1 couldn't be read (ships.json is damaged), so the one from %s was loaded."
			% SaveGame.date_text(100.0))
	write_text(SaveGame.autosave_paths("1")[0].path_join("ships.json"), "{")
	assert_eq(SaveGame.load_slot("1"), {"problem": "Slot 1 couldn't be read: ships.json is damaged."})


func test_autosaves_keep_the_last_three() -> void:
	fresh()
	for saved in [1.0, 2.0, 3.0, 4.0]:
		assert_eq(SaveGame.write(SaveGame.autosave_path("1"), good_save(saved)), OK)
	var kept := SaveGame.autosave_paths("1").map(func(path: String) -> float: return SaveGame.read(path)["save"]["world"]["saved"])
	assert_eq(kept, [4.0, 2.0, 3.0], "the oldest made way")
	assert_eq(SaveGame.load_slot("1")["save"]["world"]["saved"], 4.0)


func test_an_empty_slot_is_empty() -> void:
	fresh()
	assert_eq(SaveGame.load_slot("1"), {})
	assert_eq(SaveGame.summary("1"), "Slot 1   empty")
	SaveGame.write(SaveGame.slot_path("1"), good_save())
	assert_eq(SaveGame.summary("1"), "Slot 1   Ann · 2340 crowns · seed 7 · " + SaveGame.date_text(1790000000.0))
	write_text(SaveGame.slot_path("1").path_join("world.json"), "{")
	assert_eq(SaveGame.summary("1"), "Slot 1   can't be read")


func test_renaming_the_host() -> void:
	var save := good_save()
	SaveGame.rename(save, "Ann", "Anna")
	assert_true(save["players"].has("Anna") and not save["players"].has("Ann"), str(save["players"].keys()))
	assert_eq(save["players"]["Anna"]["money"], 2340, "her purse")
	assert_eq(save["ships"][0]["captain"], "Anna", "her ship")
	assert_eq(save["ships"][0]["cargo"].map(func(crate: Array) -> String: return crate[4]), ["Anna", "Anna"], "her crates")
	assert_eq(save["ships"][1]["captain"], "Bo", "Bo's are Bo's")
	assert_eq(save["world"]["host"], "Anna")


func test_exploration_round_trips() -> void:
	var seen := Exploration.new()
	seen.reveal(Vector3(0, 900, 7000))
	seen.reveal(Vector3(3000, 900, -2000))
	var copy := Exploration.new()
	assert_true(copy.read_text(seen.to_text()))
	assert_eq(copy.image.get_data(), seen.image.get_data(), "the same cells seen")
	assert_eq(copy.seen_fraction(), seen.seen_fraction())
	assert_false(copy.read_text("junk"))
	assert_eq(copy.seen_fraction(), seen.seen_fraction(), "junk changes nothing")
