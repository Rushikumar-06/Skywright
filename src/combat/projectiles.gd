class_name Projectiles
extends Node3D
## Every shot in flight and every harpoon's rope (spec §3.5, §4.6). A shot is only
## its launch data: every machine flies it on the same arc, the server at its own
## clock and clients DELAY behind, as they draw ships, so shots meet ships where
## they're drawn. Only the server looks for hits: each physics tick a ray from the
## shot's last place to its new one, past the firing ship, and anyone standing
## within CREW_HIT of that path before the ray's hit is hit instead. It says so
## through hit and crew_hit, and WorldSync does the rest. A shot that hits ends
## once it's drawn reaching that point, in a burst; one that doesn't ends after
## LIFETIME or below 0 m.
##
## A rope ties a block of one ship to a block of another. On the server it pulls
## them together while it's stretched past its length, and goes after TETHER_TIME,
## when stretched past TETHER_BREAK times its length, or when a ship or block is
## gone. Every machine draws it between the two blocks. A dedicated server draws nothing.
##
## ponytail: every shot and rope is its own MeshInstance3D; draw them from one
## MultiMesh each if big battles cost too many draw calls. A late joiner doesn't
## get shots or ropes already out; send them with the world if that shows.

## Server: shot hit collider at point (world space), flying along direction.
signal hit(shot: Dictionary, collider: Object, point: Vector3, direction: Vector3)
## Server: shot hit peer's crew member at point.
signal crew_hit(shot: Dictionary, peer: int, point: Vector3)

const LIFETIME := 20.0          ## s a shot flies before it's gone.
const CREW_HIT := 0.7           ## m from a shot's path that hits someone.
const TETHER_TIME := 45.0       ## s a rope lasts.
const TETHER_STIFFNESS := 4000.0  ## N per m a rope is stretched.
const TETHER_MAX_FORCE := 40000.0 ## N: the hardest a rope pulls.
const TETHER_BREAK := 2.0       ## Stretched past this times its length, a rope snaps.
const TETHER_MIN := 15.0        ## m: the shortest rope.

const SHOT_SIZE := 0.2
const HARPOON_SIZE := Vector3(0.1, 0.1, 1.2)
const ROPE_WIDTH := 0.08
const SHOT_COLOR := Color("2b2b2e")
const ROPE_COLOR := Color("7a5a36")
## Ammunition -> [diameter in m, seconds, colour, glowing] of its burst. Harpoons have none.
const BURSTS := {
	"shell": [3.0, 0.4, Color("ff8a2a"), true],
	"round": [1.0, 0.3, Color("8a6a45"), false],
	"chain": [1.0, 0.3, Color("8a6a45"), false],
}

## Shot id -> {"id", "ammo", "origin", "velocity", "time" (server clock at launch),
## "ship" (firing ship id), "cell" (the cell it was fired from), "ends" (server
## clock when it hit, INF until then), "node"; and "at" (the server's last place for
## it) and "point" (where it hit)}.
var shots: Dictionary = {}
## Rope id -> {"a": Ship, "a_cell", "b": Ship, "b_cell", "length", "since" (this
## machine's clock when tied), "node"}.
var ropes: Dictionary = {}

var _sync: WorldSync
var _visuals: bool
var _shot_mesh: SphereMesh
var _harpoon_mesh: BoxMesh
var _rope_mesh: BoxMesh


func _init(world_sync: WorldSync, with_visuals: bool) -> void:
	_sync = world_sync
	_visuals = with_visuals
	name = "Projectiles"
	if not with_visuals:
		return
	var dark := StandardMaterial3D.new()
	dark.albedo_color = SHOT_COLOR
	_shot_mesh = SphereMesh.new()
	_shot_mesh.radius = SHOT_SIZE / 2.0
	_shot_mesh.height = SHOT_SIZE
	_shot_mesh.material = dark
	_harpoon_mesh = BoxMesh.new()
	_harpoon_mesh.size = HARPOON_SIZE
	_harpoon_mesh.material = dark
	var hemp := StandardMaterial3D.new()
	hemp.albedo_color = ROPE_COLOR
	_rope_mesh = BoxMesh.new()
	_rope_mesh.size = Vector3(ROPE_WIDTH, ROPE_WIDTH, 1.0)
	_rope_mesh.material = hemp


## Where a shot launched from origin at velocity is t seconds later.
static func position_at(origin: Vector3, velocity: Vector3, t: float) -> Vector3:
	return origin + velocity * t + 0.5 * Vector3(0.0, -_gravity(), 0.0) * t * t


