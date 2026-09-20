extends EnemyBase
class_name EnemyElite
## Chaser variant with a shield phase: invulnerable while `shielded`, drops
## it periodically. Reads via tint swap on Body (shield = cyan glow).

@export_group("Elite")
@export var shield_up_time: float = 2.2
@export var shield_down_time: float = 1.4

var _shielded: bool = true
var _shield_timer: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("elites")   # Main counts elite kills for the unlockables
	_shield_timer = shield_up_time
	_apply_tint()


func _update_behavior(delta: float) -> void:
	_shield_timer -= delta
	if _shield_timer <= 0.0:
		_shielded = not _shielded
		_shield_timer = shield_up_time if _shielded else shield_down_time
		_apply_tint()


func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> int:
	if _shielded:
		return 0  # bullet still deactivates on contact; no damage is dealt
	return super.take_damage(amount, knockback)


func _apply_tint() -> void:
	if is_instance_valid(_body):
		# Only the base colour is owned here: EnemyBase applies it (and swaps in
		# the white hit flash for a few frames without losing the shield tint).
		_base_color = Color(0.4, 0.9, 1.0) if _shielded else Color(0.9, 0.3, 0.5)
		_body.color = _base_color
