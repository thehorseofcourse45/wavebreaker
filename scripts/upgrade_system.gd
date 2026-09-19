extends Node
class_name UpgradeSystem
## Flat registry of shop upgrades: keys, labels, base cost, apply step.
## No scene, no autoload -- instantiated by Main and read by the shop UI.
## Stats live on the player's exports, or on BulletPool for pooled bullet config;
## upgrades mutate those so the HUD/next wave sees fresh numbers.

signal upgraded(id: String, new_value)

@export var cost_growth: float = 1.35  # price multiplier per purchase of the same id

const DEFS: Array[Dictionary] = [
	{"id": "damage",    "label": "Damage +4",          "base_cost": 40,  "max_level": 8},
	{"id": "fire_rate", "label": "Fire rate +12%",     "base_cost": 50,  "max_level": 6},
	{"id": "max_hp",    "label": "Max HP +25",         "base_cost": 45,  "max_level": 6},
	{"id": "move_spd",  "label": "Speed +8%",          "base_cost": 35,  "max_level": 6},
	{"id": "bullet_vel","label": "Bullet vel +12%",    "base_cost": 30,  "max_level": 5},
	{"id": "split_shot","label": "Split shot +1",      "base_cost": 120, "max_level": 3},
	{"id": "armor",     "label": "Damage taken -10%",  "base_cost": 55,  "max_level": 4},
	{"id": "iframes",   "label": "Invuln +0.15s",      "base_cost": 40,  "max_level": 4},
	{"id": "leech",     "label": "Heal +1 per kill",   "base_cost": 65,  "max_level": 4},
	{"id": "recoil",    "label": "Recoil -25%",        "base_cost": 30,  "max_level": 4},
	{"id": "pierce",    "label": "Pierce +1 enemy",    "base_cost": 95,  "max_level": 3},
	{"id": "charge",    "label": "Charge shot (RMB)",  "base_cost": 160, "max_level": 1},
]

var levels: Dictionary = {}   # id -> times purchased
## Ids this RUN refuses to sell, set by Main when the run starts (the "glass
## cannon" mutator blocks armor). Empty for a normal run, so nothing changes for
## anyone who has not toggled it on.
var blocked: Array[String] = []


func level(id: String) -> int:
	return int(levels.get(id, 0))


func cost(id: String) -> int:
	for d: Dictionary in DEFS:
		if d.id == id:
			var price: float = float(d.base_cost) * pow(cost_growth, float(level(id)))
			# Unlockable "black_market": 10% off everything, forever. Applied here
			# so the displayed price, the affordability check and the charge all
			# quote the same number.
			if Unlockables.is_unlocked("black_market"):
				price *= 0.9
			return int(round(price))
	return 0


func definition(id: String) -> Dictionary:
	for d: Dictionary in DEFS:
		if d.id == id:
			return d
	return {}


func is_blocked(id: String) -> bool:
	return blocked.has(id)


## Block a row for this run (Main calls this for the "glass cannon" mutator). A
## method rather than assigning the field from outside: `blocked` is a typed array,
## and a cross-script assignment of an untyped [] is rejected at runtime.
func block(id: String) -> void:
	if not blocked.has(id):
		blocked.append(id)


func can_buy(id: String, credits: int) -> bool:
	var d: Dictionary = definition(id)
	if d.is_empty():
		return false
	if is_blocked(id):
		return false   # this run's mutator refuses the row (see `blocked`)
	if level(id) >= int(d.max_level):
		return false
	return credits >= cost(id)


func buy(id: String, credits: int, player: Player) -> Dictionary:
	## Returns {"spent": int, "ok": bool, "reason": String}. Pure: no UI.
	if not can_buy(id, credits):
		return {"spent": 0, "ok": false, "reason": "unaffordable_or_maxed"}
	var spent: int = cost(id)
	levels[id] = level(id) + 1
	match id:
		"damage":     player.bullet_damage += 4
		"fire_rate":  player.fire_rate = maxf(0.06, player.fire_rate * 0.88)
		"max_hp":     player.max_health += 25; player.health = mini(player.health + 25, player.max_health); player.health_changed.emit(player.health, player.max_health)
		"move_spd":   player.move_speed *= 1.08
		"bullet_vel": player.bullet_speed *= 1.12
		"split_shot": player.bullets_per_shot += 1
		"armor":      player.damage_reduction = minf(0.6, player.damage_reduction + 0.10)
		"iframes":    player.invulnerability_time += 0.15
		"leech":      player.kill_heal += 1
		"recoil":     player.fire_recoil *= 0.75
		"pierce":     player.pierce_count += 1
		"charge":     player.charge_unlocked = true
	upgraded.emit(id, levels[id])
	return {"spent": spent, "ok": true, "reason": ""}
