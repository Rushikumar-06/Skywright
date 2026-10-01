extends NetCase
## The campaign's rules (spec §3.5–3.7): one region table for danger and reward, the
## story's twelve logs and where they're found, and the Wallbreaker a log gives.

const INWARD := [WorldGen.Region.CALM, WorldGen.Region.SHATTERED, WorldGen.Region.GALE, WorldGen.Region.STORMWALL, WorldGen.Region.EYE]

var gen := WorldGen.new(NetCase.SEED)


func pirates(sync: WorldSync) -> Array:
	return sync.ships.values().filter(func(each: Ship) -> bool: return each.pirate)


func test_the_regions_get_harder_further_in() -> void:
	for i in range(1, INWARD.size()):
		var outer: Dictionary = Campaign.REGIONS[INWARD[i - 1]]
		var inner: Dictionary = Campaign.REGIONS[INWARD[i]]
		assert_true(inner["rewards"] >= outer["rewards"], "rewards in %s" % WorldGen.REGION_NAMES[INWARD[i]])
		assert_true(inner["prices"] >= outer["prices"], "prices in %s" % WorldGen.REGION_NAMES[INWARD[i]])
	for region in [WorldGen.Region.EYE, WorldGen.Region.STORMWALL, WorldGen.Region.RIM]:
		assert_eq(Campaign.REGIONS[region]["raids"], 0.0, "no raids in %s" % WorldGen.REGION_NAMES[region])
	for region in WorldGen.REGION_NAMES.size():
		var row: Dictionary = Campaign.REGIONS[region]
		var gale := region == WorldGen.Region.GALE
		assert_eq(row["leviathans"] > 0, gale, "leviathans in %s" % WorldGen.REGION_NAMES[region])
		assert_eq(row["spawn"] > 0.0, gale, "spawns in %s" % WorldGen.REGION_NAMES[region])
		assert_eq(row["strikes"] > 0.0, gale or region == WorldGen.Region.STORMWALL, "strikes in %s" % WorldGen.REGION_NAMES[region])
	assert_true(Campaign.REGIONS[WorldGen.Region.STORMWALL]["strikes"] > Campaign.REGIONS[WorldGen.Region.GALE]["strikes"])
	assert_eq(Campaign.of(Vector3(0, 1000, -1900)), Campaign.REGIONS[WorldGen.Region.STORMWALL])


func test_prices_rise_further_in() -> void:
	for town in gen.towns.size():
		var prices: float = Campaign.REGIONS[gen.towns[town]["region"]]["prices"]
		var trade := Economy.trade_of(gen, town)
		for good: String in Economy.GOODS:
			var base: int = Economy.GOODS[good]["price"]
			if base == 0:
				continue
			var factor := Economy.MAKES if good in trade["makes"] else Economy.WANTS if good in trade["wants"] else 1.0
			var price := Economy.price(gen, town, good)
			assert_true(price >= roundi(base * factor * 0.9 * prices) and price <= roundi(base * factor * 1.1 * prices),
					"%s at town %d: %d" % [good, town, price])
			assert_true(Economy.sell_price(gen, town, good) < price)
	# Town 0 (the Calm Reaches) charges what stage 7 charged.
	var trade := Economy.trade_of(gen, 0)
	for good: String in ["grain", "timber", "cloth", "tools", "spirits"]:
		var factor := Economy.MAKES if good in trade["makes"] else Economy.WANTS if good in trade["wants"] else 1.0
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([gen.world_seed, 0, good, "price"])
		var stage_7 := maxi(1, roundi(Economy.GOODS[good]["price"] * factor * (1.0 + rng.randf_range(-Economy.PRICE_NOISE, Economy.PRICE_NOISE))))
		assert_eq(Economy.price(gen, 0, good), stage_7, good)


## The stage 7 reward of a delivery or a bounty drawn at town, or -1 for other kinds.
func plain_reward(town: int, contract: Dictionary) -> int:
	match contract["kind"]:
		"bounty":
			return contract["count"] * Economy.BOUNTY_PAY
		"delivery":
			var km: float = (gen.towns[town]["dock"] as Vector3).distance_to(gen.towns[contract["target"]]["dock"]) / 1000.0
			return contract["count"] * (Economy.DELIVERY_BASE + roundi(Economy.DELIVERY_PER_KM * km))
	return -1


