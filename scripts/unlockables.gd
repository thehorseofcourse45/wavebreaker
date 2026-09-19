extends Node
class_name Unlockables
## Registry of unlockables: id, display name, the condition shown while the row is
## still locked, and the condition itself (`need` = one lifetime counter plus the
## value it has to reach).
##
## The ICONS are res://assets/icons/unlockables/<id>.png -- 64x64, sliced from
## the delivered sheet in ROW-MAJOR order, so the order of DEFS must stay in step
## with that sheet (id 1 = top-left). The pause menu's UNLOCKABLES tab renders
## this table, so adding an unlockable is one row here plus its 64x64 PNG.
##
## Progress is LIFETIME and lives at the top level of save.json. Main keeps the
## current run's counters in memory and hands them over at exactly two boundaries
## -- each cleared wave (so an unlock can land mid-run) and the end of the run --
## so nothing writes the file per kill:
##
##   * [method evaluate] judges `stored + this run` and persists only the FLAGS.
##     Safe to call as often as you like; it never touches the counters.
##   * [method flush_run] is the one place this run's counters are added to the
##     stored totals. Call it ONCE per run, at the end.
##
## Because evaluate() merges the live run into the stored totals, calling it with
## a run dict AFTER that run was flushed would count it twice -- hence Main calls
## `evaluate()` with no argument once the run is over (the totals are already in).
##
## The earned set is CACHED in memory: effects read `is_unlocked()` from hot paths
## (every fired round, every enemy tint), which must never hit the disk.

const Storage := preload("res://scripts/storage.gd")
const ICON_DIR := "res://assets/icons/unlockables/"

## save.json key holding {id: true} for everything earned so far.
const SAVE_KEY := "unlocks"

## Counters that accumulate across runs. `total_kills`, `best_score` and
## `best_wave` are written by Storage.record_run() -- flush_run deliberately
## skips them so a run is never counted twice.
const SUM_KEYS: Array[String] = ["total_kills", "bosses", "elites", "crits", "charged",
	"purchases", "hard_clears"]
## Counters that only ever keep the best value seen.
const MAX_KEYS: Array[String] = ["best_score", "best_wave", "best_streak", "no_armor_best_wave"]
## The subset flush_run() owns (everything record_run() does not already write).
const FLUSH_SUM_KEYS: Array[String] = ["bosses", "elites", "crits", "charged", "purchases", "hard_clears"]
const FLUSH_MAX_KEYS: Array[String] = ["best_streak", "no_armor_best_wave"]

## Row-major sheet order. `need.stat` must be one of SUM_KEYS/MAX_KEYS -- the
## suite checks that, so a typo cannot leave a condition that never fires.
const DEFS: Array[Dictionary] = [
	{"id": "neon_skin", "name": "Neon skin", "hint": "Reach wave 5",
		"need": {"stat": "best_wave", "at": 5}},
	{"id": "crimson_arena", "name": "Crimson arena", "hint": "Kill your first boss",
		"need": {"stat": "bosses", "at": 1}},
	{"id": "hollow_point", "name": "Hollow-point\nrounds", "hint": "500 lifetime kills",
		"need": {"stat": "total_kills", "at": 500}},
	{"id": "rime_horde", "name": "Rime horde", "hint": "1,000 lifetime kills",
		"need": {"stat": "total_kills", "at": 1000}},
	{"id": "rim_palette", "name": "Rim palette", "hint": "200 elite kills",
		"need": {"stat": "elites", "at": 200}},
	{"id": "trail_rounds", "name": "Trail rounds", "hint": "2,500 lifetime kills",
		"need": {"stat": "total_kills", "at": 2500}},
	{"id": "gold_crits", "name": "Gold crits", "hint": "Land 50 crits",
		"need": {"stat": "crits", "at": 50}},
	{"id": "streak_banners", "name": "Streak banners", "hint": "Hit a 50-kill streak",
		"need": {"stat": "best_streak", "at": 50}},
	{"id": "war_chest", "name": "War chest", "hint": "Best score 2,500+",
		"need": {"stat": "best_score", "at": 2500}},
	{"id": "nightmare", "name": "Nightmare\ndifficulty", "hint": "Clear a Hard run",
		"need": {"stat": "hard_clears", "at": 1}},
	{"id": "glass_cannon", "name": "Glass cannon", "hint": "Reach wave 12 with no Armor",
		"need": {"stat": "no_armor_best_wave", "at": 12}},
	{"id": "boss_rush", "name": "Boss rush", "hint": "Kill 5 bosses",
		"need": {"stat": "bosses", "at": 5}},
	{"id": "black_market", "name": "Black market", "hint": "100 lifetime purchases",
		"need": {"stat": "purchases", "at": 100}},
	{"id": "second_wind", "name": "Second wind", "hint": "Survive to wave 15",
		"need": {"stat": "best_wave", "at": 15}},
	{"id": "overcharge", "name": "Overcharge", "hint": "Fire 250 charged shots",
		"need": {"stat": "charged", "at": 250}},
	{"id": "vault_arena", "name": "Arena 3:\nVault", "hint": "Clear wave 20",
		"need": {"stat": "best_wave", "at": 20}},
	{"id": "boss_track_2", "name": "Boss track 2", "hint": "Kill 10 bosses",
		"need": {"stat": "bosses", "at": 10}},
	{"id": "mid_boss_waves", "name": "Mid-boss waves", "hint": "Clear wave 30",
		"need": {"stat": "best_wave", "at": 30}},
	{"id": "fast_shop", "name": "Fast shop", "hint": "50 lifetime purchases",
		"need": {"stat": "purchases", "at": 50}},
	{"id": "run_stats", "name": "Run stats\ntab", "hint": "Reach wave 25",
		"need": {"stat": "best_wave", "at": 25}},
]

