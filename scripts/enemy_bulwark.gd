extends EnemyBase
class_name EnemyBulwark
## Slow armoured carrier that projects a damage-reduction aura onto every
## nearby enemy (not itself: it is already the tanky one). The aura is one
## write per frame through the shared take_damage() path -- `damage_taken_mult`
## on EnemyBase -- so mitigation has exactly one owner and the aura never
## reimplements damage.
##
## ponytail: the aura is recomputed per physics frame over the enemies group
## (O(n) per bulwark); if hundreds of enemies ever field, fold this into the
## separation pass that already walks the same group.

@export_group("Bulwark")
@export var aura_radius: float = 170.0
@export var aura_mult: float = 0.55

## Enemies currently holding this bulwark's mult, so it can be taken away again
## when they walk out of range -- and when the bulwark dies (_exit_tree).
var _aided: Array[EnemyBase] = []


func _update_behavior(_delta: float) -> void:
	var still_aided: Array[EnemyBase] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var other := node as EnemyBase
		if other == null or other == self or not is_instance_valid(other):
			continue
		if global_position.distance_to(other.global_position) <= aura_radius:
			# min, not overwrite: with two bulwarks overlapping, the stronger
			# aura must never be pushed back up by the weaker one.
			other.damage_taken_mult = minf(other.damage_taken_mult, aura_mult)
			still_aided.append(other)
	for prev: EnemyBase in _aided:
		# Clearing can transiently clobber a second bulwark's grant for one
		# frame; that bulwark re-applies on its own next tick.
		if is_instance_valid(prev) and not still_aided.has(prev):
			prev.damage_taken_mult = 1.0
	_aided = still_aided


func _exit_tree() -> void:
	# Death and arena switches free the bulwark mid-coverage: the aura must not
	# outlive the body that casts it.
	for prev: EnemyBase in _aided:
		if is_instance_valid(prev):
			prev.damage_taken_mult = 1.0
	_aided.clear()
