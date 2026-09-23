extends CharacterBody2D
class_name Player
## Twin-stick player: WASD moves (acceleration + friction), mouse aims the gun
## pivot, hold LMB to auto-fire. Emits signals -- Main wires them to HUD/camera.
##
## Godot 4 notes vs Godot 3:
## - move_and_slide() takes NO arguments; it uses the `velocity` property and
##   reads delta internally. up_direction defaults to Vector2.UP.
## - There is no is_action "strength" magic needed here; Input.get_vector()
##   builds a normalized 2D axis vector from the four move_* actions.

signal health_changed(current: int, maximum: int)
signal damaged(amount: int)
signal died
signal shoot
## Fired by fire_charged() only -- Main counts it for the "overcharge" unlockable.
signal charged_shot

## Unlockable "neon_skin": a violet body + magenta gun, read once at spawn (the
## hit flash owns Body.modulate, so recolouring .color never fights it).
const NEON_SKIN_BODY := Color(0.62, 0.28, 0.95)
const NEON_SKIN_GUN := Color(1.0, 0.55, 0.95)
## Unlockable "overcharge": charged-round damage multiplier.
const OVERCHARGE_MULT := 1.25
## Unlockable "glass_cannon" (a run mutator the menu toggles): 50 HP and harder
## hits, at the cost of never being able to buy armor.
const GLASS_CANNON_HP := 50
const GLASS_CANNON_DAMAGE := 1.5
## Unlockable "second_wind": i-frames handed over on the one auto-revive.
const REVIVE_IFRAMES := 1.5
## Lit torch: the player's own light, and the only shadow-casting light in the game.
## Range/energy are tuned against the arena, which is 1320 px across: at 430/1.15 the lit
## pool was only ~200 px wide, so the room read as pitch black past the player's feet.
## Energy is deliberately under half what the room-wide range alone would want: the light
## sits inside the player, so the player's own body is the brightest surface in the frame
## and clips to near-white (246/255 at 2.1). Neon cyan, not a warm flame: the backdrop is
## near-black with a crimson grid, so a saturated cool light is what reads as neon-lit.
const TORCH_COLOR := Color(0.45, 0.95, 1.0)
const TORCH_RANGE := 820.0
const TORCH_ENERGY := 0.52

@export_group("Movement")
@export var move_speed: float = 230.0
@export var acceleration: float = 2000.0
@export var friction: float = 2400.0

@export_group("Shooting")
@export var fire_rate: float = 0.15
@export var bullet_damage: int = 12
@export var bullet_speed: float = 700.0
@export var fire_recoil: float = 55.0

## Shop "split shot" raises this: one trigger pull fires N bullets across an arc.
var bullets_per_shot: int = 1

## Shop "pierce": how many EXTRA enemies a round passes through before it dies.
var pierce_count: int = 0

## ---------------------------------------------------------------- weapon ---
## The run's archetype (see weapons.gd). The shop still mutates fire_rate /
## bullets_per_shot / pierce_count / bullet_damage on top of it -- a weapon only
## decides what those start from.
var weapon_id: String = "rifle"
## Angle between neighbouring pellets of one volley (the weapon owns it).
var bullet_spread_deg: float = BULLET_SPREAD_DEG
## How long a round flies, i.e. the gun's reach. 0 = the bullet scene's own default.
var bullet_lifetime: float = 0.0
## Round size, hitbox included. 0 = unscaled.
var bullet_scale: float = 0.0
## Per-shot push scale (the slugger shoves, the needler does not).
var weapon_knockback: float = 1.0

@export_group("Charge shot")
## Shop "charge" unlocks this. RMB holds a heavy round; releasing it fires one
## big, slow, high-knockback, piercing shot. LMB autofire is deliberately
## untouched so the tuned feel of a normal trigger pull never changes.
@export var charge_time: float = 0.6
@export var charge_damage_mult: float = 3.0
@export var charge_speed_mult: float = 0.55
@export var charge_knockback_mult: float = 2.5
@export var charge_pierce: int = 2

