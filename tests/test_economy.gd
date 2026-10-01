extends TestCase
## The economy's rules (spec §3.6): prices from the world, part costs, what a ship
## is worth and costs to launch, unlocks, contracts, and checking accounts.

var gen := WorldGen.new(NetCase.SEED)


func traded() -> Array[String]:
	var goods: Array[String] = []
	for good: String in Economy.GOODS:
		if Economy.GOODS[good]["price"] > 0:
			goods.append(good)
	return goods


func test_prices_come_from_the_world() -> void:
	var twin := WorldGen.new(NetCase.SEED)
	var other := WorldGen.new(1)
	var differs := false
	for town in gen.towns.size():
		for good: String in Economy.GOODS:
			assert_eq(Economy.price(twin, town, good), Economy.price(gen, town, good), "%s at %d" % [good, town])
			assert_eq(Economy.sell_price(twin, town, good), Economy.sell_price(gen, town, good))
			if town < other.towns.size() and Economy.price(other, town, good) != Economy.price(gen, town, good):
				differs = true
	assert_true(differs, "another world has other prices")


func test_each_town_makes_two_goods_and_wants_two() -> void:
	for town in gen.towns.size():
		var trade := Economy.trade_of(gen, town)
		var makes: Array = trade["makes"]
		var wants: Array = trade["wants"]
		assert_eq(makes.size(), 2)
		assert_eq(wants.size(), 2)
		for good: String in makes:
			assert_false(good in wants, "%s is made and wanted at %d" % [good, town])
		assert_false("mail" in makes or "mail" in wants, "never mail")
		for good in traded():
			var base: int = Economy.GOODS[good]["price"]
			var factor := Economy.MAKES if good in makes else Economy.WANTS if good in wants else 1.0
			var p := Economy.price(gen, town, good)
			assert_true(p >= roundi(base * factor * 0.9) and p <= roundi(base * factor * 1.1),
					"%s at %d costs %d, near %.1f" % [good, town, p, base * factor])


func test_a_market_buys_for_less_than_it_sells() -> void:
	for town in gen.towns.size():
		for good in traded():
			assert_true(Economy.sell_price(gen, town, good) < Economy.price(gen, town, good), "%s at %d" % [good, town])
		assert_eq(Economy.price(gen, town, "mail"), 0)
		assert_eq(Economy.sell_price(gen, town, "mail"), 0)


func test_some_route_pays() -> void:
	for good: String in Economy.trade_of(gen, 0)["makes"]:
		var best := 0
		for town in range(1, gen.towns.size()):
			best = maxi(best, Economy.sell_price(gen, town, good))
		assert_true(best > Economy.price(gen, 0, good), "%s bought at town 0 sells for more somewhere" % good)


func test_a_ship_costs_her_parts_and_a_full_load_of_spares() -> void:
	var grid := ShipGrid.new()
	grid.set_block(Vector3i.ZERO, "frame")
	assert_eq(Economy.cost(grid), 204)
	grid = ShipGrid.new()
	var parts := 0
	var x := 0
	for type: String in Tuning.BLOCKS:
		grid.set_block(Vector3i(x, 0, 0), type)
		parts += Economy.PART_COST[type]
		x += 1
	assert_eq(Economy.cost(grid), parts + 200)


func test_a_damaged_ship_is_worth_less() -> void:
	var grid := StarterShip.build()
	var whole := Economy.cost(grid)
	assert_eq(Economy.value(grid, 40), whole)
	var frame: Vector3i = grid.cells_of("frame")[0]
	grid.blocks[frame]["hp"] = 50
	assert_eq(Economy.value(grid, 40), whole - 2)
	assert_eq(Economy.value(grid, 30), whole - 52)
	grid.blocks.erase(grid.cells_of("cannon")[0])
	assert_eq(Economy.value(grid, 30), whole - 112)


