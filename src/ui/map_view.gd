class_name MapView
extends Control
## The whole world as a disc over the screen, filling in as you explore: the ground of
## seen chunks, rivers, towns, landmarks and wrecks you have seen, every ship, and you.

const MARGIN := 40.0
const UNSEEN := Color("1b1828")
const SEEN := Color("40506a")
const LAND := Color("8fae6b")
const RIVER := Color("7fb2e6")
const GOLD := Color("f0c24b")
const WRECK := Color("9a9a9a")
const PIRATE := Color("d9534f")
const BEAST := Color("9b7fd4")
const RING := Color(1, 1, 1, 0.12)
const FONT_SIZE := 16

## Paints the unseen world dark and the seen cells lighter, inside the disc only.
const SHADER := """
shader_type canvas_item;
uniform vec4 unseen : source_color;
uniform vec4 seen : source_color;
uniform float edge = 0.97656;
void fragment() {
	float known = texture(TEXTURE, UV).r;
	COLOR = vec4(mix(unseen.rgb, seen.rgb, known), step(length(UV - vec2(0.5)) * 2.0, edge));
}
"""

var _gen: WorldGen
var _explored: Exploration
var _sync: WorldSync
var _you: Callable
var _fog: TextureRect
var _texture: ImageTexture
var _drawn_revision := -1
var _islands: Dictionary = {}  ## Chunk -> its islands as [Vector3, radius] pairs, once seen.


## The map of world_gen's world as explored shows it. you returns [your world position, your heading in
## radians as Ship.heading() counts it]. world_sync's ships are drawn as dots, pirates red; it can be null.
func _init(world_gen: WorldGen, explored: Exploration, world_sync: WorldSync, you: Callable) -> void:
	_gen = world_gen
	_explored = explored
	_sync = world_sync
	_you = you
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = SHADER
	material.set_shader_parameter("unseen", UNSEEN)
	material.set_shader_parameter("seen", SEEN)
	_texture = ImageTexture.create_from_image(explored.image)
	_fog = TextureRect.new()
	_fog.texture = _texture
	_fog.stretch_mode = TextureRect.STRETCH_SCALE
	_fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.material = material
	_fog.show_behind_parent = true
	add_child(_fog)


## Where p is on the map, in pixels. North is up.
func place_of(p: Vector3) -> Vector2:
	return size / 2.0 + Vector2(p.x, p.z) * _scale()


## The towns you have seen, as indices into the world's towns.
func known_towns() -> Array[int]:
	var known: Array[int] = []
	for i in _gen.towns.size():
		if _explored.seen(_gen.towns[i]["dock"]):
			known.append(i)
	return known


## The landmarks you have seen, as indices into the world's landmarks.
func known_landmarks() -> Array[int]:
	var known: Array[int] = []
	for i in _gen.landmarks.size():
		if _explored.seen(_gen.landmarks[i]["at"]):
			known.append(i)
	return known


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _fog != null:
		_fog.size = Vector2.ONE * Exploration.HALF * 2.0 * _scale()
		_fog.position = size / 2.0 - _fog.size / 2.0


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if _drawn_revision != _explored.revision:
		_refresh()
	var font := get_theme_default_font()
	var scale := _scale()
	var middle := size / 2.0
	for ring: float in WorldGen.REGION_OUTER:
		draw_arc(middle, ring * scale, 0.0, TAU, 96, RING, 1.0)
	var inner := 0.0
	for i in 5:
		var outer: float = WorldGen.REGION_OUTER[i]
		var title: String = WorldGen.REGION_NAMES[i]
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, middle + Vector2(-width / 2.0, -(inner + outer) / 2.0 * scale), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(UiTheme.TEXT, 0.3))
		inner = outer
	for islands: Array in _islands.values():
		for island: Array in islands:
			draw_circle(place_of(island[0]), maxf(island[1] * scale, 1.5), LAND)
	for river in _gen.rivers:
		var points: PackedVector3Array = river["points"]
		for k in points.size() - 1:
			if _explored.seen(points[k]) and _explored.seen(points[k + 1]):
				draw_line(place_of(points[k]), place_of(points[k + 1]), RIVER, 2.0)
	for wreck in _gen.wrecks:
		if _explored.seen(wreck["at"]):
			var at := place_of(wreck["at"])
			draw_line(at - Vector2(3, 3), at + Vector2(3, 3), WRECK, 1.5)
			draw_line(at - Vector2(3, -3), at + Vector2(3, -3), WRECK, 1.5)
	for i in known_landmarks():
		var at := place_of(_gen.landmarks[i]["at"])
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(5, 0), at + Vector2(0, 6), at + Vector2(-5, 0)]), Color.WHITE)
		draw_string(font, at + Vector2(8, 5), _gen.landmarks[i]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)
	for i in known_towns():
		var at := place_of(_gen.towns[i]["dock"])
		draw_circle(at, 5.0, GOLD)
		draw_string(font, at + Vector2(8, 5), _gen.towns[i]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, GOLD)
	if _sync != null:
		for ship: Ship in _sync.ships.values():
			draw_circle(place_of(ship.global_position), 3.0, ship_color(ship))
		if _sync.leviathans != null:
			for beast: Leviathan in _sync.leviathans.beasts.values():
				draw_circle(place_of(beast.global_position), 5.0 if beast.kind == "warden" else 3.5, BEAST)
	var you: Array = _you.call()
	var heading := Vector2(-sin(you[1]), -cos(you[1]))
	var tip := place_of(you[0])
	draw_colored_polygon(PackedVector2Array([tip + heading * 11.0, tip + heading.rotated(2.5) * 8.0, tip + heading * -3.0, tip + heading.rotated(-2.5) * 8.0]), UiTheme.ACCENT)


## Uploads the exploration image and works out the islands of newly seen chunks.
func _refresh() -> void:
	_drawn_revision = _explored.revision
	_texture.update(_explored.image)
	var half := roundi(Exploration.HALF / WorldGen.CHUNK)
	for cz in range(-half, half):
		for cx in range(-half, half):
			var chunk := Vector2i(cx, cz)
			if not _islands.has(chunk) and _explored.seen(WorldGen.chunk_origin(chunk) + Vector3(WorldGen.CHUNK, 0.0, WorldGen.CHUNK) / 2.0):
				var found: Array = []
				for island in _gen.islands_in(chunk):
					found.append([island["at"], island["radius"]])
				_islands[chunk] = found


func _scale() -> float:
	return (minf(size.x, size.y) / 2.0 - MARGIN) / WorldGen.RADIUS


## The colour a ship's dot is drawn in: red for pirates.
static func ship_color(ship: Ship) -> Color:
	return PIRATE if ship.pirate else UiTheme.TEXT
