extends Node
class_name UpgradeSystem
## Flat registry of shop upgrades: keys, labels, base cost, apply step.
## No scene, no autoload -- instantiated by Main and read by the shop UI.
## Stats live on the player's exports, or on BulletPool for pooled bullet config;
## upgrades mutate those so the HUD/next wave sees fresh numbers.

signal upgraded(id: String, new_value)

@export var cost_growth: float = 1.55  # price multiplier per purchase of the same id

## Rarity is a fixed per-row tier. It multiplies the price and the size of the
## effect, so a rare/epic row is a bigger, costlier swing. The rows with exact
## value probes in the suite are deliberately left "common" so a rarity bump can
## never silently change a tested magnitude.
const RARITY_COST: Dictionary = {"common": 1.0, "rare": 1.25, "epic": 1.5}
const RARITY_EFFECT: Dictionary = {"common": 1.0, "rare": 1.25, "epic": 1.5}

const DEFS: Array[Dictionary] = [
	{"id": "damage",    "label": "Damage +4",          "base_cost": 80,  "max_level": 5, "rarity": "common"},
	# fire_rate/bullet_vel stay common: they feed the suite's boss-TTK balance
	# check, and a rarity bump there is a balance change, not a label change.
	{"id": "fire_rate", "label": "Fire rate +12%",     "base_cost": 100, "max_level": 4, "rarity": "common"},
	{"id": "max_hp",    "label": "Max HP +25",         "base_cost": 90,  "max_level": 4, "rarity": "rare"},
	{"id": "move_spd",  "label": "Speed +8%",          "base_cost": 70,  "max_level": 4, "rarity": "rare"},
	{"id": "bullet_vel","label": "Bullet vel +12%",    "base_cost": 60,  "max_level": 3, "rarity": "common"},
	{"id": "split_shot","label": "Split shot +1",      "base_cost": 260, "max_level": 2, "rarity": "common"},
	{"id": "armor",     "label": "Damage taken -10%",  "base_cost": 110, "max_level": 3, "rarity": "common"},
	{"id": "iframes",   "label": "Invuln +0.15s",      "base_cost": 80,  "max_level": 3, "rarity": "common"},
	{"id": "leech",     "label": "Heal +1 per kill",   "base_cost": 130, "max_level": 3, "rarity": "common"},
	{"id": "recoil",    "label": "Recoil -25%",        "base_cost": 60,  "max_level": 3, "rarity": "common"},
	{"id": "pierce",    "label": "Pierce +1 enemy",    "base_cost": 200, "max_level": 2, "rarity": "rare"},
	{"id": "charge",    "label": "Charge shot (RMB)",  "base_cost": 340, "max_level": 1, "rarity": "epic"},
	# The one HEALING row: the "no shop" mutator keeps exactly this one open, so a
	# run with it can still buy health and nothing else.
	{"id": "repair",    "label": "Field repair (full)", "base_cost": 140, "max_level": 1, "rarity": "common"},
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
			price *= _rarity_mult(id, RARITY_COST)
			# Unlockable "black_market": 10% off everything, forever. Applied here
			# so the displayed price, the affordability check and the charge all
			# quote the same number.
			if Unlockables.is_unlocked("black_market"):
				price *= 0.9
			return int(round(price))
	return 0


func _rarity_mult(id: String, table: Dictionary) -> float:
	var d: Dictionary = definition(id)
	return float(table.get(String(d.get("rarity", "common")), 1.0))


## The rarity tier shown in the shop label ("" when the row is missing).
func rarity(id: String) -> String:
	return String(definition(id).get("rarity", "common"))


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
	# "Field repair" heals to full, so it is only worth selling while hurt. The
	# UI also greys it out; this is the authority.
	if id == "repair" and player.health >= player.max_health:
		return {"spent": 0, "ok": false, "reason": "at_full_health"}
	var spent: int = cost(id)
	levels[id] = level(id) + 1
	var m: float = _rarity_mult(id, RARITY_EFFECT)
	match id:
		"damage":     player.bullet_damage += int(round(4.0 * m))
		"fire_rate":  player.fire_rate = maxf(0.06, player.fire_rate * (1.0 - 0.12 * m))
		"max_hp":
			var hp_gain: int = int(round(25.0 * m))
			player.max_health += hp_gain
			player.health = mini(player.health + hp_gain, player.max_health)
			player.health_changed.emit(player.health, player.max_health)
		"move_spd":   player.move_speed *= 1.0 + 0.08 * m
		"bullet_vel": player.bullet_speed *= 1.0 + 0.12 * m
		"split_shot": player.bullets_per_shot += int(round(1.0 * m))
		"armor":      player.damage_reduction = minf(0.6, player.damage_reduction + 0.10 * m)
		"iframes":    player.invulnerability_time += 0.15 * m
		"leech":      player.kill_heal += int(round(1.0 * m))
		"recoil":     player.fire_recoil *= maxf(0.1, 1.0 - 0.25 * m)
		"pierce":     player.pierce_count += int(round(1.0 * m))
		"charge":     player.charge_unlocked = true
		"repair":     player.heal(player.max_health)
	upgraded.emit(id, levels[id])
	return {"spent": spent, "ok": true, "reason": ""}
