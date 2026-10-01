extends Node3D
## The game world: sky, the Roil, the islands made from the session's seed (streamed
## in around every ship), the ten towns with their docks, and the starter ship at the
## first town's first slipway with you aboard. Its Weather (fog sheets, storm columns
## and lightning) is only drawn where someone plays. Its Session is a sibling: the
## Session autoload in the game, or a test's own. The server builds the ships and flies them;
## clients get them through the world's WorldSync. You board the host's ship when you
## arrive, and your own ship whenever one arrives: launch a design and you're at its
## helm, and B brings you back from a test flight. When the ship you're on goes, you
## board its successor, or the ship you came from, or your own, or the host's (never
## a wreck), and with none of those you step off into the air, or when she was lost
## wake on the nearest town's quay. Abandoning ship (the pause menu) loses your own
## ship the same way. Stepping off a deck
## puts you ashore, on foot in this world; landing on a deck (a wreck's too), or E
## next to a hull (not a wreck's), puts you aboard; and falling into the Roil puts
## you back aboard (not on a wreck), or with no ship left onto the nearest town's
## quay. A ship lost to the Roil leaves her blueprint in her captain's shipyard. Its
## Projectiles fly and draw every shot. A shot
## that hits you knocks you down for a few seconds, and you come to at a bunk.
## Holding R repairs the ship you're aboard, and E by a wreck salvages her, both
## through the WorldSync. A
## dedicated server's world has no player, HUD, pause menu or Weather.

## Where the ship starts: over the Calm Reaches, 7 km from the Eye.
const START := WorldGen.START
const REVEAL_EVERY := 0.5  ## Seconds between looks around, for the map.
const AUTOSAVE_EVERY := 300.0  ## s of play between autosaves,
const AUTOSAVE_GAP := 30.0     ## and the least before docking autosaves again.

var session: Node
var sync: WorldSync
var ledger: Ledger             ## The world's books, beside the Sync.
var ship: Ship                 ## The ship you're aboard. Null while ashore.
var left: Ship                 ## The ship you last stepped off, while it's here.
var player: PlayerController   ## You, once the ship has arrived.
var hud: Hud
var towns: Array[Node3D] = []  ## Every town, in WorldGen.towns' order, under the Towns node.
var shipyard: Shipyard         ## Null while closed.
var town_panel: TownPanel      ## The town you're doing business in, opened with T. Null while closed.
var design: ShipDesign         ## Your design, kept for the whole game.
var gen: WorldGen              ## The world made from the session's seed.
var wind: Wind                 ## Its wind, on the world's clock.
var projectiles: Projectiles   ## Its shots and harpoon ropes.
var streamer: WorldStreamer    ## Loads its chunks around every ship and player.
var exploration := Exploration.new()  ## What you have seen of it, on this machine only.
var map: MapView               ## The whole world, hidden until M. Made with the HUD.

var _reveal_left := 0.0        ## Seconds until the next look around.
var _came_from: Ship           ## The ship you were on before this one, while it's still here.
var _yard_town := 0            ## The town whose dock the shipyard was last opened at.
var _down_left := 0.0          ## s until you come to, while knocked down.
var _abandoning := false       ## You asked to abandon your ship, and she isn't gone yet.
var _since_save := 0.0         ## Server: s of play since the last save.
var _arrival_note := ""        ## Said when you arrive: why an older save was loaded.

var _sky: WorldSky
var _pause: PanelContainer
var _resume: Button
var _abandon: Button
var _save_button: Button
var _pause_note: Label