## steps + 1 points along a shot's arc, evenly in time from 0 to seconds.
static func arc(origin: Vector3, velocity: Vector3, seconds: float, steps: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in steps + 1:
		points.append(position_at(origin, velocity, seconds * i / steps))
	return points


## The unit direction of the low arc that reaches offset at speed, or
## Vector3.ZERO when it's out of reach.
static func aim(offset: Vector3, speed: float) -> Vector3:
	var g := _gravity()
	var v2 := speed * speed
	var flat := Vector2(offset.x, offset.z).length()
	if flat < 0.001:  # straight up or down
		if offset.y <= 0.0:
			return Vector3.DOWN
		return Vector3.UP if v2 >= 2.0 * g * offset.y else Vector3.ZERO
	var root := v2 * v2 - g * (g * flat * flat + 2.0 * offset.y * v2)
	if root < 0.0:
		return Vector3.ZERO
	var elevation := atan((v2 - sqrt(root)) / (g * flat))
	return Vector3(offset.x, 0.0, offset.z) / flat * cos(elevation) + Vector3.UP * sin(elevation)


static func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity"))


## Starts shot id of ammo from origin at velocity, fired at server time time from
## ship ship_id. An id already flying is left alone.
func launch(id: int, ammo: String, origin: Vector3, velocity: Vector3, time: float, ship_id: int) -> void:
	if shots.has(id):
		return
	var node: MeshInstance3D = null
	if _visuals:
		node = MeshInstance3D.new()
		node.mesh = _harpoon_mesh if ammo == "harpoon" else _shot_mesh
		node.visible = false  # until it's drawn leaving
		add_child(node)
	shots[id] = {"id": id, "ammo": ammo, "origin": origin, "velocity": velocity, "time": time, "ship": ship_id,
			"cell": Vector3i.ZERO, "ends": INF, "node": node, "at": origin, "point": origin}


## Shot id ends at point, at server time time: it's drawn up to there, then bursts.
func land(id: int, point: Vector3, time: float) -> void:
	if shots.has(id):
		shots[id]["ends"] = time
		shots[id]["point"] = point


## Ties rope id from a_cell of a to b_cell of b, length long.
func tie(id: int, a: Ship, a_cell: Vector3i, b: Ship, b_cell: Vector3i, length: float) -> void:
	if ropes.has(id):
		return
	var node: MeshInstance3D = null
	if _visuals:
		node = MeshInstance3D.new()
		node.mesh = _rope_mesh
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # placed every frame
		node.visible = false
		add_child(node)
	ropes[id] = {"a": a, "a_cell": a_cell, "b": b, "b_cell": b_cell, "length": length, "since": _sync.now(), "node": node}


## Lets rope id go. On the server, everyone is told.
func untie(id: int) -> void:
	if not ropes.has(id):
		return
	var node: Node = ropes[id]["node"]
	if node != null:
		node.queue_free()
	ropes.erase(id)
	if _sync.session.is_server():
		_sync.tell_world(&"_untether", [id])


func _physics_process(_delta: float) -> void:
	var now := _sync.now()
	var server: bool = _sync.session.is_server()
	var drawn_at := now if server else now - WorldSync.DELAY
	for id: int in shots.keys():
		var shot: Dictionary = shots[id]
		if server and shot["ends"] == INF:
			_fly(shot, now, _sync.crew_positions())  # afresh: the last shot may have knocked someone down
		if drawn_at >= shot["ends"]:
			_burst(shot["ammo"], shot["point"])
			_drop(id)
			continue
		var t: float = drawn_at - shot["time"]
		var at := position_at(shot["origin"], shot["velocity"], t)
		if t >= LIFETIME or at.y < 0.0:
			_drop(id)
		elif shot["node"] != null and t >= 0.0:
			_place(shot, at, t)
	if server:
		_pull(now)


## Server: moves shot on to where it is at now, and ends it at the first thing in
## its way: a crew member in crew (peer -> world position), else whatever the ray hits.
func _fly(shot: Dictionary, now: float, crew: Dictionary) -> void:
	var from: Vector3 = shot["at"]
	var to := position_at(shot["origin"], shot["velocity"], minf(now - shot["time"], LIFETIME))
	var ray := PhysicsRayQueryParameters3D.create(from, to)
	var shooter: Ship = _sync.ships.get(shot["ship"])
	if shooter != null:
		ray.exclude = [shooter.get_rid()]
	var found := get_world_3d().direct_space_state.intersect_ray(ray)
	var end: Vector3 = found["position"] if not found.is_empty() else to
	var path := end - from
	var nearest := INF
	var victim := 0
	for peer: int in crew:
		var body: Vector3 = crew[peer]
		var along := clampf((body - from).dot(path) / path.length_squared(), 0.0, 1.0) if path.length_squared() > 0.0 else 0.0
		if body.distance_to(from + path * along) <= CREW_HIT and along < nearest:
			nearest = along
			victim = peer
	shot["at"] = to
	if victim != 0:
		var point := from + path * nearest
		land(shot["id"], point, now)
		crew_hit.emit(shot, victim, point)
	elif not found.is_empty():
		land(shot["id"], end, now)
		hit.emit(shot, found["collider"], end, (to - from).normalized())


## Draws shot at at, t seconds after it was fired.
func _place(shot: Dictionary, at: Vector3, t: float) -> void:
	var node: MeshInstance3D = shot["node"]
	node.position = at
	if shot["ammo"] == "harpoon":
		var heading := (shot["velocity"] as Vector3) + Vector3(0.0, -_gravity(), 0.0) * t
		if heading.length_squared() > 0.0:
			node.basis = Basis.looking_at(heading, Vector3.RIGHT if absf(heading.normalized().y) > 0.99 else Vector3.UP)
	if not node.visible:
		node.visible = true
		node.reset_physics_interpolation()  # or it would streak in from where it was made


func _drop(id: int) -> void:
	var node: Node = shots[id]["node"]
	if node != null:
		node.queue_free()
	shots.erase(id)


## A burst where a shot of ammo ended, fading out.
func _burst(ammo: String, point: Vector3) -> void:
	if not _visuals or not BURSTS.has(ammo):
		return
	var look: Array = BURSTS[ammo]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = look[2]
	if look[3]:
		material.emission_enabled = true
		material.emission = look[2]
		material.emission_energy_multiplier = 4.0
	var sphere := SphereMesh.new()
	sphere.radius = look[0] / 2.0
	sphere.height = look[0]
	var puff := MeshInstance3D.new()
	puff.mesh = sphere
	puff.material_override = material
	puff.position = point
	add_child(puff)
	var fade := puff.create_tween()
	fade.tween_property(material, "albedo_color:a", 0.0, look[1])
	fade.tween_callback(puff.queue_free)


## Server: each rope pulls its ships together while stretched, and goes when it's
## old, snapped, or a ship or block is gone.
func _pull(now: float) -> void:
	for id: int in ropes.keys():
		var rope: Dictionary = ropes[id]
		var a: Ship = rope["a"] if is_instance_valid(rope["a"]) else null
		var b: Ship = rope["b"] if is_instance_valid(rope["b"]) else null
		if a == null or b == null or _sync.id_of(a) == 0 or _sync.id_of(b) == 0 or not a.grid.blocks.has(rope["a_cell"]) \
				or not b.grid.blocks.has(rope["b_cell"]) or now - rope["since"] > TETHER_TIME:
			untie(id)
			continue
		var pa := a.global_transform * Vector3(rope["a_cell"])
		var pb := b.global_transform * Vector3(rope["b_cell"])
		var apart := pa.distance_to(pb)
		if apart > TETHER_BREAK * rope["length"]:
			untie(id)
		elif apart > rope["length"]:
			var pull := (pb - pa) / apart * minf(TETHER_STIFFNESS * (apart - rope["length"]), TETHER_MAX_FORCE)
			a.apply_force(pull, pa - a.global_position)
			b.apply_force(-pull, pb - b.global_position)


## Draws each rope between its blocks, as the ships are drawn this frame.
func _process(_delta: float) -> void:
	for rope: Dictionary in ropes.values():
		var node: MeshInstance3D = rope["node"]
		if node == null:
			continue
		var a: Ship = rope["a"] if is_instance_valid(rope["a"]) else null
		var b: Ship = rope["b"] if is_instance_valid(rope["b"]) else null
		node.visible = a != null and b != null and a.is_inside_tree() and b.is_inside_tree()
		if not node.visible:
			continue  # a ship went; the server lets the rope go next
		var pa := a.get_global_transform_interpolated() * Vector3(rope["a_cell"])
		var pb := b.get_global_transform_interpolated() * Vector3(rope["b_cell"])
		var span := pb - pa
		if span.length_squared() < 0.0001:
			node.visible = false
			continue
		var up := Vector3.RIGHT if absf(span.normalized().y) > 0.99 else Vector3.UP
		node.transform = Transform3D(Basis.looking_at(span, up).scaled_local(Vector3(1.0, 1.0, span.length())), (pa + pb) / 2.0)
