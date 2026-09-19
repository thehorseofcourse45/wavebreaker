extends Node
class_name Perks
## Meta-progression registry: permanent perks bought with SALVAGE (banked from
## finished runs into save.json) in the pause menu's PERKS tab.
##
## Effects are checked by the system that owns the event, the established
## pattern: the run-start stat rows are applied by Main in start_game(), the
## fortune row is read where credits are actually granted. Nothing here touches
## the live game -- a perk bought mid-run applies on the next run.
##
## Levels are CACHED in memory because Main reads credits_multiplier() per kill;
## any external writer (the suite, a reset) must call refresh().

const Storage := preload("res://scripts/storage.gd")

const SAVE_KEY := "perks"

const VIGOR_HP := 20
const ARSENAL_DAMAGE := 3
const VELOCITY_PER_LEVEL := 0.06
const RESILIENCE_PER_LEVEL := 0.05
const FORTUNE_PER_LEVEL := 0.10
const HEADSTART_CREDITS := 50

## Row order is display order in the PERKS tab.
const DEFS: Array[Dictionary] = [
	{"id": "vigor", "name": "VIGOR", "hint": "+%d max HP / level" % VIGOR_HP,
		"base_cost": 40, "max_level": 3},
	{"id": "arsenal", "name": "ARSENAL", "hint": "+%d bullet damage / level" % ARSENAL_DAMAGE,
		"base_cost": 50, "max_level": 3},
	{"id": "velocity", "name": "VELOCITY", "hint": "+%d%% move speed / level" % int(VELOCITY_PER_LEVEL * 100.0),
		"base_cost": 35, "max_level": 3},
	{"id": "resilience", "name": "RESILIENCE", "hint": "+%d%% damage reduction / level" % int(RESILIENCE_PER_LEVEL * 100.0),
		"base_cost": 60, "max_level": 2},
	{"id": "fortune", "name": "FORTUNE", "hint": "+%d%% credits / level" % int(FORTUNE_PER_LEVEL * 100.0),
		"base_cost": 45, "max_level": 3},
	{"id": "headstart", "name": "HEAD START", "hint": "+%d starting credits / level" % HEADSTART_CREDITS,
		"base_cost": 30, "max_level": 2},
]

static var _levels: Dictionary = {}
static var _loaded: bool = false


static func definition(id: String) -> Dictionary:
	for d: Dictionary in DEFS:
		if String(d.id) == id:
			return d
	return {}


static func level(id: String) -> int:
	return int(_levels_live().get(id, 0))


## Price of the NEXT level: linear, readable, and never a surprise.
static func cost(id: String) -> int:
	var d: Dictionary = definition(id)
	if d.is_empty():
		return 0
	return int(d.get("base_cost", 0)) * (level(id) + 1)


static func can_buy(id: String, balance: int) -> bool:
	var d: Dictionary = definition(id)
	if d.is_empty() or level(id) >= int(d.get("max_level", 1)):
		return false
	return balance >= cost(id)


## Buy one level with saved salvage. Persists immediately; returns whether it
## happened. The menu renders the result -- no UI here.
static func buy(id: String, path: String = Storage.PATH) -> bool:
	var data: Dictionary = Storage.read_all(path)
	var lv: Dictionary = data.get(SAVE_KEY, {}) if data.get(SAVE_KEY, {}) is Dictionary else {}
	var cur: int = int(lv.get(id, 0))
	var d: Dictionary = definition(id)
	if d.is_empty() or cur >= int(d.get("max_level", 1)):
		return false
	var price: int = int(d.get("base_cost", 0)) * (cur + 1)
	if Storage.salvage(path) < price:
		return false
	Storage.spend_salvage(price, path)
	lv[id] = cur + 1
	Storage.set_value(SAVE_KEY, lv, path)
	refresh()
	return true


## Drop the cache so the next read follows the file (a buy, a reset, or the
## suite swapping the save under the game's feet).
static func refresh() -> void:
	_loaded = false
	_levels = {}


## Apply the run-start stat perks to the player from its pristine base values,
## so calling it on every run start cannot compound a multiplier. Main calls
## this before the mutators (glass cannon overwrites max HP/damage on purpose).
static func apply_to_player(player: Player) -> void:
	var vigor: int = level("vigor")
	if vigor > 0:
		player.max_health = player._base_max_health + VIGOR_HP * vigor
		player.health = player.max_health
	var arsenal: int = level("arsenal")
	if arsenal > 0:
		player.bullet_damage = player._base_bullet_damage + ARSENAL_DAMAGE * arsenal
	var velocity: int = level("velocity")
	if velocity > 0:
		player.move_speed = player._base_move_speed * (1.0 + VELOCITY_PER_LEVEL * velocity)
	var resilience: int = level("resilience")
	if resilience > 0:
		player.damage_reduction = minf(0.6, player._base_damage_reduction + RESILIENCE_PER_LEVEL * resilience)
	if vigor > 0:
		player.health_changed.emit(player.health, player.max_health)


static func credits_multiplier() -> float:
	return 1.0 + FORTUNE_PER_LEVEL * level("fortune")


static func scaled_credits(base: int) -> int:
	return int(round(float(base) * credits_multiplier()))


static func starting_credits() -> int:
	return HEADSTART_CREDITS * level("headstart")


static func _levels_live() -> Dictionary:
	if not _loaded:
		var raw: Variant = Storage.get_value(SAVE_KEY, {})
		_levels = raw if raw is Dictionary else {}
		_loaded = true
	return _levels
