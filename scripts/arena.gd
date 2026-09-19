extends Node2D
## Arena root: bakes the NavigationRegion2D's polygon at startup so enemies
## can path AROUND walls/obstacles instead of beelining through them.
## Without this the nav poly is empty, is_target_reachable() is false, and
## every enemy in the game silently falls back to straight-line steering.

@export var agent_radius: float = 18.0   # matches ~largest enemy collision radius

@export_group("Unlockable look")
## Unlockable id whose earned state recolours this arena's backdrop ("" = this
## arena is never recoloured). Only arena 1 sets it: the deep arena is already
## crimson and its palette is its own.
@export var recolor_unlock: String = ""
@export var recolor_base: Color = Color(0.11, 0.045, 0.06)
@export var recolor_grid: Color = Color(0.78, 0.24, 0.28)

## Half extents of the playfield interior, measured to the walls' inner face.
## MUST match scenes/arena.tscn (wall bodies at +/-810 x, +/-610 y, 20 thick).
const ARENA_HALF := Vector2(800.0, 600.0)

@onready var _nav_region: NavigationRegion2D = $NavRegion


func _ready() -> void:
	_apply_unlockable_backdrop()
	_setup_lighting()
	var art := preload("res://scripts/retro_arena_art.gd").new()
	art.name = "RetroArenaArt"
	add_child(art)
	var backdrop := get_node_or_null("Backdrop") as ColorRect
	if backdrop != null and backdrop.material is ShaderMaterial:
		var material_copy := backdrop.material.duplicate() as ShaderMaterial
		backdrop.material = material_copy
		material_copy.set_shader_parameter("scan_alpha", 0.006)
		material_copy.set_shader_parameter("grid_alpha", 0.17)
		material_copy.set_shader_parameter("grid_width", 1.0)
		if recolor_unlock != "" and not Unlockables.is_unlocked(recolor_unlock):
			material_copy.set_shader_parameter("base_color", Color("#100d20"))
			material_copy.set_shader_parameter("grid_color", Color("#69499e"))
	call_deferred("_bake_navmesh")   # deferred: all children exist by then


## Lit lighting pass: one darkness for the room, an occluder mirrored from every wall
## and obstacle's own collision rectangle, and the receiver material on the visuals --
## so the walls both block the player's torch and are shaded by it. The arena's
## BACKDROP and FLOOR are deliberately left out: they are the ambient background (a
## shader grid and a flat colour), and making them receivers would shade the grid away.
func _setup_lighting() -> void:
	if not LitLighting.available():
		push_warning("[Arena] the Lit addon is missing -- playing unlit.")
		return
	LitLighting.darken(self)
	var occluders: int = LitLighting.add_room_occluders(self)
	for wall: Node in get_children():
		var body := wall as StaticBody2D
		if body == null:
			continue
		for child: Node in body.get_children():
			var item := child as CanvasItem
			if item != null:
				LitLighting.make_receiver(item)
	print("[Arena] Lit: %d occluders, ambient %s." % [occluders, str(LitLighting.ARENA_DARKNESS)])


## Cosmetic: the backdrop is one ColorRect with a shader, so recolouring the arena
## is two uniforms -- no second material, no second scene. The material belongs to
## this scene, so this never touches the other arena.
func _apply_unlockable_backdrop() -> void:
	if recolor_unlock == "" or not Unlockables.is_unlocked(recolor_unlock):
		return
	var backdrop: CanvasItem = get_node_or_null("Backdrop") as CanvasItem
	if backdrop == null:
		return
	var mat: ShaderMaterial = backdrop.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("base_color", recolor_base)
	mat.set_shader_parameter("grid_color", recolor_grid)


func _bake_navmesh() -> void:
	await get_tree().physics_frame   # let NavigationRegion2D register its map
	var poly: NavigationPolygon = _nav_region.navigation_polygon
	if poly == null:
		return
	# Offline-bake mode: parse + bake + SAVE the polygon as a .tres so the game
	# never needs to rebuild it at runtime. Trigger with  --  BAKE_NAVMESH  --.
	if "BAKE_NAVMESH" in OS.get_cmdline_args():
		var inset: float = agent_radius + 12.0
		var w: float = ARENA_HALF.x - inset
		var h: float = ARENA_HALF.y - inset
		poly.clear_outlines()
		poly.add_outline(PackedVector2Array([
			Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)]))
		poly.parsed_collision_mask = 8
		poly.agent_radius = agent_radius
		var src := NavigationMeshSourceGeometryData2D.new()
		NavigationServer2D.parse_source_geometry_data(poly, src, self)
		NavigationServer2D.bake_from_source_geometry_data(poly, src)
		print("[Arena] offline bake: %d polygons." % poly.get_polygon_count())
		var save_path: String = get_scene_file_path().get_basename() + "_navpoly.tres"
		ResourceSaver.save(poly, save_path)
		print("[Arena] navmesh saved to %s" % save_path)
		get_tree().quit(0)
		return
	# Runtime: the polygon was pre-baked into arena_navpoly.tres (see
	# scripts/_bake_once.gd). Just force the map to refresh with it.
	NavigationServer2D.map_force_update(get_world_2d().navigation_map)
	print("[Arena] Navmesh loaded: %d polygons." % poly.get_polygon_count())
