extends Node
class_name Beasts
## The enemy roster: every type in the game, its display name, one line on how it
## fights, and its stats -- grouped by the tagging group the enemy scenes actually
## join ("", "elites", "bosses"; EnemyBase._ready adds "enemies").
##
## This is ONE list on purpose: the WaveManager builds its spawn registry from it
## (scene path + short name) and the pause menu's BESTIARY tab renders it, so
## adding an enemy is a row here plus its scene -- never three lists to keep in
## step. `ROSTER` is the subset the WaveManager spawns, and the ORDER IS THE
## SPAWN WAVE's roster order in the composition table.
##
## Scenario slot for the portrait: `scenes/bestiary/<id>.png`, if it ever exists.
## Until then the tab draws the enemy's own octagon at runtime (see
## PauseMenu._beast_icon) -- no art authoring, and a new enemy still gets a
## portrait that is recognisably ITS silhouette.
##
## `hp` is the base health as authored in the scene, before the wave, difficulty,
## arena and director multipliers. Listed for reference, not for balance.
##
## `id` is BOTH the row's key and the display name (the enemy scenes' slugs are
## the WaveManager's composition keys, and they are these same strings lowercased
## for the base roster; the boss rows all share the one `boss` slug).

const Storage := preload("res://scripts/storage.gd")

## Group keys, in display order, each with the heading the pause menu prints.
## One map, so a 4th group is a row here and nothing else -- a hardcoded heading
## list in the UI is how a roster and its labels drift apart.
const GROUP_LABELS: Dictionary = {"": "NORMAL", "elites": "ELITES", "bosses": "BOSSES"}
## Family defaults for an elite variant (see the elite rows in DEFS for the
## per-row `hp_mult` and the comment above `elite_rows()`).
const ELITE_HP_MULT := 2.5
const ELITE_SCORE_MULT := 3.0