func _ready() -> void:
	session = get_node("../Session")
	_sky = WorldSky.new()
	add_child(_sky)
	add_child(Roil.new())
	gen = WorldGen.new(session.world_seed)
	wind = Wind.new(gen)
	var town_root := Node3D.new()
	town_root.name = "Towns"
	add_child(town_root)
	for i in gen.towns.size():
		var town := Town.create(gen.towns[i], not session.dedicated)
		town.name = "Town%d" % i
		town_root.add_child(town)
		towns.append(town)
	sync = WorldSync.new(session)
	sync.wind = wind
	sync.gen = gen
	sync.ship_added.connect(_on_ship_added)
	sync.ship_removed.connect(_on_ship_removed)
	for town: Dictionary in gen.towns:
		sync.docks.append(town["dock"])
	for wreck: Dictionary in gen.wrecks:
		sync.sites.append(Sites.wreck_center(wreck))
	add_child(sync)
	ledger = Ledger.new(sync)
	sync.ledger = ledger
	ledger.told.connect(_on_told)
	ledger.account_changed.connect(_on_account_changed)
	add_child(ledger)
	projectiles = Projectiles.new(sync, not session.dedicated)
	sync.projectiles = projectiles
	add_child(projectiles)  # after the Sync, so shots fly on this tick's clock
	sync.knocked_out.connect(knock_out)
	sync.salvage_result.connect(_on_salvage_result)
	sync.world_arrived.connect(_on_world_arrived)
	if not session.dedicated:
		var weather := Weather.new(gen, sync.now)
		add_child(weather)
		sync.struck.connect(func(on: Ship, cell: Vector3i) -> void: weather.bolt_to(on.global_transform * Vector3(cell)))
	sync.docked.connect(func(_ship: Ship, _town: int) -> void:
		if _since_save >= AUTOSAVE_GAP:
			_autosave())
	if session.is_server() and not session.loaded.is_empty():
		_restore(session.loaded)
	elif session.is_server():
		sync.add_ship(StarterShip.build(), Dock.slipway(START, 0), 0 if session.dedicated else 1)
	streamer = WorldStreamer.new(gen, not session.dedicated)
	streamer.focus = sync.focus_points
	add_child(streamer)
	if not session.dedicated:
		_build_pause_menu()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_sky.hour = WorldSky.hour_at(sync.now())
	_sky.storm = wind.roughness(player.camera.global_position, sync.now()) if player != null else 0.0
	if hud != null:
		hud.test_flight = on_test_flight()
		hud.at_dock = at_dock()
		hud.salvage = not salvage_in_reach().is_empty()
	_reveal_left -= delta
	if player != null and _reveal_left <= 0.0:
		_reveal_left = REVEAL_EVERY
		exploration.reveal(player.world_position())


func _physics_process(delta: float) -> void:
	if session.is_server() and not session.save_slot.is_empty():
		_since_save += delta
		if _since_save >= AUTOSAVE_EVERY:
			_autosave()
	if _down_left > 0.0:
		_down_left -= delta
		if _down_left <= 0.0:
			_come_to()


## The world as a save keeps it (see SaveGame): every ship but pirates, nobody's wrecks
## and test flights, the ships waiting for their captains, every account, the clock, the
## stripped wrecks, and your map.
func capture() -> Dictionary:
	var records := []
	for each: Ship in sync.ships.values():
		if not (each.test or each.pirate or (each.is_wreck() and each.captain == 0)):
			records.append(sync.record(each))
	records.append_array(sync.stored.values())
	var stripped := sync.salvaged.keys()
	stripped.sort()
	return {"world": {"seed": session.world_seed, "time": sync.now(), "salvaged": stripped,
			"exploration": exploration.to_text() if player != null else "",
			"host": "" if session.dedicated else sync.name_of(multiplayer.get_unique_id()), "saved": Time.get_unix_time_from_system()},
			"ships": records, "players": ledger.accounts.duplicate(true)}


## Server: saves the game to its slot (an autosave when auto). With no slot it writes
## nothing.
func save_game(auto := false) -> Error:
	if not session.is_server() or session.save_slot.is_empty():
		return ERR_UNCONFIGURED
	var slot: String = session.save_slot
	var error := SaveGame.write(SaveGame.autosave_path(slot) if auto else SaveGame.slot_path(slot), capture())
	if error == OK:
		_since_save = 0.0
	return error


func _autosave() -> void:
	if not session.is_server() or session.save_slot.is_empty():
		return
	_since_save = 0.0  # a failed autosave waits for the next, rather than retrying every frame
	var error := save_game(true)
	if error != OK and hud != null:
		hud.show_message("Couldn't autosave (%s)." % error_string(error))