func test_launch_costs_the_parts_less_her_trade_in() -> void:
	var starter := StarterShip.build()
	var worth := Economy.value(starter, 40)
	assert_eq(Economy.launch_cost(starter, worth), 0, "relaunching her whole")
	assert_eq(Economy.launch_cost(starter, worth - 52), 52, "relaunching her damaged")
	var armoured := StarterShip.build()
	for z in range(-4, 6):
		armoured.set_block(Vector3i(0, -2, z), "iron")
	assert_eq(Economy.launch_cost(armoured, worth), 120, "ten iron plates more")
	var skiff := StarterShip.build()
	for cell in skiff.cells_of("balloon"):
		if absi(cell.z) > 1:
			skiff.blocks.erase(cell)
	assert_eq(Economy.launch_cost(skiff, worth), 0, "a smaller ship pays nothing back")
	assert_eq(Economy.launch_cost(starter, 0), Economy.cost(starter), "no trade-in")
	var insured := roundi(Economy.INSURANCE * Economy.cost(starter))
	assert_eq(Economy.launch_cost(starter, insured), Economy.cost(starter) - insured, "against her insurance")


func test_alloy_and_lift_stones_are_locked() -> void:
	assert_eq(Economy.locked(StarterShip.build(), []), [])
	var grid := StarterShip.build()
	grid.set_block(Vector3i(0, -2, 0), "lift_stone")
	grid.set_block(Vector3i(0, -2, 1), "alloy")
	assert_eq(Economy.locked(grid, []), ["alloy", "lift_stone"])
	assert_eq(Economy.locked(grid, ["alloy"]), ["lift_stone"])


func test_unlocks_are_sold_further_in() -> void:
	assert_false(Economy.unlockable_at("alloy", WorldGen.Region.CALM))
	assert_true(Economy.unlockable_at("alloy", WorldGen.Region.SHATTERED))
	assert_true(Economy.unlockable_at("alloy", WorldGen.Region.GALE))
	assert_false(Economy.unlockable_at("lift_stone", WorldGen.Region.SHATTERED))
	assert_true(Economy.unlockable_at("lift_stone", WorldGen.Region.GALE))
	for region in WorldGen.Region.values():
		assert_false(Economy.unlockable_at("iron", region), "iron is never sold")


## Indices of entries (with their place under key, or through place_of) nearest from, nearest first.
func nearest(entries: Array, from: Vector3, place_of: Callable, skip := -1) -> Array:
	var order := []
	for i in entries.size():
		if i != skip:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da := from.distance_to(place_of.call(entries[a]))
		var db := from.distance_to(place_of.call(entries[b]))
		return da < db or (da == db and a < b))
	return order