const DEFS: Array[Dictionary] = [
	{"id": "Chaser", "name": "Chaser", "group": "", "hp": 40,
		"scene": "res://scenes/enemy_chaser.tscn", "slug": "chaser",
		"hint": "Steady pursuit. The baseline every other enemy is measured against."},
	{"id": "Rusher", "name": "Rusher", "group": "", "hp": 22,
		"scene": "res://scenes/enemy_rusher.tscn", "slug": "rusher",
		"hint": "Fast and fragile. Flashes, then dashes in a locked line -- side-step it."},
	{"id": "Tank", "name": "Tank", "group": "", "hp": 90,
		"scene": "res://scenes/enemy_tank.tscn", "slug": "tank",
		"hint": "Slow, heavy, shrugs off knockback and launches you on contact."},
	{"id": "Weaver", "name": "Weaver", "group": "", "hp": 30,
		"scene": "res://scenes/enemy_weaver.tscn", "slug": "weaver",
		"hint": "Zig-zags in: a sine sway across its approach line, so it dodges without aiming at you."},
	{"id": "Orbiter", "name": "Orbiter", "group": "", "hp": 25,
		"scene": "res://scenes/enemy_orbiter.tscn", "slug": "orbiter",
		"hint": "Circles you on a fixed ring instead of closing -- fastest of the melee."},
	{"id": "Shooter", "name": "Shooter", "group": "", "hp": 35,
		"scene": "res://scenes/enemy_shooter.tscn", "slug": "shooter",
		"hint": "Keeps its distance and fires. Backs off when you crowd it."},
	{"id": "Splitter", "name": "Splitter", "group": "", "hp": 60,
		"scene": "res://scenes/enemy_splitter.tscn", "slug": "splitter",
		"hint": "Bursts into two minis on death. Minis count -- the wave is not clear until they are."},
	{"id": "Mini", "name": "Mini", "group": "", "hp": 18,
		"scene": "res://scenes/enemy_mini.tscn", "slug": "",
		"hint": "A splitter's offspring: small, fast, only ever arrives in pairs."},
	{"id": "Leaper", "name": "Leaper", "group": "", "hp": 26,
		"scene": "res://scenes/enemy_leaper.tscn", "slug": "leaper",
		"hint": "Plants, flashes, then leaps. Discrete hops with a rest between them."},
	{"id": "Bulwark", "name": "Bulwark", "group": "", "hp": 130,
		"scene": "res://scenes/enemy_bulwark.tscn", "slug": "bulwark",
		"hint": "Slow armoured carrier with an aura that cuts damage taken by everything near it. Kill it first."},
	{"id": "Sniper", "name": "Sniper", "group": "", "hp": 52,
		"scene": "res://scenes/enemy_sniper.tscn", "slug": "sniper",
		"hint": "Holds a long line and hits hard from it. Close the gap or break line of sight."},
	{"id": "Pulsar", "name": "Pulsar", "group": "", "hp": 68,
		"scene": "res://scenes/enemy_pulsar.tscn", "slug": "pulsar",
		"hint": "Orbits you and pulses a full ring of shots on a timer."},
	{"id": "Medic", "name": "Medic", "group": "", "hp": 86,
		"scene": "res://scenes/enemy_medic.tscn", "slug": "medic",
		"hint": "Heals every enemy around it on a timer. It is the reason a wave suddenly will not die."},
	{"id": "Skirmisher", "name": "Skirmisher", "group": "", "hp": 48,
		"scene": "res://scenes/enemy_skirmisher.tscn", "slug": "skirmisher",
		"hint": "Fast, closes in, and pecks at you with quick light shots."},
	{"id": "Rammer", "name": "Rammer", "group": "", "hp": 120,
		"scene": "res://scenes/enemy_rammer.tscn", "slug": "rammer",
		"hint": "Builds speed the longer it chases, up to a punishing collision."},

	{"id": "Elite Chaser", "name": "Elite Chaser", "group": "elites", "hp": 120,
		"scene": "res://scenes/enemy_elite.tscn", "slug": "elite_chaser",
		"elite": true, "hp_mult": 1.0, "affix": "",
		"hint": "The classic elite: a chaser that shields itself in bursts. Cyan means wait, natural colour means fire."},

	# --- Elite variants: one per archetype you can meet ------------------------
	# An elite is its base scene promoted at spawn: the same silhouette and the
	# same behaviour, plus the shielded phase (the affix that IS the elite's
	# mechanic), ELITE_HP_MULT health and ELITE_SCORE_MULT score. Only the
	# registry distinguishes them -- there is no per-enemy elite scene, so a new
	# enemy gets an elite variant for free.
	{"id": "Elite Rusher", "name": "Elite Rusher", "group": "elites", "hp": 55,
		"scene": "res://scenes/enemy_rusher.tscn", "slug": "elite_rusher", "elite": true,
		"hint": "Goes untouchable in bursts, then dashes. Bait the dash, punish the open window."},
	{"id": "Elite Tank", "name": "Elite Tank", "group": "elites", "hp": 225,
		"scene": "res://scenes/enemy_tank.tscn", "slug": "elite_tank", "elite": true,
		"hint": "A tank behind a shield phase: wait out the cyan, then unload."},
	{"id": "Elite Weaver", "name": "Elite Weaver", "group": "elites", "hp": 75,
		"scene": "res://scenes/enemy_weaver.tscn", "slug": "elite_weaver", "elite": true,
		"hint": "Still sways across its approach, and now the dodging is paid for."},
	{"id": "Elite Orbiter", "name": "Elite Orbiter", "group": "elites", "hp": 63,
		"scene": "res://scenes/enemy_orbiter.tscn", "slug": "elite_orbiter", "elite": true,
		"hint": "Keeps its ring and adds a cycle: you have to time the ring instead of just outrunning it."},
	{"id": "Elite Shooter", "name": "Elite Shooter", "group": "elites", "hp": 88,
		"scene": "res://scenes/enemy_shooter.tscn", "slug": "elite_shooter", "elite": true,
		"hint": "Untouchable between volleys. The gap in its shield is the gap you close."},
	{"id": "Elite Splitter", "name": "Elite Splitter", "group": "elites", "hp": 150,
		"scene": "res://scenes/enemy_splitter.tscn", "slug": "elite_splitter", "elite": true,
		"hint": "Kill it in an open window, or fight its minis and the shield both."},
	{"id": "Elite Leaper", "name": "Elite Leaper", "group": "elites", "hp": 65,
		"scene": "res://scenes/enemy_leaper.tscn", "slug": "elite_leaper", "elite": true,
		"hint": "Shields between hops -- the flash tells you which half of the cycle you are in."},
	{"id": "Elite Bulwark", "name": "Elite Bulwark", "group": "elites", "hp": 325,
		"scene": "res://scenes/enemy_bulwark.tscn", "slug": "elite_bulwark", "elite": true,
		"hint": "A shielded aura carrier. Its cover and its shield multiply, so it dies last for a reason."},
	{"id": "Elite Sniper", "name": "Elite Sniper", "group": "elites", "hp": 130,
		"scene": "res://scenes/enemy_sniper.tscn", "slug": "elite_sniper", "elite": true,
		"hint": "Holds its long line behind a shield phase. Break the line before you break the shield."},
	{"id": "Elite Pulsar", "name": "Elite Pulsar", "group": "elites", "hp": 170,
		"scene": "res://scenes/enemy_pulsar.tscn", "slug": "elite_pulsar", "elite": true,
		"hint": "The ring pattern keeps coming while the shield cycles: dodge on its clock, not yours."},
	{"id": "Elite Medic", "name": "Elite Medic", "group": "elites", "hp": 215,
		"scene": "res://scenes/enemy_medic.tscn", "slug": "elite_medic", "elite": true,
		"hint": "Heals the pack from behind a shield phase -- and the shield is what makes it a priority."},
	{"id": "Elite Skirmisher", "name": "Elite Skirmisher", "group": "elites", "hp": 120,
		"scene": "res://scenes/enemy_skirmisher.tscn", "slug": "elite_skirmisher", "elite": true,
		"hint": "Quick light shots, and a window you have to plan a burst around."},
	{"id": "Elite Rammer", "name": "Elite Rammer", "group": "elites", "hp": 300,
		"scene": "res://scenes/enemy_rammer.tscn", "slug": "elite_rammer", "elite": true,
		"hint": "Still builds speed. The shield only decides when you are allowed to answer."},

	{"id": "Warden", "name": "Warden", "group": "bosses", "hp": 5500,
		"scene": "res://scenes/enemy_boss.tscn", "slug": "boss",
		"hint": "The base boss. Walks through cover and sprays bullet-hell patterns in three phases."},
	{"id": "Tempest", "name": "Tempest", "group": "bosses", "hp": 4800,
		"scene": "res://scenes/enemy_boss_tempest.tscn", "slug": "boss",
		"hint": "The fastest boss: rapid fire, then a committed charge in phase three."},
	{"id": "Hive", "name": "Hive", "group": "bosses", "hp": 6200,
		"scene": "res://scenes/enemy_boss_hive.tscn", "slug": "boss",
		"hint": "Keeps summoning reinforcements, so the arena never empties while it lives."},
	{"id": "Juggernaut", "name": "Juggernaut", "group": "bosses", "hp": 7600,
		"scene": "res://scenes/enemy_boss_juggernaut.tscn", "slug": "boss",
		"hint": "The heaviest boss: shock rings that force you to keep moving."},
]


