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

## Shop stats that have no export: flat damage soaked (0..1) and health won per
## kill. Both are read where they apply -- take_damage() and Main's kill handler.
var damage_reduction: float = 0.0
var kill_heal: int = 0

## How long the muzzle flash polygon stays lit after a shot.
const MUZZLE_FLASH_TIME := 0.045

var health: int = max_health
var controls_enabled: bool = false
var is_alive: bool = true

var _fire_cooldown: float = 0.0
## Pristine bullet_damage from _ready: mutators scale THIS, never the live value.
var _base_bullet_damage: int = 0
## Pristine max_health from _ready -- what a mutator is measured against.
var _base_max_health: int = 0
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
	move_and_slide()


func _process(delta: float) -> void:
	_update_damage_visuals(delta)


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
		_fire_cooldown = fire_rate
		_fire_bullet()


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
	_fire_cooldown = fire_rate * CHARGE_COOLDOWN_MULT
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
	BulletPool.fire(_muzzle.global_position, dir,
			int(round(float(bullet_damage) * charge_damage_mult * k * overcharge)),
			bullet_speed * charge_speed_mult, false, charge_pierce, charge_knockback_mult)
	shoot.emit()
	charged_shot.emit()
	velocity -= dir * fire_recoil * charge_knockback_mult
	_flash_timer_muzzle = MUZZLE_FLASH_TIME * 2.0
	if is_instance_valid(_muzzle_flash):
		_muzzle_flash.visible = true


func _fire_bullet() -> void:
	var base_dir: Vector2 = Vector2.RIGHT.rotated(_aim_pivot.rotation)
	var count: int = maxi(1, bullets_per_shot)
	# Volley spreads evenly around the aim line: a 1-bullet shot is unchanged,
	# extra bullets sit +/- k*7 degrees off it.
	var step: float = deg_to_rad(BULLET_SPREAD_DEG)
	for i: int in count:
		var offset: float = step * (float(i) - float(count - 1) * 0.5)
		BulletPool.fire(_muzzle.global_position, base_dir.rotated(offset), bullet_damage, bullet_speed, false, pierce_count)
	shoot.emit()
	velocity -= base_dir * fire_recoil
	_flash_timer_muzzle = MUZZLE_FLASH_TIME
	if is_instance_valid(_muzzle_flash):
		_muzzle_flash.visible = true


func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if not is_alive or _invuln_timer > 0.0 or amount <= 0:
		return
	# Shop "armor" soaks a flat share of every hit, always leaving at least 1.
	var dealt: int = maxi(1, int(round(float(amount) * (1.0 - clampf(damage_reduction, 0.0, 0.9)))))
	health = maxi(health - dealt, 0)
	_invuln_timer = invulnerability_time
	_flash_timer = flash_time
	if knockback != Vector2.ZERO:
		velocity += knockback
	health_changed.emit(health, max_health)
	damaged.emit(dealt)
	if health <= 0:
		_die()


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