## The heavy shot is a commitment: it locks the normal trigger for this long.
const CHARGE_COOLDOWN_MULT := 4.0
## Below this fraction of a full charge, a release is a mis-tap, not a shot.
const CHARGE_MIN_RATIO := 0.35

## Shop "charge" raises this once bought (no export: the shop owns it).
var charge_unlocked: bool = false

## Angle between neighbouring bullets of a volley, in degrees.
const BULLET_SPREAD_DEG := 7.0

@export_group("Health")
@export var max_health: int = 100
@export var invulnerability_time: float = 0.6
@export var flash_time: float = 0.12

@export_group("Dash")
## Space: a short burst in the held move direction (facing if idle) with
## i-frames, on a cooldown. Reuses the SAME i-frame timer take_damage gates
## on -- there is no second invulnerability flag to fall out of sync, and a
## dash never SHORTENS standing i-frames (maxf, below).
@export var dash_speed: float = 900.0
@export var dash_time: float = 0.16
@export var dash_cooldown: float = 1.6

## Shop stats that have no export: flat damage soaked (0..1) and health won per
## kill. Both are read where they apply -- take_damage() and Main's kill handler.
var damage_reduction: float = 0.0
var kill_heal: int = 0
## The second twenty's player-side rows (see UpgradeSystem.DEFS). Each is read
## where it applies: dash scan, take_damage, _process, _effective_fire_rate.
var dash_strike_dmg: int = 0
var retaliate_dmg: int = 0
var regen_rate: float = 0.0        # HP per second (0 = off)
var adrenaline_mult: float = 1.0   # fire-rate multiplier below half health
var evasion_chance: float = 0.0    # 0..1 dodge odds, capped at 0.40 by the shop
## The third ten's player-side rows (see UpgradeSystem.DEFS). Each is read where
## it applies: _handle_movement, take_damage, Main's kill handler.
var credit_mult: float = 1.0       # shop "bounty": kill credits multiplier
var knockback_resist: float = 0.0  # shop "anchor": 0..0.8 of a push ignored
var last_stand_charges: int = 0    # shop "last_stand": lethal hits eaten
const DASH_STRIKE_RADIUS := 42.0
const RETALIATE_RADIUS := 90.0

## How long the muzzle flash polygon stays lit after a shot.
const MUZZLE_FLASH_TIME := 0.045

var health: int = max_health
var controls_enabled: bool = false
var is_alive: bool = true

var _fire_cooldown: float = 0.0
## Dash state: ticks in _physics_process; velocity is written every dash tick
## (move_and_slide still resolves the collisions).
var _dash_timer: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
## Shop "dash strike": enemies this dash already hit (instance ids), cleared on
## the next dash so one pass damages each body at most once.
var _dash_hit: Array[int] = []
## Shop "regen": fractional HP accumulator, so 0.2 HP/s heals 1 HP every 5 s.
var _regen_acc: float = 0.0
## Pristine bullet_damage from _ready: mutators scale THIS, never the live value.
var _base_bullet_damage: int = 0
## The weapon-folded base for the two stats the shop only ever multiplies, so
## "pristine" survives a purchase (see apply_weapon).
var _base_fire_rate: float = 0.0
var _base_bullet_speed: float = 0.0
## The SCENE's own shooting stats, recorded before any weapon touches them: a weapon
## is a multiplier of these, so switching guns can never compound.
var _scene_fire_rate: float = 0.0
var _scene_bullet_damage: int = 0
var _scene_bullet_speed: float = 0.0
var _scene_fire_recoil: float = 0.0
## Pristine max_health from _ready -- what a mutator is measured against.
var _base_max_health: int = 0
## Pristine move_speed / damage_reduction from _ready, for perks that scale them.
var _base_move_speed: float = 0.0
var _base_damage_reduction: float = 0.0
## Lit: the player's torch (see _setup_lighting).
var _torch: LitPointLight2D = null
var _charge_t: float = 0.0   # seconds RMB has been held (see _handle_charge)
var _invuln_timer: float = 0.0
var _flash_timer: float = 0.0
var _flash_timer_muzzle: float = 0.0
var _blink_phase: float = 0.0
var _simulated_fire: bool = false  # headless smoke-test flag (--autofire)

