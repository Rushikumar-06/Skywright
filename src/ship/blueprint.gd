class_name Blueprint
## Ship designs saved as plain JSON files that players share, so a file is as
## untrusted as anything off the network (spec §4.10).

const SettingsScript := preload("res://src/core/settings.gd")

const FORMAT := "skywright-blueprint"
const VERSION := 1
const DIR := "user://blueprints"
const EXTENSION := ".skyship.json"
const MAX_FILE_SIZE := 1048576  ## 1 MiB; a full 4,000-block ship is about 100 KB.
const MAX_NAME_LENGTH := 32
const DEFAULT_NAME := "Untitled ship"


## The blueprint file's text for grid, blocks in cell order.
static func to_text(grid: ShipGrid, ship_name: String) -> String:
	var cells := grid.blocks.keys()
	cells.sort()
	var blocks := []
	for cell: Vector3i in cells:
		var block: Dictionary = grid.blocks[cell]
		blocks.append([cell.x, cell.y, cell.z, block["type"], block["rotation"]])
	return JSON.stringify({"format": FORMAT, "version": VERSION, "name": clean_name(ship_name), "blocks": blocks, "paint": grid.paint_names()})


## Reads blueprint text: {"grid": ShipGrid, "name": String} or {"problem": String}.
static func parse(text: String) -> Dictionary:
	var json := JSON.new()  # unlike JSON.parse_string, a bad file logs nothing
	if json.parse(text) != OK or not json.data is Dictionary or json.data.get("format") != FORMAT:
		return {"problem": "This isn't a Skywright blueprint."}
	var data: Dictionary = json.data
	var version: Variant = data.get("version")
	if not version is float or not is_finite(version) or version != floorf(version):
		return {"problem": "This isn't a Skywright blueprint."}
	if version != VERSION:
		return {"problem": "This blueprint is version %s; this game reads version %d." % [str(int(version)) if absf(version) < 1e9 else "?", VERSION]}
	var read := ShipGrid.read_blocks(data.get("blocks"))
	if read.has("problem"):
		return read
	var paint: Variant = ShipGrid.read_paint(data.get("paint", {}))
	if paint == null:
		return {"problem": "The paint colours aren't valid."}
	var grid: ShipGrid = read["grid"]
	grid.paint = paint
	return {"grid": grid, "name": clean_name(data["name"]) if data.get("name") is String else DEFAULT_NAME}


## Writes grid to its file in dir, making the folder if needed.
static func save(grid: ShipGrid, ship_name: String, dir := DIR) -> Error:
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return made
	var path := path_for(ship_name, dir)
	var temp := path + ".tmp"  # written whole first, so a failed write never empties an old blueprint
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_text(grid, ship_name))
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temp, path)
	if error != OK:
		DirAccess.remove_absolute(temp)
	return error


## Reads a blueprint file as parse() does, refusing files that are too big or won't open.
static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"problem": "Couldn't open \"%s\"." % path.get_file()}
	if file.get_length() > MAX_FILE_SIZE:
		return {"problem": "\"%s\" is too big to be a blueprint." % path.get_file()}
	var bytes := file.get_buffer(file.get_length())
	if not _is_utf8(bytes):
		return {"problem": "This isn't a Skywright blueprint."}
	return parse(bytes.get_string_from_utf8())


## Where a ship of this name is saved: the cleaned name, made safe as a file name.
static func path_for(ship_name: String, dir := DIR) -> String:
	var stem := clean_name(ship_name).validate_filename().lstrip(". ")
	return dir.path_join((stem if not stem.is_empty() else "ship") + EXTENSION)


## The saved blueprints in dir, as sorted paths. A missing folder has none.
static func list(dir := DIR) -> PackedStringArray:
	var paths := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return paths
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(EXTENSION):
			paths.append(dir.path_join(file))
	paths.sort()
	return paths


static func clean_name(raw: String) -> String:
	return SettingsScript.clean_name(raw, MAX_NAME_LENGTH, DEFAULT_NAME)


# Godot has no silent UTF-8 check (get_string_from_utf8 logs an error on bad bytes),
# so walk the bytes. ponytail: about 1 MiB at most; upgrade if Godot adds a quiet check.
static func _is_utf8(bytes: PackedByteArray) -> bool:
	var i := 0
	var n := bytes.size()
	while i < n:
		var b := bytes[i]
		if b < 0x80:
			i += 1
			continue
		var extra := 1 if b >= 0xC2 and b < 0xE0 else 2 if b >= 0xE0 and b < 0xF0 else 3 if b >= 0xF0 and b < 0xF5 else 0
		if extra == 0 or i + extra >= n:
			return false
		for k in range(1, extra + 1):
			if bytes[i + k] & 0xC0 != 0x80:
				return false
		# Overlong, surrogate and out-of-range forms.
		var b1 := bytes[i + 1]
		if (b == 0xE0 and b1 < 0xA0) or (b == 0xED and b1 >= 0xA0) or (b == 0xF0 and b1 < 0x90) or (b == 0xF4 and b1 >= 0x90):
			return false
		i += extra + 1
	return true