static var _earned: Dictionary = {}
static var _loaded: bool = false


static func icon_path(id: String) -> String:
	return ICON_DIR + id + ".png"


## Display name for a row, or the id itself if the row is gone (a rename must not
## crash a callout).
static func display_name(id: String) -> String:
	for d: Dictionary in DEFS:
		if String(d.id) == id:
			return String(d.name).replace("\n", " ")
	return id


## Has this been earned? Cached -- safe to call from a per-frame path.
static func is_unlocked(id: String) -> bool:
	return bool(_earned_set().get(id, false))


## Every id earned so far (read-only; the dictionary is the live cache).
static func earned() -> Dictionary:
	return _earned_set()


static func count_unlocked() -> int:
	var unlocked: int = 0
	for id: String in _earned_set():
		if bool(_earned_set()[id]):
			unlocked += 1
	return unlocked


## Drop the cache after the flags changed (evaluate/flush) or the save was reset.
static func refresh() -> void:
	_loaded = false
	_earned = {}


## Does `stats` satisfy this row's condition? `stats` is a full progress view
## (stored totals merged with the live run), not just one counter.
static func qualifies(id: String, stats: Dictionary) -> bool:
	for d: Dictionary in DEFS:
		if String(d.id) != id:
			continue
		var need: Dictionary = d.get("need", {})
		if need.is_empty():
			return false
		return int(stats.get(String(need.get("stat", "")), 0)) >= int(need.get("at", 1))
	return false


## Judge every row against `stored + run_stats` and persist whatever just became
## true. Returns the newly earned ids, in registry order (empty on the common
## path). Never writes the counters -- only the flags.
static func evaluate(run_stats: Dictionary = {}) -> Array[String]:
	var stored: Dictionary = Storage.read_all()
	var view: Dictionary = _merged(stored, run_stats)
	var earned_flags: Dictionary = _flag_dict(stored)
	var newly: Array[String] = []
	for d: Dictionary in DEFS:
		var id: String = String(d.id)
		if bool(earned_flags.get(id, false)):
			continue
		if qualifies(id, view):
			earned_flags[id] = true
			newly.append(id)
	if newly.is_empty():
		return newly
	stored[SAVE_KEY] = earned_flags
	Storage.write_all(stored)
	refresh()
	return newly


## Add this run's counters to the stored totals. ONCE per run, at the end -- the
## keys record_run() already owns are skipped so nothing is counted twice.
static func flush_run(run_stats: Dictionary) -> void:
	var stored: Dictionary = Storage.read_all()
	for key: String in FLUSH_SUM_KEYS:
		if run_stats.has(key):
			stored[key] = int(stored.get(key, 0)) + int(run_stats[key])
	for key: String in FLUSH_MAX_KEYS:
		if run_stats.has(key):
			stored[key] = maxi(int(stored.get(key, 0)), int(run_stats[key]))
	Storage.write_all(stored)
	refresh()


static func _merged(stored: Dictionary, run_stats: Dictionary) -> Dictionary:
	var view: Dictionary = stored.duplicate()
	for key: String in SUM_KEYS:
		if run_stats.has(key):
			view[key] = int(view.get(key, 0)) + int(run_stats[key])
	for key: String in MAX_KEYS:
		if run_stats.has(key):
			view[key] = maxi(int(view.get(key, 0)), int(run_stats[key]))
	return view


static func _flag_dict(stored: Dictionary) -> Dictionary:
	var raw: Variant = stored.get(SAVE_KEY, {})
	if raw is Dictionary:
		return raw as Dictionary
	return {}


static func _earned_set() -> Dictionary:
	if not _loaded:
		_earned = _flag_dict(Storage.read_all())
		_loaded = true
	return _earned
