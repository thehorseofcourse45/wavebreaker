extends Node
class_name Weapons
## Player weapon archetypes: one registry row = one starting gun.
##
## A weapon is a BASE loadout, not a live modifier. Player.apply_weapon() writes a
## row onto the player's PRISTINE scene stats (recorded in _ready), and the shop then
## mutates the live values on top -- so "Damage +4" means +4 whatever the run started
## with, and switching guns can never compound a multiplier.
##
## The DEFAULT row is all-1.0 with the scene's own spread/range/size, so applying it
## is a no-op: that is what keeps the boss-TTK balance probe's measured dps valid.
##
## Keys, and why each one is the shape it is:
##   fire_rate  - multiplier on the scene's fire_rate (it is an INTERVAL: >1 = slower)
##   damage     - multiplier on bullet_damage
##   speed      - multiplier on bullet_speed
##   recoil     - multiplier on fire_recoil, the push a shot gives the PLAYER
##   pellets    - ABSOLUTE bullets per volley (shop "split shot" adds to it)
##   spread_deg - ABSOLUTE angle between neighbouring pellets of one volley
##   pierce     - ABSOLUTE base enemies passed through (shop "pierce" adds to it)
##   lifetime   - ABSOLUTE seconds a round flies, i.e. how far the gun reaches
##   scale      - ABSOLUTE round size, hitbox included
##   knockback  - per-shot push handed to BulletPool.fire (the charge shot has its own)

const SAVE_KEY := "weapon"
const DEFAULT_ID := "rifle"

## Registry order is the menu's picker order. Rough raw dps against the rifle (pellets
## x damage / fire_rate) sits between 0.74x and 1.12x for every row: a gun changes HOW
## the run plays, never the boss fight's length.
const DEFS: Array[Dictionary] = [
	{"id": "rifle", "name": "RIFLE", "hint": "Balanced automatic",
		"fire_rate": 1.0, "damage": 1.0, "speed": 1.0, "recoil": 1.0,
		"pellets": 1, "spread_deg": 7.0, "pierce": 0, "lifetime": 2.0, "scale": 1.0, "knockback": 1.0},
	{"id": "needler", "name": "NEEDLER", "hint": "Fast, light, sloppy",
		"fire_rate": 0.40, "damage": 0.45, "speed": 1.10, "recoil": 0.40,
		"pellets": 1, "spread_deg": 12.0, "pierce": 0, "lifetime": 2.0, "scale": 0.75, "knockback": 0.7},
	{"id": "breacher", "name": "BREACHER", "hint": "Five pellets, close range",
		"fire_rate": 3.2, "damage": 0.60, "speed": 0.85, "recoil": 3.0,
		"pellets": 5, "spread_deg": 26.0, "pierce": 0, "lifetime": 0.55, "scale": 1.15, "knockback": 1.4},
	{"id": "viper", "name": "VIPER", "hint": "Precise marksman",
		"fire_rate": 2.2, "damage": 1.90, "speed": 1.60, "recoil": 1.10,
		"pellets": 1, "spread_deg": 0.0, "pierce": 0, "lifetime": 2.4, "scale": 1.1, "knockback": 1.2},
	{"id": "lance", "name": "LANCE", "hint": "Piercing rail slug",
		"fire_rate": 4.6, "damage": 3.40, "speed": 2.0, "recoil": 1.6,
		"pellets": 1, "spread_deg": 0.0, "pierce": 3, "lifetime": 2.6, "scale": 1.4, "knockback": 1.8},
	{"id": "furnace", "name": "FURNACE", "hint": "Short-range cone",
		"fire_rate": 0.25, "damage": 0.20, "speed": 0.55, "recoil": 0.30,
		"pellets": 1, "spread_deg": 20.0, "pierce": 0, "lifetime": 0.30, "scale": 1.7, "knockback": 0.5},
	{"id": "slugger", "name": "SLUGGER", "hint": "Slow hand cannon, huge shove",
		"fire_rate": 5.5, "damage": 4.50, "speed": 0.90, "recoil": 2.40,
		"pellets": 1, "spread_deg": 0.0, "pierce": 1, "lifetime": 2.2, "scale": 2.0, "knockback": 4.0},
]


static func definition(id: String) -> Dictionary:
	for d: Dictionary in DEFS:
		if String(d.id) == id:
			return d
	return {}


## The row for `id`, FALLING BACK to the default. A save file edited by hand (or a
## row deleted in a later version) must never leave the player with no gun at all.
static func resolve(id: String) -> Dictionary:
	var d: Dictionary = definition(id)
	return d if not d.is_empty() else DEFS[0]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for d: Dictionary in DEFS:
		out.append(String(d.id))
	return out


static func display_name(id: String) -> String:
	return String(resolve(id).get("name", DEFAULT_ID.to_upper()))


static func hint(id: String) -> String:
	return String(resolve(id).get("hint", ""))
