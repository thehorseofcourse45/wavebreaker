extends EnemyBase
class_name EnemySplitter
## Midsize blob that splits into two mini chasers on death.
## WaveManager listens for `split_spawned` and re-parents the pair so they
## count toward the wave's alive total (and must die for the wave to clear).

signal split_spawned(pair: Array)

@export_group("Splitter")
@export var mini_scene: PackedScene = preload("res://scenes/enemy_mini.tscn")
@export var split_count: int = 2
@export var split_spread_px: float = 26.0


func _die() -> void:
	if is_dead:
		return
	# Spawn before super._die() clears collision / emits died -- the pair reads
	# our position. Done as a signal so Main/WaveManager own the re-parenting.
	var pair: Array = []
	for i: int in split_count:
		var mini: EnemyBase = mini_scene.instantiate() as EnemyBase
		if mini == null:
			push_warning("EnemySplitter: mini_scene failed to instantiate.")
			continue
		mini.global_position = global_position + Vector2.RIGHT.rotated(TAU * float(i) / float(split_count)) * split_spread_px
		pair.append(mini)
	if not pair.is_empty():
		split_spawned.emit(pair)
	super._die()
