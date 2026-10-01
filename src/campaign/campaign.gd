class_name Campaign
## The campaign's rules, node-free (spec §3.5–3.7): what each region holds of danger
## and reward, and where the heart of the Eye is.

## By WorldGen.Region (Eye, Stormwall, Gale, Shattered, Calm, Rim). raids: the chance a
## raid sends a pirate at a crewed ship there, raiders: the most pirates near her.
## leviathans: the most leviathans near a ship, spawn: the chance a roam sends one.
## strikes: lightning's chance a second, per ship, in fully rough air. rewards and
## prices multiply contract rewards and goods prices at towns of that region.
const REGIONS := [
	{"raids": 0.0, "raiders": 0, "leviathans": 0, "spawn": 0.0, "strikes": 0.0, "rewards": 2.0, "prices": 1.5},
	{"raids": 0.0, "raiders": 0, "leviathans": 0, "spawn": 0.0, "strikes": 0.05, "rewards": 2.0, "prices": 1.5},
	{"raids": 0.5, "raiders": 2, "leviathans": 2, "spawn": 0.4, "strikes": 0.035, "rewards": 1.6, "prices": 1.25},
	{"raids": 0.5, "raiders": 2, "leviathans": 0, "spawn": 0.0, "strikes": 0.0, "rewards": 1.25, "prices": 1.1},
	{"raids": 0.25, "raiders": 1, "leviathans": 0, "spawn": 0.0, "strikes": 0.0, "rewards": 1.0, "prices": 1.0},
	{"raids": 0.0, "raiders": 0, "leviathans": 0, "spawn": 0.0, "strikes": 0.0, "rewards": 1.0, "prices": 1.0},
]

const HEART := Vector3(0.0, 1000.0, 0.0)
const HEART_REACH := 250.0  ## m from the heart that reaching it counts.


## The region table's row for where p is.
static func of(p: Vector3) -> Dictionary:
	return REGIONS[WorldGen.region_at(p)]