## Server: plays a saved game (see SaveGame.load_slot): the host keeps their progress
## under a new name, captains here get their ships back, and the ships of captains who
## aren't wait for them.
func _restore(loaded: Dictionary) -> void:
	_arrival_note = loaded.get("note", "")
	session.loaded = {}
	var save: Dictionary = (loaded["save"] as Dictionary).duplicate(true)
	var world: Dictionary = save["world"]
	var me := multiplayer.get_unique_id()
	if not session.dedicated and not (world["host"] as String).is_empty():
		SaveGame.rename(save, world["host"], sync.name_of(me))
	sync.set_clock(world["time"])
	for index: int in world["salvaged"]:
		if index < sync.sites.size():
			sync.salvaged[index] = true
	if not session.dedicated:
		exploration.read_text(world["exploration"])
	ledger.set_accounts(save["players"])
	if not session.dedicated:
		ledger.send_account(me)
	for saved: Dictionary in save["ships"]:
		var captain := 0
		for peer: int in session.players:
			if sync.name_of(peer) == saved["captain"]:
				captain = peer
		if captain == 0 and not (saved["captain"] as String).is_empty():
			sync.stored[saved["captain"]] = saved
		else:
			sync.restore(saved, captain)
	if player == null and not session.dedicated:
		come_ashore(Dock.quay_spot(START))


## Your place in the roster, which is where you stand when you board: crew board
## at different spots, in the order they joined.
func my_slot() -> int:
	return maxi(0, session.players.keys().find(multiplayer.get_unique_id()))


## The town whose dock p is near, or -1.
func town_at(p: Vector3) -> int:
	return sync.town_at(p)


## Takes grid for a test flight from your test berth at the shipyard's town (with it
## shut, the nearest), at its helm.
func test_flight(grid: ShipGrid) -> void:
	_launch(grid, true)


## Launches grid as your ship, at your slipway at the shipyard's town (with it shut, the
## nearest) and at its helm. It replaces your old ship, whose crew come too.
func launch(grid: ShipGrid) -> void:
	_launch(grid, false)


func _launch(grid: ShipGrid, test: bool) -> void:
	if not sync.launch(grid, test, _town_here()) and shipyard != null:
		shipyard.say("Wait a moment, then try again.")


## Whether you're aboard your own test flight.
func on_test_flight() -> bool:
	return ship != null and ship.test and ship.captain == multiplayer.get_unique_id()


## Whether your crew member, where the world draws them, is near a town's dock.
func at_dock() -> bool:
	return player != null and town_at(player.world_position()) >= 0


## Puts you aboard target at spot (-1 for your roster slot), with your controls.
func board(target: Ship, spot := -1) -> void:
	come_aboard(target, target.crew_spawn(my_slot() if spot < 0 else spot))


## Puts you aboard target at local (in its space), standing still, with your controls.
func come_aboard(target: Ship, local: Vector3) -> void:
	var crew := CrewMember.new(target, local)
	target.interior.add_child(crew)
	if player == null:
		_arrive(crew)
	else:
		var from := ship if ship != null else left
		var here := sync.id_of(from) != 0  # a ship on its way out can't be gone back to
		if ship != null and here:
			player.leave_station()  # or nobody else could take it until you left
		if not on_test_flight() and target != from:  # from a second test flight, B still goes back where the first came from
			_came_from = from if here else null
		_swap_crew(crew)
	ship = target


