extends EnemyBase
class_name EnemyBoss
## Wave boss: a giant shape that ignores every barrier and sprays swirling
## bullet-hell patterns out of the shared BulletPool.
##
## "Through any barrier" is two settings, not a physics trick: the collision
## MASK has no Wall bit (3 = Player | Enemy, layer 8 deliberately absent) so
## walls and obstacles never block or slide it, and `_nav_fallback = true` skips
## the navmesh entirely so it steers straight at the player instead of pathing
## around cover. It still collides with the player (contact damage) and other
## enemies, and player rounds still hit it (its BODY stays on the Enemy layer).
##
## Attacks: a rotating ring on a slow interval plus a fast swirl, both keyed off
## one accumulating `_phase` so the patterns interleave instead of syncing up.

@export_group("Bullet hell")
@export var ring_interval: float = 1.5
@export var ring_bullets: int = 14
@export var spiral_interval: float = 0.26
@export var spiral_bullets: int = 3
@export var spiral_step_deg: float = 17.0
@export var bullet_speed: float = 340.0
@export var spiral_speed_scale: float = 1.25
@export var bullet_damage: int = 8

@export_group("Boss look")
@export var body_color_full: Color = Color(0.55, 0.15, 0.45)
@export var body_color_hurt: Color = Color(1.0, 0.55, 0.1)

var _ring_timer: float = 1.0
var _spiral_timer: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("bosses")    # Main counts boss kills for the unlockables
	collision_mask = 3        # Player (1) + Enemy (2); no Wall (8) -> walks through cover
	_nav_fallback = true      # straight-line pursuit, no navmesh


func _update_behavior(delta: float) -> void:
	_ring_timer -= delta
	_spiral_timer -= delta
	_phase += deg_to_rad(spiral_step_deg) * delta / maxf(spiral_interval, 0.01)
	if _ring_timer <= 0.0:
		_ring_timer = ring_interval
		_fire_ring()
	if _spiral_timer <= 0.0:
		_spiral_timer = spiral_interval
		_fire_spiral()


## Straight at the player -- the base class still handles separation, knockback
## (scaled by `knockback_resist` in the scene) and contact damage.
func _desired_velocity() -> Vector2:
	return _steer_toward_player(move_speed)


## Health read-out without new UI: the body heats up from violet to orange as
## it takes damage, so a long fight still shows progress. EnemyBase applies this
## (and overrides it with white on the frame the boss is hit).
func _base_tint() -> Color:
	var hurt: float = 1.0 - clampf(float(health) / float(maxi(max_health, 1)), 0.0, 1.0)
	return body_color_full.lerp(body_color_hurt, hurt)


func _fire_ring() -> void:
	var count: int = maxi(3, ring_bullets)
	for i: int in count:
		var angle: float = _phase + TAU * float(i) / float(count)
		BulletPool.fire(global_position, Vector2.RIGHT.rotated(angle), bullet_damage, bullet_speed, true)


func _fire_spiral() -> void:
	var count: int = maxi(1, spiral_bullets)
	for i: int in count:
		var angle: float = _phase + TAU * float(i) / float(count)
		BulletPool.fire(global_position, Vector2.RIGHT.rotated(angle), bullet_damage,
				bullet_speed * spiral_speed_scale, true)