@onready var _body: Polygon2D = $Body
@onready var _aim_pivot: Node2D = $AimPivot
@onready var _muzzle: Marker2D = $AimPivot/Muzzle
@onready var _muzzle_flash: Polygon2D = $AimPivot/MuzzleFlash
@onready var _camera: PlayerCamera = $PlayerCamera


func _ready() -> void:
	add_to_group("player")
	health = max_health
	_base_bullet_damage = bullet_damage   # pristine, for mutators that scale it
	_base_max_health = max_health
	_base_move_speed = move_speed
	_base_damage_reduction = damage_reduction
	# The scene's own shooting stats, so a weapon archetype scales THESE and never a
	# value a previous weapon already wrote.
	_scene_fire_rate = fire_rate
	_scene_bullet_damage = bullet_damage
	_scene_bullet_speed = bullet_speed
	_scene_fire_recoil = fire_recoil
	_base_fire_rate = fire_rate
	_base_bullet_speed = bullet_speed
	_setup_lighting()
	_apply_unlockable_skin()
	# An emissive rim stays readable outside the torch; inherits hit/iframe modulation.
	var rim := Line2D.new()
	rim.name = "NeonHullRim"
	rim.points = _body.polygon
	rim.closed = true
	rim.width = 1.8
	rim.antialiased = true
	rim.default_color = _body.color.lightened(0.55)
	_body.add_child(rim)
	var core := Polygon2D.new()
	core.name = "NeonVisor"
	core.polygon = PackedVector2Array([Vector2(-6, -4), Vector2(5, -3), Vector2(9, 0), Vector2(5, 3), Vector2(-6, 4)])
	core.color = Color("#ddffff")
	_body.add_child(core)
	if OS.get_cmdline_user_args().has("--autofire"):
		_simulated_fire = true


## Make this run's weapon archetype the shooting baseline. Called by Main at every
## run start (and by the menu's picker), so it is IDEMPOTENT: every number is derived
## from the pristine scene stats, never from the live ones, and applying the same
## weapon twice -- or switching guns and back -- lands on exactly the same stats.
##
## Order matters with the other run modifiers: this re-derives _base_bullet_damage,
## which Perks.apply_to_player() and glass cannon scale, so apply the weapon FIRST.
func apply_weapon(id: String) -> void:
	var d: Dictionary = Weapons.resolve(id)
	weapon_id = String(d.get("id", Weapons.DEFAULT_ID))
	_base_fire_rate = _scene_fire_rate * float(d.get("fire_rate", 1.0))
	_base_bullet_damage = maxi(1, int(round(float(_scene_bullet_damage) * float(d.get("damage", 1.0)))))
	_base_bullet_speed = _scene_bullet_speed * float(d.get("speed", 1.0))
	fire_rate = _base_fire_rate
	bullet_damage = _base_bullet_damage
	bullet_speed = _base_bullet_speed
	fire_recoil = _scene_fire_recoil * float(d.get("recoil", 1.0))
	bullet_spread_deg = float(d.get("spread_deg", BULLET_SPREAD_DEG))
	bullet_lifetime = float(d.get("lifetime", 0.0))
	bullet_scale = float(d.get("scale", 0.0))
	weapon_knockback = float(d.get("knockback", 1.0))
	# Absolute bases the shop then ADDS to (so "pierce +1" still means +1).
	pierce_count = int(d.get("pierce", 0))
	bullets_per_shot = int(d.get("pellets", 1))


## Unlockable "glass_cannon": the run mutator. Absolute values from the pristine
## damage, so calling it on every run start cannot compound the multiplier.
func apply_glass_cannon() -> void:
	max_health = GLASS_CANNON_HP
	health = max_health
	bullet_damage = int(round(float(_base_bullet_damage) * GLASS_CANNON_DAMAGE))
	health_changed.emit(health, max_health)


