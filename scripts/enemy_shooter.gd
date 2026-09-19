extends EnemyBase
class_name EnemyShooter
## Keeps distance (flees when close, creeps when far) and fires pooled bullets
## at the player. Shares the player's BulletPool so projectiles stay cheap:
## BulletPool.fire(..., is_hostile = true) is the whole contract -- the round gets
## the Player/Wall mask and red tint, and Bullet._handle_hit calls
## Player.take_damage on contact.

@export_group("Shooter")
@export var keep_distance: float = 260.0
@export var flee_range: float = 190.0
@export var creep_speed_scale: float = 0.7
@export var shot_interval: float = 1.7
@export var bullet_speed: float = 340.0
@export var bullet_damage: int = 8

var _shot_timer: float = 0.0


func _update_behavior(delta: float) -> void:
	_shot_timer -= delta
	if _shot_timer <= 0.0:
		_shot_timer = shot_interval
		_fire_at_player()


func _desired_velocity() -> Vector2:
	var to_player: Vector2 = _player_position() - global_position
	var dist: float = to_player.length()
	if dist < 1.0:
		return Vector2.ZERO
	if dist < flee_range:
		return -to_player.normalized() * move_speed            # back off
	if dist > keep_distance:
		return to_player.normalized() * move_speed * creep_speed_scale
	return Vector2.ZERO                                        # hold the ring


func _fire_at_player() -> void:
	var dir: Vector2 = (_player_position() - global_position).normalized()
	if dir == Vector2.ZERO:
		return
	BulletPool.fire(global_position, dir, bullet_damage, bullet_speed, true)
