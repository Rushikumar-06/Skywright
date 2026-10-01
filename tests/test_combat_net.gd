extends NetCase
## A battle on two machines (spec §4.6): every shot, hit, break, fire and wreck the
## server decides reaches the guest, who ends up with the same ships, blocks and
## fires; a fight stays inside the network budget; and a dedicated server fights too.

const STARBOARD := Vector3i(2, 1, 1)


## Whether the guest's ships are the host's: the same ids, and for each the same
## blocks (type, rotation, hit points) and the same cells burning.
func agree(host_sync: WorldSync, guest_sync: WorldSync) -> bool:
	if host_sync.ships.keys() != guest_sync.ships.keys():
		return false
	for id: int in host_sync.ships:
		var ours: Ship = host_sync.ships[id]
		var theirs: Ship = guest_sync.ships[id]
		if ours.grid.blocks != theirs.grid.blocks or ours.burning != theirs.burning:
			return false
	return true


## The host's ship and a second ship 200 m to her starboard, in open sky, calm; hers
## anchored, the target not.
func lined_up() -> Ship:
	var ours: Ship = host_world.ship
	ours.calm = true
	ours.anchored = true
	ours.global_position = open_sky(host_world, 1000.0)
	var host_sync: WorldSync = host_world.sync
	var target := host_sync.add_ship(StarterShip.build(), ours.global_transform.translated(Vector3(200, 0, 0)))
	target.calm = true
	return target


## Fires ammo from the host's starboard cannon at target's middle.
func fire_at(target: Ship, ammo: String) -> void:
	var host_sync: WorldSync = host_world.sync
	var ours: Ship = host_world.ship
	var muzzle := ours.global_transform * Vector3(STARBOARD)
	var aim := Projectiles.aim(target.global_transform * target.center_of_mass - muzzle, Damage.AMMO[ammo]["speed"])
	host_sync.fire(ours, STARBOARD, ours.global_basis.inverse() * aim, ammo)


func test_host_and_guest_agree_after_a_broadside() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	host_sync.rng.seed = 1
	var target := lined_up()
	for round_ in 3:
		for ammo: String in Damage.AMMO:
			fire_at(target, ammo)
			await play(1.5)
	await play(8.0)
	assert_true(host_sync.ships.size() >= 2, "both ships are still about")
	assert_true(target.condition() < 1.0, "the target took hits")
	assert_true(await play_until(func() -> bool: return agree(host_sync, client_world.sync), 3.0),
			"the guest has the same ships, blocks and fires as the host")


func test_a_battle_stays_within_the_network_budget() -> void:
	assert_true(await sail_together(), "the ship arrives")
	var host_sync: WorldSync = host_world.sync
	host_sync.rng.seed = 1
	var target := lined_up()
	host_sync.spawn_pirate(host_world.ship)
	var link := (client.multiplayer.multiplayer_peer as ENetMultiplayerPeer).host
	link.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)  # from now on
	for second in 20:
		if second % 2 == 0:
			fire_at(target, Damage.AMMO.keys()[second / 2 % Damage.AMMO.size()])
		await play(1.0)
	var received := link.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	assert_true(received < 20 * 32 * 1024, "%.1f KB/s down, within half the 64 KB/s budget" % (received / 20.0 / 1024.0))


func test_a_dedicated_server_fights_too() -> void:
	host = make_session("Server")
	var port := free_port()
	host.host("Skyport", port, true)
	host_world = add_world(host)
	await get_tree().process_frame
	client = make_session("Client")
	client.join("Guest", "127.0.0.1", port)
	assert_true(await play_until(func() -> bool: return client.sailing, 5.0), "a guest joins")
	client_world = add_world(client)
	assert_true(await play_until(func() -> bool: return client_world.ship != null, 5.0), "and comes aboard")
	assert_true(await heard(host_world, client), "the server hears where they are")
	var guest: PlayerController = client_world.player
	client_world.launch(StarterShip.build())
	var host_sync: WorldSync = host_world.sync
	assert_true(await play_until(func() -> bool: return host_sync.ship_of(guest.peer, false) != null and client_world.ship != null \
			and client_world.ship.captain == guest.peer, 5.0), "the guest launches their own ship")
	var theirs := host_sync.ship_of(guest.peer, false)
	theirs.anchored = true
	theirs.global_position = open_sky(host_world, 1000.0)
	host_sync.rng.seed = 1
	var pirate := host_sync.spawn_pirate(theirs)
	assert_true(pirate != null, "a pirate comes for them")
	var guest_copy: Ship = client_world.sync.ships[host_sync.id_of(theirs)]
	assert_true(await play_until(func() -> bool: return guest_copy.condition() < 1.0, 120.0), "the guest sees their ship hit")
	var shots: Projectiles = host_world.projectiles
	var meshes := shots.get_children().filter(func(child: Node) -> bool: return child is MeshInstance3D)
	assert_eq(meshes, [], "the dedicated server draws no shots")