## Unlockable "second_wind": stand the player back up at a fraction of max HP with
## i-frames to get clear. Main calls this instead of ending the run, once per run.
func revive(health_fraction: float) -> void:
	health = maxi(1, int(round(float(max_health) * clampf(health_fraction, 0.05, 1.0))))
	is_alive = true
	visible = true
	_invuln_timer = maxf(_invuln_timer, REVIVE_IFRAMES)
	_flash_timer = flash_time
	# _die() zeroed these deferred; undo it the same way so the player is solid and
	# hittable again on the next physics tick.
	set_deferred("collision_layer", 1)
	set_deferred("collision_mask", 10)
	health_changed.emit(health, max_health)


## Lit: the player IS the light source. Without this torch the ambient darkness makes
## the arena almost unreadable, and with shadows on the walls finally read as solid
## geometry instead of painted rectangles.
func _setup_lighting() -> void:
	if not LitLighting.available():
		return
	LitLighting.make_receiver(_body)
	LitLighting.make_receiver(get_node_or_null("AimPivot/GunBarrel") as CanvasItem)
	_torch = LitLighting.add_point_light(self, TORCH_COLOR, TORCH_RANGE, TORCH_ENERGY, true)


## "fog" run mutator: scale the torch's reach. 1.0 restores the full range, so a
## run start always sets it (a fog run followed by a normal one cannot keep fog).
func set_torch_scale(scale: float) -> void:
	if _torch != null:
		_torch.set("range", TORCH_RANGE * clampf(scale, 0.05, 2.0))


## Unlockable "neon_skin". Body + gun only: every other colour on the player is
## owned by the damage/blink flash in _update_damage_visuals().
func _apply_unlockable_skin() -> void:
	if not Unlockables.is_unlocked("neon_skin"):
		return
	if is_instance_valid(_body):
		_body.color = NEON_SKIN_BODY
	var barrel: Polygon2D = get_node_or_null("AimPivot/GunBarrel") as Polygon2D
	if barrel != null:
		barrel.color = NEON_SKIN_GUN