func test_contracts_pay_more_further_in() -> void:
	assert_eq(gen.towns[7]["region"], WorldGen.Region.GALE, "town 7 is the first Gale town")
	for town in [7, 0]:
		var rewards: float = Campaign.REGIONS[gen.towns[town]["region"]]["rewards"]
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var checked := 0
		for i in 200:
			var contract := Economy.draw_contract(gen, town, {}, rng)
			var plain := plain_reward(town, contract)
			if plain < 0:
				continue
			checked += 1
			assert_eq(contract["reward"], roundi(plain * rewards), "%s at town %d" % [contract["title"], town])
			if contract["kind"] == "bounty":
				assert_eq(contract["reward"], contract["count"] * (400 if town == 7 else 250))
		assert_true(checked > 50, "%d checked" % checked)


func test_accounts_keep_their_logs() -> void:
	assert_eq(Economy.new_account()["logs"], [])
	var account := Economy.new_account()
	account["logs"] = [0, 5]
	assert_eq(Economy.read_account(account)["logs"], [0, 5])
	account["logs"] = [0.0, 5.0]
	var read: Dictionary = Economy.read_account(account)
	assert_eq(read["logs"], [0, 5])
	assert_true(read["logs"][0] is int, "ints")
	account.erase("logs")
	assert_eq(Economy.read_account(account)["logs"], [], "a stage 7 account")
	for junk: Variant in [[12], [-1], [1, 1], ["2"], 2.5]:
		account["logs"] = junk
		assert_eq(Economy.read_account(account), null, str(junk))


func test_the_story_is_placed_in_the_world() -> void:
	assert_eq(Story.LOGS.size(), 12)
	var titles := {}
	for i in Story.LOGS.size():
		var entry: Dictionary = Story.LOGS[i]
		assert_true(entry["title"].length() <= 40 and entry["text"].length() <= 600, entry["title"])
		titles[entry["title"]] = true
		var spot: Variant = Story.spot(gen, i)
		match entry["at"]:
			"landmark":
				var landmark: Dictionary = gen.landmarks[entry["index"]]
				var foot: Vector3 = landmark["at"] + Vector3(0, IslandMesh.height(landmark["island"], 0, 0), 0)
				assert_eq(spot, foot, entry["title"])
			"town":
				assert_eq(spot, Dock.quay_spot(gen.towns[entry["index"]]["dock"]), entry["title"])
			"heart":
				assert_eq(i, Story.HEART_LOG)
				assert_eq(spot, null)
	assert_eq(titles.size(), 12, "distinct titles")
	var unlocks := range(12).filter(func(i: int) -> bool: return Story.LOGS[i]["unlocks"] != "")
	var blueprints := range(12).filter(func(i: int) -> bool: return Story.LOGS[i]["blueprint"] != "")
	assert_eq(unlocks, [3])
	assert_eq(Story.LOGS[3]["unlocks"], "alloy")
	assert_eq(blueprints, [5])
	assert_eq(Story.blueprints([5]), ["Wallbreaker"])
	assert_eq(Story.blueprints([0, 3]), [])
	assert_eq(Story.blueprint("Wallbreaker").to_blocks(), Wallbreaker.build().to_blocks())


func test_the_wallbreaker_flies() -> void:
	var grid := Wallbreaker.build()
	var stats := ShipStats.of(grid, 880.0)
	assert_near(stats.thrust, 10000.0, 1.0, "thrust")
	assert_true(stats.top_speed > 27.0, "top speed %.1f" % stats.top_speed)
	assert_eq(stats.warnings, PackedStringArray())
	assert_true(stats.float_altitude > 950.0 and stats.float_altitude < 1050.0, "floats at %.0f m" % stats.float_altitude)
	assert_true(absf(stats.list) < 0.1, "list %.2f" % stats.list)
	assert_true(absf(stats.bow_down) < 1.0, "trim %.2f" % stats.bow_down)
	assert_eq(grid.cells_of("helm").size(), 1)
	assert_eq(grid.cells_of("engine").size(), 2)
	assert_eq(grid.cells_of("propeller").size(), 4)
	assert_eq(grid.paint, {"balloon": Color("2f5d8a")})


func test_raids_follow_the_table() -> void:
	var world := solo_world()
	await get_tree().process_frame
	var sync: WorldSync = world.sync
	var ship: Ship = world.ship
	world.session.pirates = true
	sync.rng.seed = 1
	ship.anchored = true
	open_sky(world, 1000.0)
	ship.global_position = Vector3(0, 1000, -3000)
	for i in 40:
		sync._raid()
	assert_eq(pirates(sync).size(), 2, "the Gale Expanse's limit")
	for spot in [Vector3(0, 1000, -1900), Vector3(0, 1000, -1000)]:
		for pirate: Ship in pirates(sync):
			sync.remove_ship(pirate, null, true)
		ship.global_position = spot
		for i in 40:
			sync._raid()
		assert_eq(pirates(sync).size(), 0, "none in %s" % WorldGen.REGION_NAMES[WorldGen.region_at(spot)])
