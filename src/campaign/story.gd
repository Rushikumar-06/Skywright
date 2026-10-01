class_name Story
## The story, told in twelve logs (spec §3.7): one at each landmark, three on town
## quays, and the heart's own, which is the ending. Two of them give something: the
## armourer's ledger unlocks alloy, and the Wallwright's notes the Wallbreaker.

const REACH := 30.0  ## m from a log's spot that it's read from.
const HEART_LOG := 11

## at: "town", "landmark" or "heart"; index: the town's or landmark's, in WorldGen's lists.
const LOGS := [
	{"title": "A notice on the quay", "at": "town", "index": 0, "unlocks": "", "blueprint": "",
		"text": "Captains wanted for the inward routes. The Shattered Belt pays in salvage, the Gale Expanse pays in everything, and nobody has come back over the Stormwall in living memory. Fill your tanks, fill your spares, and don't fly into a storm you can't see out of. The harbourmaster."},
	{"title": "Carved at the spire's foot", "at": "landmark", "index": 0, "unlocks": "", "blueprint": "",
		"text": "We raised this spire on the first island that held. When the ground went down into the Roil, the stone at the Eye's heart kept the rest of us up. Every island still turns around it, slow as the hand of a clock. Remember the heart."},
	{"title": "A traveller's journal", "at": "landmark", "index": 1, "unlocks": "", "blueprint": "",
		"text": "The wind goes round the Eye the way the islands do, and it blows harder the further in you go. Fly with it and an engine lasts all day. Fly against it and you'll learn what fuel costs. Plan the way back before the way in."},
	{"title": "An armourer's ledger", "at": "landmark", "index": 2, "unlocks": "alloy", "blueprint": "",
		"text": "Iron is too heavy for the inward routes. We beat alloy thin and it stops shot nearly as well, at two-thirds of the weight. The method is written out below, for any yard that wants it. Take it: we won't be needing it now."},
	{"title": "A salvager's last entry", "at": "landmark", "index": 3, "unlocks": "", "blueprint": "",
		"text": "The wrecks in the Belt are what the Gale sends back: ships that went in proud and came out as kindling. We strip them and say a word for their crews. Lift stones are sold further in, they say. So is trouble."},
	{"title": "The Wallwright's notes", "at": "landmark", "index": 4, "unlocks": "", "blueprint": "Wallbreaker",
		"text": "The Stormwall blows outward, harder than any one engine can push. Two engines and four propellers will make headway, slowly, and burn fuel all the while: carry four tanks. Or climb above it, where the wall lets go, if your envelope or your stones can take you there. My drawings are pinned beneath."},
	{"title": "A leviathan watcher's log", "at": "landmark", "index": 5, "unlocks": "", "blueprint": "",
		"text": "They're curious, not cruel. One swam beside us for an hour today, close enough to count its scars. Shoot one and it won't forget you until you're gone, and it hits like a falling island. The great one in the Eye is another matter."},
	{"title": "Scratched into the stone", "at": "landmark", "index": 6, "unlocks": "", "blueprint": "",
		"text": "We made it this far on stones and balloons. Above the storm the wind lets go, and the air is thin and quiet. Below, the lightning never stops. If you can read this, you're in the wall. Keep going in."},
	{"title": "The wardens' charge", "at": "landmark", "index": 7, "unlocks": "", "blueprint": "",
		"text": "We bound the Warden to the heart, to keep the storm away from the Keel. While it circles, the Keel holds. It knows nothing of friends now. Whoever comes after us: it will not let you pass without a fight, and you must not let it win."},
	{"title": "A dockmaster's warning", "at": "town", "index": 7, "unlocks": "", "blueprint": "",
		"text": "Ships out of here fly through storms that strike the highest thing they find, which is usually your envelope. Keep a hand on the repairs, keep your spares full, and give the leviathans room. They only fight when you start it."},
	{"title": "The lamplighters' book", "at": "town", "index": 9, "unlocks": "", "blueprint": "",
		"text": "We came over the wall with what we could carry, and found the calm. The heart is close: you can see its light from the quay. The Warden circles it day and night, and comes for anything that flies near. Rest here first."},
	{"title": "The Keel", "at": "heart", "index": 0, "unlocks": "", "blueprint": "",
		"text": "Below the calm, a stone the size of a town turns in the air, humming. The Keel: every island in the sky hangs from it. The wardens bound a guardian to it and were forgotten, and the guardian forgot everything but the stone. Now it's quiet. The Keel still turns, the islands will hold, and the way to the heart is open to anyone with a ship and the nerve to cross the wall."},
]


## Where log is read in gen's world, or null: the heart's is the ending, and a world
## without that town or landmark has nowhere to read it.
static func spot(gen: WorldGen, log_index: int) -> Variant:
	var entry: Dictionary = LOGS[log_index]
	match entry["at"]:
		"landmark":
			if entry["index"] >= gen.landmarks.size():
				return null
			var landmark: Dictionary = gen.landmarks[entry["index"]]
			return landmark["at"] + Vector3(0, IslandMesh.height(landmark["island"], 0, 0), 0)
		"town":
			if entry["index"] >= gen.towns.size():
				return null
			return Dock.quay_spot(gen.towns[entry["index"]]["dock"])
	return null


## The blueprints the found logs give, in log order.
static func blueprints(logs: Array) -> Array[String]:
	var found: Array[String] = []
	for i in LOGS.size():
		if logs.has(i) and LOGS[i]["blueprint"] != "":
			found.append(LOGS[i]["blueprint"])
	return found


static func blueprint(blueprint_name: String) -> ShipGrid:
	match blueprint_name:
		"Wallbreaker":
			return Wallbreaker.build()
	return null
