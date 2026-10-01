class_name Economy
## The economy's rules, node-free so the server, the shipyard and tests can share them
## (spec §3.6): goods and each town's prices, part costs, what a ship is worth and
## costs to launch, unlocks, hired hands, insurance, contracts, and checking accounts.

const STARTING_MONEY := 1500

## The keys' order is the market's. A price of 0 means it's never traded: mail is a
## contract's crates.
const GOODS := {
	"grain": {"name": "Grain", "price": 20},
	"timber": {"name": "Timber", "price": 32},
	"cloth": {"name": "Cloth", "price": 48},
	"tools": {"name": "Tools", "price": 70},
	"spirits": {"name": "Spirits", "price": 95},
	"mail": {"name": "Mail", "price": 0},
}
const MAKES := 0.6        ## A town sells what it makes for less...
const WANTS := 1.5        ## ...and pays more for what it wants.
const PRICE_NOISE := 0.1
const SELL_SHARE := 0.85  ## What a market pays, as a share of what it charges.

## Crowns a block costs at the shipyard.
const PART_COST := {"frame": 4, "deck": 3, "iron": 12, "alloy": 30, "balloon": 2, "lift_stone": 150, "engine": 80,
		"propeller": 20, "rudder": 10, "sail": 6, "fuel_tank": 20, "ballast_tank": 15, "helm": 40, "cannon": 60,
		"cargo_bay": 10, "bunk": 8, "ladder": 2}
const SPARE_PRICE := 5
const INSURANCE := 0.5  ## A lost ship pays this share of her cost.

## Parts bought once with money, at towns in region or further in.
const UNLOCKS := {
	"alloy": {"price": 2000, "region": WorldGen.Region.SHATTERED},
	"lift_stone": {"price": 4000, "region": WorldGen.Region.GALE},
}

const HANDS := {
	"gunner": {"name": "gunner", "fee": 150},
	"repairer": {"name": "repairer", "fee": 120},
	"engineer": {"name": "engineer", "fee": 200},
}
const HAND_NAMES := ["Fenn", "Marta", "Osric", "Ilse", "Bram", "Tove", "Cass", "Joss", "Wren", "Edda", "Rook", "Sable"]

const SALVAGE_MONEY := 150  ## A world wreck's loot.
const SCRAP_MONEY := 1      ## A crown a block, breaking up a wreck.

const MAX_CONTRACTS := 3
const BOARD_SIZE := 3
const NEARBY := 3  ## Contracts go to one of the town's NEARBY nearest targets.
const KINDS := ["delivery", "bounty", "salvage", "scout"]
const DELIVERY_BASE := 30    ## A crate.
const DELIVERY_PER_KM := 40  ## A crate.
const BOUNTY_PAY := 250      ## A pirate.
const SALVAGE_BASE := 100
const SALVAGE_PER_KM := 50
const SCOUT_BASE := 80
const SCOUT_PER_KM := 50
const SCOUT_REACH := 400.0
const BOUNTY_REACH := 1500.0

const LEVIATHAN_REWARD := 300  ## Each player near a slain leviathan.
const WARDEN_REWARD := 2000     ## Each player near the Warden when it falls.

const MAX_TITLE := 120
const MAX_REWARD := 100000
const MAX_COUNT := 64


## role's name with its article: "a gunner", "an engineer".
static func a_hand(role: String) -> String:
	var hand_name: String = HANDS[role]["name"]
	return ("an " if hand_name[0] in "aeiou" else "a ") + hand_name


static func new_account() -> Dictionary:
	return {"money": STARTING_MONEY, "unlocks": [], "contracts": [], "insured": 0, "logs": []}