func test_contracts_are_drawn_from_the_world() -> void:
	var dock: Vector3 = gen.towns[0]["dock"]
	var home: String = gen.towns[0]["name"]
	var towns := nearest(gen.towns, dock, func(t: Dictionary) -> Vector3: return t["dock"], 0).slice(0, 3)
	var wrecks_all := nearest(gen.wrecks, dock, func(w: Dictionary) -> Vector3: return Sites.wreck_center(w))
	var salvaged := {wrecks_all[0]: true}
	var wrecks := wrecks_all.slice(1, 4)
	var marks := nearest(gen.landmarks, dock, func(l: Dictionary) -> Vector3: return l["at"]).slice(0, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var drawn := []
	var kinds := {}
	for i in 200:
		var c := Economy.draw_contract(gen, 0, salvaged, rng)
		drawn.append(c)
		kinds[c["kind"]] = true
		assert_eq(c["done"], 0)
		match c["kind"]:
			"delivery":
				assert_true(c["target"] in towns, "to a near town")
				assert_true(c["count"] >= 1 and c["count"] <= 3)
				var to: Dictionary = gen.towns[c["target"]]
				var km := dock.distance_to(to["dock"]) / 1000.0
				assert_eq(c["reward"], c["count"] * (Economy.DELIVERY_BASE + roundi(Economy.DELIVERY_PER_KM * km)))
				var title := "Carry a crate of mail to %s" % to["name"] if c["count"] == 1 else "Carry %d crates of mail to %s" % [c["count"], to["name"]]
				assert_eq(c["title"], title)
			"bounty":
				assert_true(c["count"] == 1 or c["count"] == 2)
				assert_eq(c["reward"], c["count"] * 250)
				assert_eq(c["target"], -1)
				assert_eq(c["title"], "Sink a pirate" if c["count"] == 1 else "Sink %d pirates" % c["count"])
			"salvage":
				assert_true(c["target"] in wrecks, "a near wreck, not the salvaged one (%d)" % c["target"])
				var at := Sites.wreck_center(gen.wrecks[c["target"]])
				var km := dock.distance_to(at) / 1000.0
				assert_eq(c["reward"], Economy.SALVAGE_BASE + roundi(Economy.SALVAGE_PER_KM * km))
				assert_eq(c["title"], "Salvage the wreck %.1f km %s of %s" % [km, Economy.bearing_word(dock, at), home])
				assert_eq(c["count"], 1)
			"scout":
				assert_true(c["target"] in marks, "a near landmark")
				var mark: Dictionary = gen.landmarks[c["target"]]
				var km := dock.distance_to(mark["at"]) / 1000.0
				assert_eq(c["reward"], Economy.SCOUT_BASE + roundi(Economy.SCOUT_PER_KM * km))
				assert_eq(c["title"], "Scout %s, %.1f km %s of %s" % [mark["name"], km, Economy.bearing_word(dock, mark["at"]), home])
				assert_eq(c["count"], 1)
	assert_eq(kinds.size(), 4, "every kind: %s" % [kinds.keys()])
	rng.seed = 1
	for i in 200:
		assert_eq(Economy.draw_contract(gen, 0, salvaged, rng), drawn[i], "the same draw %d" % i)


func test_accounts_and_contracts_are_checked() -> void:
	var account := Economy.new_account()
	assert_eq(Economy.read_account(account), account)
	var floats := {"money": 1500.0, "unlocks": [], "contracts": [], "insured": 0.0}
	assert_eq(Economy.read_account(floats), account, "whole floats read as ints")
	assert_eq(typeof(Economy.read_account(floats)["money"]), TYPE_INT)
	var contract := {"id": 1, "kind": "bounty", "title": "Sink a pirate", "reward": 250, "target": -1, "count": 1, "done": 0}
	var with_one := Economy.new_account()
	with_one["contracts"] = [contract]
	with_one["unlocks"] = ["alloy"]
	assert_eq(Economy.read_account(with_one), with_one)
	assert_eq(Economy.read_contract(contract), contract)
	for change: Array in [["money", -1], ["money", "5"], ["money", 1.5], ["unlocks", ["gold"]], ["unlocks", ["alloy", "alloy"]],
			["contracts", [contract, contract, contract, contract]], ["insured", -3]]:
		var bad := with_one.duplicate(true)
		bad[change[0]] = change[1]
		assert_eq(Economy.read_account(bad), null, "%s" % [change])
	for change: Array in [["kind", "heist"], ["title", "x".repeat(121)], ["done", 2], ["count", 0], ["reward", 100001]]:
		var bad := contract.duplicate()
		bad[change[0]] = change[1]
		assert_eq(Economy.read_contract(bad), null, "%s" % [change])
	var no_id := contract.duplicate()
	no_id.erase("id")
	assert_eq(Economy.read_contract(no_id), null, "no id")
	assert_eq(Economy.read_account("junk"), null)
	assert_eq(Economy.read_contract([1]), null)


func test_bearing_words() -> void:
	assert_eq(Economy.bearing_word(Vector3.ZERO, Vector3(0, 0, -100)), "N")
	assert_eq(Economy.bearing_word(Vector3.ZERO, Vector3(100, 0, 0)), "E")
	assert_eq(Economy.bearing_word(Vector3.ZERO, Vector3(-100, 0, 100)), "SW")