## You arrive in the world as crew: your controls, camera, HUD and map are made.
func _arrive(crew: CrewMember) -> void:
	player = PlayerController.new(crew)
	add_child(player)
	sync.player = player
	player.left_ship.connect(go_ashore)
	player.landed_on.connect(func(on: Ship) -> void: come_aboard(on, on.to_local(player.crew.global_position)))
	player.climbing.connect(board)
	player.lost.connect(rescue)
	player.repairing.connect(func(cell: Vector3i) -> void: sync.repair(ship, cell))
	player.idle_interact.connect(salvage)
	hud = Hud.new(player, session)
	hud.ledger = ledger
	if not _arrival_note.is_empty():
		hud.show_message.call_deferred(_arrival_note)
		_arrival_note = ""
	hud.wind = wind
	hud.gen = gen
	hud.exploration = exploration
	add_child(hud)
	map = MapView.new(gen, exploration, sync, _you)
	map.visible = false
	hud.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Client: with the world here and no ship to board (every one gone, wrecked or a
## pirate), you arrive standing on the first town's quay.
func _on_world_arrived() -> void:
	if player == null and not session.dedicated:
		come_ashore(Dock.quay_spot(gen.towns[0]["dock"]))


## Puts you standing at at in the world, making your controls if you have none yet.
func come_ashore(at: Vector3) -> void:
	var crew := CrewMember.new(null, at)
	add_child(crew)
	if player == null:
		_arrive(crew)
	else:
		if ship != null and sync.id_of(ship) != 0:
			player.leave_station()
		_swap_crew(crew)
	ship = null


## Gives up your own ship: she's lost (and insured), and you wake on the nearest quay
## unless you're aboard another ship.
func abandon_ship() -> void:
	if sync.ship_of(multiplayer.get_unique_id(), false) == null:
		return
	_abandoning = true
	sync.abandon()


## Steps you off your ship into this world, where you are, keeping the ship's
## velocity there and the way you face.
func go_ashore() -> void:
	var from := ship
	var old := player.crew
	var point := from.global_transform * old.position
	var crew := CrewMember.new(null, point)
	crew.velocity = (from.point_velocity(point) + from.global_basis * old.velocity).limit_length(CrewMember.FALL_LIMIT)
	var facing := from.global_basis * (Basis(Vector3.UP, old.look_yaw) * Vector3.FORWARD)
	crew.look_yaw = atan2(-facing.x, -facing.z)
	add_child(crew)
	if sync.id_of(from) != 0:
		player.leave_station()
	left = from
	ship = null
	_swap_crew(crew)
	if from.test and from.captain == multiplayer.get_unique_id() and sync.id_of(from) != 0:
		# Or a free test flight in locked parts could ferry you over the Stormwall.
		hud.show_message("You stepped off your test flight, so it's over.")
		sync.end_test()


## Out of the Roil: aboard the ship you left, else your own, else the host's (never
## a wreck), else on the nearest town's quay.
func rescue() -> void:
	if recover(left) != null:
		hud.show_message("The Roil nearly took you. Back aboard!")
	else:
		var town: String = gen.towns[_nearest_town(player.world_position())]["name"]
		hud.show_message("The Roil nearly took you. You wake on the quay at %s." % town)


## What E would salvage where you are: ["site", index] for a world wreck not yet
## stripped within Damage.SITE_REACH, else ["ship", wreck] for a wreck ship (nobody's)
## whose box grown Damage.SALVAGE_REACH holds you, else [].
func salvage_in_reach() -> Array:
	if player == null:
		return []
	var here := player.world_position()
	for i in sync.sites.size():
		if not sync.salvaged.has(i) and here.distance_to(sync.sites[i]) <= Damage.SITE_REACH:
			return ["site", i]
	for wreck: Ship in sync.ships.values():
		if wreck.is_wreck() and wreck.captain == 0 and (wreck.global_transform * wreck.bounds).grow(Damage.SALVAGE_REACH).has_point(here):
			return ["ship", wreck]
	return []


## Salvages what's in reach, if anything. The server decides.
func salvage() -> void:
	var found := salvage_in_reach()
	if found.is_empty():
		return
	if found[0] == "site":
		sync.salvage_site(found[1])
	else:
		sync.salvage_ship(found[1])


func _on_salvage_result(spares: int, money: int) -> void:
	if money == 0:
		hud.show_message("Nothing left to salvage here.")
	elif spares > 0:
		hud.show_message("Salvaged %d crowns and %d spares." % [money, spares])
	else:
		hud.show_message("Salvaged %d crowns." % money)


## The server's word for you: in the open shipyard's note, else as a message.
func _on_told(text: String) -> void:
	if shipyard != null:
		shipyard.say(text)
	elif town_panel != null:
		town_panel.say(text)
	elif hud != null:
		hud.show_message(text)


## A shot knocked you down: your controls stop until you come to, KNOCKOUT_TIME later.
func knock_out() -> void:
	if player == null:
		return
	_down_left = WorldSync.KNOCKOUT_TIME
	player.enabled = false
	hud.show_message("You're hit! Back on your feet in %d s." % roundi(WorldSync.KNOCKOUT_TIME))


## You come to at a bunk of the ship you're on (ashore, wherever recover finds),
## with your controls unless a menu is open.
func _come_to() -> void:
	recover(ship, true)
	player.enabled = shipyard == null and not _pause.visible


## Puts you aboard the first of prefer, your own ship and the home ship that's still
## here and not a wreck, at its respawn spot when at_bunk, else at your roster slot,
## and returns it. With none, you stand on the quay of quay_town (the town nearest you
## when it's below 0), and get null.
func recover(prefer: Ship, at_bunk := false, quay_town := -1) -> Ship:
	for next: Variant in [prefer, sync.ship_of(multiplayer.get_unique_id(), false), sync.home_ship()]:
		if is_instance_valid(next) and sync.id_of(next) != 0 and not (next as Ship).is_wreck():
			var on: Ship = next
			come_aboard(on, on.respawn_spot() if at_bunk else on.crew_spawn(my_slot()))
			return on
	var town := quay_town if quay_town >= 0 else _nearest_town(player.world_position())
	come_ashore(Dock.quay_spot(gen.towns[town]["dock"]))
	return null


## The index of the town whose dock is nearest p.
func _nearest_town(p: Vector3) -> int:
	var best := 0
	for i in gen.towns.size():
		if (gen.towns[i]["dock"] as Vector3).distance_to(p) < (gen.towns[best]["dock"] as Vector3).distance_to(p):
			best = i
	return best


## Opens the shipyard on your design, when you're at a dock or dock_only is off. Off, it
## stays with the town it was last opened at, as when you're back from a test flight.
func open_shipyard(dock_only := true) -> void:
	if shipyard != null or player == null:
		return
	if dock_only and not at_dock():
		hud.show_message("The shipyard is at the dock.")
		return
	if dock_only:
		_yard_town = _town_here()
	if map != null and map.visible:
		_toggle_map()  # or it would be back when the shipyard closes
	if design == null:
		design = ShipDesign.new(ship.grid if ship != null else StarterShip.build())
	shipyard = Shipyard.new(design, (gen.towns[_yard_town]["dock"] as Vector3).y)
	shipyard.layer = 3
	shipyard.account = ledger.mine
	shipyard.trade_in = _trade_in()
	shipyard.region = gen.towns[_yard_town]["region"]
	shipyard.test_flight_requested.connect(test_flight)
	shipyard.launch_requested.connect(launch)
	shipyard.unlock_requested.connect(ledger.unlock)
	shipyard.close_requested.connect(close_shipyard)
	add_child(shipyard)
	player.enabled = false
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().disable_3d = true


## What your old ship counts for at a launch: your own ship as this machine has her
## (hit points and spares), else her insurance.
func _trade_in() -> int:
	var own := sync.ship_of(multiplayer.get_unique_id(), false)
	return Economy.value(own.grid, own.spares, own.fuel) if own != null else ledger.mine["insured"]


func _on_account_changed() -> void:
	if shipyard != null:
		shipyard.trade_in = _trade_in()
		shipyard.set_account(ledger.mine)


## Closes the shipyard, keeping the design, and gives you back the controls.
func close_shipyard() -> void:
	if shipyard == null:
		return
	shipyard.queue_free()
	shipyard = null
	player.enabled = _down_left <= 0.0
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_viewport().disable_3d = false


## Opens the town whose dock you're at (aboard or ashore), to do business there.
func open_town() -> void:
	if town_panel != null or shipyard != null or player == null or on_test_flight():
		return
	var town := town_at(player.world_position())
	if town < 0:
		hud.show_message("The market is at the dock.")
		return
	if map != null and map.visible:
		_toggle_map()
	town_panel = TownPanel.new(ledger, town, func() -> Ship: return ship)
	town_panel.layer = 3
	town_panel.close_requested.connect(close_town)
	add_child(town_panel)
	player.enabled = false
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Closes the town, and gives you back the controls.
func close_town() -> void:
	if town_panel == null:
		return
	town_panel.queue_free()
	town_panel = null
	player.enabled = _down_left <= 0.0
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Gives your controls to crew, and lets the crew member you had go.
func _swap_crew(crew: CrewMember) -> void:
	var old := player.crew
	player.board(crew)
	old.queue_free()


## The shipyard's town while it's open, else the town you're at, or the first when
## you're not at one.
func _town_here() -> int:
	if shipyard != null:
		return _yard_town
	return maxi(0, town_at(player.world_position())) if player != null else 0


func _on_ship_added(added: Ship) -> void:
	if session.dedicated:
		return
	if added.captain == multiplayer.get_unique_id():
		board(added, 0)
		close_shipyard()  # your test flight or new ship is ready
	elif player == null and added == sync.home_ship():
		board(added)


func _on_ship_removed(removed: Ship, successor: Ship) -> void:
	if removed.lost and player != null:
		_on_ship_lost(removed)
		if _abandoning and removed.captain == multiplayer.get_unique_id():
			_abandoning = false
			if ship == null:
				recover(null)  # ashore: back to a quay, as from aboard her
	if ship == null and player != null and removed.test and removed.captain == multiplayer.get_unique_id():
		recover(_came_from, false, _yard_town)  # off your test flight: back where you flew from
	if _came_from == removed:
		_came_from = null
	if left == removed:
		left = null
	if ship != removed:
		return
	for next: Ship in [successor, _came_from, sync.ship_of(multiplayer.get_unique_id(), false), sync.home_ship()]:
		if next != null and not next.is_wreck():
			board(next)
			if removed.test and removed.captain == multiplayer.get_unique_id() and not _pause.visible:
				open_shipyard(false)  # back from a test flight
			return
	if removed.lost:
		recover(null)  # nowhere to go: the nearest quay
	else:
		go_ashore()  # nowhere to go: into the air where she was
	left = null


## The Roil took removed. Her captain's shipyard gets her blueprint, to launch her
## again whole (a test flight is only ended); anyone else aboard is told. Wrecks
## nobody owned, and pirates, go without a word.
func _on_ship_lost(removed: Ship) -> void:
	if removed.pirate or (removed.is_wreck() and removed.captain == 0):
		return
	if removed.captain == multiplayer.get_unique_id() and not removed.test:
		design = ShipDesign.new(removed.blueprint)
		if _abandoning:
			hud.show_message("You abandon ship. The shipyard has her blueprint, and her insurance pays half of her.")
		else:
			hud.show_message("Your ship is lost to the Roil. The shipyard has her blueprint, and her insurance pays half of her.")
	elif ship == removed:
		hud.show_message("She's lost to the Roil.")


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().disable_3d = false  # the session can end with the shipyard open


func _unhandled_input(event: InputEvent) -> void:
	if _pause == null:
		return
	if event.is_action_pressed("pause"):
		if shipyard != null:
			close_shipyard()
		elif town_panel != null:
			close_town()
		elif map != null and map.visible:
			_toggle_map()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and shipyard == null and not _pause.visible and map != null:
		_toggle_map()  # M is the shipyard's mirror key too
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("town") and shipyard == null and not _pause.visible:
		if town_panel != null:  # T is the shipyard's tip key too
			close_town()
		else:
			open_town()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shipyard") and not _pause.visible:
		if shipyard != null:
			close_shipyard()
		elif on_test_flight():
			sync.end_test()
		else:
			open_shipyard()
		get_viewport().set_input_as_handled()


func _toggle_map() -> void:
	map.visible = not map.visible
	hud.map_open = map.visible


## Where you are and which way you face, for the map: your ship's heading aboard,
## the way you look ashore.
func _you() -> Array:
	var facing := -player.camera.global_basis.z
	var heading := ship.heading() if ship != null else atan2(-facing.x, -facing.z)
	return [player.world_position(), heading]


func _build_pause_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var center := CenterContainer.new()
	center.theme = UiTheme.build()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	_pause = PanelContainer.new()
	_pause.visible = false
	center.add_child(_pause)
	var column := VBoxContainer.new()
	_pause.add_child(column)
	_resume = UiTheme.button("Resume", _toggle_pause)
	column.add_child(_resume)
	_abandon = UiTheme.button("Abandon ship", _on_abandon_pressed)
	column.add_child(_abandon)
	_save_button = UiTheme.button("Save game", _save_from_menu)
	column.add_child(_save_button)
	column.add_child(UiTheme.button("Leave game", leave_game))
	_pause_note = UiTheme.caption("")
	column.add_child(_pause_note)
	column.add_child(UiTheme.caption("World seed %d" % session.world_seed))


## The first press asks again; the second abandons ship.
func _on_abandon_pressed() -> void:
	if _abandon.text == "Abandon ship":
		_abandon.text = "Abandon ship: press again"
		return
	_toggle_pause()
	abandon_ship()


## Leaves the game, autosaving first on a server with a slot.
## ponytail: closing the window leaves without saving; the last autosave is at most five
## minutes old. Save on NOTIFICATION_WM_CLOSE_REQUEST if players lose progress.
func leave_game() -> void:
	_autosave()
	session.leave()


func _save_from_menu() -> void:
	var error := save_game()
	_pause_note.text = "Saved to slot %s." % session.save_slot if error == OK else "Couldn't save (%s)." % error_string(error)


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	_pause_note.text = ""
	_save_button.visible = session.is_server() and not session.save_slot.is_empty()
	_abandon.text = "Abandon ship"
	_abandon.visible = sync.ship_of(multiplayer.get_unique_id(), false) != null
	if player != null:
		player.enabled = not _pause.visible and _down_left <= 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pause.visible else Input.MOUSE_MODE_CAPTURED
	if _pause.visible:
		_resume.grab_focus()