## What town makes (sold cheap) and wants (bought dear): two goods each, from the world seed.
static func trade_of(gen: WorldGen, town: int) -> Dictionary:
	var goods: Array[String] = []
	for good: String in GOODS:
		if GOODS[good]["price"] > 0:
			goods.append(good)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([gen.world_seed, town, "market"])
	for i in range(goods.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := goods[i]
		goods[i] = goods[j]
		goods[j] = swap
	return {"makes": goods.slice(0, 2), "wants": goods.slice(2, 4)}


## What a crate of good costs at town: dearer further in, by its region's prices.
static func price(gen: WorldGen, town: int, good: String) -> int:
	var base: int = GOODS[good]["price"]
	if base == 0:
		return 0
	var trade := trade_of(gen, town)
	var factor := MAKES if good in trade["makes"] else WANTS if good in trade["wants"] else 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([gen.world_seed, town, good, "price"])
	var prices: float = Campaign.REGIONS[gen.towns[town]["region"]]["prices"]
	return maxi(1, roundi(base * factor * (1.0 + rng.randf_range(-PRICE_NOISE, PRICE_NOISE)) * prices))


## What town's market pays for a crate of good.
static func sell_price(gen: WorldGen, town: int, good: String) -> int:
	return roundi(price(gen, town, good) * SELL_SHARE)


## A new ship's price: her parts and a full load of spares.
static func cost(grid: ShipGrid) -> int:
	var total := Damage.SPARES_MAX * SPARE_PRICE
	for cell: Vector3i in grid.blocks:
		total += PART_COST[grid.blocks[cell]["type"]]
	return total


## What a ship is worth as she is: her parts by their hit points, and her spares.
static func value(grid: ShipGrid, spares: int) -> int:
	var total := float(spares * SPARE_PRICE)
	for cell: Vector3i in grid.blocks:
		var block: Dictionary = grid.blocks[cell]
		total += float(PART_COST[block["type"]]) * block["hp"] / Tuning.BLOCKS[block["type"]]["hp"]
	return roundi(total)


## What launching design costs, trading in a ship worth trade_in. A smaller ship pays nothing back.
static func launch_cost(design: ShipGrid, trade_in: int) -> int:
	return maxi(0, cost(design) - trade_in)


## The parts grid uses that aren't in unlocks, sorted.
static func locked(grid: ShipGrid, unlocks: Array) -> Array[String]:
	var found: Array[String] = []
	for cell: Vector3i in grid.blocks:
		var type: String = grid.blocks[cell]["type"]
		if UNLOCKS.has(type) and not unlocks.has(type) and not found.has(type):
			found.append(type)
	found.sort()
	return found


## Whether part is sold at towns in region (regions count inward from the Eye, 0).
static func unlockable_at(part: String, region: int) -> bool:
	return UNLOCKS.has(part) and region <= UNLOCKS[part]["region"]


## A new contract on town's board, without its id: {kind, title, reward, target, count,
## done}. It pays more further in, by its town's region's rewards.
static func draw_contract(gen: WorldGen, town: int, salvaged: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var contract := _plain_contract(gen, town, salvaged, rng)
	contract["reward"] = roundi(contract["reward"] * Campaign.REGIONS[gen.towns[town]["region"]]["rewards"])
	return contract


static func _plain_contract(gen: WorldGen, town: int, salvaged: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var dock: Vector3 = gen.towns[town]["dock"]
	var home: String = gen.towns[town]["name"]
	var kind: String = KINDS[rng.randi_range(0, 3)]
	var places := []
	match kind:
		"salvage":
			for i in gen.wrecks.size():
				if not salvaged.has(i):
					places.append([i, Sites.wreck_center(gen.wrecks[i])])
			if places.is_empty():
				kind = "delivery"
		"scout":
			for i in gen.landmarks.size():
				places.append([i, gen.landmarks[i]["at"]])
	if kind == "delivery":
		for i in gen.towns.size():
			if i != town:
				places.append([i, gen.towns[i]["dock"]])
	var contract := {"kind": kind, "title": "", "reward": 0, "target": -1, "count": 1, "done": 0}
	if kind == "bounty":
		contract["count"] = 1 + (1 if rng.randf() < 0.3 else 0)
		contract["reward"] = contract["count"] * BOUNTY_PAY
		contract["title"] = "Sink a pirate" if contract["count"] == 1 else "Sink %d pirates" % contract["count"]
		return contract
	places.sort_custom(func(a: Array, b: Array) -> bool:
		var da := dock.distance_to(a[1])
		var db := dock.distance_to(b[1])
		return da < db or (da == db and a[0] < b[0]))
	var pick: Array = places[rng.randi_range(0, mini(NEARBY, places.size()) - 1)]
	var at: Vector3 = pick[1]
	var km := dock.distance_to(at) / 1000.0
	contract["target"] = pick[0]
	match kind:
		"delivery":
			var to: String = gen.towns[pick[0]]["name"]
			contract["count"] = rng.randi_range(1, 3)
			contract["reward"] = contract["count"] * (DELIVERY_BASE + roundi(DELIVERY_PER_KM * km))
			contract["title"] = "Carry a crate of mail to %s" % to if contract["count"] == 1 else "Carry %d crates of mail to %s" % [contract["count"], to]
		"salvage":
			contract["reward"] = SALVAGE_BASE + roundi(SALVAGE_PER_KM * km)
			contract["title"] = "Salvage the wreck %.1f km %s of %s" % [km, bearing_word(dock, at), home]
		"scout":
			contract["reward"] = SCOUT_BASE + roundi(SCOUT_PER_KM * km)
			contract["title"] = "Scout %s, %.1f km %s of %s" % [gen.landmarks[pick[0]]["name"], km, bearing_word(dock, at), home]
	return contract


## The compass point to looks from from: N, NE, E and so on.
static func bearing_word(from: Vector3, to: Vector3) -> String:
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][roundi(Hud.bearing(to - from) / 45.0) % 8]


## An account from the network or a save, cleaned (ints, not floats), or null for junk.
static func read_account(data: Variant) -> Variant:
	if not data is Dictionary:
		return null
	var money: Variant = whole(data.get("money"), 0, 1 << 52)
	var insured: Variant = whole(data.get("insured"), 0, 1 << 52)
	var unlocks: Variant = data.get("unlocks")
	var contracts: Variant = data.get("contracts")
	if money == null or insured == null or not unlocks is Array or not contracts is Array or contracts.size() > MAX_CONTRACTS:
		return null
	var logs: Variant = data.get("logs", [])  # a stage 7 save has none
	if not logs is Array:
		return null
	var clean := {"money": money, "unlocks": [], "contracts": [], "insured": insured, "logs": []}
	for entry: Variant in logs:
		var index: Variant = whole(entry, 0, Story.LOGS.size() - 1)
		if index == null or clean["logs"].has(index):
			return null
		clean["logs"].append(index)
	for part: Variant in unlocks:
		if not part is String or not UNLOCKS.has(part) or clean["unlocks"].has(part):
			return null
		clean["unlocks"].append(part)
	for entry: Variant in contracts:
		var contract: Variant = read_contract(entry)
		if contract == null:
			return null
		clean["contracts"].append(contract)
	return clean


## A contract from the network or a save, cleaned, or null for junk.
static func read_contract(data: Variant) -> Variant:
	if not data is Dictionary:
		return null
	var id: Variant = whole(data.get("id"), 1, 1 << 52)
	var kind: Variant = data.get("kind")
	var title: Variant = data.get("title")
	var reward: Variant = whole(data.get("reward"), 0, MAX_REWARD)
	var target: Variant = whole(data.get("target"), -1, 1 << 30)
	var count: Variant = whole(data.get("count"), 1, MAX_COUNT)
	if id == null or not kind is String or not kind in KINDS or not title is String or title.length() > MAX_TITLE \
			or reward == null or target == null or count == null:
		return null
	var done: Variant = whole(data.get("done"), 0, count)
	if done == null:
		return null
	return {"id": id, "kind": kind, "title": title, "reward": reward, "target": target, "count": count, "done": done}


## value as an int when it's a whole number (or a whole float, as JSON gives) from low
## to high, else null.
static func whole(value: Variant, low: int, high: int) -> Variant:
	if value is float and is_finite(value) and value == floorf(value):
		value = int(value)
	if not value is int or value < low or value > high:
		return null
	return value
