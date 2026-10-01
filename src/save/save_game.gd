class_name SaveGame
## Saved games (spec §4.10): a save is three files of plain JSON in a folder, world.json,
## ships.json and player.json, each {"version": 1, "<part>": …}. A slot holds a save
## made by hand and up to AUTOSAVES autosaves. Everything read back is checked as
## untrusted input, and loading a slot takes the newest save in it that reads, saying
## so when that isn't the newest.
##
## A save is {"world": {seed, time, salvaged, exploration, host, saved}, "ships":
## [records (see WorldSync.record)], "players": {name: account}}.

static var dir := "user://saves"  ## Where slots live. Tests point it elsewhere.

const VERSION := 1
const FILES := {"world": "world.json", "ships": "ships.json", "players": "player.json"}
const SLOTS := ["1", "2", "3"]
const AUTOSAVES := 3
const MAX_FILE_SIZE := 16777216  ## Bytes. A file bigger than this isn't read.
const MAX_SEED := 2147483647
const MAX_SHIPS := 256


static func slot_path(slot: String) -> String:
	return dir.path_join(slot)


static func autosave_paths(slot: String) -> Array[String]:
	var paths: Array[String] = []
	for i in AUTOSAVES:
		paths.append(slot_path(slot).path_join("auto-%d" % (i + 1)))
	return paths


## Where the next autosave goes: the first missing autosave, else the oldest.
static func autosave_path(slot: String) -> String:
	var paths := autosave_paths(slot)
	for path in paths:
		if not FileAccess.file_exists(path.path_join(FILES["world"])):
			return path
	var oldest := paths[0]
	for path in paths:
		if _saved_at(path) < _saved_at(oldest):
			oldest = path
	return oldest


