extends Node
## Tiny JSON store for the handful of things that outlive a run: the best
## score/wave and the audio mute flags. One file, one flat dictionary.
##
## ponytail: no schema version and no migration chain -- add one when a saved
## shape actually has to change, not before. Every caller takes an optional
## `path` so tests can round-trip against a temp file instead of the player's
## real save.

const PATH := "user://save.json"

## Keys that belong to the PLAYER, not to a run: a progress reset must keep them.
## `difficulty`, `glass_cannon` and `boss_rush` are the menu's run preferences --
## wiping records must not silently move the player back to NORMAL either.
const PREFERENCE_KEYS: Array[String] = ["music_volume", "sfx_volume", "endless",
	"difficulty", "glass_cannon", "boss_rush", "fog", "elite_storm", "no_shop"]


static func read_all(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	push_warning("[Storage] %s is not a JSON object -- ignoring it." % path)
	return {}


static func write_all(data: Dictionary, path: String = PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[Storage] cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data))
	f.close()


static func get_value(key: String, fallback: Variant, path: String = PATH) -> Variant:
	return read_all(path).get(key, fallback)


## Merge-write one key, so the audio flags and the records never stomp each
## other's entries in the shared file.
static func set_value(key: String, value: Variant, path: String = PATH) -> void:
	var data: Dictionary = read_all(path)
	data[key] = value
	write_all(data, path)


## Compare a finished run against the stored record, persist the improvement,
## and hand back everything the game-over panel needs to print.
## `kills` accumulates into a lifetime total, so the menu can show it.
## Returns {best_score, best_wave, new_score, new_wave, total_kills}.
static func record_run(score: int, wave: int, kills: int = 0, path: String = PATH) -> Dictionary:
	var data: Dictionary = read_all(path)
	var prev_score: int = int(data.get("best_score", 0))
	var prev_wave: int = int(data.get("best_wave", 0))
	var result := {
		"best_score": maxi(prev_score, score),
		"best_wave": maxi(prev_wave, wave),
		"new_score": score > prev_score,
		"new_wave": wave > prev_wave,
		"total_kills": int(data.get("total_kills", 0)) + kills,
	}
	data["best_score"] = result["best_score"]
	data["best_wave"] = result["best_wave"]
	data["total_kills"] = result["total_kills"]
	write_all(data, path)
	return result


## Salvage: the meta-currency banked from a run's unspent credits (a share,
## banked at game over) and spent on permanent perks in the pause menu. It is
## earned PROGRESS, not a preference, so RESET SAVE wipes it with the records.
static func record_salvage(amount: int, path: String = PATH) -> void:
	if amount <= 0:
		return
	var data := read_all(path)
	data["salvage"] = int(data.get("salvage", 0)) + amount
	write_all(data, path)


## Current salvage balance.
static func salvage(path: String = PATH) -> int:
	return int(read_all(path).get("salvage", 0))


## Spend up to `amount` salvage. Returns what was actually spent (clamped to the
## balance), so a caller can detect a shortfall. Kept here rather than reused from
## record_salvage() because that helper deliberately ignores non-positive amounts.
static func spend_salvage(amount: int, path: String = PATH) -> int:
	if amount <= 0:
		return 0
	var data: Dictionary = read_all(path)
	var balance: int = int(data.get("salvage", 0))
	var spent: int = mini(balance, amount)
	data["salvage"] = balance - spent
	write_all(data, path)
	return spent


## Erase the run records and keep the preferences (mutes, endless). One owner
## for "what counts as progress", so no caller has to remember the key list.
static func reset_progress(path: String = PATH) -> void:
	var data: Dictionary = read_all(path)
	var kept: Dictionary = {}
	for key: String in PREFERENCE_KEYS:
		if data.has(key):
			kept[key] = data[key]
	write_all(kept, path)


## Best wave reached on one difficulty (the STATS tab's "best wave by difficulty"
## rows). Keyed `best_wave_<id>`, max-merged, so a worse run never lowers it.
static func record_difficulty_wave(difficulty: String, wave: int, path: String = PATH) -> void:
	if difficulty == "" or wave <= 0:
		return
	var key: String = "best_wave_" + difficulty
	var data: Dictionary = read_all(path)
	if int(data.get(key, 0)) >= wave:
		return
	data[key] = wave
	write_all(data, path)
