extends NetCase
## A leviathan (spec §3.5): a creature, not a ship. It drifts, grows curious about
## ships and paces them without harm, and once shot it rams whoever shot it until it
## calms down or they get away. Slain, it sinks and pays the players near it.

var world: Node3D
var sync: WorldSync
var ledger: Ledger
var ship: Ship
var beasts: Leviathans


## A solo world, your ship anchored in open sky at 1,000 m.
func start() -> void:
	world = solo_world()
	await get_tree().process_frame
	sync = world.sync
	ledger = world.ledger
	ship = world.ship
	beasts = world.leviathans
	sync.rng.seed = 1
	ship.anchored = true
	ship.global_position = open_sky(world, 1000.0)


## One leviathan offset from your ship, facing facing.
func spawn(offset: Vector3, facing := 0.0) -> Leviathan:
	return beasts.spawn("leviathan", ship.global_position + offset, facing)


func test_a_leviathan_drifts() -> void:
	await start()
	var whole := ship.grid.to_blocks()
	var beast := spawn(Vector3(1500, 0, 0))
	var from := beast.global_position
	var heights := [INF, -INF]
	await simulate(60.0, func(_tick: int) -> void:
		heights[0] = minf(heights[0], beast.global_position.y)
		heights[1] = maxf(heights[1], beast.global_position.y))
	assert_true(beast.global_position.distance_to(from) > 300.0, "it moved %.0f m" % beast.global_position.distance_to(from))
	assert_true(heights[0] >= Leviathan.LOW and heights[1] <= Leviathan.HIGH, "between %.0f and %.0f m" % heights)
	assert_eq(beast.mood, "drift")
	assert_eq(ship.grid.to_blocks(), whole, "your ship is whole")


func test_a_leviathan_is_curious_and_harmless() -> void:
	await start()
	var whole := ship.grid.to_blocks()
	var beast := spawn(Vector3(500, 0, -100), PI / 2.0)  # swimming across your bow
	assert_true(await simulate_until(func() -> bool:
		return beast.mood == "curious" and beast.global_position.distance_to(ship.global_position) < 200.0, 60.0), "it comes to look")
	await simulate(60.0)
	assert_eq(ship.grid.to_blocks(), whole, "and never harms her")


func test_shots_hurt_and_anger_a_leviathan() -> void:
	await start()
	var beast := spawn(Vector3(200, 0, 0))
	beast.held = true
	var cell := Vector3i(2, 1, 1)
	var muzzle := ship.global_transform * Vector3(cell)
	var aim := Projectiles.aim(beast.global_position - muzzle, Damage.AMMO["round"]["speed"])
	sync.fire(ship, cell, ship.global_basis.inverse() * aim, "round")
	assert_true(await simulate_until(func() -> bool: return beast.hp < 2000, 3.0), "hit")
	assert_eq(beast.hp, 1840)
	assert_eq(beast.mood, "angry")
	assert_eq(beast.target, ship)


func test_an_angry_leviathan_rams() -> void:
	await start()
	var count := ship.grid.blocks.size()
	var beast := spawn(Vector3(300, 0, 0))
	beast.hurt(0, ship)
	assert_true(await simulate_until(func() -> bool: return ship.grid.blocks.size() < count, 40.0), "it rams her")
	count = ship.grid.blocks.size()
	assert_true(await simulate_until(func() -> bool: return ship.grid.blocks.size() < count, 30.0), "backs off, turns and rams again")


func test_a_ram_knocks_down_crew_nearby() -> void:
	await start()
	var knocks := [0]
	sync.knocked_out.connect(func() -> void: knocks[0] += 1)
	var you: Vector3 = world.player.world_position()
	sync.ram(ship, you + ship.global_basis.z * 20.0, 3.0, 120.0, Vector3.ZERO)
	assert_eq(knocks[0], 0, "20 m off, you stay up")
	var before := ship.grid.to_blocks()
	sync.ram(ship, you, 3.0, 120.0, Vector3.ZERO)
	assert_eq(knocks[0], 1, "knocked down")
	assert_true(ship.grid.to_blocks() != before, "and the blocks around you hurt")


func test_an_angry_leviathan_calms_down() -> void:
	await start()
	var beast := spawn(Vector3(300, 0, 0))
	beast.hurt(0, ship)
	await simulate(Leviathan.CALM_AFTER + 1.0)
	assert_eq(beast.mood, "drift", "calm again")
	assert_eq(beast.target, null)
	beast.hurt(0, ship)
	assert_eq(beast.mood, "angry")
	ship.global_position += Vector3(2000, 0, 0)
	assert_true(await simulate_until(func() -> bool: return beast.mood == "drift", 1.0), "she got away")


func test_a_slain_leviathan_sinks_and_pays() -> void:
	await start()
	var beast := spawn(Vector3(300, 0, 0))
	var money: int = ledger.mine["money"]
	for i in 13:
		beasts.shot(beast, "round", ship)
	assert_eq(beast.mood, "slain")
	assert_eq(ledger.mine["money"], money + 300)
	assert_eq(world.hud._message.text, "The leviathan falls. +300 crowns.")
	var id: Variant = beasts.beasts.find_key(beast)
	await simulate(Leviathan.SLAIN_TIME + 0.5)
	assert_false(beasts.beasts.has(id), "gone")
	sync.add_ship(StarterShip.build(), ship.global_transform.translated(Vector3(0, 0, 100)), 1, true)  # a test flight of yours
	var second := spawn(Vector3(300, 0, 0))
	for i in 13:
		beasts.shot(second, "round", ship)
	assert_eq(second.mood, "slain")
	assert_eq(ledger.mine["money"], money + 300, "nothing on a test flight")