## Writes save to the folder at path, each file whole (to a .tmp first, then renamed
## over the old one), as Blueprint.save does.
## ponytail: the three files go one after another on the main thread (about 240 ms for
## eight 4,000-block ships); a crash between files mixes two saves, and the autosaves
## cover it. Thread it if autosaves stutter.
static func write(path: String, save: Dictionary) -> Error:
	var made := DirAccess.make_dir_recursive_absolute(path)
	if made != OK:
		return made
	for part: String in FILES:
		var file_path := path.path_join(FILES[part])
		var temp := file_path + ".tmp"
		var file := FileAccess.open(temp, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_string(JSON.stringify({"version": VERSION, part: save[part]}))
		var error := file.get_error()
		file.close()
		if error == OK:
			error = DirAccess.rename_absolute(temp, file_path)
		if error != OK:
			DirAccess.remove_absolute(temp)
			return error
	return OK


## The save in the folder at path, checked: {"save": Dictionary} (ints where they were
## ints), or {"problem": String} naming the first thing wrong and its file.
static func read(path: String) -> Dictionary:
	var parts := {}
	for part: String in FILES:
		var file_name: String = FILES[part]
		var file_path := path.path_join(file_name)
		if not FileAccess.file_exists(file_path):
			return {"problem": "This save is missing %s." % file_name}
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			return {"problem": "%s is damaged." % file_name}
		if file.get_length() > MAX_FILE_SIZE:
			return {"problem": "%s is too big." % file_name}
		var text := file.get_as_text()
		var json := JSON.new()
		if json.parse(text) != OK or not json.data is Dictionary or not json.data.has(part):
			return {"problem": "%s is damaged." % file_name}
		var version: Variant = Economy.whole(json.data.get("version"), 0, 1 << 30)
		if version != VERSION:
			return {"problem": "This save is version %s; this game reads version %d." % [str(version) if version != null else "?", VERSION]}
		parts[part] = json.data[part]
	var world: Variant = _read_world(parts["world"])
	if world is String:
		return {"problem": "world.json: %s" % world}
	if not parts["ships"] is Array or parts["ships"].size() > MAX_SHIPS:
		return {"problem": "ships.json: the ships aren't a list of at most %d." % MAX_SHIPS}
	var ships := []
	for i in parts["ships"].size():
		var ship := read_ship(parts["ships"][i])
		if ship.has("problem"):
			return {"problem": "ships.json: ship %d %s" % [i + 1, ship["problem"]]}
		ships.append(ship["record"])
	if not parts["players"] is Dictionary:
		return {"problem": "player.json: the players aren't a list by name."}
	var players := {}
	for player_name: Variant in parts["players"]:
		var account: Variant = Economy.read_account(parts["players"][player_name])
		if not player_name is String or player_name.is_empty() or player_name.length() > ShipGrid.MAX_NAME or account == null:
			return {"problem": "player.json: %s's account doesn't make sense." % str(player_name).left(24)}
		players[player_name] = account
	return {"save": {"world": world, "ships": ships, "players": players}}


## A ship's record from a save, checked: {"record": the record cleaned, "grid": her
## grid with paint and crates, "blueprint", "at": Transform3D, "trim", "anchored",
## "spares", "captain", "hands": entries with ids from -1 down}, or {"problem"}.
static func read_ship(record: Variant) -> Dictionary:
	if not record is Dictionary:
		return {"problem": "isn't written as a ship."}
	var captain: Variant = record.get("captain")
	if not captain is String or captain.length() > ShipGrid.MAX_NAME:
		return {"problem": "has no captain's name."}
	var at: Variant = record.get("at")
	if not at is Array or at.size() != 7 or not at.all(func(n: Variant) -> bool: return (n is float or n is int) and is_finite(float(n))):
		return {"problem": "isn't anywhere."}
	var turn := Quaternion(at[3], at[4], at[5], at[6])
	if absf(turn.length() - 1.0) > 0.001:
		return {"problem": "isn't turned a way a ship can face."}
	var trim: Variant = record.get("trim")
	if not (trim is float or trim is int) or not is_finite(float(trim)) or trim < Tuning.TRIM_MIN or trim > Tuning.TRIM_MAX:
		return {"problem": "has her balloons trimmed past their limits."}
	var anchored: Variant = record.get("anchored")
	var spares: Variant = Economy.whole(record.get("spares"), 0, Damage.SPARES_MAX)
	if not anchored is bool or spares == null:
		return {"problem": "has no anchor or spares that make sense."}
	var read := ShipGrid.read_blocks(record.get("blocks"), false)
	if read.has("problem"):
		return {"problem": "has a problem: %s" % (read["problem"] as String).to_lower()}
	var blueprint := ShipGrid.read_blocks(record.get("blueprint"), false)
	if blueprint.has("problem"):
		return {"problem": "has a blueprint with a problem: %s" % (blueprint["problem"] as String).to_lower()}
	var paint: Variant = ShipGrid.read_paint(record.get("paint"))
	if paint == null:
		return {"problem": "has paint that isn't colours."}
	var grid: ShipGrid = read["grid"]
	var cargo: Variant = ShipGrid.read_cargo(record.get("cargo"), grid)
	if cargo == null:
		return {"problem": "has crates that don't fit her cargo bays."}
	var listed: Variant = record.get("hands")
	if not listed is Array:
		return {"problem": "has hands that don't make sense."}
	var wire := []
	var clean_hands := []  # as written, in doubles: a Vector3 would round where he stands
	for entry: Variant in listed:
		if not entry is Array or entry.size() != 8:
			return {"problem": "has hands that don't make sense."}
		var numbers := []
		for i in range(2, 8):
			var n: Variant = entry[i]
			if not (n is float or n is int) or not is_finite(float(n)):
				return {"problem": "has hands that don't make sense."}
			numbers.append(n)
		var post: Variant = Economy.whole(numbers[0], ShipGrid.MIN_CELL, ShipGrid.MAX_CELL)
		var post_y: Variant = Economy.whole(numbers[1], ShipGrid.MIN_CELL, ShipGrid.MAX_CELL)
		var post_z: Variant = Economy.whole(numbers[2], ShipGrid.MIN_CELL, ShipGrid.MAX_CELL)
		if post == null or post_y == null or post_z == null:
			return {"problem": "has hands that don't make sense."}
		wire.append([-(wire.size() + 1), entry[0], entry[1], Vector3i(post, post_y, post_z),
				Vector3(float(numbers[3]), float(numbers[4]), float(numbers[5]))])
		clean_hands.append([entry[0], entry[1], post, post_y, post_z, float(numbers[3]), float(numbers[4]), float(numbers[5])])
	var hands: Variant = CrewHand.read_hands(wire, grid)
	if hands == null:
		return {"problem": "has hands that don't make sense."}
	grid.paint = paint
	grid.cargo = cargo
	var plan: ShipGrid = blueprint["grid"]
	plan.paint = paint
	var place := Transform3D(Basis(turn.normalized()), Vector3(at[0], at[1], at[2]))
	var clean := {"captain": captain, "at": at.map(func(n: Variant) -> float: return float(n)), "trim": float(trim),
			"anchored": anchored, "spares": spares, "blocks": grid.to_blocks(), "blueprint": plan.to_blocks(),
			"paint": grid.paint_names(), "cargo": grid.cargo_list(),
			"hands": clean_hands}
	return {"record": clean, "grid": grid, "blueprint": plan, "at": place, "trim": float(trim), "anchored": anchored,
			"spares": spares, "captain": captain, "hands": hands}


## The slot's save to load: {} when it's empty, {"save", "note"} for the newest save in
## it that reads (the note says why when that isn't the newest), or {"problem"}.
static func load_slot(slot: String) -> Dictionary:
	var paths: Array[String] = []
	for path: String in [slot_path(slot)] + autosave_paths(slot):
		if FILES.values().any(func(file_name: String) -> bool: return FileAccess.file_exists(path.path_join(file_name))):
			paths.append(path)
	if paths.is_empty():
		return {}
	paths.sort_custom(func(a: String, b: String) -> bool: return _saved_at(a) > _saved_at(b))
	var newest_problem := ""
	for path in paths:
		var read := read(path)
		if read.has("save"):
			var note := ""
			if not newest_problem.is_empty():
				note = "The latest save in slot %s couldn't be read (%s), so the one from %s was loaded." % [slot,
						newest_problem.trim_suffix("."), date_text(read["save"]["world"]["saved"])]
			return {"save": read["save"], "note": note}
		if newest_problem.is_empty():
			newest_problem = read["problem"]
	return {"problem": "Slot %s couldn't be read: %s" % [slot, newest_problem]}


## Loads slot into session for the next game: it saves there, and with a save that
## reads, plays it (its seed too). Returns what load_slot gave.
static func prepare(session: Node, slot: String) -> Dictionary:
	session.save_slot = slot
	session.loaded = {}
	var loaded := load_slot(slot)
	if loaded.has("save"):
		session.loaded = loaded
		session.requested_seed = loaded["save"]["world"]["seed"]
	return loaded


## Gives what save keeps under from (account, captaincies, crates) to to.
static func rename(save: Dictionary, from: String, to: String) -> void:
	if from == to:
		return
	if save["players"].has(from):
		save["players"][to] = save["players"][from]
		save["players"].erase(from)
	for record: Dictionary in save["ships"]:
		if record["captain"] == from:
			record["captain"] = to
		for crate: Array in record["cargo"]:
			if crate[4] == from:
				crate[4] = to
	if save["world"]["host"] == from:
		save["world"]["host"] = to


## unix as local time: "2026-10-01 14:02".
static func date_text(unix: float) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var t := Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"]]


## What the menu shows for slot.
static func summary(slot: String) -> String:
	var loaded := load_slot(slot)
	if loaded.is_empty():
		return "Slot %s   empty" % slot
	if not loaded.has("save"):
		return "Slot %s   can't be read" % slot
	var world: Dictionary = loaded["save"]["world"]
	var host: String = world["host"]
	var money: int = loaded["save"]["players"].get(host, {}).get("money", 0)
	return "Slot %s   %s · %d crowns · seed %d · %s" % [slot, host if not host.is_empty() else "server", money, world["seed"],
			date_text(world["saved"])]


## The world part, checked and cleaned, or what's wrong with it.
static func _read_world(data: Variant) -> Variant:
	if not data is Dictionary:
		return "the world isn't written as one."
	var world_seed: Variant = Economy.whole(data.get("seed"), 0, MAX_SEED)
	if world_seed == null:
		return "the seed isn't 0 to %d." % MAX_SEED
	var time: Variant = data.get("time")
	if not (time is float or time is int) or not is_finite(float(time)) or time < 0.0:
		return "the clock doesn't make sense."
	var salvaged: Variant = data.get("salvaged")
	if not salvaged is Array or salvaged.size() > 4096:
		return "the stripped wrecks aren't a list."
	var stripped := []
	for index: Variant in salvaged:
		var whole: Variant = Economy.whole(index, 0, 4096)
		if whole == null:
			return "a stripped wreck isn't a whole number."
		stripped.append(whole)
	var exploration: Variant = data.get("exploration")
	var host: Variant = data.get("host")
	var saved: Variant = data.get("saved")
	if not exploration is String or not host is String or host.length() > ShipGrid.MAX_NAME:
		return "the map or the host's name doesn't make sense."
	if not (saved is float or saved is int) or not is_finite(float(saved)):
		return "when it was saved doesn't make sense."
	return {"seed": world_seed, "time": float(time), "salvaged": stripped, "exploration": exploration, "host": host, "saved": float(saved)}


## When the save at path was made, from its world.json; a save whose world.json
## won't read counts by when its files were last written.
static func _saved_at(path: String) -> float:
	var file_path := path.path_join(FILES["world"])
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file != null and file.get_length() <= MAX_FILE_SIZE:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary and json.data.get("world") is Dictionary:
			var saved: Variant = json.data["world"].get("saved")
			if (saved is float or saved is int) and is_finite(float(saved)):
				return float(saved)
	var newest := -INF
	for file_name: String in FILES.values():
		if FileAccess.file_exists(path.path_join(file_name)):
			newest = maxf(newest, float(FileAccess.get_modified_time(path.path_join(file_name))))
	return newest
