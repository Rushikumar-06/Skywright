extends NetCase
## Abandon ship (spec §3.3): a stranded captain gives up their own ship from the pause
## menu (pressing twice). She's lost, insured like a sunk ship, and they wake on the
## nearest town's quay, as anyone does at once when the ship they're on is lost.

const ABANDONED := "You abandon ship. The shipyard has her blueprint, and her insurance pays half of her."
const LOST := "Your ship is lost to the Roil. The shipyard has her blueprint, and her insurance pays half of her."

var world: Node3D
var sync: WorldSync
var ship: Ship
var player: PlayerController


## A solo world, your ship anchored in open sky.
func start() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ship = world.ship
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)
	player = world.player


func abandon_button() -> Button:
	for node in world._pause.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with("Abandon ship"):
			return node
	return null


## The quay of the town whose dock is nearest p.
func quay_near(p: Vector3) -> Vector3:
	var best: Dictionary = world.gen.towns[0]
	for town: Dictionary in world.gen.towns:
		if (town["dock"] as Vector3).distance_to(p) < (best["dock"] as Vector3).distance_to(p):
			best = town
	return Dock.quay_spot(best["dock"])


func on_quay(spot: Vector3) -> bool:
	return player.ship == null and player.crew.is_on_floor() and player.world_position().distance_to(spot) < 3.0


func test_abandoning_ship_puts_you_on_the_nearest_quay() -> void:
	await start()
	var quay := quay_near(player.world_position())
	world._toggle_pause()
	var button := abandon_button()
	assert_true(button != null and button.visible, "Abandon ship is in the pause menu")
	button.pressed.emit()
	assert_eq(button.text, "Abandon ship: press again")
	assert_true(sync.id_of(ship) != 0, "not yet")
	button.pressed.emit()
	assert_eq(sync.id_of(ship), 0, "she's gone")
	assert_true(await wait_until(func() -> bool: return on_quay(quay), 2.0), "you wake on the nearest quay")
	assert_eq(world.hud._message.text, ABANDONED)
	assert_eq(world.design.grid.blocks, StarterShip.build().blocks, "the shipyard has her blueprint")


func test_an_abandoned_ship_is_insured() -> void:
	await start()
	world.abandon_ship()
	assert_eq(world.ledger.mine["insured"], 740)


func test_a_wrecked_ship_can_be_abandoned_from_ashore() -> void:
	await start()
	sync.damage_ship(ship, {ship.grid.cells_of("helm")[0]: 0})
	world.go_ashore()
	player.crew.position = ship.global_position + Vector3(2000, 0, 0)
	player.crew.velocity = Vector3.ZERO
	var quay := quay_near(player.crew.position)
	await get_tree().process_frame
	world.abandon_ship()
	assert_true(await wait_until(func() -> bool: return on_quay(quay), 2.0), "you wake on the quay nearest you")
	assert_eq(world.hud._message.text, ABANDONED)


func test_the_abandon_button_needs_a_ship_of_your_own() -> void:
	await start()
	world.abandon_ship()
	world._toggle_pause()
	assert_false(abandon_button().visible, "no ship of your own, nothing to abandon")
	world._toggle_pause()
	assert_true(await wait_until(func() -> bool: return player.crew.is_on_floor(), 2.0), "on the quay")
	world.test_flight(StarterShip.build())
	assert_true(world.on_test_flight(), "on a test flight")
	world._toggle_pause()
	assert_false(abandon_button().visible, "a test flight isn't yours to abandon")


func test_losing_a_ship_puts_you_on_the_quay_at_once() -> void:
	await start()
	var quay := quay_near(player.world_position())
	ship.global_position.y = -5.0
	sync._wear()
	assert_eq(sync.id_of(ship), 0, "lost")
	assert_true(player.ship == null and player.world_position().distance_to(quay) < 3.0, "on the quay at once")
	await simulate(1.0)
	assert_true(on_quay(quay), "standing there, no fall")
	assert_eq(world.hud._message.text, LOST, "the loss message stays")
	assert_true(world.hud._message.visible)


func test_a_guest_can_abandon_only_their_own_ship() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	var count := host_sync.ships.size()
	client_world.sync._abandon.rpc_id(1)
	await play(0.3)
	assert_eq(host_sync.ships.size(), count, "no ship of their own, nothing gone")
	var guest := client.multiplayer.get_unique_id()
	client_world.launch(StarterShip.build())
	assert_true(await play_until(func() -> bool: return host_sync.ship_of(guest, false) != null, 2.0), "the guest's own ship")
	client_world.sync._abandon.rpc_id(1)
	assert_true(await play_until(func() -> bool: return host_sync.ship_of(guest, false) == null, 2.0), "abandoned")
	assert_true(host_sync.id_of(ours) != 0, "the host's ship stays")
