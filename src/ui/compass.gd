class_name Compass
extends Control
## The strip along the top of the screen: the bearing you look toward in the middle,
## 90 degrees either side, the eight points, the towns you know, and the region under it.

const POINTS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const SPAN := 90.0                ## Degrees visible either side of the bearing.
const GOLD := Color("f0c24b")
const FONT_SIZE := 14

var bearing := 0.0  ## Degrees clockwise from north, from the camera. Set each frame by the HUD.
var origin := Vector3.ZERO  ## Where you are, to bear towns from. Set each frame by the HUD.
var region := "":  ## The name of the region you're in.
	set(value):
		region = value
		_region_label.text = value

var _gen: WorldGen
var _explored: Exploration
var _region_label: Label


func _init(world_gen: WorldGen, explored: Exploration) -> void:
	_gen = world_gen
	_explored = explored
	custom_minimum_size = Vector2(520.0, 44.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_region_label = UiTheme.caption("")
	_region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_label.position = Vector2(0.0, 48.0)
	_region_label.size = Vector2(520.0, 28.0)
	add_child(_region_label)


## The point of the compass at bearing degrees ("N", "NE", ... "NW"), or "" between them.
static func label_at(degrees: float) -> String:
	var step := fposmod(degrees, 360.0) / 45.0
	if absf(step - roundf(step)) > 0.01:
		return ""
	return POINTS[roundi(step) % 8]


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var middle := size.x / 2.0
	var per_degree := middle / SPAN
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PANEL)
	var first := ceili((bearing - SPAN) / 15.0)
	for k in range(first, floori((bearing + SPAN) / 15.0) + 1):
		var x := middle + (k * 15.0 - bearing) * per_degree
		var point := label_at(k * 15.0)
		draw_line(Vector2(x, size.y), Vector2(x, size.y - (12.0 if point != "" else 6.0)), UiTheme.TEXT_DIM, 1.0)
		if point != "":
			_centred(font, x, size.y - 16.0, point, UiTheme.TEXT)
	for town: Dictionary in _gen.towns:
		var dock: Vector3 = town["dock"]
		if not _explored.seen(dock):
			continue
		var offset := wrapf(Hud.bearing(dock - origin) - bearing, -180.0, 180.0)
		if absf(offset) <= SPAN:
			var x := middle + offset * per_degree
			draw_colored_polygon(PackedVector2Array([Vector2(x - 5.0, size.y), Vector2(x + 5.0, size.y), Vector2(x, size.y - 10.0)]), GOLD)
			_centred(font, x, size.y - 16.0, town["name"], GOLD)
	draw_line(Vector2(middle, 0.0), Vector2(middle, size.y), Color(UiTheme.ACCENT, 0.7), 1.0)
	draw_rect(Rect2(middle - 24.0, 0.0, 48.0, 17.0), UiTheme.PANEL)
	_centred(font, middle, 13.0, "%03d°" % posmod(roundi(bearing), 360), UiTheme.ACCENT)


func _centred(font: Font, x: float, baseline: float, text: String, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(x - width / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
