extends Node
class_name UpgradeSystem
## Flat registry of shop upgrades: keys, labels, base cost, apply step.
## No scene, no autoload -- instantiated by Main and read by the shop UI.
## Stats live on the player's exports, or on BulletPool for pooled bullet config;
## upgrades mutate those so the HUD/next wave sees fresh numbers. The BEHAVIOR rows
## (crit / homing / ricochet / explosive) write to BulletPool, which Main restores
## per run via BulletPool.reset_run_config().

signal upgraded(id: String, new_value)

## Prices are deliberately steeper than they look: growth 1.70 plus the ~+50%
## base-cost pass makes a full build a real economy question, not a shopping list.
@export var cost_growth: float = 1.70  # price multiplier per purchase of the same id

## Rarity is a fixed per-row tier. It multiplies the price and the size of the
## effect, so a rare/epic row is a bigger, costlier swing. The rows with exact
## value probes in the suite are deliberately left "common" so a rarity bump can
## never silently change a tested magnitude.
const RARITY_COST: Dictionary = {"common": 1.0, "rare": 1.25, "epic": 1.5}
const RARITY_EFFECT: Dictionary = {"common": 1.0, "rare": 1.25, "epic": 1.5}

const DEFS: Array[Dictionary] = [
	{"id": "damage",    "label": "Damage +4",          "base_cost": 120, "max_level": 5, "rarity": "common", "icon": ["bolt", "#ff5566"]},
	# fire_rate/bullet_vel stay common: they feed the suite's boss-TTK balance
	# check, and a rarity bump there is a balance change, not a label change.
	{"id": "fire_rate", "label": "Fire rate +12%",     "base_cost": 150, "max_level": 4, "rarity": "common", "icon": ["spark", "#ffaa33"]},
	{"id": "max_hp",    "label": "Max HP +25",         "base_cost": 140, "max_level": 4, "rarity": "rare", "icon": ["cross", "#4cc9f0"]},
	{"id": "move_spd",  "label": "Speed +8%",          "base_cost": 110, "max_level": 4, "rarity": "rare", "icon": ["wing", "#ffe66d"]},
	{"id": "bullet_vel","label": "Bullet vel +12%",    "base_cost": 95,  "max_level": 3, "rarity": "common", "icon": ["chevron", "#7bdff2"]},
	{"id": "split_shot","label": "Split shot +1",      "base_cost": 400, "max_level": 2, "rarity": "common", "icon": ["hex", "#c77dff"]},
	{"id": "armor",     "label": "Damage taken -10%",  "base_cost": 170, "max_level": 3, "rarity": "common", "icon": ["square", "#4895ef"]},
	{"id": "iframes",   "label": "Invuln +0.15s",      "base_cost": 125, "max_level": 3, "rarity": "common", "icon": ["ring", "#80ffdb"]},
	{"id": "leech",     "label": "Heal +1 per kill",   "base_cost": 200, "max_level": 3, "rarity": "common", "icon": ["drop", "#5ef39a"]},
	{"id": "recoil",    "label": "Recoil -25%",        "base_cost": 95,  "max_level": 3, "rarity": "common", "icon": ["chevron", "#90e0ef"]},
	{"id": "pierce",    "label": "Pierce +1 enemy",    "base_cost": 300, "max_level": 2, "rarity": "rare", "icon": ["bolt", "#a0f0ff"]},
	{"id": "charge",    "label": "Charge shot (RMB)",  "base_cost": 520, "max_level": 1, "rarity": "epic", "icon": ["spark", "#c77dff"]},
	# Behavior rows: they reshape rounds instead of scaling a number, and they write
	# to BulletPool (see Main's per-run reset). crit_chance/crit_damage feed the crit
	# system that already exists on the pool; the rest drive bullet.gd's homing,
	# ricochet and kill-blast. Probe-pinned magnitudes are left "common" earlier --
	# these are new rows, so a rarity bump here is the intended balance lever.
	{"id": "crit_chance", "label": "Crit +6%",          "base_cost": 200, "max_level": 4, "rarity": "rare", "icon": ["spark", "#ff5d8f"]},
	{"id": "crit_damage", "label": "Crit dmg +30%",     "base_cost": 230, "max_level": 3, "rarity": "rare", "icon": ["skull", "#ff477e"]},
	{"id": "homing",      "label": "Homing rounds",     "base_cost": 340, "max_level": 2, "rarity": "epic", "icon": ["ring", "#9b5de5"]},
	{"id": "ricochet",    "label": "Ricochet +1",       "base_cost": 275, "max_level": 2, "rarity": "rare", "icon": ["chevron", "#f15bb5"]},
	{"id": "explosive",   "label": "Explosive rounds",  "base_cost": 370, "max_level": 2, "rarity": "epic", "icon": ["skull", "#7b2cbf"]},
	# The one HEALING row: the "no shop" mutator keeps exactly this one open, so a
	# run with it can still buy health and nothing else.
	{"id": "repair",    "label": "Field repair (full)", "base_cost": 215, "max_level": 1, "rarity": "common", "icon": ["cross", "#5ef39a"]},
	# -- the second twenty: mobility, precision, payback, and pool multipliers --
	# Player-state rows mutate the live player (a fresh scene instance every run);
	# pool rows extend BulletPool/PickupPool and ride their reset_run_config().
	{"id": "magnet",      "label": "Magnet field +50%",  "base_cost": 110, "max_level": 3, "rarity": "common", "icon": ["ring", "#ffd166"]},
	{"id": "dash_cadence","label": "Dash cooldown -15%", "base_cost": 130, "max_level": 3, "rarity": "common", "icon": ["wing", "#ffe66d"]},
	{"id": "dash_burst",  "label": "Dash distance +20%", "base_cost": 120, "max_level": 2, "rarity": "common", "icon": ["chevron", "#ffd166"]},
	{"id": "dash_strike", "label": "Dash contact damage","base_cost": 200, "max_level": 3, "rarity": "rare", "icon": ["bolt", "#f4a261"]},
	{"id": "caliber",     "label": "Round size +18%",    "base_cost": 100, "max_level": 3, "rarity": "common", "icon": ["square", "#7bdff2"]},
	{"id": "punch",       "label": "Knockback +30%",     "base_cost": 95,  "max_level": 3, "rarity": "common", "icon": ["cross", "#ff9770"]},
	{"id": "focus",       "label": "Spread -35%",        "base_cost": 140, "max_level": 2, "rarity": "rare", "icon": ["ring", "#80ffdb"]},
	{"id": "quickdraw",   "label": "Charge 20% faster",  "base_cost": 240, "max_level": 2, "rarity": "rare", "icon": ["spark", "#ffd166"]},
	{"id": "retaliate",   "label": "Retaliate on hit",   "base_cost": 170, "max_level": 3, "rarity": "rare", "icon": ["cross", "#ff5d73"]},
	{"id": "scavenger",   "label": "Bonus drop +15%",    "base_cost": 150, "max_level": 3, "rarity": "rare", "icon": ["hex", "#ffd166"]},
	{"id": "regen",       "label": "Regen 1 HP / 5s",    "base_cost": 180, "max_level": 3, "rarity": "rare", "icon": ["drop", "#5ef39a"]},
	{"id": "adrenaline",  "label": "+15% fire under 50%","base_cost": 160, "max_level": 2, "rarity": "rare", "icon": ["drop", "#ff5d73"]},
	{"id": "bossbane",    "label": "+25% dmg to bosses", "base_cost": 300, "max_level": 2, "rarity": "epic", "icon": ["skull", "#c77dff"]},
	{"id": "mark",        "label": "+25% dmg to elites", "base_cost": 280, "max_level": 2, "rarity": "epic", "icon": ["hex", "#b388ff"]},
	{"id": "executioner", "label": "+40% dmg under 20%", "base_cost": 260, "max_level": 2, "rarity": "epic", "icon": ["skull", "#9b5de5"]},
	{"id": "burn",        "label": "Rounds set alight",  "base_cost": 250, "max_level": 3, "rarity": "epic", "icon": ["spark", "#7b2cbf"]},
	{"id": "offers",      "label": "+1 shop offer",      "base_cost": 220, "max_level": 2, "rarity": "rare", "icon": ["hex", "#ffd166"]},
	{"id": "bargain",     "label": "Rerolls -40% cost",  "base_cost": 190, "max_level": 2, "rarity": "rare", "icon": ["ring", "#ffe66d"]},
	{"id": "evasion",     "label": "8% chance to dodge", "base_cost": 210, "max_level": 3, "rarity": "rare", "icon": ["wing", "#80ffdb"]},
	{"id": "longshot",    "label": "Round lifetime +25%","base_cost": 120, "max_level": 3, "rarity": "common", "icon": ["chevron", "#7bdff2"]},
	# -- the third ten: handling, the charge line, economy, and a death save --
	# Player rows write the live player; "seeker" and "aid" are pool rows (homing
	# range / health-pickup value) that ride reset_run_config() beside magnet.
	# "charge_*" rows only pay off once the epic "charge" row unlocks the shot.
	{"id": "handling",     "label": "Handling +25%",        "base_cost": 100, "max_level": 3, "rarity": "common", "icon": ["chevron", "#80ffdb"]},
	{"id": "dash_time",    "label": "Dash linger +20%",     "base_cost": 115, "max_level": 3, "rarity": "common", "icon": ["wing", "#ffd166"]},
	{"id": "seeker",       "label": "Seeker range +35%",    "base_cost": 105, "max_level": 3, "rarity": "common", "icon": ["ring", "#9b5de5"]},
	{"id": "aid",          "label": "Aid kits +50%",        "base_cost": 160, "max_level": 2, "rarity": "common", "icon": ["cross", "#5ef39a"]},
	{"id": "bounty",       "label": "Credits +15% / kill",  "base_cost": 200, "max_level": 3, "rarity": "rare", "icon": ["hex", "#ffe66d"]},
	{"id": "anchor",       "label": "Knockback taken -35%", "base_cost": 150, "max_level": 2, "rarity": "rare", "icon": ["square", "#4895ef"]},
	{"id": "charge_power", "label": "Charge damage +25%",   "base_cost": 260, "max_level": 3, "rarity": "rare", "icon": ["bolt", "#c77dff"]},
	{"id": "charge_knock", "label": "Charge push +30%",     "base_cost": 180, "max_level": 2, "rarity": "rare", "icon": ["bolt", "#f4a261"]},
	{"id": "charge_pierce","label": "Charge pierce +1",     "base_cost": 280, "max_level": 2, "rarity": "rare", "icon": ["chevron", "#a0f0ff"]},
	{"id": "last_stand",   "label": "Cheat one death",      "base_cost": 420, "max_level": 2, "rarity": "epic", "icon": ["skull", "#ff5d8f"]},
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
		# Behavior rows: mutate the POOL (shared by every player round), which is why
		# Main calls BulletPool.reset_run_config() at run start.
		"crit_chance": BulletPool.crit_chance = minf(0.85, BulletPool.crit_chance + 0.06 * m)
		"crit_damage": BulletPool.crit_multiplier += 0.30 * m
		"homing":      BulletPool.homing_strength = minf(9.0, BulletPool.homing_strength + 3.0 * m)
		"ricochet":    BulletPool.bounce_count += int(round(1.0 * m))
		"explosive":
			BulletPool.explosive_radius = minf(150.0, BulletPool.explosive_radius + 46.0 * m)
			BulletPool.explosive_damage += int(round(8.0 * m))
		"charge":     player.charge_unlocked = true
		"repair":     player.heal(player.max_health)
		# The second twenty (see DEFS). Player rows write the live player; pool rows
		# write BulletPool/PickupPool, which reset per run beside the crit rows.
		"magnet":       PickupPool.magnet_mult *= 1.0 + 0.5 * m
		"dash_cadence": player.dash_cooldown = maxf(0.5, player.dash_cooldown * 0.85)
		"dash_burst":   player.dash_speed *= 1.20
		"dash_strike":  player.dash_strike_dmg += int(round(8.0 * m))
		"caliber":
			# 0 means "unscaled": normalise to 1.0 first so +18% is always a real
			# growth, and fire_charged passes the result on (charge inherits size).
			player.bullet_scale = maxf(player.bullet_scale, 1.0) * (1.0 + 0.18 * m)
		"punch":      player.weapon_knockback *= 1.0 + 0.30 * m
		"focus":      player.bullet_spread_deg = maxf(0.5, player.bullet_spread_deg * 0.65)
		"quickdraw":  player.charge_time = maxf(0.30, player.charge_time * 0.80)
		"retaliate":  player.retaliate_dmg += int(round(6.0 * m))
		"scavenger":  PickupPool.extra_drop_chance += 0.15 * m
		"regen":      player.regen_rate += 0.2 * m   # 1 HP per 5 s per common level
		"adrenaline": player.adrenaline_mult += 0.15 * m
		"bossbane":   BulletPool.vs_boss_mult += 0.25 * m
		"mark":       BulletPool.vs_elite_mult += 0.25 * m
		"executioner": BulletPool.exec_mult += 0.40 * m
		"burn":       BulletPool.burn_dps += 4.0 * m
		# Pure registry rows: their effect is READ from level() by the owner
		# (ShopPanel.deal / effective_reroll_cost), probed there directly.
		"offers":  pass
		"bargain": pass
		"evasion": player.evasion_chance = minf(0.40, player.evasion_chance + 0.08 * m)
		"longshot":
			# 0 means the scene default (2.0 s): normalise before growing so a
			# furnace's 0.3 s rounds stay short through weapon * longshot.
			var base_lt: float = player.bullet_lifetime if player.bullet_lifetime > 0.0 else 2.0
			player.bullet_lifetime = maxf(0.5, base_lt * (1.0 + 0.25 * m))
		# The third ten (see DEFS). "seeker"/"aid" are pool rows; the rest write
		# the live player and are read in _handle_movement / take_damage /
		# fire_charged / Main's kill handler.
		"handling":      player.acceleration *= 1.0 + 0.25 * m
		"dash_time":     player.dash_time *= 1.0 + 0.20 * m
		"seeker":        BulletPool.homing_range *= 1.0 + 0.35 * m
		"aid":           PickupPool.heal_mult += 0.5 * m
		"bounty":        player.credit_mult += 0.15 * m
		"anchor":        player.knockback_resist = minf(0.8, player.knockback_resist + 0.35 * m)
		"charge_power":  player.charge_damage_mult *= 1.0 + 0.25 * m
		"charge_knock":  player.charge_knockback_mult *= 1.0 + 0.30 * m
		"charge_pierce": player.charge_pierce += int(round(1.0 * m))
		# Flat +1 per level: rarity is the price lever only here (like "charge" /
		# "repair"), so an epic rank cannot hand out two saved deaths a level.
		"last_stand":    player.last_stand_charges += 1
	upgraded.emit(id, levels[id])
	return {"spent": spent, "ok": true, "reason": ""}