## Rows the wave spawner draws from, as {id, slug, scene, elite, hp_mult, affix} --
## derived from DEFS so the two can never drift. `mini` has no slug (the splitter
## spawns it), the boss rows all map to the one roster entry the boss rule picks
## from, and the elite rows carry the multipliers the spawner applies to a base
## archetype promoted to elite.
static func roster() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in DEFS:
		var slug: String = String(d.get("slug", ""))
		if slug == "":
			continue
		var elite: bool = bool(d.get("elite", false))
		out.append({
			"id": String(d.id),
			"slug": slug,
			"scene": String(d.scene),
			"elite": elite,
			# The family default lives here so a row that wants different numbers
			# says so in its own `hp_mult` (the chaser's elite scene is already
			# authored as an elite, so it carries 1.0).
			"hp_mult": float(d.get("hp_mult", ELITE_HP_MULT if elite else 1.0)),
			"score_mult": float(d.get("score_mult", ELITE_SCORE_MULT if elite else 1.0)),
			# An elite's shield phase IS its identity, so it is the family default
			# like the multipliers above: a row that does the shielding itself (the
			# chaser's dedicated elite scene) says `"affix": ""`.
			"affix": String(d.get("affix", "shielded" if elite else "")),
		})
	return out


## The ONE lookup the spawner does: a roster row by slug, or {} for an unknown
## type. Scene, elite flag, multipliers and forced affix all come from the row.
static func roster_row(slug: String) -> Dictionary:
	for row: Dictionary in roster():
		if String(row.slug) == slug:
			return row
	return {}


