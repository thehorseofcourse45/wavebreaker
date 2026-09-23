extends Node
## Gated self-test. Run with  NEON_TEST  in OS.get_cmdline_args().
## Exercises: upgrade economy (buy/gate/level), shop pause handoff,
## wave_table new keys, splitter pair joining wave roster.

const Storage := preload("res://scripts/storage.gd")

## A maxed build must need at least this long to clear the wave-10 ENCOUNTER
## (both bosses, killed back to back). Measured at boss_count=2 x 9000 base hp
## (the hardened Warden); raise it together with the boss's max_health /
## boss_count for a longer fight.
const MIN_BOSS_FIGHT_SECONDS := 10.0

func attach_to(main: Node) -> void:
	if "NEON_TEST" in OS.get_cmdline_args():
		call_deferred("_run", main)
	else:
		queue_free()

func _run(main: Node) -> void:
	await main.get_tree().create_timer(0.3).timeout
	var failed: Array[String] = []
	# The game persists a save file now (records + audio flags). Snapshot it so a
	# test run can never destroy the player's own data, and restore it at the end.
	var save_had_file: bool = FileAccess.file_exists(Storage.PATH)
	var save_snapshot: PackedByteArray = PackedByteArray()
	if save_had_file:
		var save_f := FileAccess.open(Storage.PATH, FileAccess.READ)
		if save_f != null:
			save_snapshot = save_f.get_buffer(save_f.get_length())
			save_f.close()
	# Unlockable flags are cleared for the WHOLE run, not just the unlockables
	# section: several probes answer differently once something is earned (shop
	# prices with black_market, the difficulty row with nightmare, the boss rule
	# with mid_boss_waves) and the suite must never depend on the player's own
	# progress. The real save is restored at the end.
	Storage.set_value(Unlockables.SAVE_KEY, {})
	Unlockables.refresh()
	Storage.set_value(Perks.SAVE_KEY, {})
	Perks.refresh()
	# Run-mode preferences pin off too: the composition assertions read the
	# AUTHORED table, and Main re-seeds the live flags from these keys every
	# time a probe returns to the menu (a save with random_waves on rolls
	# archetypes that carry no "elite" key and share no keys with the table).
	Storage.set_value("random_waves", false)
	Storage.set_value("boss_rush", false)

	# -- Upgrade economy ------------------------------------------------------
	var up: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(up)
	var player: Node = main.get_node("World/Player")
	# The loadout is a saved preference as well: Main seeded the player with the
	# save's gun before this suite ran, and the upgrade/balance probes below
	# assume the scene's baseline rifle (e.g. needler bottoms fire_rate out at
	# the 0.06 floor, so a buy cannot shrink it).
	Storage.set_value(Weapons.SAVE_KEY, Weapons.DEFAULT_ID)
	player.apply_weapon(Weapons.DEFAULT_ID)
	var base_damage: int = player.bullet_damage
	var base_hp: int = player.max_health
	var base_rate: float = player.fire_rate
	up.buy("fire_rate", 99999, player)
	if player.fire_rate >= base_rate:
		failed.append("fire_rate should have shrunk after buy")

	var r0: Dictionary = up.buy("damage", 120, player)
	if not bool(r0.ok):
		failed.append("buy damage ok")
	if player.bullet_damage != base_damage + 4:
		failed.append("damage +4 applied, got %d" % player.bullet_damage)
	if up.level("damage") != 1:
		failed.append("damage level 1")
	# gate: only 39 credits, second purchase (204 = 120 x 1.70 growth) must fail
	var r1: Dictionary = up.buy("damage", 39, player)
	if bool(r1.ok):
		failed.append("124-cost purchase with 39 should fail")
	# max level
	for i in range(20):
		up.buy("max_hp", 99999, player)
	if up.level("max_hp") != 4:
		failed.append("max_hp capped at 4, got %d" % up.level("max_hp"))
	var r2: Dictionary = up.buy("max_hp", 99999, player)
	if bool(r2.ok):
		failed.append("buy past max should fail")
	if player.max_health <= base_hp:
		failed.append("max_hp should have grown")
	# --- reset incidentals from the earlier probe ----------------------------
	player.bullet_damage = base_damage
	player.max_health = base_hp
	player.health = base_hp
	player.fire_rate = base_rate
	up.queue_free()

	# -- Wave composition -----------------------------------------------------
	var wm: Node = main.get_node("WaveManager")
	# The composition assertions below are written against the AUTHORED table.
	# Main seeded the live flags from the player's save before this suite ran
	# (random_waves in particular rolls archetypes that carry no "elite" key),
	# so pin them off here -- same reason _hp_mult/_speed_mult get pinned later.
	wm.random_waves = false
	wm.boss_rush = false
	# Main holds its OWN copies of the run-mode preferences, seeded at boot and
	# pushed back onto the WaveManager by every start_game() -- clearing the
	# storage keys above cannot reach them, so pin Main's copies directly.
	main._random_waves = false
	main._boss_rush = false
	main._weapon = Weapons.DEFAULT_ID

	# -- The second twenty: buy-all, curated observables, icons ---------------
	# Idea-pin (20 new upgrades). Every DEFS row must buy at level 1 with a real
	# effect; the curated checks below cover one observable per family, and the
	# dedicated probes (burn / group mults / evasion / offers / bargain) follow.
	# Throwaway player + fresh registry: no live run stat is mutated. Pool
	# writes from the buy-all are undone with reset_run_config() at the end so
	# later probes (drop chance, crits) still see authored defaults.
	var d3_player: Node = load("res://scenes/player.tscn").instantiate()
	main.add_child(d3_player)
	var d3_up: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(d3_up)
	var d3_shop: CanvasLayer = main.get_node("UI/ShopPanel") as CanvasLayer
	if d3_up.DEFS.size() != 48:
		failed.append("upgrades: DEFS has %d rows, expected 48" % d3_up.DEFS.size())
	# repair is a full heal: start hurt so its arm is observable, not a no-op.
	d3_player.health = 1
	for d3_d: Dictionary in d3_up.DEFS:
		var d3_id := String(d3_d.id)
		var d3_r: Dictionary = d3_up.buy(d3_id, 99999, d3_player)
		if not bool(d3_r.ok):
			failed.append("upgrades: buy-all failed on %s" % d3_id)
			continue
		if d3_up.level(d3_id) != 1:
			failed.append("upgrades: %s did not reach level 1" % d3_id)
	# Curated observables, one per hook family. Expected values fold in
	# RARITY_EFFECT (common 1.0 / rare 1.25 / epic 1.5) at level 1.
	if not is_equal_approx(PickupPool.magnet_mult, 1.5):
		failed.append("magnet: magnet_mult %.2f, expected 1.50" % PickupPool.magnet_mult)
	if not is_equal_approx(d3_player.dash_cooldown, 1.6 * 0.85):
		failed.append("dash_cadence: cooldown %.3f, expected %.3f" % [d3_player.dash_cooldown, 1.6 * 0.85])
	if d3_player.dash_strike_dmg != 10:
		failed.append("dash_strike: damage %d, expected 10 (8 x 1.25 rare)" % d3_player.dash_strike_dmg)
	if not is_equal_approx(d3_player.bullet_scale, 1.18):
		failed.append("caliber: bullet_scale %.2f, expected 1.18" % d3_player.bullet_scale)
	if not is_equal_approx(d3_player.weapon_knockback, 1.3):
		failed.append("punch: knockback %.2f, expected 1.30" % d3_player.weapon_knockback)
	if not is_equal_approx(d3_player.bullet_spread_deg, 7.0 * 0.65):
		failed.append("focus: spread %.2f, expected %.2f" % [d3_player.bullet_spread_deg, 7.0 * 0.65])
	if not is_equal_approx(d3_player.charge_time, 0.6 * 0.80):
		failed.append("quickdraw: charge_time %.3f, expected %.3f" % [d3_player.charge_time, 0.6 * 0.80])
	if d3_player.retaliate_dmg != 8:
		failed.append("retaliate: damage %d, expected 8 (6 x 1.25 rare)" % d3_player.retaliate_dmg)
	if not is_equal_approx(PickupPool.extra_drop_chance, 0.1875):
		failed.append("scavenger: extra_drop_chance %.4f, expected 0.1875" % PickupPool.extra_drop_chance)
	if not is_equal_approx(d3_player.regen_rate, 0.25):
		failed.append("regen: rate %.2f, expected 0.25 (0.2 x 1.25 rare)" % d3_player.regen_rate)
	if not is_equal_approx(d3_player.adrenaline_mult, 1.1875):
		failed.append("adrenaline: mult %.4f, expected 1.1875" % d3_player.adrenaline_mult)
	if not is_equal_approx(BulletPool.vs_boss_mult, 1.375):
		failed.append("bossbane: vs_boss_mult %.3f, expected 1.375 (0.25 x 1.5 epic)" % BulletPool.vs_boss_mult)
	if not is_equal_approx(BulletPool.vs_elite_mult, 1.375):
		failed.append("mark: vs_elite_mult %.3f, expected 1.375" % BulletPool.vs_elite_mult)
	if not is_equal_approx(BulletPool.exec_mult, 1.6):
		failed.append("executioner: exec_mult %.2f, expected 1.60 (0.4 x 1.5 epic)" % BulletPool.exec_mult)
	if not is_equal_approx(BulletPool.burn_dps, 6.0):
		failed.append("burn: burn_dps %.1f, expected 6.0 (4 x 1.5 epic)" % BulletPool.burn_dps)
	if not is_equal_approx(d3_player.evasion_chance, 0.1):
		failed.append("evasion: chance %.3f, expected 0.10 (0.08 x 1.25 rare)" % d3_player.evasion_chance)
	if not is_equal_approx(d3_player.bullet_lifetime, 2.5):
		failed.append("longshot: lifetime %.2f, expected 2.50 (0 -> 2.0 x 1.25)" % d3_player.bullet_lifetime)
	# The third ten: one observable per row (same buy-all, same rarity maths).
	if not is_equal_approx(d3_player.acceleration, 2000.0 * 1.25):
		failed.append("handling: acceleration %.0f, expected %.0f (2000 x 1.25)" % [d3_player.acceleration, 2000.0 * 1.25])
	if not is_equal_approx(d3_player.dash_time, 0.16 * 1.20):
		failed.append("dash_time: linger %.3f, expected %.3f" % [d3_player.dash_time, 0.16 * 1.20])
	if not is_equal_approx(BulletPool.homing_range, 420.0 * 1.35):
		failed.append("seeker: homing_range %.0f, expected %.0f (420 x 1.35)" % [BulletPool.homing_range, 420.0 * 1.35])
	if not is_equal_approx(PickupPool.heal_mult, 1.5):
		failed.append("aid: heal_mult %.2f, expected 1.50" % PickupPool.heal_mult)
	if not is_equal_approx(d3_player.credit_mult, 1.1875):
		failed.append("bounty: credit_mult %.4f, expected 1.1875 (0.15 x 1.25 rare)" % d3_player.credit_mult)
	if not is_equal_approx(d3_player.knockback_resist, 0.4375):
		failed.append("anchor: resist %.4f, expected 0.4375 (0.35 x 1.25 rare)" % d3_player.knockback_resist)
	if not is_equal_approx(d3_player.charge_damage_mult, 3.0 * 1.3125):
		failed.append("charge_power: mult %.3f, expected %.3f" % [d3_player.charge_damage_mult, 3.0 * 1.3125])
	if not is_equal_approx(d3_player.charge_knockback_mult, 2.5 * 1.375):
		failed.append("charge_knock: mult %.3f, expected %.3f" % [d3_player.charge_knockback_mult, 2.5 * 1.375])
	if d3_player.charge_pierce != 3:
		failed.append("charge_pierce: %d, expected 3 (2 built-in + 1)" % d3_player.charge_pierce)
	if d3_player.last_stand_charges != 1:
		failed.append("last_stand: charges %d, expected 1 (flat +1)" % d3_player.last_stand_charges)
	# Icon parity: every row carries a known shape and a parseable colour.
	var d3_shapes: Array[String] = ["chevron", "bolt", "ring", "hex", "cross",
			"drop", "wing", "spark", "skull", "square", "default"]
	for d3_ic: Dictionary in d3_up.DEFS:
		var d3_ient: Variant = d3_ic.get("icon", null)
		if not (d3_ient is Array) or (d3_ient as Array).size() != 2:
			failed.append("icons: %s lacks a [shape, colour] icon entry" % String(d3_ic.id))
			continue
		if not d3_shapes.has(String((d3_ient as Array)[0])):
			failed.append("icons: %s uses unknown shape %s" % [String(d3_ic.id), String((d3_ient as Array)[0])])
		if not Color.html_is_valid(String((d3_ient as Array)[1])):
			failed.append("icons: %s colour %s does not parse" % [String(d3_ic.id), String((d3_ient as Array)[1])])
	# offers: deal() widens the hand by its level (OFFER_COUNT is 6, +1 here).
	d3_shop.deal(d3_up)
	if d3_shop._offered.size() != 7:
		failed.append("offers: hand has %d rows at level 1, expected 7" % d3_shop._offered.size())
	# bargain: one price formula, checked at every level (0 must stay REROLL_COST).
	var d3_bar: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(d3_bar)
	if ShopPanel.effective_reroll_cost(d3_bar) != ShopPanel.REROLL_COST:
		failed.append("bargain: level 0 costs %d, expected flat %d" % [ShopPanel.effective_reroll_cost(d3_bar), ShopPanel.REROLL_COST])
	d3_bar.buy("bargain", 99999, d3_player)
	if ShopPanel.effective_reroll_cost(d3_bar) != 18:
		failed.append("bargain: level 1 costs %d, expected 18" % ShopPanel.effective_reroll_cost(d3_bar))
	d3_bar.buy("bargain", 99999, d3_player)
	if ShopPanel.effective_reroll_cost(d3_bar) != 6:
		failed.append("bargain: level 2 costs %d, expected 6" % ShopPanel.effective_reroll_cost(d3_bar))
	d3_bar.queue_free()
	# evasion: chance 1 always dodges (no HP loss, no i-frame spent); 0 never does.
	d3_player.evasion_chance = 1.0
	d3_player._invuln_timer = 0.0
	var d3_ehp: int = d3_player.health
	d3_player.take_damage(30)
	if d3_player.health != d3_ehp:
		failed.append("evasion: chance 1.0 still took damage (%d -> %d)" % [d3_ehp, d3_player.health])
	d3_player.evasion_chance = 0.0
	d3_player._invuln_timer = 0.0
	d3_player.take_damage(30)
	if d3_player.health >= d3_ehp:
		failed.append("evasion: chance 0.0 dodged a hit")
	d3_player.health = d3_player.max_health
	# retaliate: a hit pulses every enemy inside 90 px (throwaway is at origin).
	# The WaveManager's container binding happens later in the suite, so reach
	# the live box straight from Main (same node the splitter probe installs).
	var d3_box: Node = main.get_node("World/EnemyContainer")
	var d3_ret_e: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	d3_ret_e.position = Vector2(50, 0)
	d3_ret_e.is_dormant = true
	d3_box.add_child(d3_ret_e)
	await main.get_tree().physics_frame
	d3_player.global_position = Vector2.ZERO
	d3_player._invuln_timer = 0.0
	var d3_rethp: int = d3_ret_e.health
	d3_player.take_damage(10)
	if d3_ret_e.health >= d3_rethp:
		failed.append("retaliate: adjacent enemy took no damage (%d -> %d)" % [d3_rethp, d3_ret_e.health])
	d3_ret_e.queue_free()
	# dash strike: one dash damages each body it touches exactly once.
	var d3_ds_e: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	d3_ds_e.position = Vector2(30, 0)
	d3_ds_e.is_dormant = true
	d3_box.add_child(d3_ds_e)
	await main.get_tree().physics_frame
	d3_player.global_position = Vector2.ZERO
	d3_player.controls_enabled = true
	var d3_dshp: int = d3_ds_e.health
	if not d3_player.try_dash():
		failed.append("dash strike: try_dash refused with controls enabled")
	await main.get_tree().physics_frame
	if d3_ds_e.health != d3_dshp - d3_player.dash_strike_dmg:
		failed.append("dash strike: enemy HP %d -> %d, expected -%d" % [d3_dshp, d3_ds_e.health, d3_player.dash_strike_dmg])
	d3_player.controls_enabled = false
	d3_ds_e.queue_free()
	# burn: a lit enemy ticks whole HP through take_damage, then stops when the
	# window ends. 40 px/s chaser parked far away cannot reach anyone in time.
	var d3_burn_e: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	d3_burn_e.position = Vector2(4000, 4000)
	d3_box.add_child(d3_burn_e)
	for i in 3:
		await main.get_tree().physics_frame
	var d3_bhp0: int = d3_burn_e.health
	d3_burn_e.apply_burn(4.0, 0.5)
	for i in 30:
		await main.get_tree().physics_frame
	var d3_bhp1: int = d3_burn_e.health
	if d3_bhp1 >= d3_bhp0:
		failed.append("burn: health unchanged after 0.5 s at 4 dps (%d)" % d3_bhp0)
	elif d3_bhp0 - d3_bhp1 > 4:
		failed.append("burn: dealt %d HP in 0.5 s at 4 dps, expected 1-4" % (d3_bhp0 - d3_bhp1))
	d3_burn_e.apply_burn(0.0, 0.0)   # cut the window (dps<=0 is refused; force it)
	d3_burn_e._burn_time_left = 0.0
	d3_burn_e._burn_dps = 0.0
	var d3_bhp2: int = d3_burn_e.health
	for i in 12:
		await main.get_tree().physics_frame
	if d3_burn_e.health != d3_bhp2:
		failed.append("burn: still ticking after the window closed (%d -> %d)" % [d3_bhp2, d3_burn_e.health])
	d3_burn_e.queue_free()
	# Group multipliers on a real hit: crit off, burn off, only the multiplier
	# under test left standing. Corridor y=100 is the suite's reserved lane.
	var d3_sv_crit: float = BulletPool.crit_chance
	var d3_sv_burn: float = BulletPool.burn_dps
	var d3_sv_boss: float = BulletPool.vs_boss_mult
	var d3_sv_elite: float = BulletPool.vs_elite_mult
	var d3_sv_exec: float = BulletPool.exec_mult
	BulletPool.crit_chance = 0.0
	BulletPool.burn_dps = 0.0
	BulletPool.vs_boss_mult = 1.25
	BulletPool.vs_elite_mult = 1.0
	BulletPool.exec_mult = 1.0
	var d3_bb_boss: Node = load("res://scenes/enemy_boss.tscn").instantiate()
	d3_bb_boss.position = Vector2(355, 100)
	d3_bb_boss.is_dormant = true
	d3_box.add_child(d3_bb_boss)
	for i in 3:
		await main.get_tree().physics_frame
	var d3_bb_hp0: int = d3_bb_boss.health
	BulletPool.reset()
	var d3_bb_round: Node = BulletPool.fire(Vector2(-300, 100), Vector2.RIGHT, 12, 700.0)
	var d3_bb_frames := 0
	while is_instance_valid(d3_bb_round) and d3_bb_round.is_active and d3_bb_frames < 120:
		await main.get_tree().physics_frame
		d3_bb_frames += 1
	var d3_bb_want: int = int(round(12.0 * 1.25))
	if d3_bb_hp0 - d3_bb_boss.health != d3_bb_want:
		failed.append("bossbane: boss lost %d HP, expected %d (12 x 1.25)" % [d3_bb_hp0 - d3_bb_boss.health, d3_bb_want])
	# Wound it under 20% and stack executioner on top of bossbane.
	d3_bb_boss.take_damage(int(float(d3_bb_boss.max_health) * 0.85))
	BulletPool.exec_mult = 1.4
	var d3_bb_hp1: int = d3_bb_boss.health
	BulletPool.reset()
	var d3_bb_round2: Node = BulletPool.fire(Vector2(-300, 100), Vector2.RIGHT, 12, 700.0)
	var d3_bb_frames2 := 0
	while is_instance_valid(d3_bb_round2) and d3_bb_round2.is_active and d3_bb_frames2 < 120:
		await main.get_tree().physics_frame
		d3_bb_frames2 += 1
	var d3_bb_want2: int = int(round(12.0 * 1.25 * 1.4))
	if d3_bb_hp1 - d3_bb_boss.health != d3_bb_want2:
		failed.append("executioner: wounded boss lost %d HP, expected %d (12 x 1.25 x 1.4)" % [d3_bb_hp1 - d3_bb_boss.health, d3_bb_want2])
	d3_bb_boss.queue_free()
	# mark: elite group multiplier alone.
	BulletPool.vs_boss_mult = 1.0
	BulletPool.exec_mult = 1.0
	BulletPool.vs_elite_mult = 1.25
	var d3_mk_e: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	d3_mk_e.add_to_group("elites")   # manual: WaveManager promotes real elites itself
	d3_mk_e.position = Vector2(355, 100)
	d3_mk_e.is_dormant = true
	d3_box.add_child(d3_mk_e)
	for i in 3:
		await main.get_tree().physics_frame
	var d3_mk_hp0: int = d3_mk_e.health
	BulletPool.reset()
	var d3_mk_round: Node = BulletPool.fire(Vector2(-300, 100), Vector2.RIGHT, 12, 700.0)
	var d3_mk_frames := 0
	while is_instance_valid(d3_mk_round) and d3_mk_round.is_active and d3_mk_frames < 120:
		await main.get_tree().physics_frame
		d3_mk_frames += 1
	var d3_mk_want: int = int(round(12.0 * 1.25))
	if d3_mk_hp0 - d3_mk_e.health != d3_mk_want:
		failed.append("mark: elite lost %d HP, expected %d (12 x 1.25)" % [d3_mk_hp0 - d3_mk_e.health, d3_mk_want])
	d3_mk_e.queue_free()
	# Undo every pool write from this block: later probes pin authored defaults.
	BulletPool.crit_chance = d3_sv_crit
	BulletPool.burn_dps = d3_sv_burn
	BulletPool.vs_boss_mult = d3_sv_boss
	BulletPool.vs_elite_mult = d3_sv_elite
	BulletPool.exec_mult = d3_sv_exec
	BulletPool.reset_run_config()
	PickupPool.reset_run_config()
	BulletPool.reset()
	d3_player.queue_free()
	d3_up.queue_free()

	var comp1: Dictionary = wm._composition_for_wave(1)
	if not (comp1.has("weaver") and comp1.has("elite") and comp1.has("shooter")):
		failed.append("wave_table lacks new enemy keys")
	# The two new archetypes enter the authored table and survive into the
	# procedural stretch (a key only in the table is a wave that never spawns).
	var comp2: Dictionary = wm._composition_for_wave(2)
	if int(comp2.get("leaper", 0)) < 1:
		failed.append("wave 2 should field leapers")
	var comp3: Dictionary = wm._composition_for_wave(3)
	if int(comp3.get("bulwark", 0)) < 1:
		failed.append("wave 3 should field a bulwark")
	var comp6: Dictionary = wm._composition_for_wave(6)
	if int(comp6["elite"]) < 1:
		failed.append("wave 6 should include at least one elite")
	if int(comp6.get("bulwark", 0)) < 1 or int(comp6.get("leaper", 0)) < 1:
		failed.append("wave 6 lost the new archetypes")
	# procedural stretch should grow: wave 11's elite count > wave 6's
	# (wave 10 is a BOSS wave now, so it carries no elite by design -- compare
	# against the next ordinary procedural wave instead.)
	var comp10: Dictionary = wm._composition_for_wave(11)
	if int(comp10["elite"]) < int(comp6["elite"]):
		failed.append("procedural waves should at least keep elite count")
	if int(comp10.get("bulwark", 0)) < 1 or int(comp10.get("leaper", 0)) < 1:
		failed.append("procedural waves lost the new archetypes")

	# -- Splitter: pair spawns on death ---------------------------------------
	var wm_split_count_before: int = wm._alive
	wm._enemy_container = main.get_node("World/EnemyContainer")
	var sp: Node = load("res://scenes/enemy_splitter.tscn").instantiate()
	wm._enemy_container.add_child(sp)
	var got_pair: Array = [""]
	sp.connect("split_spawned", func(pair: Array) -> void: got_pair[0] = "yes")
	var spawned_before: float = sp.move_speed
	sp.initialize(sp.max_health, 1.0)
	if sp.move_speed != spawned_before:
		failed.append("initialize(1.0) changed speed")
	wm._enemy_container.remove_child(sp); sp.queue_free()
	if got_pair[0] != "":
		failed.append("split_spawned fired without death")

	# -- Shop pause wiring -----------------------------------------------------
	wm.shop_pause_enabled = true
	wm.is_running = true
	wm._alive = 0
	wm._spawn_queue.clear()
	var cleared_seen: Array = [false]
	wm.wave_cleared.connect(func(_n: int) -> void: cleared_seen[0] = true)
	wm._on_enemy_died(null)
	if not cleared_seen[0]:
		failed.append("wave_cleared did not emit on _on_enemy_died")
	if wm._intermission_timer.time_left > 0.0:
		failed.append("intermission started despite shop pause")
	wm.resume_waves()
	if not (wm._intermission_timer.time_left > 0.0):
		failed.append("resume_waves did not start intermission")
	wm.shop_pause_enabled = false
	wm.stop()

	# -- Tank actually dies (regression for "unkillable" report) ---------------
	var tank: Node = load("res://scenes/enemy_tank.tscn").instantiate()
	wm._enemy_container.add_child(tank)
	var tank_died := [false]
	tank.connect("died", func(_e: Node) -> void: tank_died[0] = true)
	tank.take_damage(50)
	if tank.health != tank.max_health - 50:
		failed.append("tank should have lost 50 hp, has %d" % tank.health)
	tank.take_damage(9999)
	if not tank_died[0]:
		failed.append("tank died signal never fired")
	tank.queue_free()

	# -- Bullet swept hit: a fast shot at a distant enemy still registers -----
	# Deterministic by construction: the dummy's position is set BEFORE it enters
	# the tree (set_deferred placement flaked one run in three -- under jitter Godot
	# runs several physics steps in one iteration and the deferred set only flushes
	# at the iteration boundary, so the aim was computed at the dummy's stale
	# pre-placement position). It is parked INSIDE the reserved clear corridor
	# (y=100, x=-300..360), ahead of the muzzle, and dormant so nothing moves it.
	var tank2: Node = load("res://scenes/enemy_tank.tscn").instantiate()
	tank2.position = Vector2(200, 100)
	tank2.is_dormant = true  # freeze: target must not wander mid-shot
	wm._enemy_container.add_child(tank2)
	var tank_hits := [0]
	tank2.connect("damaged", func(_a: int) -> void: tank_hits[0] += 1)
	for i in 2:
		await main.get_tree().physics_frame   # let the space state register the body
	var bullet: Node = BulletPool.fire(Vector2(-300, 100), Vector2.RIGHT, 12, 700.0)
	var fired_frames := 0
	while is_instance_valid(bullet) and bullet.is_active and fired_frames < 120:
		await main.get_tree().physics_frame
		fired_frames += 1
	# At ~60Hz the bullet crosses the 500 px lane in ~43 frames; 120 is a hard
	# budget, not slack -- a miss must time out loudly, not pass quietly.
	if tank_hits[0] != 1:
		failed.append("tank got %d hits, expected exactly 1 (sweep broken)" % tank_hits[0])
	if fired_frames >= 120:
		failed.append("bullet never deactivated (missed everything & timed out)")
	tank2.queue_free()
	# Long-range tunneling: speed so high a single frame outweighs the body.
	# Sweep must still register the hit mid-frame. The muzzle sits 15 px from the
	# dummy's centre, i.e. INSIDE its 22 px circle: the ray starts inside the body
	# and cannot report it, so this doubles as the swept-hit fallback's in-body
	# start case (a body overlapping the muzzle absorbs the shot, immediately).
	tank2 = load("res://scenes/enemy_tank.tscn").instantiate()
	tank2.position = Vector2(355, 100)
	tank2.is_dormant = true
	wm._enemy_container.add_child(tank2)
	var tank2_hits := [0]
	tank2.connect("damaged", func(_a: int) -> void: tank2_hits[0] += 1)
	for i in 2:
		await main.get_tree().physics_frame
	var bullet2: Node = BulletPool.fire(Vector2(340, 100), Vector2.RIGHT, 12, 2400.0)  # ~40px/frame
	fired_frames = 0
	while is_instance_valid(bullet2) and bullet2.is_active and fired_frames < 60:
		await main.get_tree().physics_frame
		fired_frames += 1
	if tank2_hits[0] != 1:
		failed.append("tunneling probe: expected 1 hit on thin band, got %d" % tank2_hits[0])
	tank2.queue_free()

	# -- Direct approach probe: knife-edge case. Chaser sits on the muzzle line. --
	var chase3: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	chase3.position = Vector2(-100, 240)
	chase3.is_dormant = true   # freeze for a deterministic first shot
	wm._enemy_container.add_child(chase3)
	var chase_hits := [0]
	chase3.connect("damaged", func(_a: int) -> void: chase_hits[0] += 1)
	for i in 3:   # 3 frames of damping so the space state settles
		await main.get_tree().physics_frame
	var b1: Node = BulletPool.fire(Vector2(-100, 40), Vector2(0, 1), 12, 700.0)
	var hit_frames := 0
	while is_instance_valid(b1) and b1.is_active and hit_frames < 60:
		await main.get_tree().physics_frame
		hit_frames += 1
	if chase_hits[0] < 1:
		# bullet reached its target without registering -- capture evidence
		failed.append("head-on probe: bullet did not register on dormant chaser at %s (bullet last at %s)" % [str(chase3.global_position), str(b1.global_position) if is_instance_valid(b1) else "?"])
	chase3.queue_free()

	# -- Moving-target probe: a LIVE enemy crosses the round's path mid-flight --
	# The chaser is live and steering at the player at the arena centre, but it
	# starts inside the corridor 50 px ahead of the muzzle, ON the firing line:
	# geometry guarantees the intercept (closing speed ~815 px/s, lateral drift
	# under 1 px/frame against a ~20 px combined radius), not wall-clock luck.
	var chaser2: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	chaser2.position = Vector2(-250, 100)
	wm._enemy_container.add_child(chaser2)
	var chaser_hits := [0]
	chaser2.connect("damaged", func(_a: int) -> void: chaser_hits[0] += 1)
	for i in 2:
		await main.get_tree().physics_frame
	var cb: Node = BulletPool.fire(Vector2(-300, 100), Vector2.RIGHT, 12, 700.0)
	var c_frames := 0
	while is_instance_valid(cb) and cb.is_active and c_frames < 30:
		await main.get_tree().physics_frame
		c_frames += 1
	if chaser_hits[0] < 1:
		failed.append("moving-chaser probe: 0 hits (sweep still flaky)")
	chaser2.queue_free()

	# -- Navmesh baked and paths AROUND cover exist ----------------------------
	await main.get_tree().physics_frame
	await main.get_tree().physics_frame
	var nav_region: NavigationRegion2D = main.get_node("World/NavRegion")
	var polys: int = nav_region.navigation_polygon.get_polygon_count()
	if polys < 1:
		failed.append("navmesh has 0 polygons (not baked)")
	# Route through a live NavigationAgent2D exactly like enemies do -- this is
	# the same code path the game actually depends on, so it tells the truth.
	var nav_probe: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	wm._enemy_container.add_child(nav_probe)
	nav_probe.set_deferred("global_position", Vector2(-400, 300))
	for i in 10:
		await main.get_tree().physics_frame   # let the map flush before we test
	nav_probe._nav.target_position = Vector2(0, 0)
	for i in 5:
		await main.get_tree().physics_frame
		if nav_probe._nav.is_target_reachable():
			break
	if not nav_probe._nav.is_target_reachable():
		failed.append("enemy NavigationAgent2D cannot path to player (navmesh carve or map link broken)")
	nav_probe.queue_free()

	# -- Arena: every spawn point is on the navmesh and can reach the player ----
	# A marker authored on top of a wall/obstacle, or a layout that seals a region
	# off, leaves those enemies unable to path -- and a wave that never clears.
	var arena_world: Node2D = main.get_node("World")
	var arena_map: RID = arena_world.get_world_2d().navigation_map
	var arena_spawns: Array[Node] = main.get_tree().get_nodes_in_group("spawn_points")
	if arena_spawns.size() < 4:
		failed.append("arena: %d spawn points, expected at least 4" % arena_spawns.size())
	var arena_player: Node2D = main.get_node("World/Player")
	# Direct geometry probe: a marker sitting on a wall/obstacle is the failure the
	# path check alone misses (the map silently snaps an off-mesh start to the
	# nearest walkable point, so the route still "exists").
	var arena_shape := CircleShape2D.new()
	arena_shape.radius = 20.0
	var arena_space: PhysicsDirectSpaceState2D = arena_world.get_world_2d().direct_space_state
	for arena_sp: Node in arena_spawns:
		var arena_from: Vector2 = (arena_sp as Node2D).global_position
		var arena_q := PhysicsShapeQueryParameters2D.new()
		arena_q.shape = arena_shape
		arena_q.collision_mask = 8          # Wall layer: outer walls + all obstacles
		arena_q.transform = Transform2D(0.0, arena_from)
		if not arena_space.intersect_shape(arena_q, 1).is_empty():
			failed.append("arena: spawn %s at %s is inside wall/obstacle geometry" % [arena_sp.name, str(arena_from)])
		var arena_path: PackedVector2Array = NavigationServer2D.map_get_path(
				arena_map, arena_from, arena_player.global_position, true)
		if arena_path.size() < 2:
			failed.append("arena: spawn %s at %s cannot path to the player (sealed off or blocked)" % [arena_sp.name, str(arena_from)])
		elif arena_path[0].distance_to(arena_from) > 30.0:
			failed.append("arena: spawn %s at %s sits %.0f px off the navmesh (no walkable ground there)" % [arena_sp.name, str(arena_from), arena_path[0].distance_to(arena_from)])

	# -- Pathfinding: an off-mesh target must not flip agents to straight-line --
	# The player stands a few px off the navmesh whenever it hugs a wall (the bake
	# insets walkable ground by the agent radius). Targeting that raw point once
	# made is_target_reachable() false, which flipped EVERY enemy to straight-line
	# steering -- the whole horde ignoring cover. The fix snaps the target to the
	# nearest mesh point. Drive a chaser at an off-mesh probe and prove it keeps a
	# path instead of beelining.
	var pn_probe := Node2D.new()
	pn_probe.global_position = Vector2(-795, 0)   # between the wall face and the mesh
	main.add_child(pn_probe)
	var pn_enemy: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	pn_enemy.global_position = Vector2(200, 0)
	wm._enemy_container.add_child(pn_enemy)
	pn_enemy._player = pn_probe   # force the agent to chase the off-mesh point
	for pn_i in 20:
		await main.get_tree().physics_frame
	var pn_snapped: Vector2 = NavigationServer2D.map_get_closest_point(arena_map, pn_probe.global_position)
	if pn_probe.global_position.distance_to(pn_snapped) < 5.0:
		failed.append("pathfinding: the probe point was not off the navmesh (test setup)")
	if pn_enemy.get_node("NavAgent").target_position.distance_to(pn_snapped) > 2.0:
		failed.append("pathfinding: the agent did not snap its target onto the navmesh")
	if pn_enemy._nav_fallback:
		failed.append("pathfinding: an off-mesh target flipped the agent to straight-line steering")
	pn_enemy.queue_free()
	pn_probe.queue_free()

	# -- Enemy scenes have valid bodies + scripts -----------------------------
	for scene_path in ["res://scenes/enemy_weaver.tscn", "res://scenes/enemy_orbiter.tscn",
			"res://scenes/enemy_shooter.tscn", "res://scenes/enemy_splitter.tscn",
			"res://scenes/enemy_elite.tscn", "res://scenes/enemy_mini.tscn",
			"res://scenes/enemy_bulwark.tscn", "res://scenes/enemy_leaper.tscn"]:
		var ps: PackedScene = load(scene_path)
		if ps == null:
			failed.append("scene failed to load: %s" % scene_path)
			continue
		var e: Node2D = ps.instantiate()
		if e.find_child("Body") == null:
			failed.append("%s: no Body" % scene_path)
		if e.find_child("CollisionShape2D") == null:
			failed.append("%s: no CollisionShape2D" % scene_path)
		# The neon rim is built in _ready() from the body polygon, and _ready only
		# runs in the tree -- so add it, read, then pull it straight back out
		# (free(), not queue_free(), or a group member survives the frame).
		main.add_child(e)
		var e_rim: Line2D = e.get_node_or_null("Rim") as Line2D
		var e_body: Polygon2D = e.get_node_or_null("Body") as Polygon2D
		if e_rim == null:
			failed.append("%s: no neon rim after _ready" % scene_path)
		elif e_body != null and e_rim.points.size() != e_body.polygon.size():
			failed.append("%s: rim outline does not match its body polygon (%d vs %d)" % [scene_path, e_rim.points.size(), e_body.polygon.size()])
		main.remove_child(e)
		e.free()

	# -- New archetypes: bulwark aura, leaper burst movement -------------------
	# Both must be real enemies (group + halo), must actually close on the
	# player, and the bulwark's aura must be a write through the shared
	# take_damage() path that leaves when it leaves.
	var arch_player: Node2D = main.get_node("World/Player")
	var bulwark: Node = load("res://scenes/enemy_bulwark.tscn").instantiate()
	bulwark.position = Vector2(-420, -320)
	wm._enemy_container.add_child(bulwark)
	var leaper: Node = load("res://scenes/enemy_leaper.tscn").instantiate()
	leaper.position = Vector2(-420, 340)
	wm._enemy_container.add_child(leaper)
	await main.get_tree().physics_frame
	if not bulwark.is_in_group("enemies"):
		failed.append("bulwark: not in the enemies group")
	if not leaper.is_in_group("enemies"):
		failed.append("leaper: not in the enemies group")
	if not _has_lit_halo(bulwark):
		failed.append("bulwark: no LitPointLight2D halo (invisible in a dark arena)")
	if not _has_lit_halo(leaper):
		failed.append("leaper: no LitPointLight2D halo (invisible in a dark arena)")
	# Movement: both start >500 px out; 40 physics frames (~0.66 s) at their
	# speeds closes 25-100 px -- strictly toward the player, whatever their
	# state machines did in between.
	var bulwark_start: float = bulwark.global_position.distance_to(arch_player.global_position)
	var leaper_start: float = leaper.global_position.distance_to(arch_player.global_position)
	for i in 40:
		await main.get_tree().physics_frame
	if bulwark.global_position.distance_to(arch_player.global_position) >= bulwark_start:
		failed.append("bulwark: never closed on the player (%.0f px)" % bulwark.global_position.distance_to(arch_player.global_position))
	if leaper.global_position.distance_to(arch_player.global_position) >= leaper_start:
		failed.append("leaper: never closed on the player (%.0f px)" % leaper.global_position.distance_to(arch_player.global_position))
	# Aura: in range -> mult < 1 and damage is actually mitigated; out of
	# range -> back to 1; freed while covering -> back to 1. The ward is a TANK:
	# 90 hp, so the 55-damage probe cannot kill it mid-probe and free the node
	# (the suite aborts on a freed access, hiding everything after it).
	var ward: Node = load("res://scenes/enemy_tank.tscn").instantiate()
	ward.position = Vector2(-350, -320)   # ~70 px from the bulwark: inside the aura
	ward.is_dormant = true
	wm._enemy_container.add_child(ward)
	for i in 5:
		await main.get_tree().physics_frame
	if ward.damage_taken_mult >= 1.0:
		failed.append("bulwark: neighbour inside the aura kept damage_taken_mult %.2f" % ward.damage_taken_mult)
	else:
		var ward_hp: int = ward.health
		ward.take_damage(100)
		if ward_hp - ward.health != 55:
			failed.append("bulwark: 100 damage through the aura moved health by %d, expected 55" % (ward_hp - ward.health))
	ward.position = Vector2(0, 560)   # far outside the aura
	for i in 5:
		await main.get_tree().physics_frame
	if not is_equal_approx(ward.damage_taken_mult, 1.0):
		failed.append("bulwark: neighbour out of range kept the aura mult (%.2f)" % ward.damage_taken_mult)
	ward.position = Vector2(-350, -320)   # back inside, then kill the bulwark under it
	for i in 5:
		await main.get_tree().physics_frame
	if ward.damage_taken_mult >= 1.0:
		failed.append("bulwark: aura never re-engaged after the neighbour returned")
	# A second overlapping source must keep the ward protected when the first
	# source leaves; this is the regression for source-clobbering auras.
	var bulwark_two: Node = load("res://scenes/enemy_bulwark.tscn").instantiate()
	bulwark_two.position = Vector2(-420, -320)
	wm._enemy_container.add_child(bulwark_two)
	for i in 3:
		await main.get_tree().physics_frame
	bulwark.queue_free()
	await main.get_tree().process_frame
	if ward.damage_taken_mult >= 1.0:
		failed.append("bulwark: one source leaving erased an overlapping aura")
	bulwark_two.queue_free()
	await main.get_tree().process_frame
	if not is_equal_approx(ward.damage_taken_mult, 1.0):
		failed.append("bulwark: the aura outlived all bulwarks (mult %.2f)" % ward.damage_taken_mult)
	ward.queue_free()
	leaper.queue_free()

	# -- Affixes: shielded / frenzied / volatile --------------------------------
	# Shielded: 0 damage while the shield is up, full damage in the down window.
	var aff_fixture: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	aff_fixture.affix = "shielded"
	aff_fixture.position = Vector2(-300, -420)
	wm._enemy_container.add_child(aff_fixture)
	await main.get_tree().physics_frame
	if not aff_fixture._affix_shielded:
		failed.append("affix shielded: shield never came up in _ready")
	var aff_hp0: int = aff_fixture.health
	var blocked_damage: int = aff_fixture.take_damage(10)
	if aff_fixture.health != aff_hp0:
		failed.append("affix shielded: damage leaked through a raised shield")
	if blocked_damage != 0:
		failed.append("damage accounting: a raised shield reported %d applied damage" % blocked_damage)
	aff_fixture._affix_shield_timer = 0.01   # force the toggle on the next tick
	var aff_shield_frames := 0
	while aff_fixture._affix_shielded and aff_shield_frames < 30:
		await main.get_tree().physics_frame
		aff_shield_frames += 1
	var applied_damage: int = aff_fixture.take_damage(10)
	if aff_fixture.health != aff_hp0 - 10:
		failed.append("affix shielded: %d damage in the down window, expected 10" % (aff_hp0 - aff_fixture.health))
	if applied_damage != 10:
		failed.append("damage accounting: an open hit reported %d applied damage, expected 10" % applied_damage)
	aff_fixture.queue_free()

	# Frenzied: measurably further over the same frames, its tint reaches the
	# halo (the documented trap: tints applied after the halo keeps the old
	# light colour), and its touch cooldown shrank.
	var plain_ch: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	plain_ch.position = Vector2(-400, 320)
	wm._enemy_container.add_child(plain_ch)
	var frenz_ch: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	frenz_ch.affix = "frenzied"
	frenz_ch.position = Vector2(-400, -320)
	wm._enemy_container.add_child(frenz_ch)
	var plain_contact: float = plain_ch.contact_cooldown
	await main.get_tree().physics_frame
	var plain_closing: float = plain_ch.global_position.distance_to(arch_player.global_position)
	var frenz_closing: float = frenz_ch.global_position.distance_to(arch_player.global_position)
	for i in 40:
		await main.get_tree().physics_frame
	plain_closing -= plain_ch.global_position.distance_to(arch_player.global_position)
	frenz_closing -= frenz_ch.global_position.distance_to(arch_player.global_position)
	if frenz_closing <= plain_closing + 10.0:
		failed.append("affix frenzied: closed %.0f px vs plain %.0f px -- the speed hook never landed" % [frenz_closing, plain_closing])
	if frenz_ch.contact_cooldown >= plain_contact:
		failed.append("affix frenzied: contact cooldown %.2f did not shrink below %.2f" % [frenz_ch.contact_cooldown, plain_contact])
	if frenz_ch._base_color != EnemyBase.AFFIXES["frenzied"]["tint"]:
		failed.append("affix frenzied: the tint never reached _base_color")
	else:
		var frenz_halo: Node = null
		for frenz_child: Node in frenz_ch.get_children():
			if frenz_child is LitPointLight2D:
				frenz_halo = frenz_child
		if frenz_halo == null or not frenz_halo.color.is_equal_approx(
				(frenz_ch._base_color as Color).lightened(EnemyBase.GLOW_LIFT)):
			failed.append("affix frenzied: the halo kept the pre-affix colour")
	plain_ch.queue_free()
	frenz_ch.queue_free()

	# Volatile: death blasts the player ONCE inside the radius, and never at
	# range. The player is pinned (earlier probes knock it around) and given a
	# big HP pool so the probe measures the blast, not a death.
	arch_player.global_position = Vector2.ZERO
	arch_player.velocity = Vector2.ZERO
	arch_player.is_alive = true
	arch_player.max_health = 400
	arch_player.health = 400
	arch_player._invuln_timer = 0.0
	var vol: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	vol.affix = "volatile"
	vol.position = Vector2(60, 0)
	wm._enemy_container.add_child(vol)
	vol.is_dormant = true
	await main.get_tree().physics_frame
	arch_player._invuln_timer = 0.0
	vol.take_damage(9999)
	await main.get_tree().process_frame
	if 400 - arch_player.health != EnemyBase.VOLATILE_DAMAGE:
		failed.append("affix volatile: blast moved the player's health by %d, expected %d" % [400 - arch_player.health, EnemyBase.VOLATILE_DAMAGE])
	# Same death far outside the radius: nothing.
	arch_player.health = 400
	arch_player._invuln_timer = 0.0
	vol = load("res://scenes/enemy_chaser.tscn").instantiate()
	vol.affix = "volatile"
	vol.position = Vector2(500, 0)
	wm._enemy_container.add_child(vol)
	vol.is_dormant = true
	await main.get_tree().physics_frame
	if vol._base_color != EnemyBase.AFFIXES["volatile"]["tint"]:
		failed.append("affix volatile: the tint never reached _base_color")
	vol.take_damage(9999)
	await main.get_tree().process_frame
	if 400 - arch_player.health != 0:
		failed.append("affix volatile: the blast reached %d px out (radius is %d)" % [500, EnemyBase.VOLATILE_RADIUS])
	arch_player.max_health = base_hp
	arch_player.health = base_hp

	# -- New affixes: regenerating / teleporting / reflective / splitting / vampiric / warded --
	# Scene-free modifiers, so every probe drives the hook directly on a throwaway
	# chaser instead of authoring a fixture scene.
	var aff_saved_alive_new: int = wm._alive
	# Suppress drops for this block: these kills must not leave stray pickups for
	# the pickup probe below (or shift its collect count).
	var na_saved_drop: float = main.pickup_drop_chance
	main.pickup_drop_chance = 0.0
	arch_player.global_position = Vector2.ZERO
	arch_player.velocity = Vector2.ZERO
	arch_player.is_alive = true
	arch_player.max_health = 400
	arch_player.health = 400
	arch_player._invuln_timer = 0.0

	# Regenerating: heals back up over time after taking damage.
	var regen_ch: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	regen_ch.affix = "regenerating"
	regen_ch.position = Vector2(-320, 300)
	wm._enemy_container.add_child(regen_ch)
	await main.get_tree().physics_frame
	regen_ch.take_damage(int(regen_ch.max_health / 2))
	var regen_hurt: int = regen_ch.health
	for regen_i in 30:
		await main.get_tree().physics_frame
	if regen_ch.health <= regen_hurt:
		failed.append("affix regenerating: health never climbed back (%d -> %d)" % [regen_hurt, regen_ch.health])
	regen_ch.queue_free()

	# Teleporting: a timer-driven hop closes on the player.
	var tele_ch: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	tele_ch.affix = "teleporting"
	tele_ch.position = Vector2(-420, 0)
	wm._enemy_container.add_child(tele_ch)
	await main.get_tree().physics_frame
	var tele_before: float = tele_ch.global_position.distance_to(arch_player.global_position)
	tele_ch._affix_teleport_timer = 0.01
	var na_tele_frames := 0
	while tele_ch._affix_teleport_timer > 0.0 and na_tele_frames < 20:
		await main.get_tree().physics_frame
		na_tele_frames += 1
	var tele_after: float = tele_ch.global_position.distance_to(arch_player.global_position)
	if tele_after >= tele_before - 60.0:
		failed.append("affix teleporting: hop did not close on the player (%.0f -> %.0f)" % [tele_before, tele_after])
	tele_ch.queue_free()

	# Reflective: a hit inside the window lands no damage and becomes a hostile round.
	var refl_ch: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	refl_ch.affix = "reflective"
	refl_ch.position = Vector2(260, 260)
	wm._enemy_container.add_child(refl_ch)
	await main.get_tree().physics_frame
	var refl_hp: int = refl_ch.health
	var refl_hostile_before: int = _count_hostile_active()
	refl_ch.take_damage(10)
	if refl_ch.health != refl_hp:
		failed.append("affix reflective: damage landed inside the window")
	if _count_hostile_active() <= refl_hostile_before:
		failed.append("affix reflective: the hit was not reflected back")
	BulletPool.reset()
	refl_ch.queue_free()

	# Splitting: death emits its minis (the WaveManager re-parents and counts them).
	var split_ch: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	split_ch.affix = "splitting"
	split_ch.position = Vector2(0, -420)
	wm._enemy_container.add_child(split_ch)
	await main.get_tree().physics_frame
	# Direct-added enemies are not wired to the WaveManager's split handler (only
	# registry spawns are), so listen for the signal the affix emits -- the same
	# contract the splitter is tested against.
	var split_pair: Array = []
	split_ch.split_spawned.connect(func(pair: Array) -> void: split_pair.append_array(pair))
	split_ch.take_damage(99999)
	await main.get_tree().process_frame
	if split_pair.size() != int(EnemyBase.AFFIXES["splitting"]["count"]):
		failed.append("affix splitting: death produced %d minis, expected %d" % [split_pair.size(), int(EnemyBase.AFFIXES["splitting"]["count"])])
	for split_mini: Node in split_pair:
		split_mini.free()

	# Vampiric: the heal hook raises health by the table's amount.
	var vamp_ch: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	vamp_ch.affix = "vampiric"
	vamp_ch.position = Vector2(-200, -200)
	wm._enemy_container.add_child(vamp_ch)
	await main.get_tree().physics_frame
	vamp_ch.take_damage(10)
	var vamp_hurt: int = vamp_ch.health
	vamp_ch._vampiric_heal()
	var vamp_want: int = mini(vamp_hurt + int(EnemyBase.AFFIXES["vampiric"]["heal"]), vamp_ch.max_health)
	if vamp_ch.health != vamp_want:
		failed.append("affix vampiric: heal left health at %d, expected %d" % [vamp_ch.health, vamp_want])
	vamp_ch.queue_free()

	# Warded: the first hit lands, the next hit inside the window does not.
	var ward_ch: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	ward_ch.affix = "warded"
	ward_ch.position = Vector2(200, -200)
	wm._enemy_container.add_child(ward_ch)
	await main.get_tree().physics_frame
	var na_ward_hp: int = ward_ch.health
	ward_ch.take_damage(10)
	if ward_ch.health != na_ward_hp - 10:
		failed.append("affix warded: the first hit did not land (%d -> %d)" % [na_ward_hp, ward_ch.health])
	var ward_mid: int = ward_ch.health
	ward_ch.take_damage(10)
	if ward_ch.health != ward_mid:
		failed.append("affix warded: a hit landed inside the ward window")
	ward_ch.queue_free()

	# Tint must reach _base_color (applied before the halo is built) for a new
	# tint-only affix, mirroring the frenzied/volatile trap checks.
	var tint_probe: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	tint_probe.affix = "regenerating"
	wm._enemy_container.add_child(tint_probe)
	await main.get_tree().physics_frame
	if tint_probe._base_color != EnemyBase.AFFIXES["regenerating"]["tint"]:
		failed.append("affix regenerating: the tint never reached _base_color")
	tint_probe.queue_free()

	wm._alive = aff_saved_alive_new
	main.pickup_drop_chance = na_saved_drop
	arch_player.max_health = base_hp
	arch_player.health = base_hp

	# The roll itself: forced on, a spawn through the real registry path must
	# carry one; and forced spawns never pick an id outside the table.
	var aff_saved_force: bool = wm.force_affixes
	var aff_saved_tele: float = wm.spawn_telegraph_time
	var aff_saved_alive: int = wm._alive
	var aff_kids: Array[Node] = wm._enemy_container.get_children()
	wm.force_affixes = true
	wm.spawn_telegraph_time = 0.0
	wm._spawn_enemy("chaser")
	wm._spawn_enemy("tank")
	wm.spawn_telegraph_time = aff_saved_tele
	var aff_new: Array[Node] = []
	for aff_child: Node in wm._enemy_container.get_children():
		if not aff_kids.has(aff_child):
			aff_new.append(aff_child)
	if aff_new.size() != 2:
		failed.append("affix roll: forced spawns produced %d enemies, expected 2" % aff_new.size())
	for aff_spawned: Node in aff_new:
		if aff_spawned.affix == "" or not EnemyBase.AFFIXES.has(aff_spawned.affix):
			failed.append("affix roll: a forced spawn carried affix \"%s\" (empty or unknown)" % aff_spawned.affix)
		aff_spawned.queue_free()
	wm.force_affixes = aff_saved_force
	wm._alive = aff_saved_alive
	wm.stop()

	# -- Pickups: forced drop, magnet collect exactly once, despawn, reset -----
	var pk_saved_chance: float = main.pickup_drop_chance
	var pk_saved_pos: Vector2 = arch_player.global_position
	var pk_active0: int = PickupPool.active_count()
	var pk_events: Array[String] = []
	PickupPool.collected.connect(func(kind: String) -> void: pk_events.append(kind))
	main.pickup_drop_chance = 1.0
	var pk_enemy: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	pk_enemy.position = Vector2(-420, -180)
	wm._enemy_container.add_child(pk_enemy)
	await main.get_tree().process_frame   # let the kill watcher arm on entry
	# A LIVE, FULL-HEALTH player is a precondition for this whole section, and
	# neither was pinned before: collection is a body_entered OVERLAP, and
	# Player._die() clears the player's collision layer, so a corpse can pull a
	# drop with the magnet and never touch it (silent, and load-dependent -- whether
	# an earlier death probe left the player dead varies by timing). A hurt player
	# is the second half: Main rolls a HEALTH drop 35% of the time when hurt, and
	# this probe is about credits. Revive through the game's own path.
	arch_player.respawn(pk_saved_pos)
	# The chaser WANDERS between add_child and the killing blow -- further under load,
	# because the suite's awaits stretch -- so the drop lands where it DIED, not where
	# it was placed. Kill against that position and teleport the player THERE.
	var pk_death_pos: Vector2 = pk_enemy.global_position
	pk_enemy.take_damage(9999)
	await main.get_tree().process_frame
	if PickupPool.active_count() != pk_active0 + 1:
		failed.append("pickups: a forced 100%% drop produced %d new pickups, expected exactly 1" % (PickupPool.active_count() - pk_active0))
	# Walk the player onto the drop: the magnet pulls it in and the grant lands
	# exactly once, then the pickup parks again.
	arch_player.global_position = pk_death_pos
	var pk_frames := 0
	while pk_events.is_empty() and pk_frames < 60:
		await main.get_tree().physics_frame
		pk_frames += 1
	if pk_events != ["credits"]:
		failed.append("pickups: collecting one credits drop raised %s, expected exactly [\"credits\"]" % str(pk_events))
	if PickupPool.active_count() != pk_active0:
		failed.append("pickups: the collected pickup never parked (%d still active)" % PickupPool.active_count())
	# A health drop heals through the player's real heal() path.
	arch_player.health = 50
	PickupPool.fire(arch_player.global_position + Vector2(0, -40), "health")
	pk_frames = 0
	while pk_events.size() < 2 and pk_frames < 60:
		await main.get_tree().physics_frame
		pk_frames += 1
	if arch_player.health != 50 + main.PICKUP_HEALTH:
		failed.append("pickups: a health drop moved the player to %d, expected %d" % [arch_player.health, 50 + main.PICKUP_HEALTH])
	# Despawn: a short-lived drop vanishes on its own and never collects.
	var pk_short: Pickup = PickupPool.fire(Vector2(600, 520), "credits")
	pk_short.lifetime = 0.2
	pk_frames = 0
	while PickupPool.active_count() > pk_active0 and pk_frames < 30:
		await main.get_tree().physics_frame
		pk_frames += 1
	if PickupPool.active_count() != pk_active0:
		failed.append("pickups: a drop outlived its lifetime (%d active after %d frames)" % [PickupPool.active_count(), pk_frames])
	if pk_events.size() != 2:
		failed.append("pickups: the despawned drop collected anyway (%s)" % str(pk_events))
	# reset() parks everything: the arena-switch contract.
	PickupPool.fire(Vector2(-600, 0), "credits")
	PickupPool.fire(Vector2(600, 0), "credits")
	PickupPool.reset()
	if PickupPool.active_count() != 0:
		failed.append("pickups: reset() left %d live pickups" % PickupPool.active_count())
	main.pickup_drop_chance = pk_saved_chance
	arch_player.global_position = pk_saved_pos
	arch_player.velocity = Vector2.ZERO
	arch_player.health = base_hp

	# -- Dash: burst + i-frames + cooldown, pip on the HUD ----------------------
	# The player fixture stands clear of cover (right of centre is open floor
	# to the wall at x=810), so the travel number measures the dash, not a
	# collision.
	arch_player.global_position = Vector2(0, 0)
	arch_player.velocity = Vector2.ZERO
	arch_player.controls_enabled = true
	arch_player._invuln_timer = 0.0
	arch_player._aim_pivot.rotation = 0.0   # facing right: dash direction is deterministic
	var dash_start: Vector2 = arch_player.global_position
	if not arch_player.try_dash():
		failed.append("dash: try_dash refused with a full cooldown available")
	else:
		if arch_player._invuln_timer <= 0.0:
			failed.append("dash: no i-frames came with the dash (%.2f)" % arch_player._invuln_timer)
		for i in 14:
			await main.get_tree().physics_frame
		var dash_travel: float = arch_player.global_position.distance_to(dash_start)
		if dash_travel < 100.0:
			failed.append("dash: travelled %.0f px, expected 100+ (900 px/s for 0.16 s)" % dash_travel)
		if arch_player._dash_cooldown_left <= 0.0:
			failed.append("dash: the cooldown never started")
		if arch_player.try_dash():
			failed.append("dash: a second dash inside the cooldown went through")
		var dash_ratio_low: float = arch_player.dash_ready_ratio()
		for i in 40:
			await main.get_tree().physics_frame
		var dash_ratio_high: float = arch_player.dash_ready_ratio()
		if not (dash_ratio_low < 0.99 and dash_ratio_high > dash_ratio_low):
			failed.append("dash: the readiness ratio did not recover (%.2f -> %.2f)" % [dash_ratio_low, dash_ratio_high])
	arch_player.controls_enabled = false
	# The pip: same readiness drives a visible tint on the HUD.
	var dash_hud: Hud = main.get_node("UI/HUD") as Hud
	var dash_pip: ColorRect = dash_hud.get_node_or_null("PanelRoot/Panel/DashPip") as ColorRect
	if dash_pip == null:
		failed.append("dash: the HUD has no DashPip")
	else:
		dash_hud.set_dash_ratio(0.0)
		var pip_dark: Color = dash_pip.modulate
		dash_hud.set_dash_ratio(1.0)
		if dash_pip.modulate == pip_dark:
			failed.append("dash: the pip did not track the readiness ratio")
	arch_player.global_position = Vector2.ZERO
	arch_player.velocity = Vector2.ZERO

	# -- Enemy rounds are hostile: they hurt the player, never their own kind ---
	# Regression: Bullet.fire() used to reset `hostile` right after BulletPool
	# set it, so every enemy shot was harmless to the player AND damaged other
	# enemies instead (friendly fire).
	var player_v: Node = main.get_node("World/Player")
	player_v.is_alive = true
	player_v.health = player_v.max_health
	player_v._invuln_timer = 0.0
	var hp_before: int = player_v.health
	var hostile_round: Bullet = BulletPool.fire(player_v.global_position, Vector2.RIGHT, 8, 340.0, true)
	if not hostile_round.hostile or hostile_round.collision_mask != 9:
		failed.append("hostile round lost its flag (hostile=%s mask=%d)" % [str(hostile_round.hostile), hostile_round.collision_mask])
	await main.get_tree().physics_frame
	await main.get_tree().physics_frame
	if player_v.health >= hp_before:
		failed.append("hostile bullet did not damage the player (health still %d)" % player_v.health)
	player_v.health = player_v.max_health
	player_v._invuln_timer = 0.0

	# No friendly fire: a hostile round must pass through other enemies.
	var ally: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	wm._enemy_container.add_child(ally)
	ally.set_deferred("global_position", Vector2(420, -240))
	ally.is_dormant = true
	var ally_hits := [0]
	ally.connect("damaged", func(_a: int) -> void: ally_hits[0] += 1)
	for i in 3:
		await main.get_tree().physics_frame
	BulletPool.fire(ally.global_position, Vector2.RIGHT, 8, 340.0, true)
	for i in 5:
		await main.get_tree().physics_frame
	if ally_hits[0] != 0:
		failed.append("hostile bullet damaged another enemy (%d hits, friendly fire)" % ally_hits[0])
	ally.queue_free()

	# -- enemy_shooter fires a hostile round -----------------------------------
	# Used to set `b.shot_once_emit_called`, a property Bullet does not have, so
	# every shot printed a SCRIPT ERROR.
	var shooter: Node = load("res://scenes/enemy_shooter.tscn").instantiate()
	wm._enemy_container.add_child(shooter)
	shooter.set_deferred("global_position", player_v.global_position + Vector2(200, 0))
	for i in 3:
		await main.get_tree().physics_frame
	shooter._fire_at_player()
	var hostile_seen := false
	for b: Bullet in BulletPool._all:
		if b.is_active and b.hostile:
			hostile_seen = true
			break
	if not hostile_seen:
		failed.append("enemy_shooter._fire_at_player produced no hostile round")
	shooter.queue_free()

	# -- One knockback number, shared by both sides ----------------------------
	# The shop's "knockback" upgrade used to multiply PLAYER rounds only; it is gone
	# (5 levels of +30% stacked into a shove that flung bosses across the arena). What
	# remains is a single base the pool applies to every round, so this pins it.
	var kb_base: float = BulletPool.fire(Vector2(9000, 9000), Vector2.RIGHT, 1, 0.0).knockback_force
	if not is_equal_approx(kb_base, BulletPool.base_knockback):
		failed.append("player round knockback %.1f, expected base_knockback %.1f" % [kb_base, BulletPool.base_knockback])
	var kb_hostile: float = BulletPool.fire(Vector2(9000, 9000), Vector2.RIGHT, 1, 0.0, true).knockback_force
	if not is_equal_approx(kb_hostile, kb_base):
		failed.append("enemy rounds carry %.1f knockback, player rounds %.1f" % [kb_hostile, kb_base])
	BulletPool.reset()   # parks the probe rounds

	# -- Pierce: one round damages N extra enemies and never re-hits one -------
	var pi_a: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	var pi_b: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	wm._enemy_container.add_child(pi_a)
	wm._enemy_container.add_child(pi_b)
	pi_a.set_deferred("global_position", Vector2(-100, 100))
	pi_b.set_deferred("global_position", Vector2(200, 100))
	pi_a.is_dormant = true
	pi_b.is_dormant = true
	var pi_hits_a := [0]
	var pi_hits_b := [0]
	pi_a.connect("damaged", func(_a: int) -> void: pi_hits_a[0] += 1)
	pi_b.connect("damaged", func(_a: int) -> void: pi_hits_b[0] += 1)
	for i in 3:
		await main.get_tree().physics_frame
	# y=100 from x=-300..360 is a reserved clear corridor in this arena: firing
	# from further out can clip cover long before it reaches the targets.
	var pi_round: Node = BulletPool.fire(Vector2(-290, 100), Vector2.RIGHT, 12, 700.0, false, 2)
	var pi_frames := 0
	while is_instance_valid(pi_round) and pi_round.is_active and pi_frames < 60:
		await main.get_tree().physics_frame
		pi_frames += 1
	if pi_hits_a[0] != 1 or pi_hits_b[0] != 1:
		failed.append("pierce round hit %d/%d enemies, expected 1/1 each" % [pi_hits_a[0], pi_hits_b[0]])
	if is_instance_valid(pi_round) and pi_round.pierce_left != 0:
		failed.append("pierce round still holds %d pierces after 2 enemies" % pi_round.pierce_left)
	pi_a.queue_free()
	pi_b.queue_free()

	# -- Shop "pierce" reaches the FIRED ROUND, not just the stat -------------
	var pw_player: Node = load("res://scenes/player.tscn").instantiate()
	main.add_child(pw_player)
	var pw_up: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(pw_up)
	pw_up.buy("pierce", 99999, pw_player)
	pw_up.buy("pierce", 99999, pw_player)
	pw_player._aim_pivot.rotation = 0.0
	var pw_before_ids: Array[int] = []
	for b: Bullet in BulletPool._all:
		if b.is_active:
			pw_before_ids.append(b.get_instance_id())
	pw_player._fire_bullet()
	var pw_round: Bullet = null
	for b: Bullet in BulletPool._all:
		if b.is_active and not pw_before_ids.has(b.get_instance_id()):
			pw_round = b
	if pw_round == null:
		failed.append("pierce-wiring probe fired nothing")
	elif pw_round.pierce_left != pw_player.pierce_count or pw_round.pierce_left < 2:
		failed.append("shop pierce never reached the round (round %d, player %d)" % [pw_round.pierce_left, pw_player.pierce_count])
	pw_up.queue_free()
	pw_player.queue_free()
	BulletPool.reset()

	# -- Charge shot: exactly ONE heavy round, scaled, no pool clone ----------
	player.charge_unlocked = true
	# The heavy round scales with the shop: give the player a pierce upgrade and
	# prove the charged round inherits it on top of its own built-in pierce.
	var ch_saved_pierce: int = player.pierce_count
	player.pierce_count = 2
	# Identify the heavy round by IDENTITY (a leftover probe round may still be
	# flying, and pool-slot order is not fire order).
	var ch_before_ids: Array[int] = []
	for b: Bullet in BulletPool._all:
		if b.is_active:
			ch_before_ids.append(b.get_instance_id())
	player.fire_charged(1.0)
	var ch_round: Bullet = null
	for b: Bullet in BulletPool._all:
		if b.is_active and not ch_before_ids.has(b.get_instance_id()):
			ch_round = b
	if ch_round == null:
		failed.append("charge shot fired no new round")
	else:
		var ch_want_damage: int = int(round(float(player.bullet_damage) * player.charge_damage_mult))
		if ch_round.damage != ch_want_damage:
			failed.append("charge damage %d, expected %d" % [ch_round.damage, ch_want_damage])
		if not is_equal_approx(ch_round.speed, player.bullet_speed * player.charge_speed_mult):
			failed.append("charge speed %.0f, expected %.0f" % [ch_round.speed, player.bullet_speed * player.charge_speed_mult])
		if ch_round.pierce_left != player.charge_pierce + player.pierce_count:
			failed.append("charge pierce %d, expected %d (charge_pierce + pierce upgrade)" % [ch_round.pierce_left, player.charge_pierce + player.pierce_count])
		var ch_want_kb: float = BulletPool.base_knockback * player.charge_knockback_mult
		if not is_equal_approx(ch_round.knockback_force, ch_want_kb):
			failed.append("charge knockback %.0f, expected %.0f" % [ch_round.knockback_force, ch_want_kb])
	player.pierce_count = ch_saved_pierce
	player.charge_unlocked = false
	BulletPool.reset()

	# -- Charge shot scales with the shop AND the pool's run config ----------
	# Idea-pin: the heavy round is a PLAYER round through BulletPool.fire, so
	# (a) a shop "damage" purchase reaches it via the live stat (the economy
	# probe above already proved buy -> bullet_damage; this proves the second
	# hop bullet_damage -> charged damage on a throwaway player, so no live
	# stat is mutated), and (b) crit/homing/ricochet/explosive pool config
	# rides along exactly like a normal shot, and (c) lifetime/size are
	# per-shot: a furnace-style round fired immediately before must not bleed
	# its range/size into the heavy round through the shared pool.
	var ch_saved_crit: float = BulletPool.crit_chance
	var ch_saved_crit_mult: float = BulletPool.crit_multiplier
	var ch_saved_homing: float = BulletPool.homing_strength
	var ch_saved_bounce: int = BulletPool.bounce_count
	var ch_saved_boom_r: float = BulletPool.explosive_radius
	var ch_saved_boom_d: int = BulletPool.explosive_damage
	BulletPool.crit_chance = 0.42
	BulletPool.crit_multiplier = 2.5
	BulletPool.homing_strength = 3.0
	BulletPool.bounce_count = 2
	BulletPool.explosive_radius = 50.0
	BulletPool.explosive_damage = 9
	var ch_bleed: Bullet = BulletPool.fire(Vector2(4000, 4000), Vector2.RIGHT,
			1, 700.0, false, 0, 1.0, 0.3, 1.7)
	ch_bleed.deactivate()
	var ch_shop_player: Node = load("res://scenes/player.tscn").instantiate()
	main.add_child(ch_shop_player)
	var ch_shop_up: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(ch_shop_up)
	ch_shop_player.charge_unlocked = true
	var ch_shop_base: int = ch_shop_player.bullet_damage
	ch_shop_up.buy("damage", 99999, ch_shop_player)
	var ch_before_ids2: Array[int] = []
	for b: Bullet in BulletPool._all:
		if b.is_active:
			ch_before_ids2.append(b.get_instance_id())
	ch_shop_player.fire_charged(1.0)
	var ch_round2: Bullet = null
	for b: Bullet in BulletPool._all:
		if b.is_active and not ch_before_ids2.has(b.get_instance_id()):
			ch_round2 = b
	if ch_round2 == null:
		failed.append("charge scaling probe fired no new round")
	else:
		var ch_want2: int = int(round(float(ch_shop_player.bullet_damage) * ch_shop_player.charge_damage_mult))
		if ch_shop_player.bullet_damage != ch_shop_base + 4:
			failed.append("charge scaling: throwaway buy moved damage %d -> %d, expected +4" % [ch_shop_base, ch_shop_player.bullet_damage])
		elif ch_round2.damage != ch_want2:
			failed.append("charge damage %d, expected %d (shop damage x charge mult)" % [ch_round2.damage, ch_want2])
		if not is_equal_approx(ch_round2.crit_chance, 0.42) or not is_equal_approx(ch_round2.crit_multiplier, 2.5):
			failed.append("charge crit config %.2f/%.1f, pool says 0.42/2.5 - run config does not reach the heavy round" % [ch_round2.crit_chance, ch_round2.crit_multiplier])
		if not is_equal_approx(ch_round2.homing_scale, 3.0) or ch_round2.bounce_left != 2:
			failed.append("charge behavior config homing %.1f bounces %d, expected 3.0/2" % [ch_round2.homing_scale, ch_round2.bounce_left])
		if not is_equal_approx(ch_round2.explosive_radius, 50.0) or ch_round2.explosive_damage != 9:
			failed.append("charge explosive config %.0f/%d, expected 50/9" % [ch_round2.explosive_radius, ch_round2.explosive_damage])
		if not is_equal_approx(ch_round2.lifetime, Bullet.BASE_LIFETIME):
			failed.append("charge lifetime %.2f, expected BASE %.2f (previous shot's range bled through the pool)" % [ch_round2.lifetime, Bullet.BASE_LIFETIME])
		var ch_want_scale2: float = maxf(ch_shop_player.bullet_scale, 1.0)
		if not is_equal_approx(ch_round2.scale.x, ch_want_scale2):
			failed.append("charge scale %.2f, expected %.2f (previous shot's size bled through the pool)" % [ch_round2.scale.x, ch_want_scale2])
	BulletPool.crit_chance = ch_saved_crit
	BulletPool.crit_multiplier = ch_saved_crit_mult
	BulletPool.homing_strength = ch_saved_homing
	BulletPool.bounce_count = ch_saved_bounce
	BulletPool.explosive_radius = ch_saved_boom_r
	BulletPool.explosive_damage = ch_saved_boom_d
	ch_shop_up.queue_free()
	ch_shop_player.queue_free()
	BulletPool.reset()

	# -- Crits: x2 damage on the hit, and a pooled number pops ----------------
	var ct_target: Node = load("res://scenes/enemy_tank.tscn").instantiate()
	wm._enemy_container.add_child(ct_target)
	ct_target.set_deferred("global_position", Vector2(-100, 240))
	ct_target.is_dormant = true
	var ct_hits := [0]
	var ct_amount := [0]
	ct_target.connect("damaged", func(a: int) -> void: ct_hits[0] += 1; ct_amount[0] = a)
	for i in 3:
		await main.get_tree().physics_frame
	var ct_saved_chance: float = BulletPool.crit_chance
	var ct_popped_before: int = DamageNumbers._next
	BulletPool.crit_chance = 1.0            # deterministic: every hit crits
	BulletPool.fire(Vector2(-100, 40), Vector2(0, 1), 10, 700.0)
	var ct_frames := 0
	while ct_hits[0] < 1 and ct_frames < 60:
		await main.get_tree().physics_frame
		ct_frames += 1
	if ct_hits[0] != 1:
		failed.append("crit probe landed %d hits, expected 1" % ct_hits[0])
	if ct_amount[0] != 20:
		failed.append("crit dealt %d, expected 20 (10 x crit_multiplier)" % ct_amount[0])
	if DamageNumbers._next == ct_popped_before:
		failed.append("crit did not pop a damage number")
	if DamageNumbers.active_count() < 1:
		failed.append("damage number popped but none is visible")
	# Same target, no crit: plain damage (the pool config drives it).
	BulletPool.crit_chance = 0.0
	BulletPool.fire(Vector2(-100, 40), Vector2(0, 1), 10, 700.0)
	ct_frames = 0
	while ct_hits[0] < 2 and ct_frames < 60:
		await main.get_tree().physics_frame
		ct_frames += 1
	if ct_amount[0] != 10:
		failed.append("non-crit dealt %d, expected 10" % ct_amount[0])
	BulletPool.crit_chance = ct_saved_chance
	ct_target.queue_free()

	# -- Hit flash: white on the hit frame, owner tint restored after ---------
	var fl_e: Node = load("res://scenes/enemy_shooter.tscn").instantiate()
	wm._enemy_container.add_child(fl_e)
	fl_e.is_dormant = true
	var fl_base: Color = fl_e._body.color
	fl_e.take_damage(1)
	# The flash is applied by _process, and an awaited process_frame resumes
	# BEFORE that frame's _process calls -- give it one full frame.
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	if fl_e._body.color != Color(1.0, 1.0, 1.0):
		failed.append("enemy hit flash is not white (%s)" % str(fl_e._body.color))
	for i in 20:
		await main.get_tree().process_frame
	if not fl_e._body.color.is_equal_approx(fl_base):
		failed.append("enemy flash did not restore its base colour (%s vs %s)" % [str(fl_e._body.color), str(fl_base)])
	fl_e.queue_free()
	# The boss owns its health tint through _base_tint(): EnemyBase applies it.
	var fl_boss: Node = load("res://scenes/enemy_boss.tscn").instantiate()
	wm._enemy_container.add_child(fl_boss)
	fl_boss.is_dormant = true
	for i in 3:
		await main.get_tree().process_frame
	var fl_boss_tint: Color = fl_boss._base_tint()
	if fl_boss_tint.is_equal_approx(Color.WHITE):
		failed.append("boss base tint came out white -- health read-out is lost")
	if not fl_boss._body.color.is_equal_approx(fl_boss_tint):
		failed.append("boss body colour stopped tracking its tint (%s vs %s)" % [str(fl_boss._body.color), str(fl_boss_tint)])
	fl_boss.queue_free()

	# -- Shop panel still fits the window at 13 rows ---------------------------
	# The rows are what grow, and only a started run builds them -- so build them
	# HERE. (Measured on an empty panel this guard passes for the wrong reason:
	# an empty ItemList is a few px tall regardless of the theme.)
	var sw_panel: Control = main.get_node("UI/ShopPanel/Center/Panel") as Control
	var sw_up: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(sw_up)
	main._shop.build(sw_up)
	var sw_min_h: float = sw_panel.get_combined_minimum_size().y
	print("[Shop] panel wants %.0f px of a 720 px window (budget 640)." % sw_min_h)
	if sw_min_h > 640.0:
		failed.append("shop panel wants %.0f px of a 720 px window -- add a scroll" % sw_min_h)
	if sw_min_h <= 0.0:
		failed.append("shop panel measured 0 px -- was it built at all?")

	# -- Pause menu -------------------------------------------------------------
	var pm: CanvasLayer = main.get_node("UI/PauseMenu")
	if pm.visible:
		failed.append("pause menu visible at boot (should start hidden)")
	# Freeze check: start a short spawn timer, pause, wait LONGER than its
	# wait_time via a process_always SceneTree timer. Time still on the spawn
	# timer afterwards = the tree pause genuinely froze it.
	wm.is_running = true
	wm._spawn_timer.start(0.3)
	var tree: SceneTree = main.get_tree()
	tree.paused = true
	await tree.create_timer(0.6, true).timeout
	var frozen_ok: bool = wm._spawn_timer.time_left > 0.0
	tree.paused = false
	wm._spawn_timer.stop()
	wm.stop()
	if not frozen_ok:
		failed.append("pause did not freeze the WaveManager spawn timer")
	# Toggle: menu + tree pause must flip together (state guard is trivial;
	# the meat is the paused flag + menu visibility moving in lockstep).
	main._state = main.State.PLAYING
	main.toggle_pause()
	var opened: bool = pm.visible and tree.paused
	main.toggle_pause()
	var closed: bool = not pm.visible and not tree.paused
	if not (opened and closed):
		failed.append("toggle_pause did not open/close the pause menu with the tree pause")

	# -- Shop: the new upgrades move the stat they name ------------------------
	var shop_player: Node = main.get_node("World/Player")
	var up_shop: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(up_shop)
	var shots_before: int = shop_player.bullets_per_shot
	if not bool(up_shop.buy("split_shot", 99999, shop_player).ok):
		failed.append("shop: could not buy split_shot")
	# Behavioural: ONE trigger pull must spend 2 rounds on 2 different headings.
	BulletPool.reset()
	shop_player._fire_bullet()
	var volley_dirs: Array[Vector2] = []
	for volley_b: Bullet in BulletPool._all:
		if volley_b.is_active:
			volley_dirs.append(volley_b.direction)
	if volley_dirs.size() != shots_before + 1:
		failed.append("shop: split_shot fired %d bullets, expected %d" % [volley_dirs.size(), shots_before + 1])
	elif volley_dirs[0].is_equal_approx(volley_dirs[1]):
		failed.append("shop: split_shot bullets all fly one heading (no spread)")
	BulletPool.reset()
	# 50 damage costs exactly 40 once 20% is soaked (two armor ranks).
	shop_player.health = shop_player.max_health
	shop_player._invuln_timer = 0.0
	var armor_hp0: int = shop_player.health
	shop_player.take_damage(50)
	var armor_plain: int = armor_hp0 - shop_player.health
	up_shop.buy("armor", 99999, shop_player)
	up_shop.buy("armor", 99999, shop_player)
	shop_player.health = shop_player.max_health
	shop_player._invuln_timer = 0.0
	var armor_hp1: int = shop_player.health
	shop_player.take_damage(50)
	var armor_soaked: int = armor_hp1 - shop_player.health
	if armor_soaked != 40:
		failed.append("shop: 20%% armor should turn a 50-damage hit into 40, took %d" % armor_soaked)
	if armor_soaked >= armor_plain:
		failed.append("shop: armor did not reduce damage (%d -> %d)" % [armor_plain, armor_soaked])
	var iframes_before: float = shop_player.invulnerability_time
	up_shop.buy("iframes", 99999, shop_player)
	if not is_equal_approx(shop_player.invulnerability_time, iframes_before + 0.15):
		failed.append("shop: iframes did not add invulnerability time")
	var recoil_before_shop: float = shop_player.fire_recoil
	up_shop.buy("recoil", 99999, shop_player)
	if not is_equal_approx(shop_player.fire_recoil, recoil_before_shop * 0.75):
		failed.append("shop: recoil upgrade did not shrink fire_recoil")
	# leech is applied by Main's kill handler -- last, because it fires hit-stop.
	up_shop.buy("leech", 99999, shop_player)
	shop_player.health = 50
	var leech_enemy: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	wm._enemy_container.add_child(leech_enemy)
	main._on_enemy_killed(leech_enemy)
	if shop_player.health != 51:
		failed.append("shop: leech did not heal on kill (health %d)" % shop_player.health)

	# -- The third ten: the new read sites ------------------------------------
	# The sweep below proves each row MOVES a stat; these prove the stat is READ
	# where the event happens (take_damage's death save / push, Main's kill
	# credits, Main's health-pickup heal). last_stand gets a throwaway body --
	# it flips is_alive -- while bounty/aid need Main's own player and balance,
	# because Main's handlers own the grant.
	var t3_player: Node = load("res://scenes/player.tscn").instantiate()
	main.add_child(t3_player)
	t3_player.last_stand_charges = 1
	t3_player.health = 5
	t3_player._invuln_timer = 0.0
	t3_player.take_damage(999)
	if not t3_player.is_alive or t3_player.health != 1 or t3_player.last_stand_charges != 0:
		failed.append("last_stand: lethal hit should leave 1 HP and spend the charge (hp %d, charges %d)" % [t3_player.health, t3_player.last_stand_charges])
	t3_player._invuln_timer = 0.0
	t3_player.take_damage(999)
	if t3_player.is_alive:
		failed.append("last_stand: a second lethal hit with no charge left did not kill")
	# anchor: the same push shoves a braced body less (50% of 200 = 100).
	t3_player.revive(1.0)
	t3_player.last_stand_charges = 0
	t3_player.knockback_resist = 0.5
	t3_player._invuln_timer = 0.0
	t3_player.velocity = Vector2.ZERO
	t3_player.take_damage(5, Vector2(200, 0))
	if not is_equal_approx(t3_player.velocity.x, 100.0):
		failed.append("anchor: 50%% resist turned a 200 push into %.0f, expected 100" % t3_player.velocity.x)
	t3_player.queue_free()
	# bounty: Main's kill handler scales the grant by the live player's stat.
	var t3_bought: Dictionary = up_shop.buy("bounty", 99999, shop_player)   # rare: +0.15 x 1.25
	if not bool(t3_bought.ok):
		failed.append("bounty: could not buy the row")
	var t3_enemy: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	wm._enemy_container.add_child(t3_enemy)
	var t3_credits0: int = main._credits
	var t3_want: int = int(round(float(Perks.scaled_credits(t3_enemy.score_value)) * shop_player.credit_mult))
	main._on_enemy_killed(t3_enemy)
	if main._credits - t3_credits0 != t3_want:
		failed.append("bounty: kill paid %d, expected %d" % [main._credits - t3_credits0, t3_want])
	shop_player.credit_mult = 1.0   # later probes quote plain credit numbers
	# aid: the health pickup heals PICKUP_HEALTH x heal_mult (1.5 -> 23 HP).
	PickupPool.heal_mult = 1.5
	shop_player.health = 1
	main._on_pickup_collected("health")
	var t3_aid_want: int = 1 + int(round(float(main.PICKUP_HEALTH) * 1.5))
	if shop_player.health != t3_aid_want:
		failed.append("aid: health pickup landed %d HP, expected %d" % [shop_player.health, t3_aid_want])
	PickupPool.reset_run_config()

	# -- Shop: no DEFS row may be a no-op -------------------------------------
	# A row with no match arm shows in the shop, takes credits and changes
	# nothing -- the "declared but dead" failure that reads as a working upgrade.
	# A THROWAWAY player, not the live one: the sweep buys every row, and the
	# second twenty carries state (evasion, dash strike) that would make later
	# take_damage probes on the live player randomly dodge.
	var up_sweep: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(up_sweep)
	var sweep_player: Node = load("res://scenes/player.tscn").instantiate()
	main.add_child(sweep_player)
	sweep_player.health = 1   # repair must land on a hurt body to move health
	for sweep_def: Dictionary in up_sweep.DEFS:
		var sweep_id: String = String(sweep_def.id)
		var sweep_before: Dictionary = _player_stat_snapshot(sweep_player)
		var sweep_pool_before: Dictionary = _pool_stat_snapshot()
		var sweep_res: Dictionary = up_sweep.buy(sweep_id, 999999, sweep_player)
		if not bool(sweep_res.ok):
			failed.append("shop: DEFS row '%s' could not be bought" % sweep_id)
		elif sweep_id == "offers" or sweep_id == "bargain":
			# Registry rows: the effect is READ from level() by ShopPanel.deal /
			# effective_reroll_cost -- no player or pool stat moves. The hand-size
			# and reroll-price probes cover that read path directly.
			pass
		elif _player_stat_snapshot(sweep_player) == sweep_before \
				and _pool_stat_snapshot() == sweep_pool_before:
			failed.append("shop: DEFS row '%s' was bought but moved no stat" % sweep_id)
	# The sweep bought the pool-backed rows (crit / behavior / group multipliers
	# / magnet / scavenger), which mutate the SHARED autoloads: put them back,
	# or a later probe measures a build it never asked for.
	BulletPool.reset_run_config()
	PickupPool.reset_run_config()
	up_sweep.queue_free()
	sweep_player.queue_free()
	up_shop.queue_free()
	BulletPool.reset()

	# -- Storage: records round-trip, improve only, and share the file --------
	var store_path: String = "user://__selftest_records.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store_path))
	var rec_first: Dictionary = Storage.record_run(120, 4, 3, store_path)
	if not (bool(rec_first["new_score"]) and bool(rec_first["new_wave"])):
		failed.append("storage: a first run should register as a new best")
	if int(rec_first["total_kills"]) != 3:
		failed.append("storage: a run's kills were not added to the lifetime total (%d)" % int(rec_first["total_kills"]))
	var rec_worse: Dictionary = Storage.record_run(50, 2, 4, store_path)
	if bool(rec_worse["new_score"]) or bool(rec_worse["new_wave"]):
		failed.append("storage: a worse run was reported as a new best")
	if int(rec_worse["total_kills"]) != 7:
		failed.append("storage: lifetime kills did not accumulate over two runs (%d)" % int(rec_worse["total_kills"]))
	if int(rec_worse["best_score"]) != 120 or int(rec_worse["best_wave"]) != 4:
		failed.append("storage: best was not preserved (%d - wave %d)" % [rec_worse["best_score"], rec_worse["best_wave"]])
	Storage.set_value("sfx_volume", 0.25, store_path)
	if int(Storage.get_value("best_score", 0, store_path)) != 120:
		failed.append("storage: writing the audio volume clobbered the stored record")
	if not FileAccess.file_exists(store_path):
		failed.append("storage: nothing was written to disk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store_path))

	# -- Spawn telegraph: counted immediately, in the tree only after the ring -
	# Compare node IDENTITY, never counts: a queue_free() from an earlier section
	# is deferred, so the container's child count can still change under us.
	await main.get_tree().physics_frame
	var tele_before_nodes: Array[Node] = wm._enemy_container.get_children()
	var tele_alive: int = wm._alive
	var tele_default: float = wm.spawn_telegraph_time
	wm.is_running = true
	wm.spawn_telegraph_time = 0.3
	wm._spawn_enemy("chaser")
	if wm._alive != tele_alive + 1:
		failed.append("telegraph: enemy not counted while materialising (%d -> %d)" % [tele_alive, wm._alive])
	if _new_container_child(wm._enemy_container, tele_before_nodes) != null:
		failed.append("telegraph: enemy appeared in the tree with no telegraph delay")
	var tele_frames: int = 0
	var tele_enemy: Node = null
	while tele_enemy == null and tele_frames < 60:
		await main.get_tree().physics_frame
		tele_frames += 1
		tele_enemy = _new_container_child(wm._enemy_container, tele_before_nodes)
	if tele_enemy == null:
		failed.append("telegraph: enemy never materialised after the delay")
	else:
		# Remove it again: a live chaser must not contact-damage the player during
		# the health assertions that follow.
		wm._enemy_container.remove_child(tele_enemy)
		tele_enemy.queue_free()
	wm._alive = tele_alive
	wm.spawn_telegraph_time = tele_default
	wm.stop()

	# -- HUD: credits and health are actually rendered -------------------------
	# Look the labels up by UNIQUE NAME, not by structure: hud.gd reparents them into
	# panels it builds at runtime (WaveReadout / ScoreReadout), so any
	# "PanelRoot/Panel/..." path is wrong the moment the HUD is redone.
	var hud_credits: Node = main.get_node("UI/HUD")
	hud_credits.set_credits(7)
	var credits_text: String = (hud_credits.get_node("%CreditsLabel") as Label).text
	if not credits_text.contains("7"):
		failed.append("hud: credits label did not update (\"%s\")" % credits_text)
	hud_credits.set_health(30, 100)
	var health_text: String = (hud_credits.get_node("%HealthLabel") as Label).text
	if not (health_text.contains("30") and health_text.contains("100")):
		failed.append("hud: health label should read current/max, got \"%s\"" % health_text)
	# Low-health warning: it is a separate overlay driven by the same pulse, so
	# assert it turns ON when the bar is low AND OFF again at full health (a
	# one-way flag would leave the warning tinting the screen forever).
	hud_credits.set_health(10, 100)
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var low_rect: ColorRect = hud_credits.get_node("LowHealth") as ColorRect
	if not low_rect.visible or low_rect.modulate.a <= 0.0:
		failed.append("hud: the low-health vignette never showed at 10/100 health")
	hud_credits.set_health(100, 100)
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	if low_rect.visible:
		failed.append("hud: the low-health vignette stayed on after healing to full")
	hud_credits.set_health(arena_player.health, arena_player.max_health)
	hud_credits.set_credits(0)

	# -- Audio: the two volume sliders really gate and scale playback ----------
	var sfx_was: float = AudioManager.sfx_volume()
	var music_was: float = AudioManager.music_volume()
	AudioManager.set_sfx_volume(0.0)
	var playing_before: int = _count_playing_sfx()
	AudioManager.play_shoot()
	AudioManager.play_enemy_death()
	if _count_playing_sfx() > playing_before:
		failed.append("audio: a sound started with the SFX slider at zero")
	AudioManager.set_sfx_volume(0.5)
	var sfx_marker: Array = _playing_sfx_players()
	AudioManager.play_shoot()
	# Identity, not count: a leftover ringing from an earlier probe can finish
	# between the two reads and mask the new player -- a count comparison flaked
	# one run in three exactly that way.
	if _new_sfx_since(sfx_marker).is_empty():
		failed.append("audio: no sound started with the SFX slider up")
	# ...and it is actually played quieter: play_shoot asks for -4.0 dB, so the
	# slider at 0.5 has to land at -4.0 + linear_to_db(0.5) = -10.0 dB.
	var halved_db: float = _quietest_new_sfx_db(sfx_marker)
	if absf(halved_db - (-4.0 + linear_to_db(0.5))) > 0.5:
		failed.append("audio: the SFX slider did not scale playback (%.1f dB, wanted %.1f)" % [halved_db, -4.0 + linear_to_db(0.5)])
	if absf(AudioManager.sfx_volume() - 0.5) > 0.001:
		failed.append("audio: the SFX slider never reached the manager (%.2f)" % AudioManager.sfx_volume())
	# Music applies to the live player, so dragging the slider is audible at once.
	AudioManager.set_music_volume(0.25)
	if not is_equal_approx(AudioManager._music_player.volume_db, linear_to_db(0.25)):
		failed.append("audio: the music slider did not reach the track (%.1f dB, wanted %.1f)" % [AudioManager._music_player.volume_db, linear_to_db(0.25)])
	AudioManager.set_music_volume(0.0)
	# is_finite, not just "quiet": Godot's linear_to_db(0) is -inf, which passes a
	# `> -40` test while being a value you do not want in the mix.
	var silent_db: float = AudioManager._music_player.volume_db
	if not is_finite(silent_db) or silent_db > -40.0:
		failed.append("audio: the music slider at zero leaves %.1f dB (wanted finite and below -40)" % silent_db)
	AudioManager.set_sfx_volume(sfx_was)
	AudioManager.set_music_volume(music_was)
	if not is_equal_approx(AudioManager.sfx_volume(), sfx_was) or not is_equal_approx(AudioManager.music_volume(), music_was):
		failed.append("audio: the volumes did not restore (%.2f / %.2f)" % [AudioManager.sfx_volume(), AudioManager.music_volume()])
	# The pause menu's own sliders drive those volumes, and re-sync from them.
	var pm_music: HSlider = pm.get_node_or_null("Center/Card/Tabs/MENU/Audio/MusicRow/MusicSlider") as HSlider
	if pm_music == null:
		failed.append("audio: the pause menu has no music slider")
	else:
		pm_music.value = 0.6   # a real drag, not a direct manager call
		if not is_equal_approx(AudioManager.music_volume(), 0.6):
			failed.append("audio: the pause-menu music slider did not reach the manager (%.2f)" % AudioManager.music_volume())
		if not is_equal_approx(float(Storage.get_value("music_volume", -1.0)), 0.6):
			failed.append("audio: the music volume never reached the save")
		AudioManager.set_music_volume(0.15)
		pm.sync_audio_sliders()
		if not is_equal_approx(pm_music.value, 0.15):
			failed.append("audio: the pause menu did not re-sync its slider (%.2f)" % pm_music.value)
		AudioManager.set_music_volume(music_was)
	# Music has to loop: music.ogg.import ships loop=false, so if the runtime
	# stops setting it the track plays once and the game goes silent.
	if AudioManager.music == null:
		failed.append("audio: the music stream did not load")
	elif not _stream_loops(AudioManager.music):
		failed.append("audio: the music stream is not set to loop")

	# -- Audio depth: per-archetype deaths, heartbeat, sting -------------------
	# The generated one-shots are level-calibrated to the shipped beds (-15.8 dB
	# mean), so measure the heartbeat's RMS and keep it within 1 dB.
	var hb_stream: AudioStreamWAV = AudioManager._heartbeat
	if hb_stream == null:
		failed.append("audio: no generated heartbeat stream")
	else:
		var hb_rms: float = _wav_rms(hb_stream)
		var hb_db: float = linear_to_db(maxf(hb_rms, 0.00001))
		if absf(hb_db - (-15.8)) > 1.0:
			failed.append("audio: the generated heartbeat sits at %.1f dB RMS, wanted -15.8 +/- 1" % hb_db)
	# Per-archetype death tones: distinct per tag, and the enemy derives its own.
	var ad_chaser: EnemyBase = load("res://scenes/enemy_chaser.tscn").instantiate() as EnemyBase
	if ad_chaser == null:
		failed.append("audio: could not instantiate a chaser for the death-sound probe")
	else:
		main.add_child(ad_chaser)
		if ad_chaser.archetype != "chaser":
			failed.append("audio: the enemy archetype is \"%s\", expected \"chaser\"" % ad_chaser.archetype)
		if ad_chaser.death_sound == null:
			failed.append("audio: the chaser has no death sound")
		ad_chaser.free()
	var ad_a: AudioStreamWAV = AudioManager.enemy_death_stream("chaser") as AudioStreamWAV
	var ad_b: AudioStreamWAV = AudioManager.enemy_death_stream("tank") as AudioStreamWAV
	if ad_a != null and ad_b != null and ad_a.data == ad_b.data:
		failed.append("audio: two archetypes share one death tone")
	if AudioManager._sting == null:
		failed.append("audio: no generated wave-clear sting")
	# Heartbeat ONLY while low health: drive the HUD's own _process clock.
	main._hud.set_health(10, 100)
	main._hud._heartbeat_timer = 0.0
	var hb_before: int = AudioManager.heartbeat_count
	main._hud._process(0.0)
	if AudioManager.heartbeat_count <= hb_before:
		failed.append("audio: the heartbeat never played at 10/100 health")
	var hb_low: int = AudioManager.heartbeat_count
	main._hud.set_health(100, 100)
	for hb_i: int in 5:
		main._hud._process(1.0)
	if AudioManager.heartbeat_count != hb_low:
		failed.append("audio: the heartbeat kept playing at full health")
	main._hud.set_health(arena_player.health, arena_player.max_health)

	# -- Typography: the game's own files stay pure ASCII ---------------------
	# Godot draws with ThemeDB.fallback_font, which has no glyph for an em dash
	# or an arrow. A non-ASCII character in a LABEL gets substituted from a
	# system font, so on a CJK-configured machine it renders as a mismatched
	# glyph -- and in a comment it renders as garbage in a non-UTF-8 editor.
	var ascii_offenders: Array[String] = []
	for ascii_root: String in ["res://scripts", "res://scenes"]:
		_collect_non_ascii(ascii_root, ascii_offenders)
	if not ascii_offenders.is_empty():
		failed.append("non-ASCII bytes in %d game file(s): %s" % [ascii_offenders.size(), ", ".join(ascii_offenders)])

	# -- Boss wave rule -------------------------------------------------------
	if wm.is_boss_wave(9) or wm.is_boss_wave(11) or not wm.is_boss_wave(10):
		failed.append("boss: is_boss_wave() is wrong (10 must be a boss wave, 9/11 must not)")
	var boss_comp: Dictionary = wm._composition_for_wave(10)
	if int(boss_comp.get("boss", 0)) != wm.boss_count:
		failed.append("boss: wave 10 composition carries %d bosses, expected %d" % [int(boss_comp.get("boss", 0)), wm.boss_count])
	if wm.boss_count < 2:
		failed.append("boss: boss_count is %d - the wave is supposed to send a pair" % wm.boss_count)
	if int(boss_comp.get("elite", 0)) != 0 or int(boss_comp.get("tank", 0)) != 0:
		failed.append("boss: wave 10 should be the bosses plus a small escort, not a swarm")
	if int(boss_comp.get("bulwark", 0)) != 0 or int(boss_comp.get("leaper", 0)) != 0:
		failed.append("boss: the new archetypes escort the boss wave (they were zeroed for a reason)")
	if int(wm._composition_for_wave(11).get("boss", 0)) != 0:
		failed.append("boss: the boss leaked into wave 11")

	# -- Boss pair: both walk in on the same frame ---------------------------
	# Not just "two exist eventually" -- the whole point is that they arrive
	# together, so time the frames on which the first and the second appear.
	main.get_node("World/Player")._invuln_timer = 30.0   # keep the fixture alive
	var pair_kids: Array[Node] = wm._enemy_container.get_children()
	var pair_alive0: int = wm._alive
	wm.is_running = true
	wm._start_wave(10)
	var pair_first: int = -1
	var pair_second: int = -1
	var pair_frames: int = 0
	while pair_second < 0 and pair_frames < 90:
		await main.get_tree().physics_frame
		pair_frames += 1
		var pair_now: int = _count_bosses(wm._enemy_container, pair_kids)
		if pair_now >= 1 and pair_first < 0:
			pair_first = pair_frames
		if pair_now >= wm.boss_count:
			pair_second = pair_frames
	if pair_second < 0:
		failed.append("boss: wave 10 never fielded %d bosses (%d after %d frames)" % [wm.boss_count, _count_bosses(wm._enemy_container, pair_kids), pair_frames])
	elif pair_second - pair_first > 2:
		failed.append("boss: the pair arrived %d frames apart (should be together)" % (pair_second - pair_first))
	if wm._spawn_queue.has("boss"):
		failed.append("boss: bosses are still queued behind the escort instead of spawning up front")
	for pair_e: Node in wm._enemy_container.get_children():
		if not pair_kids.has(pair_e):
			pair_e.queue_free()
	wm._alive = pair_alive0
	wm.stop()
	# Drain any in-flight telegraph BEFORE anything re-enables is_running: the
	# spawn guard only checks that flag, so a pending escort would otherwise
	# materialise later and be mistaken for the next section's boss.
	for i in 30:
		await main.get_tree().physics_frame
	BulletPool.reset()

	# -- Boss: knockback resistance is applied, not just declared -------------
	var kb_boss: Node = load("res://scenes/enemy_boss.tscn").instantiate()
	wm._enemy_container.add_child(kb_boss)
	if not is_equal_approx(kb_boss.knockback_resist, 0.85):
		failed.append("boss: knockback_resist is %.2f, expected 0.85" % kb_boss.knockback_resist)
	kb_boss.take_damage(1, Vector2(100.0, 0.0))
	var kb_expected: float = 100.0 * (1.0 - 0.85)
	if not is_equal_approx(kb_boss._knockback_vel.x, kb_expected):
		failed.append("boss: 100 knockback moved it %.1f, expected %.1f at 85%% resist" % [kb_boss._knockback_vel.x, kb_expected])
	kb_boss.queue_free()

	# -- Boss phases: three thresholds, once each, never while dormant ----------
	# A dormant boss takes a past-threshold hit without transitioning (the
	# phase check lives in _update_behavior, which dormancy freezes); waking
	# below a threshold fires it exactly once, and no later hit re-fires it.
	var ph_player: Node = main.get_node("World/Player")
	var ph_keep_hp: int = ph_player.health
	var ph_keep_max: int = ph_player.max_health
	ph_player.max_health = 400
	ph_player.health = 400
	ph_player._invuln_timer = 30.0   # the fixtures below sling bullets around
	var ph_boss: Node = load("res://scenes/enemy_boss.tscn").instantiate()
	ph_boss.position = Vector2(-200, -420)
	wm._enemy_container.add_child(ph_boss)
	ph_boss.is_dormant = true
	var phase_events: Array[int] = []
	ph_boss.boss_phase_changed.connect(func(phase: int, _c: Color, _at: Vector2) -> void: phase_events.append(phase))
	ph_boss.take_damage(int(float(ph_boss.max_health) * 0.5))   # ratio ~0.5: past 0.66 already
	for i in 3:
		await main.get_tree().physics_frame
	if not phase_events.is_empty():
		failed.append("boss phases: fired while dormant (%s)" % str(phase_events))
	ph_boss.is_dormant = false
	for i in 3:
		await main.get_tree().physics_frame
	if phase_events != [2]:
		failed.append("boss phases: waking under 0.66 fired %s, expected exactly [2]" % str(phase_events))
	ph_boss.take_damage(10)   # same phase, more damage: must not re-fire
	for i in 3:
		await main.get_tree().physics_frame
	if phase_events != [2]:
		failed.append("boss phases: phase 2 re-fired (%s)" % str(phase_events))
	while float(ph_boss.health) / float(ph_boss.max_health) >= EnemyBoss.PHASE_3_AT:
		ph_boss.take_damage(int(float(ph_boss.max_health) * 0.1) + 1)
	for i in 3:
		await main.get_tree().physics_frame
	if phase_events != [2, 3]:
		failed.append("boss phases: crossing 0.33 fired %s, expected exactly [2, 3]" % str(phase_events))
	if ph_boss.ring_bullets != ph_boss.burst_ring_bullets:
		failed.append("boss phases: phase 2 never fattened the ring (%d, wanted %d)" % [ph_boss.ring_bullets, ph_boss.burst_ring_bullets])
	if not ph_boss.death_burst_color.is_equal_approx(EnemyBoss.PHASE_3_COLOR):
		failed.append("boss phases: the death burst never shifted to the phase colour (%s)" % str(ph_boss.death_burst_color))
	# Phase 3 charge: parked 800+ px out, the boss must actually DASH -- a
	# per-frame step more than double what its 72 px/s walk can manage -- and
	# it must never reach the player inside the window (a dash that connects
	# would kill the fixture mid-probe).
	var ph_last: Vector2 = ph_boss.global_position
	var ph_max_step: float = 0.0
	var ph_charged: bool = false
	for i in 120:
		await main.get_tree().physics_frame
		var ph_step: float = ph_boss.global_position.distance_to(ph_last)
		ph_last = ph_boss.global_position
		ph_max_step = maxf(ph_max_step, ph_step)
		if ph_boss._charging:
			ph_charged = true
	if not ph_charged:
		failed.append("boss phases: phase 3 never raised a charge")
	elif ph_max_step <= float(ph_boss.move_speed) / 60.0 * 2.0:
		failed.append("boss phases: the biggest step was %.1f px -- a charge at %.0f px/s never landed" % [ph_max_step, ph_boss.charge_speed])
	ph_boss.queue_free()
	# Phase 1 summon: two minis emitted on the interval. The probe parents them
	# (in the real game the WaveManager's splitter plumbing does).
	var sum_boss: Node = load("res://scenes/enemy_boss.tscn").instantiate()
	sum_boss.position = Vector2(-600, -520)
	sum_boss.minion_interval = 0.3
	wm._enemy_container.add_child(sum_boss)
	var summoned: Array = []
	sum_boss.split_spawned.connect(func(pair: Array) -> void:
		for mini: Node in pair:
			wm._enemy_container.add_child(mini)
		summoned.append_array(pair))
	for i in 40:
		await main.get_tree().physics_frame
	if summoned.size() < 2:
		failed.append("boss phases: phase 1 summoned %d minis, expected 2" % summoned.size())
	for ph_mini: Node in summoned:
		ph_mini.queue_free()
	sum_boss.queue_free()
	ph_player.max_health = ph_keep_max
	ph_player.health = ph_keep_hp
	ph_player._invuln_timer = 0.0
	BulletPool.reset()

	# -- Boss: giant, barrier-ignoring, sprays swirling hostiles --------------
	# Spawned through the SAME registry the wave uses, so a missing match arm or
	# a bad scene export fails here instead of silently spawning a chaser.
	var boss_kids: Array[Node] = wm._enemy_container.get_children()
	var boss_alive0: int = wm._alive
	wm.is_running = true
	wm._spawn_enemy("boss")
	var boss: Node = null
	for i in 60:
		await main.get_tree().physics_frame
		boss = _find_new_boss(wm._enemy_container, boss_kids)
		if boss != null:
			break
	if boss == null:
		failed.append("boss: _spawn_enemy('boss') produced no boss (match arm or scene export)")
	elif not boss.has_method("_fire_ring"):
		failed.append("boss: spawn registry produced the wrong scene for 'boss'")
	else:
		var boss_player: Node2D = main.get_node("World/Player")
		if int(boss.collision_mask) & 8:
			failed.append("boss: collision mask still has the Wall bit (cover would block it)")
		# Pin the fixture: earlier probes knock the player around with contact
		# knockback, and every number below is relative to where it stands.
		boss_player.global_position = Vector2.ZERO
		boss_player.velocity = Vector2.ZERO
		boss_player._invuln_timer = 5.0
		# Behind arena 1's NW corner bar, straight-line at the player: with the
		# Wall bit absent it walks THROUGH the bar; with it present it stalls.
		# The distance check alone is weak (a colliding boss slides around cover),
		# so also sample the bar's own footprint: the body's centre must actually
		# cross it, which physics never lets a wall-colliding body do.
		boss.set_deferred("global_position", Vector2(-700, -520))
		for i in 6:
			await main.get_tree().physics_frame
		var boss_start_dist: float = boss.global_position.distance_to(boss_player.global_position)
		var bar_samples: int = 0
		for i in 90:
			await main.get_tree().physics_frame
			var boss_pos: Vector2 = boss.global_position
			if absf(boss_pos.x + 650.0) <= 150.0 and absf(boss_pos.y + 460.0) <= 16.0:
				bar_samples += 1
		var boss_end_dist: float = boss.global_position.distance_to(boss_player.global_position)
		if boss_end_dist >= boss_start_dist - 1.0:
			failed.append("boss: did not close on the player from behind cover (%0.1f -> %0.1f)" % [boss_start_dist, boss_end_dist])
		if bar_samples == 0:
			failed.append("boss: never crossed the corner bar's footprint - cover blocked it")
		# Bullet hell: the boss must fire in the OPEN. Its rounds die on contact
		# with cover, so counting them from inside a wall would measure the wall.
		# The player is parked behind CoreN on the y axis, out of the firing line.
		var hp_keep: int = boss_player.health
		var max_keep: int = boss_player.max_health
		boss_player.max_health = 400
		boss_player.health = 400
		boss.set_deferred("global_position", Vector2(0, -520))
		await main.get_tree().physics_frame
		# Clear strays from the walk phase first: a pre-existing hostile that
		# expires inside the count frame would eat one from the tally.
		BulletPool.reset()
		var hostile_before: int = _count_hostile_active()
		# Fire the volley DIRECTLY: the ring timer's phase depends on how long the
		# boss has been alive, and counting a timer-driven volley is a coin flip on
		# whether the window catches one. The probe's subject is the volley itself.
		boss._fire_ring()
		await main.get_tree().physics_frame
		var hostile_spawned: int = _count_hostile_active() - hostile_before
		if hostile_spawned < int(boss.ring_bullets):
			failed.append("boss: no bullet-hell volley appeared (%d hostile rounds after 1 frame)" % hostile_spawned)
		# Rounds must carry the boss's OWN speed, not the Bullet default: the ring
		# flies at bullet_speed, the swirl at bullet_speed * spiral_speed_scale.
		var boss_round_speed: float = 0.0
		for speed_b: Bullet in BulletPool._all:
			if speed_b.is_active and speed_b.hostile:
				boss_round_speed = maxf(boss_round_speed, speed_b.speed)
		var boss_speed_ceiling: float = float(boss.bullet_speed) * float(boss.spiral_speed_scale)
		if boss_round_speed < float(boss.bullet_speed) or boss_round_speed > boss_speed_ceiling + 1.0:
			failed.append("boss: hostile rounds travel at %.0f, expected %.0f..%.0f" % [boss_round_speed, boss.bullet_speed, boss_speed_ceiling])
		boss_player.max_health = max_keep
		boss_player.health = hp_keep
		boss_player._invuln_timer = 0.0
		boss.queue_free()
	wm._alive = boss_alive0
	wm.stop()
	BulletPool.reset()

	# -- Balance: how long does a MAXED build need to kill the wave-10 boss? ---
	# The reported symptom was a boss that "stands no chance" once the shop is
	# maxed, so measure the real number instead of arguing about it: one volley
	# through the actual fire path, divided by the actual fire interval.
	# A FRESH player is the fixture, not the live one -- earlier sections already
	# bought upgrades on that node, so its stats are past the caps.
	BulletPool.reset()
	var balance_player: Node = load("res://scenes/player.tscn").instantiate()
	main.add_child(balance_player)
	balance_player.global_position = main.get_node("World/Player").global_position
	var balance_up: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(balance_up)
	for balance_def: Dictionary in balance_up.DEFS:
		for i: int in int(balance_def.max_level):
			balance_up.buy(String(balance_def.id), 999999, balance_player)
	var balance_boss: Node = load("res://scenes/enemy_boss.tscn").instantiate()
	wm._enemy_container.add_child(balance_boss)
	balance_boss.is_dormant = true    # stationary dummy: no shots, no drift
	balance_boss.global_position = balance_player.global_position + Vector2(200, 0)
	await main.get_tree().physics_frame
	# Aim AT the dummy (angle to it), never at a hardcoded heading: the player
	# node drifts, and a fixed 0.0 rad points the spread off-axis.
	balance_player._aim_pivot.rotation = (balance_boss.global_position - balance_player.global_position).angle()
	var volley_damage: Array[int] = [0]
	balance_boss.connect("damaged", func(amount: int) -> void: volley_damage[0] += amount)
	var balance_saved_crit: float = BulletPool.crit_chance
	# Crits are random (a crit doubles one round in ~10% of hits), so measure the
	# deterministic baseline: this number feeds a TTK call, not a damage log.
	BulletPool.crit_chance = 0.0
	balance_player._fire_bullet()
	# Wait a FIXED window, not until the first hit: the spread means the outer
	# rounds arrive a few frames after the middle pair, and breaking early reads
	# a partial volley (half the damage -> half the DPS -> a wrong HP call).
	for i in 45:
		await main.get_tree().physics_frame
	BulletPool.crit_chance = balance_saved_crit
	# A maxed build owns bossbane/exec/burn too, so the volley is NOT plain
	# damage x pellets: each round deals round(damage x target_mult) and the
	# boss is at full HP (no exec), not an elite -- one target_mult call here
	# mirrors exactly what Bullet._handle_hit computes per round.
	var balance_expected: int = int(balance_player.bullets_per_shot) \
			* int(round(float(balance_player.bullet_damage) * Bullet.target_mult(balance_boss)))
	var balance_dps: float = float(volley_damage[0]) / maxf(balance_player.fire_rate, 0.001)
	var balance_mult: float = float(wm._base_composition(10).get("hp_mult", 1.0))
	var balance_hp: float = float(balance_boss.max_health) * balance_mult
	var balance_ttk: float = balance_hp / maxf(balance_dps, 1.0)
	var balance_pair_ttk: float = balance_ttk * float(wm.boss_count)
	print("[Balance] maxed build: %d dmg/volley of %d (dmg %d x %d bullets), %.0f dps -> boss %.0f hp = %.2fs, wave-10 pair (x%d) = %.2fs" % [volley_damage[0], balance_expected, balance_player.bullet_damage, balance_player.bullets_per_shot, balance_dps, balance_hp, balance_ttk, wm.boss_count, balance_pair_ttk])
	if volley_damage[0] <= 0:
		failed.append("balance: the maxed build's volley never reached the boss dummy")
	elif volley_damage[0] != balance_expected:
		failed.append("balance: volley dealt %d, expected %d (damage x bullets_per_shot) - spread or hit path is off" % [volley_damage[0], balance_expected])
	elif balance_pair_ttk < MIN_BOSS_FIGHT_SECONDS:
		failed.append("balance: a maxed build clears the wave-10 boss pair in %.2fs (want >= %.1fs)" % [balance_pair_ttk, MIN_BOSS_FIGHT_SECONDS])
	balance_boss.queue_free()
	balance_player.queue_free()
	balance_up.queue_free()
	BulletPool.reset()

	# -- Arena swap: the deep arena loads and the run survives it -------------
	var carried_player: Node = main._player
	var world_before: Node = main.get_node("World")
	var spawn_count_before: int = main.get_tree().get_nodes_in_group("spawn_points").size()
	var player_hp_before: int = carried_player.health
	main._switch_arena(1, false)   # not a live run: leave the hazard disarmed
	await main.get_tree().physics_frame
	var world_after: Node = main.get_node_or_null("World")
	if world_after == null or world_after == world_before:
		failed.append("arena: the World node was not replaced")
	elif world_after.get_child_count() < 10:
		failed.append("arena: the new World looks empty (%d children)" % world_after.get_child_count())
	if main._player != carried_player:
		failed.append("arena: the player node was replaced instead of carried over")
	if not carried_player.is_inside_tree():
		failed.append("arena: the carried player is not in the tree after the swap")
	if carried_player.health != player_hp_before:
		failed.append("arena: the swap changed the player's health (%d -> %d)" % [player_hp_before, carried_player.health])
	var deep_spawns: Array[Node] = main.get_tree().get_nodes_in_group("spawn_points")
	if deep_spawns.size() != spawn_count_before:
		failed.append("arena: spawn count changed across the swap (%d -> %d)" % [spawn_count_before, deep_spawns.size()])
	if not wm.hard_arena:
		failed.append("arena: the deep arena did not raise the wave difficulty")
	if wm._enemy_container == null or not wm._enemy_container.is_inside_tree():
		failed.append("arena: the enemy container was not rebound to the new arena")
	var deep_nav: NavigationRegion2D = main.get_node_or_null("World/NavRegion")
	if deep_nav == null or deep_nav.navigation_polygon == null or deep_nav.navigation_polygon.get_polygon_count() < 1:
		failed.append("arena: the deep arena has no baked navmesh")
	else:
		# The player spawns inside the fortress: every spawn point must be able to
		# path in, or waves never clear in the arena.
		var deep_map: RID = (main.get_node("World") as Node2D).get_world_2d().navigation_map
		# Let the fresh region sync before pathing: the swap frees the old World and
		# the server registers the new navmesh a few frames later, so a path query
		# on the very next frame can spuriously come back empty.
		for deep_wait: int in 12:
			await main.get_tree().physics_frame
		NavigationServer2D.map_force_update(deep_map)
		for deep_sp: Node in deep_spawns:
			var deep_from: Vector2 = (deep_sp as Node2D).global_position
			if NavigationServer2D.map_get_path(deep_map, deep_from, carried_player.global_position, true).size() < 2:
				failed.append("arena: deep spawn %s cannot reach the player inside the fortress" % deep_sp.name)

	# -- Arena 2: a killed enemy is really FREED (no corpse left behind) -------
	# The swap replaces World/EnemyContainer, so the kill watcher has to be
	# re-armed on the NEW container. Stale, arena-2 kills never scored and the
	# dead node just stood there on screen.
	var corpse_score_before: int = main._score
	var corpse_enemy: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	wm._enemy_container.add_child(corpse_enemy)
	corpse_enemy.global_position = carried_player.global_position + Vector2(120, 0)
	await main.get_tree().physics_frame
	corpse_enemy.take_damage(9999)
	for i in 3:
		await main.get_tree().process_frame
	if is_instance_valid(corpse_enemy) and not corpse_enemy.is_queued_for_deletion():
		failed.append("arena: killed enemy was never freed -- corpse left on screen")
	if main._score <= corpse_score_before:
		failed.append("arena: killing an enemy in the deep arena did not score")

	# -- Main menu: title, START, ENDLESS, mutes, two-click RESET -------------
	# The menu is the ONLY writer of the ENDLESS preference, so this wiring is
	# what otherwise silently never reaches the wave manager.
	var menu: CanvasLayer = main.get_node("UI/MainMenu")
	var menu_col: Node = menu.get_node("Center/Card/Margin/Column")
	for menu_name: String in ["Subtitle", "BestLabel", "KillsLabel", "StartButton",
			"EndlessCheck", "Audio/MusicRow/MusicSlider", "Audio/SfxRow/SfxSlider",
			"ResetButton", "Controls"]:
		if menu_col.get_node_or_null(menu_name) == null:
			failed.append("menu: %s is missing from the title screen" % menu_name)
	var menu_title: Label = menu_col.get_node("Title") as Label
	# The card title is the art layer's call to action; the game's name is drawn into the
	# poster behind it. Assert the art layer's string actually reaches the label -- if the
	# poster stops styling the card, the label falls back to config/name and this fails.
	if menu_title.text != RetroMenuArt.CARD_TITLE:
		failed.append("menu: card title '%s' is not RetroMenuArt.CARD_TITLE ('%s')" % [menu_title.text, RetroMenuArt.CARD_TITLE])
	if not main.get_node("UI/MainMenu").has_node("RetroMenuArt"):
		failed.append("menu: no RetroMenuArt poster behind the menu")
	# The poster title is a RULE, not a hardcoded pair of lines: one big line when the name
	# fits the 570 px column, wrapped at spaces otherwise. This is what makes renaming the
	# game a one-line edit in project.godot (config/name also sets the window title).
	var wavebreaker_lines: PackedStringArray = RetroMenuArt.title_lines("Wavebreaker")
	if wavebreaker_lines.size() != 1 or String(wavebreaker_lines[0]) != "WAVEBREAKER":
		failed.append("menu: 'Wavebreaker' should be one upper-case poster line, got %s" % str(wavebreaker_lines))
	if RetroMenuArt.title_lines("Wave Arena Shooter").size() != 2:
		failed.append("menu: a three-word name should wrap onto two poster lines, got %s"
				% str(RetroMenuArt.title_lines("Wave Arena Shooter")))
	if String(RetroMenuArt.title_lines("wavebreaker")[0]) != String(wavebreaker_lines[0]):
		failed.append("menu: the poster title does not upper-case its input")
	var menu_started: Array = [false]
	menu.start_pressed.connect(func() -> void: menu_started[0] = true)
	(menu_col.get_node("StartButton") as Button).pressed.emit()
	if not bool(menu_started[0]):
		failed.append("menu: the START button does not emit start_pressed")
	# The stored numbers have to be READ on refresh, not just formatted once.
	Storage.set_value("total_kills", 55)
	menu.refresh_stats()
	if not (menu_col.get_node("KillsLabel") as Label).text.contains("55"):
		failed.append("menu: the lifetime kill total is not shown")
	# ENDLESS: control -> save file -> WaveManager, and back.
	var menu_endless: CheckButton = menu_col.get_node("EndlessCheck") as CheckButton
	wm.endless = true
	menu_endless.set_pressed(false)
	if wm.endless:
		failed.append("menu: ENDLESS off never reached the WaveManager")
	if bool(Storage.get_value("endless", true)):
		failed.append("menu: ENDLESS off never reached the save file")
	menu_endless.set_pressed(true)
	if not wm.endless:
		failed.append("menu: ENDLESS back on never reached the WaveManager")
	# Volumes: the menu's sliders drive AudioManager, which owns the save keys.
	var menu_music: HSlider = menu_col.get_node("Audio/MusicRow/MusicSlider") as HSlider
	var menu_music_was: float = AudioManager.music_volume()
	menu_music.value = 0.8   # a drag, through value_changed
	if not is_equal_approx(AudioManager.music_volume(), 0.8):
		failed.append("menu: the MUSIC slider does not reach AudioManager (%.2f)" % AudioManager.music_volume())
	if not is_equal_approx(float(Storage.get_value("music_volume", -1.0)), 0.8):
		failed.append("menu: the MUSIC slider never reached the save file")
	menu_music.value = 0.0
	var menu_silent_db: float = AudioManager._music_player.volume_db
	if not is_finite(menu_silent_db) or menu_silent_db > -40.0:
		failed.append("menu: the MUSIC slider at zero leaves %.1f dB (wanted finite and below -40)" % menu_silent_db)
	AudioManager.set_music_volume(menu_music_was)
	menu.sync_audio_sliders()
	if not is_equal_approx(menu_music.value, menu_music_was):
		failed.append("menu: the MUSIC slider does not mirror the current volume (%.2f)" % menu_music.value)
	var menu_sfx: HSlider = menu_col.get_node("Audio/SfxRow/SfxSlider") as HSlider
	var menu_sfx_was: float = AudioManager.sfx_volume()
	menu_sfx.value = 0.7
	if not is_equal_approx(AudioManager.sfx_volume(), 0.7):
		failed.append("menu: the SOUND FX slider does not reach AudioManager (%.2f)" % AudioManager.sfx_volume())
	if not is_equal_approx(float(Storage.get_value("sfx_volume", -1.0)), 0.7):
		failed.append("menu: the SOUND FX slider never reached the save file")
	AudioManager.set_sfx_volume(menu_sfx_was)
	menu.sync_audio_sliders()
	if not is_equal_approx(menu_sfx.value, menu_sfx_was):
		failed.append("menu: the SOUND FX slider does not mirror the current volume (%.2f)" % menu_sfx.value)
	# RESET SAVE: one click only arms it -- erasing everything on a single click
	# is the footgun the confirmation exists for.
	var menu_reset: Button = menu_col.get_node("ResetButton") as Button
	Storage.set_value("best_score", 4242)
	Storage.set_value("total_kills", 55)
	Storage.set_value("sfx_muted", true)
	menu_reset.pressed.emit()
	if int(Storage.get_value("best_score", 0)) != 4242:
		failed.append("menu: the first RESET click already wiped the record")
	if not menu._reset_armed:
		failed.append("menu: the first RESET click did not arm the button")
	menu_reset.pressed.emit()
	if int(Storage.get_value("best_score", 0)) != 0 or int(Storage.get_value("total_kills", 0)) != 0:
		failed.append("menu: the confirming RESET click did not erase the records")
	if menu._reset_armed:
		failed.append("menu: RESET stayed armed after confirming")
	if not is_equal_approx(float(Storage.get_value("sfx_volume", -1.0)), menu_sfx_was):
		failed.append("menu: RESET wiped the player's sound preference")
	if not bool(Storage.get_value("endless", true)):
		failed.append("menu: RESET wiped the ENDLESS preference")
	if (menu_col.get_node("BestLabel") as Label).text != "":
		failed.append("menu: the best label still shows the wiped record")
	menu._disarm_reset()

	# -- ENDLESS off: the finite run reaches a boss + arena transition, then ends --
	# Also proves the ending does NOT announce wave_cleared, which is what would
	# open the shop over the game-over panel.
	wm.is_running = true
	if wm.finite_wave_count() <= WaveManager.BOSS_EVERY:
		failed.append("endless off: finite run still ends before its first arena transition")
	wm.current_wave = wm.finite_wave_count()
	wm._alive = 0
	wm._spawn_queue.clear()
	wm.endless = false
	wm.shop_pause_enabled = true   # the shop is armed: the run must end anyway
	var finite_cleared: Array = [false]
	var finite_over: Array = [false]
	wm.wave_cleared.connect(func(_n: int) -> void: finite_cleared[0] = true)
	wm.game_over.connect(func() -> void: finite_over[0] = true)
	wm._on_enemy_died(null)
	if not bool(finite_over[0]):
		failed.append("endless off: clearing the final campaign wave did not end the run")
	if bool(finite_cleared[0]):
		failed.append("endless off: the final wave raised wave_cleared too -- the shop would open over the ending")
	wm.endless = true
	wm.stop()
	main._state = main.State.MENU

	# -- Difficulty: menu row -> save file -> the wave the player actually gets --
	# The row is built from WaveManager.DIFFICULTY_ORDER, so assert against the
	# registry rather than against a hardcoded list -- but only the rows that are
	# UNLOCKED get a button (nightmare waits for its unlockable), so the expected
	# count is the gated list, not the whole order.
	var diff_row: Node = menu_col.get_node_or_null("DifficultyRow")
	if diff_row == null:
		failed.append("menu: the difficulty row is missing")
	else:
		var diff_open: int = 0
		for diff_id0: String in WaveManager.DIFFICULTY_ORDER:
			if WaveManager.difficulty_unlocked(diff_id0):
				diff_open += 1
		if diff_row.get_child_count() != diff_open:
			failed.append("menu: %d difficulty buttons for %d unlocked difficulties" % [diff_row.get_child_count(), diff_open])
		for diff_id: String in WaveManager.DIFFICULTY_ORDER:
			var diff_has: bool = diff_row.get_node_or_null(diff_id.capitalize()) != null
			if WaveManager.difficulty_unlocked(diff_id) and not diff_has:
				failed.append("menu: no %s difficulty button" % diff_id)
			if not WaveManager.difficulty_unlocked(diff_id) and diff_has:
				failed.append("menu: %s is selectable while locked" % diff_id)
	# Click HARD through the real button: it must reach the save AND the manager.
	var diff_was: String = wm.difficulty
	var hard_btn: Button = diff_row.get_node_or_null("Hard") as Button
	if hard_btn == null:
		failed.append("menu: no HARD button to press")
	else:
		hard_btn.pressed.emit()
		if wm.difficulty != "hard":
			failed.append("menu: HARD never reached the WaveManager (%s)" % wm.difficulty)
		if String(Storage.get_value("difficulty", "")) != "hard":
			failed.append("menu: HARD never reached the save file")
		if not hard_btn.button_pressed:
			failed.append("menu: the HARD button did not show as selected")
	# And the difficulty must actually change the wave the player gets. Clear
	# hard_arena first: the arena-swap section above already set it, and it
	# multiplies the same value this probe is comparing against the table.
	var diff_hard_arena: bool = wm.hard_arena
	wm.hard_arena = false
	wm.endless = true
	wm._spawn_timer.stop()
	wm.difficulty = "normal"
	wm.is_running = true
	wm._start_wave(1)
	var diff_normal_hp: float = wm._hp_mult
	var diff_normal_gap: float = wm._spawn_timer.wait_time
	wm.stop()
	wm.difficulty = "hard"
	wm.is_running = true
	wm._start_wave(1)
	var diff_hard_hp: float = wm._hp_mult
	var diff_hard_gap: float = wm._spawn_timer.wait_time
	wm.stop()
	if diff_hard_hp <= diff_normal_hp:
		failed.append("difficulty: HARD did not raise the wave hp multiplier (%.2f vs %.2f)" % [diff_hard_hp, diff_normal_hp])
	if diff_hard_gap >= diff_normal_gap:
		failed.append("difficulty: HARD did not tighten the spawn interval (%.2f vs %.2f)" % [diff_hard_gap, diff_normal_gap])
	# NORMAL is the wave table scaled by its own difficulty hp row (the row is no
	# longer 1.0 after the global difficulty bump).
	var diff_normal_expected: float = float(wm.wave_table[0].get("hp_mult", 1.0)) * float(WaveManager.DIFFICULTIES["normal"]["hp"])
	if not is_equal_approx(diff_normal_hp, diff_normal_expected):
		failed.append("difficulty: NORMAL is not the wave table x its hp row (%.2f vs %.2f)" % [diff_normal_hp, diff_normal_expected])
	wm.difficulty = diff_was
	wm.hard_arena = diff_hard_arena
	wm._spawn_timer.wait_time = wm.spawn_interval
	main._state = main.State.MENU

	# -- Boss music: the bed swaps in on a boss wave and swaps back ------------
	if AudioManager.boss_music == null:
		failed.append("audio: the boss music stream did not load")
	elif not _stream_loops(AudioManager.boss_music):
		failed.append("audio: the boss music stream is not set to loop")
	main._on_wave_started(wm.BOSS_EVERY)
	if AudioManager._music_player.stream != AudioManager.boss_music:
		failed.append("audio: a boss wave did not switch to the boss music")
	main._on_wave_started(1)
	if AudioManager._music_player.stream != AudioManager.music:
		failed.append("audio: a normal wave did not switch back to the normal music")
	AudioManager.stop_music()

	# -- Pause menu: the UNLOCKABLES tab exists and is reachable ---------------
	var pm_tabs: TabContainer = pm.get_node_or_null("Center/Card/Tabs") as TabContainer
	if pm_tabs == null:
		failed.append("pause: the tab container is missing")
	else:
		var pm_titles: Array[String] = []
		for pm_i: int in pm_tabs.get_tab_count():
			pm_titles.append(pm_tabs.get_tab_title(pm_i))
		# The TabContainer orders children by their tree/child order, which the
		# @onready paths in the .tscn fix -- so compare the WHOLE strip by title,
		# not by counting: a hidden tab does not shift the list, and an extra child
		# is caught wherever it was inserted.
		if pm_titles != ["MENU", "UNLOCKABLES", "STATS", "PERKS", "BESTIARY"]:
			failed.append("pause: the tab strip is %s" % str(pm_titles))
		# STATS is hidden until earned; the rest are reference material that is
		# never gated. Read by TITLE, not index, so a hidden tab cannot shift the
		# answer to a different one.
		for pm_name: String in ["UNLOCKABLES", "PERKS", "BESTIARY"]:
			var pm_at: int = -1
			for pm_i: int in pm_tabs.get_tab_count():
				if pm_tabs.get_tab_title(pm_i) == pm_name:
					pm_at = pm_i
			if pm_at < 0 or pm_tabs.is_tab_hidden(pm_at):
				failed.append("pause: the %s tab is hidden or missing" % pm_name)
		pm_tabs.current_tab = 1
		await main.get_tree().process_frame
		var unlock_tab: Control = pm_tabs.get_current_tab_control() as Control
		if pm_tabs.current_tab != 1 or unlock_tab == null or not unlock_tab.visible:
			failed.append("pause: the UNLOCKABLES tab does not become visible")
		# A TabContainer sizes itself to the CURRENT tab, so a tab that is wider or
		# taller than the other resizes the card on click -- and the wider one gets
		# clipped until then. Both tabs must want the same box.
		var tabs_size_menu: Vector2 = pm_tabs.get_combined_minimum_size()
		pm_tabs.current_tab = 0
		await main.get_tree().process_frame
		var tabs_size_unlock: Vector2 = pm_tabs.get_combined_minimum_size()
		if not tabs_size_menu.is_equal_approx(tabs_size_unlock):
			failed.append("pause: the pause card resizes on a tab switch (%s vs %s)" % [str(tabs_size_menu), str(tabs_size_unlock)])
	# The controls the script binds must still resolve after the restructure.
	for pm_path: String in ["MENU/Audio/MusicRow/MusicSlider", "MENU/Audio/SfxRow/SfxSlider",
			"MENU/ResumeButton", "MENU/QuitButton"]:
		if pm.get_node_or_null("Center/Card/Tabs/" + pm_path) == null:
			failed.append("pause: %s went missing in the tab restructure" % pm_path)

	# -- Bestiary: every enemy, grouped, drawn from the one registry ------------
	# Three failure shapes: a row that names no scene (a portrait that cannot be
	# drawn), a group heading with no rows under it (an empty section), and the
	# encounter set never being written. Each is silent in play.
	var be_tab: Control = null
	for be_i: int in pm_tabs.get_tab_count():
		if pm_tabs.get_tab_title(be_i) == "BESTIARY":
			be_tab = pm_tabs.get_tab_control(be_i) as Control
	if be_tab == null:
		failed.append("bestiary: the tab is missing")
	else:
		for be_d: Dictionary in Beasts.DEFS:
			var be_scene: String = String(be_d.scene)
			if not ResourceLoader.exists(be_scene):
				failed.append("bestiary: '%s' names %s, which does not exist" % [String(be_d.id), be_scene])
			# An ELITE row is a variant, not a scene: `elite_<base slug>` names the
			# enemy it upgrades (the chaser's elite is its own scene, the rest share
			# the base scene so the portrait is the silhouette you meet). What must
			# hold is that it HAS a base, that it is tougher, and that it has an
			# invulnerability phase of its own -- either the shielded affix or a
			# scene that shields itself.
			if bool(be_d.get("elite", false)):
				var be_row_slug: String = String(be_d.get("slug", ""))
				var be_base_row: Dictionary = {}
				for be_other: Dictionary in Beasts.DEFS:
					if not bool(be_other.get("elite", false)) \
							and String(be_other.get("slug", "")) != "" \
							and ("elite_" + String(be_other.slug)) == be_row_slug:
						be_base_row = be_other
				if be_base_row.is_empty():
					failed.append("bestiary: elite '%s' (slug '%s') upgrades no enemy you meet"
							% [String(be_d.id), be_row_slug])
				elif String(be_d.scene) == String(be_base_row.scene):
					# A shared scene must document the family multiplier: the row's hp
					# is what the tab prints and the spawner scales from.
					var be_want_hp: int = maxi(1, int(round(float(be_base_row.hp)
							* float(be_d.get("hp_mult", Beasts.ELITE_HP_MULT)))))
					if int(be_d.hp) != be_want_hp:
						failed.append("bestiary: elite '%s' lists %d hp, base %d x %.1f says %d"
								% [String(be_d.id), int(be_d.hp), int(be_base_row.hp),
									float(be_d.get("hp_mult", Beasts.ELITE_HP_MULT)), be_want_hp])
				elif int(be_d.hp) <= int(be_base_row.hp):
					failed.append("bestiary: elite '%s' (%d hp) is no tougher than its base (%d hp)"
							% [String(be_d.id), int(be_d.hp), int(be_base_row.hp)])
				# The effective affix is what the spawner uses, so that is what the
				# probe reads (the registry applies the family default).
				var be_eff_affix: String = String(Beasts.roster_row(be_row_slug).get("affix", ""))
				if be_eff_affix != "shielded" and be_scene != "res://scenes/enemy_elite.tscn":
					failed.append("bestiary: elite '%s' has no shield phase (affix '%s', scene %s)"
							% [String(be_d.id), be_eff_affix, be_scene.get_file()])
				continue
			# The GROUP must be the classification the GAME uses, not a label the
			# registry invented: the scenes tag themselves ("elites"/"bosses") and
			# Main's kill handler counts through those groups. A row filed under the
			# wrong heading is a bestiary that lies about the roster.
			# The variant groups are added in _ready, which only runs once the node is
			# IN THE TREE -- an instantiate-and-read probe sees no groups at all and
			# would fail every elite/boss row for the wrong reason.
			var be_inst: Node = load(be_scene).instantiate()
			main._enemy_container.add_child(be_inst)
			await main.get_tree().process_frame
			var be_in_elites: bool = be_inst.is_in_group("elites")
			var be_in_bosses: bool = be_inst.is_in_group("bosses")
			be_inst.free()
			var be_group_want: String = String(be_d.group)
			var be_group_got: String = "bosses" if be_in_bosses else ("elites" if be_in_elites else "")
			if be_group_want != be_group_got:
				failed.append("bestiary: '%s' is filed under '%s' but the scene tags itself '%s'"
						% [String(be_d.id), be_group_want, be_group_got])
		# Every archetype you meet needs exactly ONE elite variant: two rows for one
		# base is a duplicate in the tab, none is a promise the tab does not keep.
		# BOSSES are deliberately excluded -- their phases are their own show and an
		# elite boss is a different design, not a multiplier.
		for be_row: Dictionary in Beasts.DEFS:
			var be_row_slug2: String = String(be_row.get("slug", ""))
			if bool(be_row.get("elite", false)) or be_row_slug2 == "" or be_row_slug2 == "boss":
				continue
			var be_variants: int = 0
			for be_cand: Dictionary in Beasts.DEFS:
				if bool(be_cand.get("elite", false)) \
						and String(be_cand.get("slug", "")) == "elite_" + be_row_slug2:
					be_variants += 1
			if be_variants != 1:
				failed.append("bestiary: '%s' has %d elite variants, expected exactly 1"
						% [String(be_row.id), be_variants])
		if Beasts.elite_rows().is_empty():
			failed.append("bestiary: the elite roster is empty")
		for be_group: String in Beasts.groups():
			var be_key: String = be_group if be_group != "" else "normal"
			var be_tiles: Node = be_tab.find_child("Tiles_" + be_key, true, false)
			var be_head: Node = be_tab.find_child("Head_" + be_key, true, false)
			if be_tiles == null or be_head == null:
				failed.append("bestiary: group '%s' has no heading/rows" % be_key)
				continue
			if be_tiles.get_child_count() != Beasts.group(be_group).size():
				failed.append("bestiary: group '%s' shows %d rows for %d registry entries"
						% [be_key, be_tiles.get_child_count(), Beasts.group(be_group).size()])
			# Every row in a group must be laid out to the SAME width, or the two
			# columns come out ragged: a GridContainer sizes each column to its
			# widest child's minimum, and an autowrap hint's minimum is its longest
			# word -- which squeezed the elite group into half its grid.
			var be_row_w: Array[float] = []
			for be_line: Node in be_tiles.get_children():
				be_row_w.append((be_line as Control).size.x)
			if not be_row_w.is_empty():
				var be_min: float = be_row_w.min()
				var be_max: float = be_row_w.max()
				if be_max - be_min > 0.5:
					failed.append("bestiary: group '%s' rows are %.0f..%.0f px wide"
							% [be_key, be_min, be_max])
				if be_max * 2.0 > (be_tiles as Control).size.x + 0.5:
					failed.append("bestiary: group '%s' columns do not fit (row %.0f px, grid %.0f px)"
							% [be_key, be_max, (be_tiles as Control).size.x])
			# Every row the player can actually meet must be spawnable, or the tab
			# lists an enemy the game never produces.
			for be_d2: Dictionary in Beasts.group(be_group):
				var be_slug: String = String(be_d2.get("slug", ""))
				if be_slug != "" and be_slug != "boss":
					var be_has_slug: bool = false
					for be_entry: Dictionary in Beasts.roster():
						if String(be_entry.slug) == be_slug:
							be_has_slug = true
					if not be_has_slug:
						failed.append("bestiary: '%s' has slug '%s' that the spawner cannot draw" % [String(be_d2.id), be_slug])
		# The heading text comes from the registry map, never a UI literal.
		if String(Beasts.GROUP_LABELS.get("", "")) != "NORMAL":
			failed.append("bestiary: the normal-group heading is not in GROUP_LABELS")
		# The multi-line hitboxes (a Hint label whose text wraps) are what make a
		# row taller than the icon: the tab must still fit the card.
		var be_hints: int = 0
		for be_node: Node in be_tab.find_children("*", "Label", true, false):
			if String(be_node.name) == "Hint" and (be_node as Label).text != "":
				be_hints += 1
		if be_hints != Beasts.DEFS.size():
			failed.append("bestiary: %d hint labels for %d enemies" % [be_hints, Beasts.DEFS.size()])
		# ...and the card must fit the window with this tab current.
		pm_tabs.current_tab = 4
		await main.get_tree().process_frame
		var be_card: Control = pm.get_node_or_null("Center/Card") as Control
		if be_card != null and be_card.get_combined_minimum_size().y > 715.0:
			failed.append("bestiary: the pause card wants %.0f px of a 720 px window with the bestiary open"
					% be_card.get_combined_minimum_size().y)
		# The roster is taller than any window: it lives in a ScrollContainer, and
		# the LAST group has to be reachable or the tab lies about "every enemy".
		var be_scroll: ScrollContainer = be_tab as ScrollContainer
		if be_scroll == null:
			failed.append("bestiary: the tab is not scrollable (the roster cannot fit a window)")
		elif be_scroll.get_v_scroll_bar().max_value <= be_scroll.size.y:
			failed.append("bestiary: nothing to scroll -- content %.0f px inside a %.0f px viewport"
					% [be_scroll.get_v_scroll_bar().max_value, be_scroll.size.y])
	# -- The spawner draws its scenes from the SAME registry ---------------------
	# The lookup replaced a hand-written match, so this is what keeps it honest: a
	# slug that resolves to the wrong scene (or to the chaser fallback) would
	# otherwise only show up as "the waves feel wrong".
	var sp_before: Array[Node] = main._enemy_container.get_children()
	var sp_telegraph: float = wm.spawn_telegraph_time
	wm.spawn_telegraph_time = 0.0
	wm.is_running = true
	# Pin the wave scaling so the elite health multiplier is measurable on its own.
	var sp_hp_saved: float = wm._hp_mult
	var sp_spd_saved: float = wm._speed_mult
	wm._hp_mult = 1.0
	wm._speed_mult = 1.0
	var sp_wrong: Array[String] = []
	var sp_missing: Array[String] = []
	var sp_elite_faults: Array[String] = []
	for sp_row: Dictionary in Beasts.roster():
		var sp_slug: String = String(sp_row.slug)
		if sp_slug == "boss":
			continue   # the boss rule picks its own scene (asserted below)
		wm._spawn_enemy(sp_slug)
		await main.get_tree().process_frame
		var sp_new: Node = null
		for sp_c: Node in main._enemy_container.get_children():
			if not sp_before.has(sp_c):
				sp_new = sp_c
		if sp_new == null:
			sp_missing.append(sp_slug)
			continue
		if sp_new.get_scene_file_path() != String(sp_row.scene):
			sp_wrong.append("%s -> %s" % [sp_slug, sp_new.get_scene_file_path()])
		# The elite flag has to reach the group (counters) and the health (the row's
		# multiplier), and a normal enemy must NOT be counted as an elite.
		var sp_is_elite: bool = bool(sp_row.get("elite", false))
		if sp_new.is_in_group("elites") != sp_is_elite:
			sp_elite_faults.append("%s: group elites=%s" % [sp_slug, str(sp_new.is_in_group("elites"))])
		var sp_ref: Node = load(String(sp_row.scene)).instantiate()
		var sp_want_hp: int = maxi(1, int(round(float(sp_ref.max_health) * float(sp_row.hp_mult))))
		sp_ref.free()
		if sp_new.max_health != sp_want_hp:
			sp_elite_faults.append("%s: %d hp, the row wants %d" % [sp_slug, sp_new.max_health, sp_want_hp])
		if sp_is_elite and String(sp_row.affix) != "" and sp_new.affix != String(sp_row.affix):
			sp_elite_faults.append("%s: affix '%s', the row wants '%s'" % [sp_slug, sp_new.affix, String(sp_row.affix)])
		sp_before.append(sp_new)
	wm._hp_mult = sp_hp_saved
	wm._speed_mult = sp_spd_saved
	if not sp_missing.is_empty():
		failed.append("bestiary: the spawner produced nothing for %s" % str(sp_missing))
	if not sp_wrong.is_empty():
		failed.append("bestiary: the spawner used the wrong scene for %s" % str(sp_wrong))
	if not sp_elite_faults.is_empty():
		failed.append("bestiary: elite variants are wrong: %s" % str(sp_elite_faults))
	# The boss rule still rotates its OWN scenes, which the roster only names.
	wm._spawn_enemy("boss")
	await main.get_tree().process_frame
	var sp_boss: Node = null
	for sp_c2: Node in main._enemy_container.get_children():
		if not sp_before.has(sp_c2):
			sp_boss = sp_c2
	var sp_boss_scenes: Array[String] = []
	for sp_row2: Dictionary in Beasts.group("bosses"):
		sp_boss_scenes.append(String(sp_row2.scene))
	if sp_boss == null or not sp_boss_scenes.has(sp_boss.get_scene_file_path()):
		failed.append("bestiary: the boss rule spawned %s, which is not a boss row"
				% ("nothing" if sp_boss == null else sp_boss.get_scene_file_path()))
	for sp_node: Node in main._enemy_container.get_children():
		if not sp_before.has(sp_node):
			sp_node.queue_free()
	for sp_frame: int in 2:
		await main.get_tree().process_frame
	wm.spawn_telegraph_time = sp_telegraph
	wm._alive = 0
	wm.is_running = false
	wm.stop()
	# Boss scene max_health must mirror the Beasts row (the bestiary prints the row).
	for bp_row: Dictionary in Beasts.group("bosses"):
		var bp_ps: PackedScene = load(String(bp_row.scene))
		if bp_ps == null:
			failed.append("boss parity: failed to load %s" % String(bp_row.scene))
			continue
		var bp_e: Node = bp_ps.instantiate()
		if int(bp_e.get("max_health")) != int(bp_row.hp):
			failed.append("boss parity: %s scene hp %d != registry hp %d"
					% [String(bp_row.id), int(bp_e.get("max_health")), int(bp_row.hp)])
		bp_e.free()
	# -- Difficulty owns the elite COUNT ----------------------------------------
	# EASY fields none at all, NORMAL the authored count, HARD and NIGHTMARE
	# multiply it -- and the ladder has to stay ordered, or "harder" stops meaning
	# anything. The count is read off the real spawn queue, not the table.
	for df_id: String in WaveManager.DIFFICULTY_ORDER:
		var df_row: Dictionary = WaveManager.DIFFICULTIES[df_id]
		for df_key: String in ["hp", "speed", "spawn", "elite"]:
			if not df_row.has(df_key):
				failed.append("difficulty: '%s' has no '%s'" % [df_id, df_key])
	var df_saved: String = wm.difficulty
	var df_counts: Dictionary = {}
	wm.is_running = true
	for df_id2: String in WaveManager.DIFFICULTY_ORDER:
		if not WaveManager.difficulty_unlocked(df_id2):
			continue
		wm.difficulty = df_id2
		# No director pressure: this measures the table and the difficulty row.
		wm._last_wave_seconds = 0.0
		wm._start_wave(6)   # wave 6 is the first authored elite wave (table says 1)
		var df_n: int = 0
		for df_entry: String in wm._spawn_queue:
			if Beasts.is_elite_slug(df_entry):
				df_n += 1
		df_counts[df_id2] = df_n
		wm.stop()
	if int(df_counts.get("easy", -1)) != 0:
		failed.append("difficulty: EASY fielded %s elites" % str(df_counts.get("easy")))
	var df_normal: int = int(df_counts.get("normal", 0))
	var df_hard: int = int(df_counts.get("hard", 0))
	if df_normal < 1:
		failed.append("difficulty: NORMAL fielded %d elites on the first elite wave" % df_normal)
	if df_hard <= df_normal:
		failed.append("difficulty: HARD (%d) does not field more elites than NORMAL (%d)"
				% [df_hard, df_normal])
	if df_counts.has("nightmare") and int(df_counts["nightmare"]) < df_hard:
		failed.append("difficulty: NIGHTMARE (%d) fields fewer elites than HARD (%d)"
				% [int(df_counts["nightmare"]), df_hard])
	wm.difficulty = df_saved
	wm._alive = 0
	wm.is_running = false
	wm.stop()

	# -- The portraits are CENTRED in their tiles -------------------------------
	# The bug this pins: the drawing was left at the SubViewport's origin, so a
	# body authored around (0,0) put its centre on the tile's TOP-LEFT corner and
	# three quarters of it fell outside -- "the portraits look cut off". Headless
	# cannot read the rendered pixels, so this measures the geometry the renderer
	# would use: the drawn box, its centre, and how much of the tile it fills.
	var pv_seen: int = 0
	for pv_path: String in ["res://scenes/enemy_chaser.tscn", "res://scenes/enemy_boss.tscn",
			"res://scenes/enemy_tank.tscn", "res://scenes/enemy_mini.tscn",
			"res://scenes/enemy_pulsar.tscn"]:
		if not ResourceLoader.exists(pv_path):
			continue
		var pv_tex: Texture2D = pm.beast_texture(pv_path)
		if pv_tex == null:
			failed.append("bestiary portrait: %s drew nothing" % pv_path.get_file())
			continue
		pv_seen += 1
		var pv_vp: SubViewport = null
		for pv_c: Node in pm.get_children():
			if pv_c is SubViewport:
				pv_vp = pv_c as SubViewport
		if pv_vp == null or pv_vp.get_child_count() == 0:
			failed.append("bestiary portrait: %s has no drawing canvas" % pv_path.get_file())
			continue
		var pv_canvas: Node2D = pv_vp.get_child(0) as Node2D
		var pv_poly: Polygon2D = null
		for pv_n: Node in pv_canvas.get_children():
			if pv_n is Polygon2D:
				pv_poly = pv_n as Polygon2D
				break
		if pv_canvas == null or pv_poly == null:
			failed.append("bestiary portrait: %s has no polygon" % pv_path.get_file())
			continue
		# The drawn box = the polygon, scaled and offset like the renderer will.
		var pv_box := Rect2(pv_poly.polygon[0], Vector2.ZERO)
		for pv_pt: Vector2 in pv_poly.polygon:
			pv_box = pv_box.expand(pv_pt)
		pv_box = Rect2(pv_box.position * pv_poly.scale + pv_canvas.position,
				pv_box.size * pv_poly.scale)
		var pv_centre: Vector2 = pv_box.get_center()
		var pv_want: float = float(PauseMenu.BEAST_ICON) * 0.5
		if pv_box.position.x < -0.5 or pv_box.position.y < -0.5 \
				or pv_box.end.x > pv_want * 2.0 + 0.5 or pv_box.end.y > pv_want * 2.0 + 0.5:
			failed.append("bestiary portrait: %s draws outside its tile (%s)"
					% [pv_path.get_file(), str(pv_box)])
		if absf(pv_centre.x - pv_want) > 2.0 or absf(pv_centre.y - pv_want) > 2.0:
			failed.append("bestiary portrait: %s is centred at %s, not the tile's middle (%s)"
					% [pv_path.get_file(), str(pv_centre), str(Vector2(pv_want, pv_want))])
		var pv_fill: float = maxf(pv_box.size.x, pv_box.size.y) / (pv_want * 2.0)
		if pv_fill < 0.5:
			failed.append("bestiary portrait: %s fills %.0f%% of its tile" % [pv_path.get_file(), pv_fill * 100.0])
	if pv_seen < 2:
		failed.append("bestiary portrait: only %d portraits were measurable" % pv_seen)

	pm.show_tab(0)

	# -- Bestiary encounters: spawning an enemy notes it, and a run banks it -----
	Beasts.forget()
	Storage.set_value(Beasts.SAVE_KEY, {})
	if Beasts.seen_count() != 0:
		failed.append("bestiary: a cleared encounter set still reports %d seen" % Beasts.seen_count())
	var be_probe: Node = load("res://scenes/enemy_sniper.tscn").instantiate()
	main._enemy_container.add_child(be_probe)
	await main.get_tree().process_frame
	if not Beasts.seen_ids().has("Sniper") or Beasts.seen_count() != 1:
		failed.append("bestiary: spawning a sniper tracked %d seen" % Beasts.seen_count())
	be_probe.free()
	# The id is the SCENE's, not the instance's class: an enemy scene the registry
	# does not list must not invent a row -- and an ELITE records the variant row,
	# not its base's (the two share a scene, so the flag is the only discriminator).
	Beasts.note_encountered("res://scenes/enemy_base.tscn")
	if Beasts.seen_count() != 1:
		failed.append("bestiary: an unlisted scene added a row (now %d seen)" % Beasts.seen_count())
	var be_seen_before: int = Beasts.seen_count()
	Beasts.note_encountered("res://scenes/enemy_sniper.tscn", true)
	if not Beasts.seen_ids().has("Elite Sniper") or Beasts.seen_count() != be_seen_before + 1:
		failed.append("bestiary: an elite encounter recorded the wrong row (%s)"
				% str(Beasts.seen_ids().keys()))
	Beasts.flush()
	# Sniper + Elite Sniper: two rows, one scene.
	if int((Storage.read_all().get(Beasts.SAVE_KEY, {}) as Dictionary).size()) != 2:
		failed.append("bestiary: flush() did not write the encounter set to the save")
	pm.refresh_bestiary()
	if String(pm._stats_values["seen"].text) != "2 / %d" % Beasts.DEFS.size():
		failed.append("bestiary: the progress line reads '%s'" % pm._stats_values["seen"].text)
	# The styling follows the set: the met enemy's hint is shown, an unmet one's is
	# not -- text nobody has earned must not be readable.
	var be_met_line: Node = be_tab.find_child("Sniper", true, false) if be_tab != null else null
	var be_unmet_line: Node = be_tab.find_child("Medic", true, false) if be_tab != null else null
	if be_met_line == null or be_unmet_line == null:
		failed.append("bestiary: the probe could not find its rows by id")
	else:
		if not (be_met_line.get_node("Hint") as Label).visible:
			failed.append("bestiary: a met enemy still hides its hint")
		if (be_unmet_line.get_node("Hint") as Label).visible:
			failed.append("bestiary: an unmet enemy shows its hint")
		if (be_unmet_line.get_node("Icon") as TextureRect).texture == null:
			failed.append("bestiary: an unmet enemy has no portrait")
		# A caption, not the monster: the row must not be labelled with the
		# capitalised BESTIARY id, which is display-only data.
		if (be_unmet_line.get_node("Name") as Label).text != "MEDIC":
			failed.append("bestiary: the row is captioned '%s'" % (be_unmet_line.get_node("Name") as Label).text)
	Beasts.forget()
	Storage.set_value(Beasts.SAVE_KEY, {})
	pm.refresh_bestiary()

	# -- Unlockables: 20 icons, 64x64 each, all greyed while locked ------------
	var unlock_grid: GridContainer = pm.get_node_or_null("Center/Card/Tabs/UNLOCKABLES/Grid") as GridContainer
	if unlock_grid == null:
		failed.append("unlockables: the icon grid is missing")
	else:
		if unlock_grid.get_child_count() != Unlockables.DEFS.size():
			failed.append("unlockables: %d tiles for %d registry entries" % [unlock_grid.get_child_count(), Unlockables.DEFS.size()])
		var icon_wrong: Array[String] = []
		var icon_greyed: int = 0
		for tile: Node in unlock_grid.get_children():
			var tile_id: String = String(tile.name)
			var icon: TextureRect = tile.get_node_or_null("Icon") as TextureRect
			if icon == null or icon.texture == null:
				failed.append("unlockables: %s has no icon" % tile_id)
				continue
			var icon_size: Vector2 = icon.texture.get_size()
			if icon_size != Vector2(64.0, 64.0):
				icon_wrong.append("%s %s" % [tile_id, str(icon_size)])
			if icon.material is ShaderMaterial and float((icon.material as ShaderMaterial).get_shader_parameter("locked")) > 0.5:
				icon_greyed += 1
		if not icon_wrong.is_empty():
			failed.append("unlockables: icons are not 64x64: %s" % ", ".join(icon_wrong))
		if icon_greyed != unlock_grid.get_child_count():
			failed.append("unlockables: %d of %d tiles are not greyed out" % [unlock_grid.get_child_count() - icon_greyed, unlock_grid.get_child_count()])
		# Registry and shipped art must agree in BOTH directions.
		for unlock_def: Dictionary in Unlockables.DEFS:
			if not ResourceLoader.exists(Unlockables.icon_path(String(unlock_def.id))):
				failed.append("unlockables: no icon file for %s" % String(unlock_def.id))
		# ...and every file on disk must belong to the registry. A rename that
		# leaves the old PNG behind is exactly how a stale icon ships.
		var icon_ids: Array[String] = []
		var icon_dir := DirAccess.open(Unlockables.ICON_DIR)
		if icon_dir == null:
			failed.append("unlockables: cannot open %s" % Unlockables.ICON_DIR)
		else:
			for icon_file: String in icon_dir.get_files():
				if icon_file.ends_with(".png"):
					icon_ids.append(icon_file.trim_suffix(".png"))
		for icon_id: String in icon_ids:
			var known: bool = false
			for unlock_def2: Dictionary in Unlockables.DEFS:
				if String(unlock_def2.id) == icon_id:
					known = true
					break
			if not known:
				failed.append("unlockables: %s.png is not in the registry (stale file?)" % icon_id)
		# The manifest pins what the slicer wrote: a mismatch means the batch was
		# re-sliced (or hand-edited) and the id -> art mapping may have shifted.
		var manifest_text: String = FileAccess.get_file_as_string("res://assets/manifest/unlockables_built.json")
		var manifest: Variant = JSON.parse_string(manifest_text) if manifest_text != "" else null
		if not (manifest is Dictionary):
			failed.append("unlockables: the icon manifest is missing or unreadable")
		else:
			var built: Dictionary = (manifest as Dictionary).get("built", {})
			for unlock_def3: Dictionary in Unlockables.DEFS:
				var man_id: String = String(unlock_def3.id)
				if not built.has(man_id):
					failed.append("unlockables: %s is not in the icon manifest" % man_id)
					continue
				var icon_bytes: PackedByteArray = FileAccess.get_file_as_bytes(Unlockables.icon_path(man_id))
				var ctx := HashingContext.new()
				ctx.start(HashingContext.HASH_SHA256)
				ctx.update(icon_bytes)
				if ctx.finish().hex_encode() != String(built[man_id]):
					failed.append("unlockables: %s.png does not match the manifest -- re-slice and update it" % man_id)
		# Greyed -> colour: flipping the save flag must clear the lock, and the
		# count label must follow it. refresh() because is_unlocked() is cached --
		# the cache is what keeps a per-shot flag read off the disk.
		Storage.set_value(Unlockables.SAVE_KEY, {"neon_skin": true})
		Unlockables.refresh()
		pm.refresh_unlockables()
		var neon_icon: TextureRect = unlock_grid.get_node_or_null("neon_skin/Icon") as TextureRect
		if neon_icon == null or float((neon_icon.material as ShaderMaterial).get_shader_parameter("locked")) > 0.5:
			failed.append("unlockables: an earned icon stayed greyed out")
		var unlock_count_text: String = (pm.get_node("Center/Card/Tabs/UNLOCKABLES/CountLabel") as Label).text
		if not unlock_count_text.begins_with("1 /"):
			failed.append("unlockables: the count label does not follow the save (\"%s\")" % unlock_count_text)
		Storage.set_value(Unlockables.SAVE_KEY, {})
		Unlockables.refresh()
		pm.refresh_unlockables()
		# Layout check: every column must come out the same width, or the icon
		# rows are unevenly spaced (a name wider than TILE_WIDTH does that).
		# Needs the menu actually shown -- a hidden container reports stale sizes.
		pm.show()
		await main.get_tree().process_frame
		var tile_widths: Array[int] = []
		for tile: Node in unlock_grid.get_children():
			tile_widths.append(int((tile as Control).size.x))
		pm.hide()
		if not tile_widths.is_empty() and tile_widths.min() != tile_widths.max():
			failed.append("unlockables: icon columns are ragged (%d..%d px)" % [tile_widths.min(), tile_widths.max()])

	# -- Unlockables: conditions, counting and the effects they gate ------------
	# Everything here sets the flag set explicitly: the suite must never depend on
	# what the player happens to have earned, and the real save is restored at the
	# end of the run. `_set_unlock_flags` also refreshes the in-memory cache --
	# is_unlocked() is cached, because effects read it from per-shot hot paths.
	_set_unlock_flags({})

	# Every condition must name a real counter: a typo'd stat is a row that can
	# never fire, sitting in the tab forever with a hint promising it will.
	var unlock_zero: Dictionary = {}
	for stat_key: String in Unlockables.SUM_KEYS:
		unlock_zero[stat_key] = 0
	for stat_key2: String in Unlockables.MAX_KEYS:
		unlock_zero[stat_key2] = 0
	var seen_unlock_ids: Dictionary = {}
	for unlock_row: Dictionary in Unlockables.DEFS:
		var unlock_id: String = String(unlock_row.id)
		var unlock_need: Dictionary = unlock_row.get("need", {})
		if seen_unlock_ids.has(unlock_id):
			failed.append("unlockables: duplicate id %s" % unlock_id)
		seen_unlock_ids[unlock_id] = true
		if String(unlock_row.get("hint", "")) == "":
			failed.append("unlockables: %s has no hint to show while locked" % unlock_id)
		if unlock_need.is_empty():
			failed.append("unlockables: %s has no condition" % unlock_id)
			continue
		var need_stat: String = String(unlock_need.get("stat", ""))
		var need_at: int = int(unlock_need.get("at", 0))
		if not (Unlockables.SUM_KEYS.has(need_stat) or Unlockables.MAX_KEYS.has(need_stat)):
			failed.append("unlockables: %s reads unknown counter \"%s\"" % [unlock_id, need_stat])
			continue
		if need_at <= 0:
			failed.append("unlockables: %s has a non-positive threshold" % unlock_id)
			continue
		# Threshold boundary: nothing fires at zero, the row fires exactly AT its
		# threshold, and it must not fire one below it (the >= / > slip).
		if Unlockables.qualifies(unlock_id, unlock_zero):
			failed.append("unlockables: %s qualifies at zero progress" % unlock_id)
		var view_at: Dictionary = unlock_zero.duplicate()
		view_at[need_stat] = need_at
		if not Unlockables.qualifies(unlock_id, view_at):
			failed.append("unlockables: %s does not fire at its own threshold" % unlock_id)
		var view_under: Dictionary = unlock_zero.duplicate()
		view_under[need_stat] = need_at - 1
		if Unlockables.qualifies(unlock_id, view_under):
			failed.append("unlockables: %s fires one below its threshold" % unlock_id)

	# evaluate() judges a MERGED view (stored totals + this run) and persists only
	# the flags -- an unlock can land mid-run without the file being written per
	# kill, and judging the same run twice must not report it twice.
	var earned_first: Array[String] = Unlockables.evaluate({"total_kills": 500})
	if not earned_first.has("hollow_point"):
		failed.append("unlockables: 500 lifetime kills did not earn hollow_point")
	if int(Storage.read_all().get("total_kills", 0)) != 0:
		failed.append("unlockables: evaluate() wrote the run's counters (flags only)")
	if not Unlockables.is_unlocked("hollow_point"):
		failed.append("unlockables: an earned flag does not read back")
	if Unlockables.evaluate({"total_kills": 500}).has("hollow_point"):
		failed.append("unlockables: evaluate() reported the same unlock twice")

	# flush_run() is the ONE place a run's counters land in the file, and it has to
	# skip what record_run() already owns or a run is counted twice.
	_set_unlock_flags({})
	Unlockables.flush_run({"total_kills": 500, "best_score": 1200, "best_wave": 4,
			"bosses": 2, "elites": 3, "crits": 7, "charged": 5, "purchases": 4,
			"best_streak": 31, "no_armor_best_wave": 9})
	var flushed: Dictionary = Storage.read_all()
	for own_key: String in ["total_kills", "best_score", "best_wave"]:
		if int(flushed.get(own_key, 0)) != 0:
			failed.append("unlockables: flush_run wrote %s, which record_run owns" % own_key)
	if int(flushed.get("bosses", 0)) != 2 or int(flushed.get("crits", 0)) != 7:
		failed.append("unlockables: flush_run did not add the run's counters")
	if int(flushed.get("best_streak", 0)) != 31 or int(flushed.get("no_armor_best_wave", 0)) != 9:
		failed.append("unlockables: flush_run did not keep the best-of counters")
	# A worse run: sums accumulate, bests stay put.
	Unlockables.flush_run({"bosses": 1, "crits": 1, "best_streak": 5, "no_armor_best_wave": 2})
	flushed = Storage.read_all()
	if int(flushed.get("bosses", 0)) != 3 or int(flushed.get("crits", 0)) != 8:
		failed.append("unlockables: run counters did not accumulate (%d bosses, %d crits)" % [int(flushed.get("bosses", 0)), int(flushed.get("crits", 0))])
	if int(flushed.get("best_streak", 0)) != 31 or int(flushed.get("no_armor_best_wave", 0)) != 9:
		failed.append("unlockables: a worse run lowered a best-of counter")
	_set_unlock_flags({})

	# -- one probe per shipped effect: an unlock whose effect nothing reads is a
	# label that lies, so every row that claims a behaviour gets a check.
	var live_player: Player = main.get_node("World/Player") as Player

	# neon_skin: a recolour read in Player._ready, so the probe spawns a real player.
	_set_unlock_flags({"neon_skin": true})
	var skin_world: Node = main.get_node("World")
	var skin_probe: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	skin_world.add_child(skin_probe)
	var skinned: Color = (skin_probe.get_node("Body") as Polygon2D).color
	skin_probe.free()
	# The probe's PlayerCamera made itself current on _ready -- hand the view back.
	(main.get_node("World/Player/PlayerCamera") as PlayerCamera).make_current()
	if skinned != Player.NEON_SKIN_BODY:
		failed.append("unlockables: neon_skin did not recolour the player (%s)" % str(skinned))

	# crimson_arena: two shader uniforms on arena 1's backdrop, and NOT on the deep
	# arena's (its palette is its own). Probed detached: instantiating an arena in
	# the tree would kick off a navmesh bake.
	_set_unlock_flags({"crimson_arena": true})
	var arena_probe: Node = (load("res://scenes/arena.tscn") as PackedScene).instantiate()
	var arena_mat: ShaderMaterial = (arena_probe.get_node("Backdrop") as CanvasItem).material as ShaderMaterial
	var grid_plain: Variant = arena_mat.get_shader_parameter("grid_color")
	arena_probe.call("_apply_unlockable_backdrop")
	if arena_mat.get_shader_parameter("grid_color") == grid_plain:
		failed.append("unlockables: crimson_arena did not recolour the arena backdrop")
	var deep_probe: Node = (load("res://scenes/arena_deep.tscn") as PackedScene).instantiate()
	var deep_mat: ShaderMaterial = (deep_probe.get_node("Backdrop") as CanvasItem).material as ShaderMaterial
	var deep_grid: Variant = deep_mat.get_shader_parameter("grid_color")
	deep_probe.call("_apply_unlockable_backdrop")
	if deep_mat.get_shader_parameter("grid_color") != deep_grid:
		failed.append("unlockables: crimson_arena recoloured the deep arena as well")
	arena_probe.free()
	deep_probe.free()

	# hollow_point: read when a player round is fired.
	_set_unlock_flags({"hollow_point": true})
	BulletPool.reset()
	var hollow_round: Bullet = BulletPool.fire(Vector2(9999.0, 9999.0), Vector2.RIGHT, 10, 500.0, false)
	var hollow_color: Color = (hollow_round.get_node("Body") as Polygon2D).color
	hollow_round.deactivate()
	if hollow_color != Bullet.HOLLOW_POINT_COLOR:
		failed.append("unlockables: hollow_point did not recolour the rounds")
	BulletPool.reset()

	# gold_crits: the number that pops on a crit.
	_set_unlock_flags({"gold_crits": true})
	DamageNumbers.spawn(Vector2.ZERO, 12, true)
	var gold_index: int = (DamageNumbers._next - 1 + DamageNumbers._labels.size()) % DamageNumbers._labels.size()
	var gold_label: Label = DamageNumbers._labels[gold_index] as Label
	if gold_label.get_theme_color("font_color") != DamageNumbers.GOLD_CRIT_COLOR:
		failed.append("unlockables: gold_crits did not restyle the crit number")

	# rime_horde + rim_palette: read every frame on every enemy, probed on a
	# detached instance -- no tree, no physics, no side effects.
	var enemy_probe: Node = (load("res://scenes/enemy_chaser.tscn") as PackedScene).instantiate()
	_set_unlock_flags({})
	var tint_plain: Color = enemy_probe.call("_base_tint")
	var rim_plain: Color = enemy_probe.call("_rim_color", Color(1.0, 0.5, 0.5))
	_set_unlock_flags({"rime_horde": true})
	if enemy_probe.call("_base_tint") == tint_plain:
		failed.append("unlockables: rime_horde did not tint enemy bodies")
	_set_unlock_flags({"rim_palette": true})
	if enemy_probe.call("_rim_color", Color(1.0, 0.5, 0.5)) == rim_plain:
		failed.append("unlockables: rim_palette did not change the rim colour")
	enemy_probe.free()

	# streak_banners: the streak callout only. Every other banner stays white.
	var live_banner: WaveBanner = main.get_node("UI/WaveBanner") as WaveBanner
	_set_unlock_flags({})
	live_banner.show_banner("STREAK 10")
	var streak_plain: Color = (live_banner.get_node("Center/BannerLabel") as Label).modulate
	_set_unlock_flags({"streak_banners": true})
	live_banner.show_banner("STREAK 10")
	if (live_banner.get_node("Center/BannerLabel") as Label).modulate == streak_plain:
		failed.append("unlockables: streak_banners did not recolour the streak callout")
	live_banner.show_banner("WAVE 3")
	if (live_banner.get_node("Center/BannerLabel") as Label).modulate != streak_plain:
		failed.append("unlockables: streak_banners recoloured a non-streak banner too")
	live_banner.hide()

	# nightmare: a fourth difficulty, and the menu must not offer it before it is
	# earned (nor leave the row one button short afterwards).
	_set_unlock_flags({})
	main._menu.set_difficulty("normal")
	var diff_locked: int = diff_row.get_child_count()
	if WaveManager.difficulty_unlocked("nightmare"):
		failed.append("unlockables: nightmare is playable while locked")
	_set_unlock_flags({"nightmare": true})
	main._menu.set_difficulty("normal")
	if not WaveManager.difficulty_unlocked("nightmare"):
		failed.append("unlockables: nightmare stayed locked after being earned")
	if diff_row.get_child_count() != diff_locked + 1:
		failed.append("unlockables: the difficulty row did not gain a button (%d -> %d)" % [diff_locked, diff_row.get_child_count()])
	if diff_row.get_node_or_null("Nightmare") == null:
		failed.append("unlockables: no NIGHTMARE difficulty button")
	var nm_row: Dictionary = WaveManager.DIFFICULTIES["nightmare"]
	var hard_row: Dictionary = WaveManager.DIFFICULTIES["hard"]
	if float(nm_row["hp"]) <= float(hard_row["hp"]) or float(nm_row["spawn"]) >= float(hard_row["spawn"]):
		failed.append("unlockables: NIGHTMARE is not harder than HARD")

	# mid_boss_waves: a single boss at the halfway mark, and wave BOSS_EVERY itself
	# must keep the pair (the balance probe above depends on it).
	_set_unlock_flags({})
	if wm.is_boss_wave(5):
		failed.append("unlockables: wave 5 is a boss wave before the unlock")
	_set_unlock_flags({"mid_boss_waves": true})
	if not wm.is_boss_wave(5):
		failed.append("unlockables: wave 5 is not a boss wave after the unlock")
	elif wm.boss_count_for_wave(5) != 1:
		failed.append("unlockables: a mid-boss wave fielded %d bosses, expected 1" % wm.boss_count_for_wave(5))
	if not wm.is_boss_wave(10) or wm.boss_count_for_wave(10) != wm.boss_count:
		failed.append("unlockables: mid_boss_waves changed wave %d" % WaveManager.BOSS_EVERY)

	# war_chest: start_game() is the only place credits are seeded, so this probe
	# starts a run for real and puts the game back in the menu afterwards.
	_set_unlock_flags({"war_chest": true})
	main._state = main.State.MENU
	main.start_game()
	if main._credits != main.WAR_CHEST_CREDITS:
		failed.append("unlockables: war_chest seeded %d credits, expected %d" % [main._credits, main.WAR_CHEST_CREDITS])
	wm.stop()
	var live_upgrades: Node = main._upgrades

	# overcharge: the same charged shot, flag on vs off.
	_set_unlock_flags({"overcharge": true})
	BulletPool.reset()
	var charged_before: int = main._charged_shots
	live_player.fire_charged(1.0)
	var over_bullet: Bullet = _last_active_bullet()
	# Read the number NOW: the pool hands the same Bullet instance back out on the
	# next fire, so holding the node and reading it later compares a round to itself.
	var dmg_overcharge: int = over_bullet.damage if over_bullet != null else -1
	if main._charged_shots <= charged_before:
		failed.append("unlockables: a charged shot never reached the run counter")
	BulletPool.reset()
	_set_unlock_flags({})
	live_player.fire_charged(1.0)
	var plain_bullet: Bullet = _last_active_bullet()
	var dmg_plain: int = plain_bullet.damage if plain_bullet != null else 0
	if over_bullet == null or plain_bullet == null:
		failed.append("unlockables: a charged shot never left the pool")
	elif dmg_overcharge <= dmg_plain:
		failed.append("unlockables: overcharge did not raise the charged damage (%d vs %d)" % [dmg_overcharge, dmg_plain])
	BulletPool.reset()

	# black_market: 10% off, probed on a FRESH registry so the number is exact
	# (40 -> 36) instead of tangled up with the economy probes' levels.
	var market_up: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(market_up)
	_set_unlock_flags({})
	var price_full: int = market_up.cost("damage")
	_set_unlock_flags({"black_market": true})
	var price_market: int = market_up.cost("damage")
	if price_market != int(round(float(price_full) * 0.9)):
		failed.append("unlockables: black_market priced damage at %d, expected %d" % [price_market, int(round(float(price_full) * 0.9))])
	market_up.free()

	# fast_shop: keys 1-9, routed through the same signal a button press uses.
	# The shop deals a RANDOM hand now, so find the first row that is actually
	# buyable and press ITS hotkey (and fund Main: it pays, the label does not).
	var shop_probe: CanvasLayer = main.get_node("UI/ShopPanel") as CanvasLayer
	var fj_saved_credits: int = main._credits
	main._credits = 9999
	shop_probe.deal(live_upgrades)
	_set_unlock_flags({})
	shop_probe.show_shop(live_upgrades, 9999, live_player)
	var fj_row: String = ""
	var fj_index: int = -1
	for fj_i in shop_probe._row_ids.size():
		var fj_id: String = String(shop_probe._row_ids[fj_i])
		if (shop_probe._rows[fj_id]["btn"] as Button).disabled:
			continue
		fj_row = fj_id
		fj_index = fj_i
		break
	if fj_row == "":
		failed.append("unlockables: the fast_shop hand offered no buyable row")
	else:
		var fj_level_before: int = live_upgrades.level(fj_row)
		shop_probe.call("_unhandled_key_input", _key_event(KEY_1 + fj_index))
		if live_upgrades.level(fj_row) != fj_level_before:
			failed.append("unlockables: a number key bought something while fast_shop was locked")
		_set_unlock_flags({"fast_shop": true})
		shop_probe.show_shop(live_upgrades, 9999, live_player)
		shop_probe.call("_unhandled_key_input", _key_event(KEY_1 + fj_index))
		if live_upgrades.level(fj_row) != fj_level_before + 1:
			failed.append("unlockables: hotkey %d did not buy the offered row" % (fj_index + 1))
	shop_probe.hide_shop()
	main._credits = fj_saved_credits

	# boss_track_2: a second boss bed, picked at random. Counted over a handful of
	# picks -- both beds must show up (2^-n chance of a false pass).
	if AudioManager.boss_music == null or AudioManager.boss_music_2 == null:
		failed.append("unlockables: a boss bed is missing (assets/sounds/boss_music_2.ogg?)")
	else:
		_set_unlock_flags({"boss_track_2": true})
		var picks: Dictionary = {}
		for pick: int in 24:
			# Stop as soon as both beds have shown up: every extra pick leaves an
			# audio playback parked at exit (the ObjectDB warning at shutdown).
			if picks.size() >= 2:
				break
			AudioManager.stop_music()
			AudioManager.start_boss_music()
			picks[AudioManager._music_player.stream] = true
		if picks.size() < 2:
			failed.append("unlockables: boss_track_2 never picked the second bed")
		AudioManager.stop_music()
	_set_unlock_flags({})

	# -- the five rows that used to be inert: each one is a system now ----------
	# glass_cannon: a menu mutator, absolute stats, and a shop that refuses armor.
	_set_unlock_flags({"glass_cannon": true})
	main._menu.refresh_run_options(false, false)
	if not main._menu._glass_check.visible:
		failed.append("unlockables: the GLASS CANNON toggle is hidden after being earned")
	main._menu._glass_check.set_pressed(true)   # a real toggle: writes the save + tells Main
	if not main._glass_cannon:
		failed.append("unlockables: the GLASS CANNON toggle never reached Main")
	if not bool(Storage.get_value("glass_cannon", false)):
		failed.append("unlockables: the GLASS CANNON toggle never reached the save")
	main._state = main.State.MENU
	main.start_game()
	wm.stop()
	# Measured against the player's PRISTINE stats, not against the constants: a
	# probe that derives its expectation from the value it is testing passes
	# whatever that value becomes. (50 HP / x1.5 is what those constants say.)
	if live_player.max_health >= live_player._base_max_health or live_player.max_health > 60:
		failed.append("unlockables: glass_cannon left max HP at %d (pristine %d)" % [live_player.max_health, live_player._base_max_health])
	if float(live_player.bullet_damage) < float(live_player._base_bullet_damage) * 1.4:
		failed.append("unlockables: glass_cannon damage is %d, barely above the pristine %d" % [live_player.bullet_damage, live_player._base_bullet_damage])
	if main._upgrades.can_buy("armor", 99999):
		failed.append("unlockables: armor is still for sale under glass_cannon")
	main._shop.refresh(main._upgrades, 999)
	if (main._shop._rows["armor"]["btn"] as Button).text != "LOCKED":
		failed.append("unlockables: the blocked armor row does not say LOCKED (\"%s\")" % (main._shop._rows["armor"]["btn"] as Button).text)
	main._menu._glass_check.set_pressed(false)   # back to a normal run for what follows
	if main._upgrades == null or bool(Storage.get_value("glass_cannon", true)):
		failed.append("unlockables: the GLASS CANNON toggle did not turn back off")

	# second_wind: one revive per run, and the run really does end on the next death.
	_set_unlock_flags({"second_wind": true})
	main._state = main.State.MENU
	main.start_game()
	wm.stop()
	var sw_player: Player = main.get_node("World/Player") as Player
	sw_player.health = 1
	sw_player.take_damage(9999)
	if not sw_player.is_alive or sw_player.health <= 0:
		failed.append("unlockables: second_wind did not revive the player")
	if main._state != main.State.PLAYING:
		failed.append("unlockables: the run ended even though second_wind revived the player")
	if not main._second_wind_used:
		failed.append("unlockables: second_wind did not consume its one revive")
	# Kill them again, past the revive's i-frames: this time nothing saves them.
	sw_player._invuln_timer = 0.0
	sw_player.health = 1
	sw_player.take_damage(9999)
	if sw_player.is_alive:
		failed.append("unlockables: second_wind fired twice in one run")
	# _on_wave_game_over awaits a beat and then writes; let it finish so the write
	# lands before the summary restores the real save.
	await main.get_tree().create_timer(1.4).timeout
	if main._state != main.State.GAME_OVER:
		failed.append("unlockables: the second death did not end the run (state %d)" % main._state)
	main._state = main.State.MENU
	wm.stop()

	# boss_rush: the second mutator, read per wave by the wave manager.
	_set_unlock_flags({"boss_rush": true})
	main._menu.refresh_run_options(false, false)
	if not main._menu._boss_check.visible:
		failed.append("unlockables: the BOSS RUSH toggle is hidden after being earned")
	main._menu._boss_check.set_pressed(true)
	if not wm.boss_rush:
		failed.append("unlockables: the BOSS RUSH toggle never reached the wave manager")
	if not wm.is_boss_wave(1):
		failed.append("unlockables: boss_rush did not make wave 1 a boss wave")
	elif int(wm._composition_for_wave(1).get("boss", 0)) < 1:
		failed.append("unlockables: a boss_rush wave has no boss in its composition")
	main._menu._boss_check.set_pressed(false)
	if wm.is_boss_wave(1):
		failed.append("unlockables: boss_rush stayed on after the toggle went off")
	# Both toggles on screen is the widest the menu ever gets: it has to still fit
	# in the window (the card is centred, so an overgrown one clips both ends).
	# 715 of 720 is the floor -- the audio sliders plus the mutator row leave the
	# card at ~708, and trimming further would mean shrinking the controls hint.
	main._menu.refresh_run_options(true, true)
	await main.get_tree().process_frame
	var menu_card: Control = main._menu.get_node_or_null("Center/Card") as Control
	if menu_card == null:
		failed.append("unlockables: the menu card went missing")
	elif menu_card.get_combined_minimum_size().y > 715.0:
		failed.append("unlockables: the menu card wants %.0f px of a 720 px window with the mutators shown" % menu_card.get_combined_minimum_size().y)
	# Height is not the only axis: the weapon picker rides in the mutators row, and a
	# row that outgrows the card is CLIPPED rather than wrapped (the card is centred).
	elif menu_card.get_combined_minimum_size().x > 1000.0:
		failed.append("unlockables: the menu card wants %.0f px wide with the mutators shown -- the widest state must still fit a small window" % menu_card.get_combined_minimum_size().x)
	main._menu.refresh_run_options(false, false)

	# -- Run mutators: fog, elite storm, no shop --------------------------------
	# Each is applied at run start by Main (the menu only owns the preference).
	# One observable per mutator, read through the real apply path.
	_set_unlock_flags({})
	main._state = main.State.MENU
	main._fog = true
	main._elite_storm = true
	main._no_shop = true
	main.start_game()
	wm.stop()
	var mut_player: Player = main.get_node("World/Player") as Player
	if mut_player._torch == null or not is_equal_approx(float(mut_player._torch.get("range")), Player.TORCH_RANGE * 0.5):
		failed.append("mutators: FOG did not halve the torch range (%s)" % str(mut_player._torch.get("range") if mut_player._torch != null else "no torch"))
	if not wm.force_affixes:
		failed.append("mutators: ELITE STORM never reached the wave manager")
	# A spawn through the real path carries an affix under elite storm.
	var mut_container: Node = main.get_node("World/EnemyContainer")
	var mut_before: Array[Node] = mut_container.get_children()
	var mut_telegraph_was: float = wm.spawn_telegraph_time
	wm.spawn_telegraph_time = 0.0
	wm._spawn_enemy("chaser")
	wm.spawn_telegraph_time = mut_telegraph_was
	var mut_enemy: EnemyBase = _new_container_child(mut_container, mut_before) as EnemyBase
	if mut_enemy == null or mut_enemy.affix == "":
		failed.append("mutators: ELITE STORM spawned an enemy with no affix")
	if mut_enemy != null:
		mut_enemy.queue_free()
	# no_shop: a non-healing row is LOCKED, the healing row is not.
	main._shop.refresh(main._upgrades, 999)
	if (main._shop._rows["damage"]["btn"] as Button).text != "LOCKED":
		failed.append("mutators: NO SHOP left the damage row buyable (\"%s\")" % (main._shop._rows["damage"]["btn"] as Button).text)
	if (main._shop._rows["repair"]["btn"] as Button).text == "LOCKED":
		failed.append("mutators: NO SHOP also locked the healing row")
	# Back to a normal run for everything that follows.
	mut_player.set_torch_scale(1.0)
	main._state = main.State.MENU
	main._fog = false
	main._elite_storm = false
	main._no_shop = false
	wm.force_affixes = false
	main._menu.refresh_run_options(false, false)

	# -- Shop depth: reroll re-deals offers and charges exactly once ------------
	main._state = main.State.MENU
	main.start_game()
	wm.stop()
	main._credits = 500
	main._shop.refresh(main._upgrades, main._credits, main.get_node("World/Player"))
	var reroll_before: Array[String] = main._shop._offered.duplicate()
	var credits_before_reroll: int = main._credits
	main._on_shop_reroll()
	if main._credits != credits_before_reroll - main._shop.REROLL_COST:
		failed.append("shop: reroll charged %d, expected exactly %d once" % [credits_before_reroll - main._credits, main._shop.REROLL_COST])
	if main._shop._offered == reroll_before:
		failed.append("shop: reroll did not change the offered rows")
	if main._shop._row_ids != main._shop._offered:
		failed.append("shop: hotkey order does not follow the rerolled offers")
	# Repair: heals to full below full, refuses at full, then is maxed.
	var rep_player: Player = main.get_node("World/Player") as Player
	rep_player.health = 1
	var rep_hp_before: int = rep_player.health
	var rep_res: Dictionary = main._upgrades.buy("repair", 999999, rep_player)
	if not bool(rep_res.ok) or rep_player.health != rep_player.max_health:
		failed.append("shop: repair did not heal to full (%d -> %d of %d)" % [rep_hp_before, rep_player.health, rep_player.max_health])
	if main._upgrades.level("repair") != 1 or main._upgrades.can_buy("repair", 999999):
		failed.append("shop: repair did not disappear after one purchase")
	var rep_up: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(rep_up)
	rep_player.health = rep_player.max_health
	if bool(rep_up.buy("repair", 99999, rep_player).ok):
		failed.append("shop: repair was sold while already at full health")
	rep_up.queue_free()
	main._state = main.State.MENU

	# vault_arena: arena 3 exists, stays shut until earned, then swaps in with its
	# own baked navmesh (the new cover has to be pathable, or enemies beeline).
	if main.ARENA_SCENES.size() < 3:
		failed.append("unlockables: no third arena registered in ARENA_SCENES")
	else:
		var vault_scene: String = main.ARENA_SCENES[2]
		if not ResourceLoader.exists(vault_scene):
			failed.append("unlockables: the arena 3 scene is missing (%s)" % vault_scene)
		_set_unlock_flags({})
		var arena_was: int = main._arena_index
		main._switch_arena(2, false)
		if main._arena_index != arena_was:
			failed.append("unlockables: the vault opened while still locked")
		_set_unlock_flags({"vault_arena": true})
		main._switch_arena(2, false)
		if main._arena_index != 2:
			failed.append("unlockables: the vault did not open after being earned")
		var vault_world: Node = main.get_node("World")
		if vault_world.get_node_or_null("VaultGate") == null:
			failed.append("unlockables: arena 3 is not the vault scene")
		var vault_nav: NavigationRegion2D = vault_world.get_node_or_null("NavRegion") as NavigationRegion2D
		if vault_nav == null or vault_nav.navigation_polygon == null or vault_nav.navigation_polygon.get_polygon_count() == 0:
			failed.append("unlockables: the vault has no baked navmesh")

	# run_stats: the third tab, hidden until earned, filled from Main + the save.
	var stats_tab: TabContainer = pm_tabs
	_set_unlock_flags({})
	pm.refresh_stats({})
	if not stats_tab.is_tab_hidden(pm._stats_page.get_index()):
		failed.append("unlockables: the STATS tab is in the strip while locked")
	var size_without_stats: Vector2 = stats_tab.get_combined_minimum_size()
	_set_unlock_flags({"run_stats": true})
	pm.refresh_stats({"wave": 7, "kills": 30, "score": 900, "credits": 120, "seconds": 60.0, "damage": 6000})
	if pm._stats_page.get_parent() != stats_tab or stats_tab.is_tab_hidden(pm._stats_page.get_index()):
		failed.append("unlockables: the STATS tab never appeared")
	else:
		if (pm._stats_values["dps"] as Label).text != "100.0":
			failed.append("unlockables: DPS reads %s for 6000 damage over 60s" % (pm._stats_values["dps"] as Label).text)
		if (pm._stats_values["credits_per_min"] as Label).text != "120":
			failed.append("unlockables: CREDITS / MIN reads %s for 120 credits in a minute" % (pm._stats_values["credits_per_min"] as Label).text)
		if (pm._stats_values["wave"] as Label).text != "7":
			failed.append("unlockables: the STATS tab does not show this run's wave")
		if not size_without_stats.is_equal_approx(stats_tab.get_combined_minimum_size()):
			failed.append("unlockables: the pause card resizes when the STATS tab appears")
		Storage.set_value("best_wave_hard", 33)
		pm.refresh_stats({})
		if (pm._stats_values["difficulty_hard"] as Label).text != "33":
			failed.append("unlockables: BEST WAVE BY DIFFICULTY does not read best_wave_<id>")
		if (pm._stats_values["difficulty_nightmare"] as Label).get_parent().visible and not WaveManager.difficulty_unlocked("nightmare"):
			failed.append("unlockables: the STATS tab names a difficulty the menu still hides")
	_set_unlock_flags({})
	pm.refresh_stats({})
	if not stats_tab.is_tab_hidden(pm._stats_page.get_index()):
		failed.append("unlockables: the STATS tab stayed after the unlockable went away")

	# -- Meta-progression: salvage banks, wipes with RESET, perks persist -------
	# Banking is the one path that turns a run's leftovers into meta progress.
	# It must write its OWN key: a bank that wrote total_kills would double-count
	# against record_run() (the same invariant the flush_run probe polices).
	Storage.set_value("total_kills", 111)
	main._credits = 200
	main._bank_salvage()
	if Storage.salvage() != 50:
		failed.append("salvage: a 200-credit run banked %d, expected 50" % Storage.salvage())
	if int(Storage.get_value("total_kills", 0)) != 111:
		failed.append("salvage: banking wrote total_kills, which record_run owns")
	# RESET SAVE is progress, not a preference: it takes the salvage with it.
	Storage.set_value("salvage", 999)
	Storage.reset_progress()
	if Storage.salvage() != 0:
		failed.append("salvage: RESET SAVE kept the salvage balance (%d)" % Storage.salvage())
	# A bought perk has to survive a cache refresh and reach the player.
	Perks.refresh()
	Storage.set_value(Perks.SAVE_KEY, {})
	Storage.set_value("salvage", 500)
	if not Perks.buy("vigor"):
		failed.append("perks: could not buy VIGOR with 500 salvage")
	if Perks.level("vigor") != 1:
		failed.append("perks: VIGOR level did not read back (%d)" % Perks.level("vigor"))
	if Storage.salvage() >= 500:
		failed.append("perks: buying VIGOR did not deduct salvage")
	Perks.refresh()   # write -> refresh -> read
	if Perks.level("vigor") != 1:
		failed.append("perks: a bought perk did not survive a refresh() round-trip")
	var perk_player: Player = main.get_node("World/Player") as Player
	var perk_hp_base: int = perk_player._base_max_health
	Perks.apply_to_player(perk_player)
	if perk_player.max_health != perk_hp_base + Perks.VIGOR_HP:
		failed.append("perks: VIGOR did not raise max HP (%d vs base %d)" % [perk_player.max_health, perk_hp_base])
	perk_player.max_health = perk_hp_base
	perk_player.health = perk_hp_base
	# The PERKS tab renders a row per registry entry, and its button buys through
	# the same Perks.buy the probe just called (no second purchase path).
	pm.refresh_perks()
	if pm._perk_rows.size() != Perks.DEFS.size():
		failed.append("perks: the PERKS tab has %d rows for %d registry entries" % [pm._perk_rows.size(), Perks.DEFS.size()])
	Storage.set_value(Perks.SAVE_KEY, {})
	Storage.set_value("salvage", 100)
	Perks.refresh()
	pm.refresh_perks()
	var perk_btn: Button = pm._perk_rows["vigor"]["btn"] as Button
	perk_btn.pressed.emit()
	if Perks.level("vigor") != 1:
		failed.append("perks: the PERKS tab button did not buy VIGOR")
	Storage.set_value(Perks.SAVE_KEY, {})
	Storage.set_value("salvage", 0)
	Perks.refresh()

	# -- Juice: crit hit-stop, boss trauma, number colour, hit flash -----------
	# A crit's slow-motion is guarded: two crits in one tick must not stack a
	# second dip, and the restore must run even with the tree paused.
	Engine.time_scale = 1.0
	main._crit_stop_active = false
	var crit_count_before: int = main._crit_stop_count
	main._on_crit_landed()
	main._on_crit_landed()
	if main._crit_stop_count != crit_count_before + 1:
		failed.append("juice: two crits produced %d time-scale dips, expected 1" % (main._crit_stop_count - crit_count_before))
	if Engine.time_scale >= 1.0:
		failed.append("juice: a crit did not dip Engine.time_scale (%.2f)" % Engine.time_scale)
	await main.get_tree().create_timer(main.HIT_STOP_TIME + 0.2, true, false, true).timeout
	if not is_equal_approx(Engine.time_scale, 1.0):
		failed.append("juice: Engine.time_scale was not restored after a crit (%.2f)" % Engine.time_scale)
	if main._crit_stop_active:
		failed.append("juice: the crit hit-stop stayed active after the dip")
	# A boss death raises trauma more than a chaser kill.
	var juice_cam: PlayerCamera = main._camera
	var trauma_before: float = juice_cam._trauma
	var juice_boss: EnemyBase = load("res://scenes/enemy_boss.tscn").instantiate() as EnemyBase
	wm._enemy_container.add_child(juice_boss)
	main._on_enemy_killed(juice_boss)
	if juice_cam._trauma <= trauma_before:
		failed.append("juice: a boss death did not raise camera trauma")
	# A damage number carries the colour it was spawned with.
	DamageNumbers.spawn(Vector2.ZERO, 42, false, Color(0.2, 0.8, 0.3))
	var dn_label: Label = null
	if not DamageNumbers._labels.is_empty():
		var dn_index: int = (DamageNumbers._next - 1 + DamageNumbers._labels.size()) % DamageNumbers._labels.size()
		dn_label = DamageNumbers._labels[dn_index] as Label
	if dn_label == null or dn_label.get_theme_color("font_color") != Color(0.2, 0.8, 0.3):
		failed.append("juice: a damage number did not carry the hit colour")
	# A hit flashes the screen edge, then fades off.
	main._hud.flash_hit()
	if not main._hud._hit_flash.visible or main._hud._hit_flash.modulate.a <= 0.0:
		failed.append("juice: the hit flash never showed")
	main._hud._process(2.0)
	if main._hud._hit_flash.visible:
		failed.append("juice: the hit flash stayed on after its timer")
	Engine.time_scale = 1.0

	# -- End-of-run summary: the card renders Main._pause_stats() --------------
	# One source of numbers, two renderers (the STATS tab and this card), so the
	# probe drives the real game-over path and compares label text to the dict.
	main._state = main.State.PLAYING
	main._kills = 7
	main._score = 1234
	main._credits = 210
	main._run_time = 42.0
	BulletPool.damage_dealt = 4200
	main._waves.current_wave = 5
	var go: GameOverScreen = main._game_over
	await main._on_wave_game_over()
	var jr: Dictionary = main._pause_stats()
	if (go._summary_values["kills"] as Label).text != str(int(jr["kills"])):
		failed.append("game over: KILLS reads %s, expected %d" % [(go._summary_values["kills"] as Label).text, int(jr["kills"])])
	if (go._summary_values["credits"] as Label).text != str(int(jr["credits"])):
		failed.append("game over: CREDITS reads %s, expected %d" % [(go._summary_values["credits"] as Label).text, int(jr["credits"])])
	var go_dps: String = "%.1f" % (float(jr["damage"]) / maxf(float(jr["seconds"]), 1.0))
	if (go._summary_values["dps"] as Label).text != go_dps:
		failed.append("game over: DPS reads %s, expected %s" % [(go._summary_values["dps"] as Label).text, go_dps])
	if (go._summary_values["time"] as Label).text != go._format_time(float(jr["seconds"])):
		failed.append("game over: TIME reads %s, expected %s" % [(go._summary_values["time"] as Label).text, go._format_time(float(jr["seconds"]))])
	var go_card: Control = go.get_node("Center/Card") as Control
	if go_card.get_combined_minimum_size().y > 715.0:
		failed.append("game over: the card wants %.0f px of a 720 px window" % go_card.get_combined_minimum_size().y)
	main._state = main.State.MENU

	# -- Shipping: the poster strap carries the version -------------------------
	if not RetroMenuArt.strap_text().contains(RetroMenuArt.VERSION):
		failed.append("ship: the poster strap does not name the version (\"%s\")" % RetroMenuArt.strap_text())

	# -- Lit lighting (addons/lit) ---------------------------------------------
	# The addon lights nothing by itself: a light with no receiver material is just a
	# node in a group, and a receiver material with no light is a flat ambient multiply.
	# These probes pin the wiring that makes the pair work, plus the two traps that made
	# it fail silently: occluders coplanar with the wall they mirror, and the addon's
	# default cone shadow algorithm.
	var lit_arena: Node = main.get_node("World")
	var lit_player: Node = main.get_node("World/Player")
	if not LitLighting.available():
		failed.append("lighting: the Lit shaders are missing (addons/lit not installed)")
	if main.get_node_or_null("/root/LitManager") == null:
		failed.append("lighting: no LitManager autoload (the manager packs the lights every frame)")
	var lit_darkness: Node = lit_arena.get_node_or_null(LitLighting.DARKNESS_NODE)
	if not lit_darkness is LitCanvasModulate:
		failed.append("lighting: the arena has no LitCanvasModulate, so the room is not dark")
	var lit_torch: Node = null
	for child in lit_player.get_children():
		if child is LitPointLight2D:
			lit_torch = child
	if lit_torch == null:
		failed.append("lighting: the player carries no LitPointLight2D (no light in the room)")
	else:
		if not lit_torch.shadow_enabled:
			failed.append("lighting: the torch does not cast shadows")
		var lit_range: float = float(lit_torch.get("range"))
		if absf(lit_range - Player.TORCH_RANGE) > 0.01:
			failed.append("lighting: the torch reaches %.0f px, not Player.TORCH_RANGE %.0f" % [lit_range, Player.TORCH_RANGE])
		var lit_energy: float = float(lit_torch.energy)
		if absf(lit_energy - Player.TORCH_ENERGY) > 0.001:
			failed.append("lighting: the torch burns at %.2f, not Player.TORCH_ENERGY %.2f" % [lit_energy, Player.TORCH_ENERGY])
		if not lit_torch.color.is_equal_approx(Player.TORCH_COLOR):
			failed.append("lighting: the torch is %s, not the neon Player.TORCH_COLOR %s" % [str(lit_torch.color), str(Player.TORCH_COLOR)])
		if lit_torch.color.b <= lit_torch.color.r or lit_torch.color.s < 0.5:
			failed.append("lighting: the torch is %s -- not a saturated cool light, so the room is not neon-lit" % str(lit_torch.color))
		if float(lit_torch.get("height")) <= 16.0:
			failed.append("lighting: the torch sits at floor height, so it only grazes distant surfaces")
	# The GROUND receives light: the Floor is a receiver and sits ABOVE the opaque
	# backdrop, or the torch and its shadows never touch the floor. The backdrop
	# itself keeps its own grid shader (a receiver material would replace it).
	var lit_floor := lit_arena.get_node_or_null("Floor") as CanvasItem
	var lit_backdrop := lit_arena.get_node_or_null("Backdrop") as CanvasItem
	if lit_floor == null or lit_floor.material != LitLighting.receiver_material():
		failed.append("lighting: the arena floor is not a lit receiver (the torch never lands on the ground)")
	elif lit_backdrop != null and lit_floor.z_index <= lit_backdrop.z_index:
		failed.append("lighting: the lit floor is under the opaque backdrop, so it is never seen")
	if lit_backdrop != null and lit_backdrop.material == LitLighting.receiver_material():
		failed.append("lighting: the backdrop was turned into a receiver (its grid shader is gone)")
	# Every enemy carries its own halo, in its own colour: that is what makes a room read
	# as a constellation of neon glows instead of one torch in the dark.
	var lit_enemy: Node = load("res://scenes/enemy_chaser.tscn").instantiate()
	lit_arena.add_child(lit_enemy)
	var lit_glow: Node = null
	for lit_e_child: Node in lit_enemy.get_children():
		if lit_e_child is LitPointLight2D:
			lit_glow = lit_e_child
	if lit_glow == null:
		failed.append("lighting: enemies carry no halo light of their own")
	else:
		var lit_want: Color = (lit_enemy.get("_base_color") as Color).lightened(EnemyBase.GLOW_LIFT)
		if not lit_glow.color.is_equal_approx(lit_want):
			failed.append("lighting: the enemy halo is %s, not the body colour lifted (%s)" % [str(lit_glow.color), str(lit_want)])
		if lit_glow.get("shadow_enabled"):
			failed.append("lighting: enemy halos cast shadows (one shadow light per enemy is the frame budget)")
	lit_enemy.free()
	# One occluder per wall and obstacle, inset from the rectangle it mirrors: an occluder
	# the size of the wall's visible face shadows that face and the room reads as unlit.
	var lit_occluders: int = 0
	var lit_coplanar: bool = false
	for lit_body: Node in lit_arena.get_children():
		var lit_occ := lit_body.get_node_or_null("LitOccluder") as LightOccluder2D
		if lit_occ == null:
			continue
		lit_occluders += 1
		for lit_child: Node in lit_body.get_children():
			var lit_collider := lit_child as CollisionShape2D
			if lit_collider == null or not (lit_collider.shape is RectangleShape2D):
				continue
			var lit_half: Vector2 = (lit_collider.shape as RectangleShape2D).size * 0.5
			for lit_pt: Vector2 in (lit_occ.occluder as OccluderPolygon2D).polygon:
				if absf(lit_pt.x) >= lit_half.x or absf(lit_pt.y) >= lit_half.y:
					lit_coplanar = true
			break
	if lit_occluders < 4:
		failed.append("lighting: the arena has %d occluders, so nothing casts a shadow" % lit_occluders)
	if lit_coplanar:
		failed.append("lighting: an occluder covers its own wall's visible face (the wall self-shadows)")
	# The walls must both block light and show it: an occluder with no receiver beside it
	# means the room is pitch dark next to solid geometry.
	var lit_receivers: int = 0
	for lit_body2: Node in lit_arena.get_children():
		for lit_vis: Node in lit_body2.get_children():
			var lit_item := lit_vis as CanvasItem
			if lit_item != null and lit_item.material is ShaderMaterial \
					and LitShaderLibrary.flags_of((lit_item.material as ShaderMaterial).shader) >= 0:
				lit_receivers += 1
	if lit_receivers < lit_occluders:
		failed.append("lighting: %d lit receivers for %d occluders (geometry blocks light but cannot show it)" % [lit_receivers, lit_occluders])
	# Glow stays unlit: bullets and hit effects carry additive materials on purpose and
	# must compose on top of the lighting instead of being shaded by it.
	var lit_additive := ColorRect.new()
	var lit_mat := CanvasItemMaterial.new()
	lit_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	lit_additive.material = lit_mat
	if LitLighting.make_receiver(lit_additive):
		failed.append("lighting: an additive material was converted to a receiver (the glow would be shaded away)")
	lit_additive.free()

	# -- Arena 4 (nexus): ungated, swaps in, every spawn reaches the player ------
	# The fourth arena is a list entry + a baked scene; the coverage probe below
	# walks ARENA_SCENES, so a missing registration is caught here, not by editing
	# that loop.
	if main.ARENA_SCENES.size() < 7:
		failed.append("arena coverage: expected 7 arenas in ARENA_SCENES, found %d" % main.ARENA_SCENES.size())
	else:
		var nexus_scene: String = main.ARENA_SCENES[3]
		if not ResourceLoader.exists(nexus_scene):
			failed.append("arena coverage: the fourth arena scene is missing (%s)" % nexus_scene)
		_set_unlock_flags({})
		main._switch_arena(3, false)
		if main._arena_index != 3:
			failed.append("arena coverage: arena 4 did not swap in (index %d)" % main._arena_index)
		var nexus_world: Node2D = main.get_node("World") as Node2D
		if nexus_world.get_node_or_null("NexusCore") == null:
			failed.append("arena coverage: arena 4 is not the nexus scene")
		var nexus_map: RID = nexus_world.get_world_2d().navigation_map
		for nexus_settle: int in 12:
			await main.get_tree().physics_frame
		NavigationServer2D.map_force_update(nexus_map)
		var nexus_spawns: Array[Node] = main.get_tree().get_nodes_in_group("spawn_points")
		if nexus_spawns.size() < 4:
			failed.append("arena coverage: arena 4 has %d spawn points, expected at least 4" % nexus_spawns.size())
		var nexus_space: PhysicsDirectSpaceState2D = nexus_world.get_world_2d().direct_space_state
		var nexus_shape := CircleShape2D.new()
		nexus_shape.radius = 20.0
		var nexus_player: Node2D = main.get_node("World/Player") as Node2D
		for nexus_sp: Node in nexus_spawns:
			var nexus_from: Vector2 = (nexus_sp as Node2D).global_position
			var nexus_q := PhysicsShapeQueryParameters2D.new()
			nexus_q.shape = nexus_shape
			nexus_q.collision_mask = 8
			nexus_q.transform = Transform2D(0.0, nexus_from)
			if not nexus_space.intersect_shape(nexus_q, 1).is_empty():
				failed.append("arena coverage: arena 4 spawn %s sits in wall/obstacle geometry" % nexus_sp.name)
			var nexus_path: PackedVector2Array = NavigationServer2D.map_get_path(
					nexus_map, nexus_from, nexus_player.global_position, true)
			if nexus_path.size() < 2 or nexus_path[0].distance_to(nexus_from) > 30.0:
				failed.append("arena coverage: arena 4 spawn %s cannot reach the player" % nexus_sp.name)
		# Arenas 5-7 (citadel / rift / foundry): ungated list entries with baked
		# navmeshes, walkable spawns and paths to the player. Generic, so a future
		# arena only has to be registered + baked to be covered here.
		for extra_index: int in range(4, main.ARENA_SCENES.size()):
			var extra_scene: String = main.ARENA_SCENES[extra_index]
			if not ResourceLoader.exists(extra_scene):
				failed.append("arena coverage: arena %d scene is missing (%s)" % [extra_index + 1, extra_scene])
				continue
			_set_unlock_flags({})
			main._switch_arena(extra_index, false)
			if main._arena_index != extra_index:
				failed.append("arena coverage: arena %d did not swap in (index %d)" % [extra_index + 1, main._arena_index])
				continue
			var extra_world: Node2D = main.get_node("World") as Node2D
			var extra_nav := extra_world.get_node_or_null("NavRegion") as NavigationRegion2D
			if extra_nav == null or extra_nav.navigation_polygon == null \
					or extra_nav.navigation_polygon.get_polygon_count() == 0:
				failed.append("arena coverage: arena %d has no baked navmesh" % (extra_index + 1))
			var extra_map: RID = extra_world.get_world_2d().navigation_map
			for extra_settle: int in 12:
				await main.get_tree().physics_frame
			NavigationServer2D.map_force_update(extra_map)
			var extra_spawns: Array[Node] = main.get_tree().get_nodes_in_group("spawn_points")
			if extra_spawns.size() < 4:
				failed.append("arena coverage: arena %d has %d spawn points, expected at least 4" % [extra_index + 1, extra_spawns.size()])
			var extra_space: PhysicsDirectSpaceState2D = extra_world.get_world_2d().direct_space_state
			var extra_shape := CircleShape2D.new()
			extra_shape.radius = 20.0
			var extra_player: Node2D = main.get_node("World/Player") as Node2D
			for extra_sp: Node in extra_spawns:
				var extra_from: Vector2 = (extra_sp as Node2D).global_position
				var extra_q := PhysicsShapeQueryParameters2D.new()
				extra_q.shape = extra_shape
				extra_q.collision_mask = 8
				extra_q.transform = Transform2D(0.0, extra_from)
				if not extra_space.intersect_shape(extra_q, 1).is_empty():
					failed.append("arena coverage: arena %d spawn %s sits in wall/obstacle geometry" % [extra_index + 1, extra_sp.name])
				var extra_path: PackedVector2Array = NavigationServer2D.map_get_path(
						extra_map, extra_from, extra_player.global_position, true)
				if extra_path.size() < 2 or extra_path[0].distance_to(extra_from) > 30.0:
					failed.append("arena coverage: arena %d spawn %s cannot reach the player" % [extra_index + 1, extra_sp.name])
		# Rotation is deterministic and wraps through all seven arenas.
		var last_index: int = main.ARENA_SCENES.size() - 1
		main._advance_arena()
		if main._arena_index != 0:
			failed.append("arena coverage: rotation did not wrap from arena 7 to arena 1")

	# -- Expanded roster: five enemies and three bosses are registered ----------
	for roster_path: String in [
			"res://scenes/enemy_sniper.tscn", "res://scenes/enemy_pulsar.tscn",
			"res://scenes/enemy_medic.tscn", "res://scenes/enemy_skirmisher.tscn",
			"res://scenes/enemy_rammer.tscn", "res://scenes/enemy_boss_tempest.tscn",
			"res://scenes/enemy_boss_hive.tscn", "res://scenes/enemy_boss_juggernaut.tscn"]:
		if not ResourceLoader.exists(roster_path):
			failed.append("roster: missing %s" % roster_path)
	var tempest: Node = load("res://scenes/enemy_boss_tempest.tscn").instantiate()
	tempest.position = Vector2(300, 0)
	wm._enemy_container.add_child(tempest)
	await main.get_tree().physics_frame
	tempest._charging = true
	tempest._charge_dir = Vector2.LEFT
	var tempest_charge: Vector2 = tempest._desired_velocity()
	if not tempest_charge.is_equal_approx(Vector2.LEFT * tempest.charge_speed):
		failed.append("tempest: phase-three charge state was ignored by movement")
	tempest.queue_free()

	# -- The retro pass covers EVERY arena, not just the one it was designed on --
	# arena.gd adds the art layer and tunes the backdrop at runtime, so an arena added or
	# rebuilt later silently loses the redesign. Instantiate each scene and check the pass
	# actually lands on it (this is how "the second arena" stays redesigned).
	var retro_scenes: Array = (main.get_script() as GDScript).get_script_constant_map()["ARENA_SCENES"]
	for retro_path: String in retro_scenes:
		var retro_arena: Node = (load(retro_path) as PackedScene).instantiate()
		main.add_child(retro_arena)
		await main.get_tree().process_frame
		if retro_arena.get_node_or_null("RetroArenaArt") == null:
			failed.append("art: %s has no RetroArenaArt (the retro pass skipped it)" % retro_path.get_file())
		var retro_backdrop := retro_arena.get_node_or_null("Backdrop") as ColorRect
		if retro_backdrop == null or not (retro_backdrop.material is ShaderMaterial):
			failed.append("art: %s has no backdrop shader to tune" % retro_path.get_file())
		else:
			var retro_mat := retro_backdrop.material as ShaderMaterial
			if float(retro_mat.get_shader_parameter("grid_alpha")) <= 0.0:
				failed.append("art: %s backdrop was not tuned (grid_alpha %s)"
						% [retro_path.get_file(), str(retro_mat.get_shader_parameter("grid_alpha"))])
		retro_arena.free()

	# -- Weapons: archetypes are BASE loadouts, not compounding modifiers --------
	# A weapon writes the pristine SCENE stats and the shop then mutates the live
	# values on top. The failure this guards is silent: a weapon scaled off its own
	# output doubles on every run start (or every click of the picker), and the
	# boss-TTK measurement drifts with it without anything erroring.
	var wp: Player = load("res://scenes/player.tscn").instantiate() as Player
	main.add_child(wp)
	# The reference numbers come from a SECOND, untouched instance -- never from the
	# player under test (a probe must not derive its expectation from the value it is
	# about to modify).
	var wp_ref: Player = load("res://scenes/player.tscn").instantiate() as Player
	main.add_child(wp_ref)
	await main.get_tree().process_frame
	var wp_pristine: Dictionary = _player_stat_snapshot(wp_ref)
	# Registry hygiene: unique ids, every key present, and no row that fires nothing.
	var wp_seen: Array[String] = []
	for wp_row: Dictionary in Weapons.DEFS:
		var wp_id: String = String(wp_row.get("id", ""))
		if wp_id == "" or wp_seen.has(wp_id):
			failed.append("weapons: registry id '%s' is empty or duplicated" % wp_id)
		wp_seen.append(wp_id)
		for wp_key: String in ["name", "hint", "fire_rate", "damage", "speed", "recoil",
				"pellets", "spread_deg", "pierce", "lifetime", "scale", "knockback"]:
			if not wp_row.has(wp_key):
				failed.append("weapons: row '%s' has no '%s'" % [wp_id, wp_key])
		if int(wp_row.get("pellets", 0)) < 1 or float(wp_row.get("lifetime", 0.0)) <= 0.0 \
				or float(wp_row.get("scale", 0.0)) <= 0.0:
			failed.append("weapons: row '%s' would fire nothing (pellets/lifetime/scale)" % wp_id)
	if Weapons.ids().size() != Weapons.DEFS.size():
		failed.append("weapons: ids() and DEFS disagree (%d vs %d)" % [Weapons.ids().size(), Weapons.DEFS.size()])
	if Weapons.ids().size() < 7:
		failed.append("weapons: expected the default plus six archetypes, found %d" % Weapons.ids().size())
	# A save edited by hand, or a row deleted in a later version, must fall back to the
	# default gun -- never to an unarmed player.
	if String(Weapons.resolve("not_a_weapon").id) != Weapons.DEFAULT_ID:
		failed.append("weapons: an unknown id does not fall back to the default row")
	# The DEFAULT row is a NO-OP. This is the assertion that keeps the boss-TTK probe's
	# measured dps honest, so it is checked against real scene stats, not assumed.
	wp.apply_weapon(Weapons.DEFAULT_ID)
	if _player_stat_snapshot(wp) != wp_pristine:
		failed.append("weapons: the default row is not a no-op (it moved the scene stats)")
	# Every archetype moves exactly what its row names.
	for wt_id: String in Weapons.ids():
		var wt_row: Dictionary = Weapons.definition(wt_id)
		wp.apply_weapon(wt_id)
		if wp.bullets_per_shot != int(wt_row.pellets):
			failed.append("weapons: '%s' fires %d pellets, not the row's %d"
					% [wt_id, wp.bullets_per_shot, int(wt_row.pellets)])
		if absf(wp.bullet_spread_deg - float(wt_row.spread_deg)) > 0.001:
			failed.append("weapons: '%s' spread is %.1f deg, not the row's %.1f"
					% [wt_id, wp.bullet_spread_deg, float(wt_row.spread_deg)])
		if wp.pierce_count != int(wt_row.pierce):
			failed.append("weapons: '%s' base pierce is %d, not the row's %d"
					% [wt_id, wp.pierce_count, int(wt_row.pierce)])
		var wt_want_damage: int = maxi(1, int(round(float(wp_pristine["bullet_damage"]) * float(wt_row.damage))))
		if wp.bullet_damage != wt_want_damage:
			failed.append("weapons: '%s' hits for %d, not the row's %d (scene %d)"
					% [wt_id, wp.bullet_damage, wt_want_damage, int(wp_pristine["bullet_damage"])])
		if absf(wp.fire_rate - float(wp_pristine["fire_rate"]) * float(wt_row.fire_rate)) > 0.0001:
			failed.append("weapons: '%s' interval is %.3f, not scene x row" % [wt_id, wp.fire_rate])
		if wt_id != Weapons.DEFAULT_ID and _player_stat_snapshot(wp) == wp_pristine:
			failed.append("weapons: '%s' changes nothing (a gun nobody can feel)" % wt_id)
	# Idempotent, the way a run start repeated on every scene load demands: applying
	# the same weapon twice, and switching guns and back, must land on the same stats.
	wp.apply_weapon("lance")
	var wp_lance: Dictionary = _player_stat_snapshot(wp)
	wp.apply_weapon("lance")
	if _player_stat_snapshot(wp) != wp_lance:
		failed.append("weapons: applying the same weapon twice compounds its stats")
	wp.apply_weapon("needler")
	wp.apply_weapon(Weapons.DEFAULT_ID)
	if _player_stat_snapshot(wp) != wp_pristine:
		failed.append("weapons: switching weapons and back does not restore the scene stats")
	# The weapon's range, size, pierce and push have to reach the FIRED ROUND, not just
	# sit on the player -- the same rule the shop's pierce probe follows.
	wp.apply_weapon("lance")
	wp._aim_pivot.rotation = 0.0
	var wp_lance_row: Dictionary = Weapons.definition("lance")
	var wp_before_ids: Array[int] = []
	for wp_b: Bullet in BulletPool._all:
		if wp_b.is_active:
			wp_before_ids.append(wp_b.get_instance_id())
	wp._fire_bullet()
	var wp_round: Bullet = null
	for wp_b2: Bullet in BulletPool._all:
		if wp_b2.is_active and not wp_before_ids.has(wp_b2.get_instance_id()):
			wp_round = wp_b2
	if wp_round == null:
		failed.append("weapons: the lance probe fired nothing")
	else:
		if wp_round.pierce_left != int(wp_lance_row.pierce):
			failed.append("weapons: the lance round holds %d pierces, not the row's %d"
					% [wp_round.pierce_left, int(wp_lance_row.pierce)])
		if absf(wp_round.lifetime - float(wp_lance_row.lifetime)) > 0.001:
			failed.append("weapons: the round flies %.2f s, not the row's %.2f"
					% [wp_round.lifetime, float(wp_lance_row.lifetime)])
		if absf(wp_round.scale.x - float(wp_lance_row.scale)) > 0.01:
			failed.append("weapons: the round is %.2fx, not the row's %.2fx"
					% [wp_round.scale.x, float(wp_lance_row.scale)])
		if absf(wp_round.knockback_force - BulletPool.base_knockback * float(wp_lance_row.knockback)) > 0.01:
			failed.append("weapons: the round pushes %.0f, not the row's push"
					% wp_round.knockback_force)
	# ...and the SHARED pool must not carry one gun's range into the enemy's rounds:
	# a parked round is the next shooter's round, so the park owns the reset.
	for wp_b3: Bullet in BulletPool._all:
		wp_b3.deactivate()
	var wp_hostile: Bullet = BulletPool.fire(Vector2.ZERO, Vector2.RIGHT, 5, 300.0, true)
	if absf(wp_hostile.lifetime - Bullet.BASE_LIFETIME) > 0.001 or not wp_hostile.scale.is_equal_approx(Vector2.ONE):
		failed.append("weapons: a hostile round inherited the player's range/size (lifetime %.2f, scale %s)"
				% [wp_hostile.lifetime, str(wp_hostile.scale)])
	BulletPool.reset()
	# The shop still stacks on top of the weapon, and the weapon's own base is what it
	# stacks on -- buying "damage" after picking a gun must not be cancelled by the gun.
	wp.apply_weapon("viper")
	var wp_viper_damage: int = wp.bullet_damage
	var wp_up: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(wp_up)
	wp_up.buy("damage", 99999, wp)
	if wp.bullet_damage <= wp_viper_damage:
		failed.append("weapons: a shop row stopped moving damage once a weapon was applied")
	wp.apply_weapon("viper")
	if wp.bullet_damage != wp_viper_damage:
		failed.append("weapons: re-applying the weapon did not restore its own base damage")
	wp_up.queue_free()
	# The menu picker: one entry per registry row, writing the save and reaching the
	# player through Main. It lives INSIDE the mutators row on purpose -- a new row
	# costs the title card ~40 px it does not have at 720p.
	var wp_menu: CanvasLayer = main.get_node("UI/MainMenu")
	var wp_picker: OptionButton = wp_menu._weapon_picker
	if wp_picker == null:
		failed.append("weapons: the menu has no weapon picker")
	else:
		if wp_picker.item_count != Weapons.ids().size():
			failed.append("weapons: the picker offers %d guns, the registry has %d"
					% [wp_picker.item_count, Weapons.ids().size()])
		if wp_picker.get_parent() != wp_menu.get_node("Center/Card/Margin/Column/Mutators"):
			failed.append("weapons: the picker left the mutators row (it costs the card height there)")
		var wp_menu_saved: Dictionary = Storage.read_all()
		wp_menu._on_weapon_selected(3)
		var wp_pick_id: String = String(Weapons.ids()[3])
		if String(Storage.get_value(Weapons.SAVE_KEY, "")) != wp_pick_id:
			failed.append("weapons: the picker never wrote its choice to the save file")
		main._on_weapon_changed(wp_pick_id)
		if main._weapon != wp_pick_id or main._player.weapon_id != wp_pick_id:
			failed.append("weapons: a picker change never reached the player (main %s, player %s)"
					% [main._weapon, main._player.weapon_id])
		# Reflecting a saved value must not re-write the file: select() is silent by
		# design, and this is what stops a launch from rewriting the save.
		Storage.write_all(wp_menu_saved)
		wp_menu.set_weapon(Weapons.DEFAULT_ID)
		main._on_weapon_changed(Weapons.DEFAULT_ID)
		if String(Storage.get_value(Weapons.SAVE_KEY, "")) != String(wp_menu_saved.get(Weapons.SAVE_KEY, "")):
			failed.append("weapons: reflecting the saved gun rewrote the save file")
		# Leave the live player on the default gun: later probes (and the next run)
		# must not inherit this section's pick.
		main._on_weapon_changed(Weapons.DEFAULT_ID)
	wp_ref.free()
	wp.free()

	# -- Adaptive director: pressure in, next wave's roster out ------------------
	# The director is one pure function plus one bias applied at wave start. The
	# failure it must not have is COMPOUNDING: an authored row in `wave_table` is a
	# live reference, so biasing it in place makes wave 5 heavier every playthrough
	# and nothing ever errors. The probes below therefore drive whole waves and
	# compare against a fresh read of the table.
	var dr_table: Array[Dictionary] = wm.wave_table
	var dr_wave: int = 5
	# Snapshot the authored row BEFORE any director call. The table itself is what
	# the compounding bug corrupts, so a later read of it would compare the damage
	# with itself -- the probe would pass on exactly the bug it exists to catch.
	var dr_authored_row: Dictionary = dr_table[dr_wave - 1].duplicate()
	var dr_authored: int = 0
	for dr_key: String in dr_authored_row.keys():
		if dr_key != "hp_mult" and dr_key != "speed_mult":
			dr_authored += int(dr_authored_row[dr_key])
	# The pure function first: +, - and 0, clamped at both ends, and a boss wave
	# (roster 0) reads no pace at all rather than reading its clock as slow.
	var dr_hot: float = WaveManager.pressure_from(1.0, 1.0, 1.0, 0.55, 40)
	var dr_cold: float = WaveManager.pressure_from(0.05, 0.05, 600.0, 0.55, 40)
	var dr_even: float = WaveManager.pressure_from(0.5, 0.5, 0.55 * 40.0, 0.55, 40)
	if dr_hot <= 0.3 or dr_cold >= -0.3 or absf(dr_even) > 0.01:
		failed.append("director: untouched / bled-dry / even pressure is wrong (%.2f, %.2f, %.2f)"
				% [dr_hot, dr_cold, dr_even])
	if WaveManager.pressure_from(9.0, 9.0, 0.0, 0.55, 400) > 1.0 \
			or WaveManager.pressure_from(-3.0, -3.0, 99999.0, 0.55, 400) < -1.0:
		failed.append("director: pressure escaped [-1, 1]")
	if absf(WaveManager.pressure_from(0.5, 0.5, 900.0, 0.55, 0)) > 0.01:
		failed.append("director: a boss wave's clock leaked into the pace term")

	# Nothing to read (wave 1 of a run): the authored table, verbatim.
	var dr_base_wait: float = wm.spawn_interval * float(WaveManager.DIFFICULTIES[wm.difficulty]["spawn"])
	wm.is_running = true
	wm.pressure = 0.0
	wm._last_wave_seconds = 0.0
	wm._start_wave(dr_wave)
	if wm._spawn_queue.size() != dr_authored:
		failed.append("director: a neutral report changed the authored wave (%d, table says %d)"
				% [wm._spawn_queue.size(), dr_authored])
	if absf(wm._spawn_timer.wait_time - dr_base_wait) > 0.001:
		failed.append("director: a neutral report moved the spawn pace (%.3f, baseline %.3f)"
				% [wm._spawn_timer.wait_time, dr_base_wait])
	wm.stop()

	# Cruising: untouched and fast -- the next wave is heavier AND faster.
	wm._hp_ratio = 1.0
	wm._hp_start = 1.0
	wm._worst_hp_ratio = 1.0
	wm._last_wave_seconds = 1.0
	wm._last_roster = 40
	wm._start_wave(dr_wave)
	var dr_heavy: int = wm._spawn_queue.size()
	var dr_heavy_elites: int = 0
	for dr_entry: String in wm._spawn_queue:
		if Beasts.is_elite_slug(dr_entry):
			dr_heavy_elites += 1
	if wm.pressure <= 0.3:
		failed.append("director: an untouched second-long wave did not read as cruising (%.2f)" % wm.pressure)
	if dr_heavy <= dr_authored:
		failed.append("director: cruising did not grow the roster (%d vs %d)" % [dr_heavy, dr_authored])
	if dr_heavy_elites <= int(dr_authored_row.get("elite", 0)):
		failed.append("director: cruising added no elites (%d)" % dr_heavy_elites)
	if wm._spawn_timer.wait_time >= dr_base_wait:
		failed.append("director: cruising did not press the pace (%0.3f vs baseline %0.3f)"
				% [wm._spawn_timer.wait_time, dr_base_wait])
	wm.stop()

	# Bleeding: 12% health and a 400 s wave -- thinner and slower.
	wm._hp_ratio = 0.12
	wm._hp_start = 0.12
	wm._worst_hp_ratio = 0.1
	wm._last_wave_seconds = 400.0
	wm._last_roster = 40
	wm._start_wave(dr_wave)
	var dr_light: int = wm._spawn_queue.size()
	if wm.pressure >= -0.3:
		failed.append("director: a 400 s wave at 12%% health did not read as bleeding (%.2f)" % wm.pressure)
	if dr_light >= dr_authored:
		failed.append("director: bleeding did not thin the roster (%d vs %d)" % [dr_light, dr_authored])
	if wm._spawn_timer.wait_time <= dr_base_wait:
		failed.append("director: bleeding did not ease the pace (%.3f vs baseline %.3f)"
				% [wm._spawn_timer.wait_time, dr_base_wait])
	wm.stop()

	# ...and none of that touched the authored table. This is the guard on the
	# `.duplicate()` in _start_wave: without it the counts above grow in place and
	# every later run inherits them.
	wm.pressure = 0.0
	wm._last_wave_seconds = 0.0
	wm._start_wave(dr_wave)
	for dr_key2: String in dr_authored_row.keys():
		if dr_key2 == "hp_mult" or dr_key2 == "speed_mult":
			continue
		var dr_want: int = int(dr_authored_row[dr_key2])
		var dr_got: int = wm._spawn_queue.count(dr_key2)
		if dr_want != dr_got:
			failed.append("director: wave_table[%d]['%s'] is now %d, authored %d"
					% [dr_wave - 1, dr_key2, dr_got, dr_want])
	wm.stop()

	# Boss waves are exempt: cruising must not pad the escort (the boss IS the
	# wave), even though the boss wave's own outcome still informs the next one.
	# The telegraph is skipped for this one call so nothing is left waiting on a
	# timer when the section moves on, and the bosses it spawns are freed again --
	# they are not what this probe is measuring.
	var dr_telegraph: float = wm.spawn_telegraph_time
	wm.spawn_telegraph_time = 0.0
	var dr_kids_before: Array[Node] = main._enemy_container.get_children()
	wm._hp_start = 1.0
	wm._worst_hp_ratio = 1.0
	wm._last_wave_seconds = 1.0
	wm._last_roster = 40
	wm._start_wave(WaveManager.BOSS_EVERY)
	if wm.pressure <= 0.3:
		failed.append("director: a boss wave's own read was not cruising (%.2f)" % wm.pressure)
	if wm._spawn_queue.size() != wm.boss_escort_chasers:
		failed.append("director: the director padded a boss wave's escort (%d, expected %d)"
				% [wm._spawn_queue.size(), wm.boss_escort_chasers])
	for dr_node: Node in main._enemy_container.get_children():
		if not dr_kids_before.has(dr_node):
			dr_node.queue_free()
	for dr_frame: int in 2:
		await main.get_tree().process_frame
	wm.spawn_telegraph_time = dr_telegraph
	wm._alive = 0
	wm.stop()

	# The wiring: the sampler and the binding run on their own -- no probe sets
	# _hp_ratio, so a stale or missing player fails here.
	player.respawn(Vector2.ZERO)
	wm.bind_player(player)
	wm.is_running = true
	wm._wave_seconds = 0.0
	wm._worst_hp_ratio = 1.0
	for dr_i: int in 3:
		await main.get_tree().process_frame
	if wm._hp_ratio < 0.99:
		failed.append("director: a full-health player sampled as %.2f" % wm._hp_ratio)
	if wm._wave_seconds <= 0.0:
		failed.append("director: the fight clock never advanced while a wave was running")
	var dr_before: int = player.health
	player.take_damage(30)
	if player.health >= dr_before:
		failed.append("director: the wiring probe could not damage the player (%d hp)" % dr_before)
	for dr_i2: int in 3:
		await main.get_tree().process_frame
	var dr_hurt: float = clampf(float(player.health) / float(player.max_health), 0.0, 1.0)
	if absf(wm._hp_ratio - dr_hurt) > 0.02:
		failed.append("director: health sample %.2f, the player is at %.2f" % [wm._hp_ratio, dr_hurt])
	if wm._worst_hp_ratio > dr_hurt + 0.02:
		failed.append("director: the low-water mark never followed the hit (%.2f)" % wm._worst_hp_ratio)
	# Main binds the run's player on boot (_bind_world), which is what makes the
	# two reads above reachable in a real run.
	if wm._player != player:
		failed.append("director: the wave manager is not bound to the run's player")
	wm.is_running = false

	# The banner label, pinned at the manager's own threshold rather than a copy.
	wm.pressure = 0.9
	var dr_rising: String = wm.pressure_label()
	wm.pressure = -0.9
	var dr_falling: String = wm.pressure_label()
	wm.pressure = 0.0
	var dr_flat: String = wm.pressure_label()
	if dr_rising != "PRESSURE RISING" or dr_falling != "EASING OFF" or dr_flat != "":
		failed.append("director: banner labels are '%s' / '%s' / '%s'" % [dr_rising, dr_falling, dr_flat])

	# -- Crit / behavior shop rows (they mutate the POOL) ------------------------
	# The pool outlives a run, so these rows write to it and Main restores it per run.
	# Capture the authored values, prove the mutate, then prove the reset.
	BulletPool.reset_run_config()
	var pc_base_chance: float = BulletPool.crit_chance
	var up2: Node = load("res://scripts/upgrade_system.gd").new()
	main.add_child(up2)
	up2.buy("crit_chance", 999999, player)
	if BulletPool.crit_chance <= pc_base_chance:
		failed.append("crit_chance row did not raise the pool's crit chance")
	up2.buy("crit_damage", 999999, player)
	if BulletPool.crit_multiplier <= 2.0:
		failed.append("crit_damage row did not raise the crit multiplier")
	up2.buy("homing", 999999, player)
	up2.buy("ricochet", 999999, player)
	up2.buy("explosive", 999999, player)
	if BulletPool.homing_strength <= 0.0:
		failed.append("homing row did not set homing_strength")
	if BulletPool.bounce_count < 1:
		failed.append("ricochet row did not grant a bounce")
	if BulletPool.explosive_radius <= 0.0 or BulletPool.explosive_damage <= 0:
		failed.append("explosive row did not arm the kill-blast")
	# A player round carries the behavior; an enemy round never does.
	BulletPool.reset()
	BulletPool.fire(Vector2.ZERO, Vector2.RIGHT, 5, 400.0, false)
	var pb: Bullet = _last_active_bullet()
	if pb == null or pb.bounce_left < 1 or pb.homing_scale <= 0.0 or pb.explosive_radius <= 0.0:
		failed.append("a player round did not inherit the behavior config")
	BulletPool.reset()
	BulletPool.fire(Vector2.ZERO, Vector2.RIGHT, 5, 400.0, true)
	var hb: Bullet = _last_active_bullet()
	if hb == null or hb.bounce_left != 0 or hb.homing_scale != 0.0 or hb.explosive_radius != 0.0:
		failed.append("a hostile round inherited the player's behavior config")
	# The per-run reset puts the pool back to its authored values.
	BulletPool.reset_run_config()
	if BulletPool.crit_chance != pc_base_chance or BulletPool.homing_strength != 0.0 \
			or BulletPool.bounce_count != 0 or BulletPool.explosive_radius != 0.0:
		failed.append("reset_run_config did not restore the pool")
	BulletPool.reset()
	up2.free()

	# -- Seeded run RNG (the DAILY toggle) ----------------------------------------
	var seed_base: Array[String] = ["chaser", "rusher", "tank", "weaver", "orbiter"]
	wm.seed_run(123456)
	var q1: Array = []
	for i: int in 200:
		wm._spawn_queue = seed_base.duplicate()
		wm._shuffle_queue()
		q1.append(wm._spawn_queue.duplicate())
	wm.seed_run(123456)
	var seeded_same: bool = true
	for i: int in 200:
		wm._spawn_queue = seed_base.duplicate()
		wm._shuffle_queue()
		if wm._spawn_queue != q1[i]:
			seeded_same = false
			break
	if not seeded_same:
		failed.append("seed_run: the same seed did not reproduce the queue order")
	wm.seed_run(4242)
	var aff1: Array = []
	for i: int in 60:
		aff1.append(wm._roll_affix(6))
	wm.seed_run(4242)
	var aff2: Array = []
	for i: int in 60:
		aff2.append(wm._roll_affix(6))
	if aff1 != aff2:
		failed.append("seed_run: affix rolls were not reproducible under one seed")

	# -- Arena hazards -----------------------------------------------------------
	if ArenaHazard.install(null, 0) != null:
		failed.append("hazard: a null arena should yield no hazard")
	for row: Dictionary in ArenaHazard.BY_ARENA:
		var hk: String = String(row.get("kind", ""))
		if hk != ArenaHazard.KIND_NONE and hk != ArenaHazard.KIND_VENTS \
				and hk != ArenaHazard.KIND_PULSE and hk != ArenaHazard.KIND_VOID:
			failed.append("hazard: unknown kind '%s' in BY_ARENA" % hk)
	var hz_arena := Node2D.new()
	main.add_child(hz_arena)
	var hz0: ArenaHazard = ArenaHazard.install(hz_arena, 0)
	if hz0 != null:
		failed.append("hazard: arena 1 should be hazard-free")
	var hz3: ArenaHazard = ArenaHazard.install(hz_arena, 3)
	if hz3 == null:
		failed.append("hazard: arena 4 should field a hazard")
	elif hz3.kind != ArenaHazard.KIND_PULSE:
		failed.append("hazard: arena 4 kind is '%s', expected pulse" % hz3.kind)
	# Integration: a void pool actually hurts a player standing in it -- through the
	# player's own take_damage, so i-frames still gate it (never a per-frame shred).
	var hz_void: ArenaHazard = ArenaHazard.install(hz_arena, 1)   # deep = void
	if hz_void == null:
		failed.append("hazard: arena 2 should field a void hazard")
	else:
		player.health = player.max_health
		player._invuln_timer = 0.0
		player.global_position = hz_void._pools[0]
		hz_void._player = player
		var hz_hp_before: int = player.health
		hz_void._tick_void(1.0)   # advances past VOID_TICK and fires a hit
		if player.is_alive and player.health >= hz_hp_before:
			failed.append("hazard: a void pool did not damage a player standing in it")
	hz_arena.free()

	# -- Affix marks (the non-colour cue) ----------------------------------------
	for id: String in EnemyBase.AFFIXES.keys():
		if not EnemyBase.AFFIX_MARKS.has(id):
			failed.append("affix '%s' has no non-colour mark" % id)
	var marked: EnemyBase = (load("res://scenes/enemy_chaser.tscn") as PackedScene).instantiate() as EnemyBase
	marked.affix = "shielded"
	main.get_node("World/EnemyContainer").add_child(marked)
	marked.is_dormant = true
	if marked.get_node_or_null("AffixMark") == null:
		failed.append("an affixed enemy did not build its affix mark")
	marked.free()

	# -- Summary ---------------------------------------------------------------
	_restore_save(save_had_file, save_snapshot)
	# The caches have to follow the RESTORED file, not the flags the probes set.
	Unlockables.refresh()
	Perks.refresh()
	if failed.is_empty():
		print("SELFTEST PASS")
	else:
		print("SELFTEST FAIL (%d):" % failed.size())
		for f in failed:
			print("  - " + f)
	var exit_code := 0 if failed.is_empty() else 1
	var main_tree := main.get_tree()
	main_tree.process_frame.connect(main_tree.quit.bind(exit_code), CONNECT_ONE_SHOT)
	queue_free()


## Test-only: hand the unlockables a flag set instantly. is_unlocked() is cached
## (that is what keeps it off the disk in per-shot hot paths), so writing the save
## directly has to refresh the cache in step or the probe reads a stale answer.
func _set_unlock_flags(flags: Dictionary) -> void:
	Storage.set_value(Unlockables.SAVE_KEY, flags)
	Unlockables.refresh()


## The most recently fired round still flying (probes read the stats it was
## configured with). BulletPool.reset() first, and there is exactly one.
func _last_active_bullet() -> Bullet:
	for i: int in range(BulletPool._all.size() - 1, -1, -1):
		var b: Bullet = BulletPool._all[i]
		if b.is_active:
			return b
	return null


## A synthetic key-down event, for probes that drive input handlers directly.
func _key_event(keycode: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	return ev


## Bosses (not escorts) spawned into `container` since `before` was captured.
func _count_bosses(container: Node, before: Array[Node]) -> int:
	var n: int = 0
	for child: Node in container.get_children():
		if not before.has(child) and child.has_method("_fire_ring"):
			n += 1
	return n


## First NEW child that is actually a boss (escorts may arrive alongside it).
func _find_new_boss(container: Node, before: Array[Node]) -> Node:
	for child: Node in container.get_children():
		if not before.has(child) and child.has_method("_fire_ring"):
			return child
	return null


## Active hostile rounds currently in the pool (the boss volley's observable).
func _count_hostile_active() -> int:
	var n: int = 0
	for b: Bullet in BulletPool._all:
		if b.is_active and b.hostile:
			n += 1
	return n


## First child of `container` that was not in `before` (identity, not count).
func _new_container_child(container: Node, before: Array[Node]) -> Node:
	for child: Node in container.get_children():
		if not before.has(child):
			return child
	return null


## Does this enemy carry its own Lit halo light? (The one thing that makes a
## body readable in a dark arena before the player's torch reaches it.)
func _has_lit_halo(e: Node) -> bool:
	for child: Node in e.get_children():
		if child is LitPointLight2D:
			return true
	return false


## RMS of a 16-bit mono AudioStreamWAV, for the level-calibration probe.
func _wav_rms(stream: AudioStreamWAV) -> float:
	var data: PackedByteArray = stream.data
	var n: int = data.size() / 2
	if n <= 0:
		return 0.0
	var sum_sq: float = 0.0
	for i: int in n:
		var s: float = float(data.decode_s16(i * 2)) / 32768.0
		sum_sq += s * s
	return sqrt(sum_sq / float(n))


## Everything a shop upgrade can move, in one dict -- the DEFS sweep compares it
## before/after a purchase, which is what proves a row is not a no-op.
func _player_stat_snapshot(p: Node) -> Dictionary:
	return {
		"bullet_damage": p.bullet_damage,
		"fire_rate": p.fire_rate,
		"max_health": p.max_health,
		"move_speed": p.move_speed,
		"bullet_speed": p.bullet_speed,
		"fire_recoil": p.fire_recoil,
		"bullets_per_shot": p.bullets_per_shot,
		"damage_reduction": p.damage_reduction,
		"invulnerability_time": p.invulnerability_time,
		"kill_heal": p.kill_heal,
		"pierce_count": p.pierce_count,
		"charge_unlocked": p.charge_unlocked,
		"health": p.health,
		# The second twenty's player-side rows.
		"dash_cooldown": p.dash_cooldown,
		"dash_speed": p.dash_speed,
		"dash_strike_dmg": p.dash_strike_dmg,
		"bullet_spread_deg": p.bullet_spread_deg,
		# Scene sentinels: 0 = "use the bullet's parked default", which apply_weapon
		# then materializes as BASE_LIFETIME / 1.0. Normalize so the DEFAULT row's
		# no-op check compares like with like.
		"bullet_lifetime": p.bullet_lifetime if p.bullet_lifetime > 0.0 else float(Bullet.BASE_LIFETIME),
		"bullet_scale": p.bullet_scale if p.bullet_scale > 0.0 else 1.0,
		"weapon_knockback": p.weapon_knockback,
		"charge_time": p.charge_time,
		"retaliate_dmg": p.retaliate_dmg,
		"regen_rate": p.regen_rate,
		"adrenaline_mult": p.adrenaline_mult,
		"evasion_chance": p.evasion_chance,
		# The third ten's player-side rows.
		"acceleration": p.acceleration,
		"dash_time": p.dash_time,
		"credit_mult": p.credit_mult,
		"knockback_resist": p.knockback_resist,
		"last_stand_charges": p.last_stand_charges,
		"charge_damage_mult": p.charge_damage_mult,
		"charge_knockback_mult": p.charge_knockback_mult,
		"charge_pierce": p.charge_pierce,
	}


## The pool tunables a shop row may move (crit + behavior + the second
## twenty's group multipliers and the PickupPool's magnet/scavenger), so the
## "no dead row" sweep covers rows that write to the autoloads, not the player.
func _pool_stat_snapshot() -> Dictionary:
	return {
		"crit_chance": BulletPool.crit_chance,
		"crit_multiplier": BulletPool.crit_multiplier,
		"homing_strength": BulletPool.homing_strength,
		"homing_range": BulletPool.homing_range,
		"bounce_count": BulletPool.bounce_count,
		"explosive_radius": BulletPool.explosive_radius,
		"explosive_damage": BulletPool.explosive_damage,
		"vs_boss_mult": BulletPool.vs_boss_mult,
		"vs_elite_mult": BulletPool.vs_elite_mult,
		"exec_mult": BulletPool.exec_mult,
		"burn_dps": BulletPool.burn_dps,
		"magnet_mult": PickupPool.magnet_mult,
		"extra_drop_chance": PickupPool.extra_drop_chance,
		"heal_mult": PickupPool.heal_mult,
	}


## Does this stream repeat, across the three stream classes the game can load?
func _stream_loops(stream: AudioStream) -> bool:
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).loop
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return false


## Number of pooled SFX players currently playing (the mute gate's observable).
func _count_playing_sfx() -> int:
	var n: int = 0
	for p: AudioStreamPlayer in AudioManager._pool:
		if p.playing:
			n += 1
	return n


## The quietest volume among pooled SFX players that started after `before` was captured.
## Reading the quietest player in the whole pool flaked (one run in two): a leftover sound
## from an earlier probe has a different base db and can still be ringing, so it -- not the
## sound just played -- set the answer. The pool reuses players, so "new since" is the only
## reliable identity.
func _quietest_new_sfx_db(before: Array) -> float:
	var quietest: float = 100.0
	for p: AudioStreamPlayer in AudioManager._pool:
		if p.playing and not before.has(p):
			quietest = minf(quietest, p.volume_db)
	return quietest


## Pooled SFX players playing right now, as a marker for _quietest_new_sfx_db.
func _playing_sfx_players() -> Array:
	var playing: Array = []
	for p: AudioStreamPlayer in AudioManager._pool:
		if p.playing:
			playing.append(p)
	return playing


## Pooled SFX players that started after `before` was captured. Identity, not
## count: the pool has ten slots and reuses them, so "playing and new since the
## marker" is the only reliable proof a sound started.
func _new_sfx_since(before: Array) -> Array:
	var fresh: Array = []
	for p: AudioStreamPlayer in AudioManager._pool:
		if p.playing and not before.has(p):
			fresh.append(p)
	return fresh


## Walk a res:// directory (scripts/scenes only -- never addons/) and collect
## any file holding a byte above 0x7F.
func _collect_non_ascii(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		out.append(dir_path + " (unreadable)")
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_non_ascii(full, out)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null:
				var bytes: PackedByteArray = f.get_buffer(f.get_length())
				f.close()
				for b: int in bytes:
					if b > 127:
						out.append(full)
						break
		entry = dir.get_next()
	dir.list_dir_end()


## Put the player's save file back exactly as it was before the run.
func _restore_save(had_file: bool, bytes: PackedByteArray) -> void:
	if not had_file:
		if FileAccess.file_exists(Storage.PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Storage.PATH))
		return
	var f := FileAccess.open(Storage.PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[Selftest] could not restore the save file")
		return
	f.store_buffer(bytes)
	f.close()