func respawn(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	health = max_health
	is_alive = true
	_invuln_timer = 0.0
	_flash_timer = 0.0
	_fire_cooldown = 0.0
	_dash_timer = 0.0
	_dash_cooldown_left = 0.0
	visible = true
	set_deferred("collision_layer", 1)
	set_deferred("collision_mask", 10)
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_handle_movement(delta)
	_handle_aiming(delta)
	if controls_enabled:
		_handle_firing(delta)
		if Input.is_action_just_pressed("dash"):
			try_dash()
	_update_dash(delta)
	move_and_slide()


## Dash now, if the run allows it (Space routes here; the self-test calls it
## directly for the same reason it calls fire_charged). Returns whether the
## dash actually went out.
func try_dash() -> bool:
	if not is_alive or not controls_enabled:
		return false
	if _dash_cooldown_left > 0.0 or _dash_timer > 0.0:
		return false
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_dash_dir = input_dir if input_dir != Vector2.ZERO else Vector2.RIGHT.rotated(_aim_pivot.rotation)
	_dash_timer = dash_time
	_dash_cooldown_left = dash_cooldown
	_dash_hit.clear()
	# i-frames for the whole dash, through the ONE timer take_damage reads.
	# maxf: a dash never shortens i-frames the player already has.
	_invuln_timer = maxf(_invuln_timer, dash_time)
	return true


## 0..1 cooldown readiness, for the HUD pip (1 = ready).
func dash_ready_ratio() -> float:
	return 1.0 - _dash_cooldown_left / maxf(dash_cooldown, 0.01)


func _update_dash(delta: float) -> void:
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	if _dash_timer <= 0.0:
		return
	_dash_timer -= delta
	# Velocity, never global_position: move_and_slide still resolves walls and
	# obstacles, so a dash into cover stops instead of tunneling through it.
	velocity = _dash_dir * dash_speed
	if dash_strike_dmg > 0:
		_dash_strike_scan()


## Shop "dash strike": every enemy this dash touches eats one hit. The per-dash
## id set keeps a lingering dash from multi-ticking the same body.
func _dash_strike_scan() -> void:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var eb := node as EnemyBase
		if eb == null or eb.is_dead:
			continue
		var eid: int = eb.get_instance_id()
		if _dash_hit.has(eid):
			continue
		if global_position.distance_to(eb.global_position) > DASH_STRIKE_RADIUS:
			continue
		_dash_hit.append(eid)
		eb.take_damage(dash_strike_dmg)


func _process(delta: float) -> void:
	_update_damage_visuals(delta)
	# Shop "regen": accumulate fractional HP so a low rate still heals on time.
	if regen_rate > 0.0 and is_alive:
		_regen_acc += regen_rate * delta
		if _regen_acc >= 1.0:
			var whole: int = int(_regen_acc)
			_regen_acc -= float(whole)
			heal(whole)


func _handle_movement(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO
	if controls_enabled:
		# get_vector(neg_x, pos_x, neg_y, pos_y) -- already normalized, so no
		# diagonal speed boost and no manual length checks needed.
		input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(input_dir * move_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


func _handle_aiming(_delta: float) -> void:
	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 1.0:
		_aim_pivot.rotation = to_mouse.angle()
	if _simulated_fire:
		# Headless smoke test: slowly sweep the gun so shots can hit things.
		_aim_pivot.rotation += 1.6 * get_physics_process_delta_time()


func _handle_firing(delta: float) -> void:
	_fire_cooldown -= delta
	_handle_charge(delta)
	var want_fire: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _simulated_fire
	if want_fire and _fire_cooldown <= 0.0:
		_fire_cooldown = _effective_fire_rate()
		_fire_bullet()


## Effective seconds between shots: shop "adrenaline" (below half health) lives
## here, and BOTH the trigger and the charge's post-shot lockout read this, so
## one stat can never drift between the two paths.
func _effective_fire_rate() -> float:
	if adrenaline_mult > 1.0 and health < max_health * 0.5:
		return fire_rate * adrenaline_mult
	return fire_rate


## RMB charge state machine. Held -> the charge grows and the muzzle flash grows
## with it (the tell, no new UI); released -> one heavy round, or nothing if the
## tap was too short to count as a charge.
func _handle_charge(delta: float) -> void:
	if not charge_unlocked:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_charge_t = minf(_charge_t + delta, charge_time)
		if is_instance_valid(_muzzle_flash):
			_muzzle_flash.visible = true
			_muzzle_flash.scale = Vector2.ONE * (1.0 + 2.0 * charge_ratio())
		return
	var released: float = _charge_t
	_charge_t = 0.0
	if is_instance_valid(_muzzle_flash):
		_muzzle_flash.scale = Vector2.ONE
	if released <= 0.0:
		return
	if released < charge_time * CHARGE_MIN_RATIO or _fire_cooldown > 0.0:
		return
	_fire_cooldown = _effective_fire_rate() * CHARGE_COOLDOWN_MULT
	fire_charged(released / charge_time)


## 0..1 how far the current hold has charged.
func charge_ratio() -> float:
	return clampf(_charge_t / maxf(charge_time, 0.01), 0.0, 1.0)


## Fire the heavy round. `power` is 0..1 of a full charge. Public so the
## self-test can drive it without synthesising mouse input.
func fire_charged(power: float) -> void:
	var k: float = clampf(power, 0.15, 1.0)
	var dir: Vector2 = Vector2.RIGHT.rotated(_aim_pivot.rotation)
	# Unlockable "overcharge": the charged round hits harder at the same charge
	# time -- the shop's "charge" upgrade is still what unlocks firing it at all.
	var overcharge: float = OVERCHARGE_MULT if Unlockables.is_unlocked("overcharge") else 1.0
	# The heavy round INHERITS the shop's damage/pierce scaling: bullet_damage
	# already folds in the "damage" upgrade (and Arsenal), and the "pierce"
	# upgrade adds on top of the charge's own built-in pierce.
	# It keeps the SCENE's range on purpose: a furnace's 0.3 s rounds must not turn the
	# paid-for heavy shot into a stub, so only the size follows the weapon.
	BulletPool.fire(_muzzle.global_position, dir,
			int(round(float(bullet_damage) * charge_damage_mult * k * overcharge)),
			bullet_speed * charge_speed_mult, false, charge_pierce + pierce_count,
			charge_knockback_mult * weapon_knockback, 0.0, bullet_scale)
	shoot.emit()
	charged_shot.emit()
	velocity -= dir * fire_recoil * charge_knockback_mult
	_flash_timer_muzzle = MUZZLE_FLASH_TIME * 2.0
	if is_instance_valid(_muzzle_flash):
		_muzzle_flash.visible = true


func _fire_bullet() -> void:
	var base_dir: Vector2 = Vector2.RIGHT.rotated(_aim_pivot.rotation)
	var count: int = maxi(1, bullets_per_shot)
	# Volley spreads evenly around the aim line: a 1-bullet shot sits on it, extra
	# bullets sit +/- k*spread off it -- the weapon owns the angle, the shop only
	# multiplies the count.
	var step: float = deg_to_rad(bullet_spread_deg)
	for i: int in count:
		var offset: float = step * (float(i) - float(count - 1) * 0.5)
		BulletPool.fire(_muzzle.global_position, base_dir.rotated(offset), bullet_damage,
				bullet_speed, false, pierce_count, weapon_knockback, bullet_lifetime, bullet_scale)
	shoot.emit()
	velocity -= base_dir * fire_recoil
	_flash_timer_muzzle = MUZZLE_FLASH_TIME
	if is_instance_valid(_muzzle_flash):
		_muzzle_flash.visible = true


func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if not is_alive or _invuln_timer > 0.0 or amount <= 0:
		return
	# Shop "evasion": a clean miss -- no damage, no i-frames spent, so the roll can
	# fire again on the next hit (chance 0/1 is deterministic for the suite).
	if evasion_chance > 0.0 and randf() < evasion_chance:
		return
	# Shop "armor" soaks a flat share of every hit, always leaving at least 1.
	var dealt: int = maxi(1, int(round(float(amount) * (1.0 - clampf(damage_reduction, 0.0, 0.9)))))
	health = maxi(health - dealt, 0)
	_invuln_timer = invulnerability_time
	_flash_timer = flash_time
	if knockback != Vector2.ZERO:
		# Shop "anchor": a braced player takes only the share it cannot soak.
		velocity += knockback * (1.0 - clampf(knockback_resist, 0.0, 0.8))
	health_changed.emit(health, max_health)
	damaged.emit(dealt)
	if health <= 0:
		# Shop "last_stand": eat the killing blow on a charge and stand back up
		# at 1 HP. The hit's i-frames still land, so the follow-up cannot chain.
		if last_stand_charges > 0:
			last_stand_charges -= 1
			health = 1
			health_changed.emit(health, max_health)
			return
		_die()
	elif retaliate_dmg > 0:
		_retaliate()


## Shop "retaliate": a short AoE pulse every time a hit actually landed (not on
## a dodge -- that path returns before this). Skips the killing blow: no pulse
## from a dead player.
func _retaliate() -> void:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var eb := node as EnemyBase
		if eb == null or eb.is_dead:
			continue
		if global_position.distance_to(eb.global_position) > RETALIATE_RADIUS:
			continue
		eb.take_damage(retaliate_dmg)


## Shop "leech" calls this from Main's kill handler.
func heal(amount: int) -> void:
	if not is_alive or amount <= 0 or health >= max_health:
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)


## Called by enemies on contact. Other systems react via the `died` signal.
func _die() -> void:
	if not is_alive:
		return
	is_alive = false
	controls_enabled = false
	visible = false
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	died.emit()


func _update_damage_visuals(delta: float) -> void:
	if not is_instance_valid(_body):
		return
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	_invuln_timer = maxf(_invuln_timer - delta, 0.0)
	_flash_timer_muzzle = maxf(_flash_timer_muzzle - delta, 0.0)
	if is_instance_valid(_muzzle_flash):
		_muzzle_flash.visible = _flash_timer_muzzle > 0.0
	# Single place that owns Body.modulate: red flash on hit, alpha blink
	# during i-frames. Avoids tween/modulate conflicts.
	var color: Color = Color.WHITE
	if _flash_timer > 0.0:
		color = Color(1.0, 0.25, 0.25)
	if _invuln_timer > 0.0 and is_alive:
		_blink_phase += delta * 18.0
		color.a = 0.45 + 0.35 * absf(sin(_blink_phase))
	_body.modulate = color