## Every elite variant, in registry order.
static func elite_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in DEFS:
		if bool(d.get("elite", false)):
			out.append(d)
	return out


## A random elite variant's slug: the composition's `elite` count says HOW MANY
## elites a wave fields, this says which archetypes they are.
static func random_elite_slug() -> String:
	var rows: Array[Dictionary] = elite_rows()
	if rows.is_empty():
		return ""
	return String(rows[randi() % rows.size()].slug)


static func is_elite_slug(slug: String) -> bool:
	return bool(roster_row(slug).get("elite", false))


## Display name for an id, or the id itself (a display path must never be the
## thing that crashes).
static func display_name(id: String) -> String:
	for d: Dictionary in DEFS:
		if String(d.id) == id:
			return String(d.name)
	return id


## Short name for a roster row, used to spawn the base composition out of it.
static func slug_name(slug: String) -> String:
	for d: Dictionary in DEFS:
		if String(d.get("slug", "")) == slug:
			return String(d.name)
	return slug


## Every row in one group, in registry order.
static func group(group_key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in DEFS:
		if String(d.group) == group_key:
			out.append(d)
	return out


## Every group key in display order, derived from the registry so a group with no
## rows cannot leave an empty heading behind.
static func groups() -> Array[String]:
	var out: Array[String] = []
	for key: String in GROUP_LABELS:
		if not group(key).is_empty():
			out.append(key)
	return out


# ------------------------------------------------------------------ seen ---
# Which enemies the player has actually MET, for the BESTIARY's progress line.
# The set is in memory and flushed into the save at run boundaries (Main calls
# flush() where it already persists the other lifetime counters), so a probe that
# spawns 20 enemies does not write the save 20 times.

const SAVE_KEY := "seen_beasts"
static var _seen: Dictionary = {}


## Called by EnemyBase._ready with the instance's own scene path: the registry id
## IS the scene stem (enemy_boss_hive.tscn -> boss_hive, and the row's `id` is the
## display name), so no enemy has to know its row and a new enemy is tracked the
## moment its scene exists. `elite` picks the VARIANT row: an elite shares its base
## scene, so the flag is the only thing that tells the two apart.
static func note_encountered(scene_path: String, elite: bool = false) -> void:
	var id: String = elite_id_for_scene(scene_path) if elite else id_for_scene(scene_path)
	if id != "":
		_seen[id] = true


## The base row for a scene. Elite rows are skipped on purpose: they share their
## base's scene, so the first match must be the normal enemy.
static func id_for_scene(scene_path: String) -> String:
	for d: Dictionary in DEFS:
		if String(d.scene) == scene_path and not bool(d.get("elite", false)):
			return String(d.id)
	return ""


## The elite VARIANT row for a base scene.
static func elite_id_for_scene(scene_path: String) -> String:
	for d: Dictionary in DEFS:
		if String(d.scene) == scene_path and bool(d.get("elite", false)):
			return String(d.id)
	return ""


## Everything encountered: the saved set merged with this session's. Read-only --
## `refresh_bestiary()` calls it on every pause.
static func seen_ids() -> Dictionary:
	var out: Dictionary = {}
	var saved: Variant = Storage.read_all().get(SAVE_KEY, {})
	if saved is Dictionary:
		out = (saved as Dictionary).duplicate()
	for id: String in _seen:
		out[id] = true
	return out


static func seen_count() -> int:
	return seen_ids().size()


## Persist this session's encounters. Merge-write, like every other save caller,
## so it cannot stomp a key another system just wrote.
static func flush() -> void:
	Storage.set_value(SAVE_KEY, seen_ids())


## Test-only: forget the in-memory set. The suite owns the saved key and clears it
## in its own setup, so this only stops one probe's spawns leaking into the next.
static func forget() -> void:
	_seen.clear()
