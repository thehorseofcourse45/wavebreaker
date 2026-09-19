extends RefCounted
class_name LitLighting
## The one place that knows about the Lit addon (res://addons/lit).
##
## Lit lights nothing by itself. An object answers to its lights only if its
## `material` is one of the addon's receiver shaders, and the ambient darkness comes
## from a `LitCanvasModulate` (NOT Godot's CanvasModulate -- the addon's shaders
## ignore that one, and having both double-darkens). Everything here is the
## hand-written equivalent of the editor's "Make Selected Nodes Lit" tool: the tool
## creates exactly this material (`receiver_materials.gd::fresh_material`), and a
## ColorRect/Polygon2D has none of the Lit exports to sync onto it.
##
## Lights are plain group members ("lit_lights") gathered by the LitManager autoload
## every frame, so adding one is just adding the node.

## ENTRY_PATHS[0] -- the fastest receiver variant (no self-exclusion march). Correct
## for everything here: an occluder is a SIBLING LightOccluder2D, never owned by the
## receiver, so no receiver ever has to subtract its own shadow.
const RECEIVER_SHADER := "res://addons/lit/shaders/receiver/lit_receiver_fast.gdshader"
## The arena's ambient. Dark enough that the player's torch reads, bright enough that
## an enemy walking in at the edge of the light is still a shape rather than a hole.
## Halved twice from (0.15, 0.16, 0.23): the lit room read as too bright against the
## backdrop's near-black grid. Tinted cool rather than neutral so the ambient reads as
## neon dark, matching the player's cyan light and the crimson grid.
const ARENA_DARKNESS := Color(0.03, 0.042, 0.07)
const DARKNESS_NODE := "LitDarkness"

## Lit: occluders are inset by this many pixels from the rectangle they mirror.
## A wall's VISIBLE face is the same rectangle as its silhouette, so a full-size
## occluder sits exactly on the surface it blocks: the wall's own lit face is then
## coplanar with its own shadow caster and the whole arena renders as if unlit (every
## receiver self-shadowed). Insetting puts the solid core behind every visible face, so
## surfaces are lit while the wall still casts a shadow -- 8 px late, at this scale
## invisible.
const OCCLUDER_INSET := 8.0

static var _receiver_material: ShaderMaterial = null


## Is the addon present? Only the SHADER path is checked: the Lit* classes are
## referenced by name in this file, so a project that lost the whole addon folder would
## fail to compile this script at all -- what this catches is an export that packed the
## scripts but stripped the shaders.
static func available() -> bool:
	return ResourceLoader.exists(RECEIVER_SHADER)


## The shared receiver material. One instance for every node: the driver collects
## receivers BY MATERIAL, and shared materials are the cheap case (a material only has
## to be unique per node when that node owns its own occluder).
static func receiver_material() -> ShaderMaterial:
	if _receiver_material == null:
		_receiver_material = ShaderMaterial.new()
		_receiver_material.shader = load(RECEIVER_SHADER)
	return _receiver_material


## Make an existing 2D node answer to Lit lights.
##
## A node carrying a deliberately unlit material (additive/blend, i.e. the bullets and
## hit effects from the visual pass) is LEFT ALONE: those are meant to compose on top
## of the lighting as glow, not be shaded by it. Returns whether it converted.
static func make_receiver(item: CanvasItem) -> bool:
	if item == null:
		return false
	var existing: Material = item.material
	if existing is CanvasItemMaterial and (existing as CanvasItemMaterial).blend_mode != CanvasItemMaterial.BLEND_MODE_MIX:
		return false
	if existing == receiver_material():
		return true
	item.material = receiver_material()
	return true


## Every CanvasItem in a subtree that draws the walls/floor of a room: the callers use
## this to convert a room without naming each visual node.
static func make_subtree_receivers(root: Node) -> int:
	var converted: int = 0
	for child: Node in root.get_children():
		var item: CanvasItem = child as CanvasItem
		if item != null and make_receiver(item):
			converted += 1
		converted += make_subtree_receivers(child)
	return converted


## The scene's ambient darkness. Idempotent: re-entering an arena reuses the node it
## found instead of stacking a second LitCanvasModulate (the last one in the tree wins,
## so two of them would silently fight).
static func darken(parent: Node, color: Color = ARENA_DARKNESS) -> LitCanvasModulate:
	var existing: Node = parent.get_node_or_null(DARKNESS_NODE)
	if existing is LitCanvasModulate:
		var lit_dark := existing as LitCanvasModulate
		lit_dark.color = color
		return lit_dark
	var created := LitCanvasModulate.new()
	created.name = DARKNESS_NODE
	created.color = color
	parent.add_child(created)
	return created


## A point light parented to `parent` (so it follows it). `shadows` turns on shadow
## casting -- the light then needs occluders, which `add_box_occluder` supplies.
static func add_point_light(parent: Node, light_color: Color, radius: float,
		energy: float = 1.0, shadows: bool = false, height: float = 170.0) -> LitPointLight2D:
	var light := LitPointLight2D.new()
	light.color = light_color
	light.energy = energy
	# `range` is a built-in GDScript function name, so the property is set by name.
	light.set("range", radius)
	# Height above the surface drives the shading angle: a light sitting on the floor
	# (the addon default of 16 px) only grazes distant walls, so a room-wide torch
	# reads as a small puddle. A hanging height lights the room instead.
	light.set("height", height)
	light.shadow_enabled = shadows
	parent.add_child(light)
	return light


## A light-blocking box, in the parent's LOCAL space. The arenas describe their walls
## and obstacles as RectangleShape2Ds, so an occluder is that rectangle turned into a
## polygon -- no polygon authoring per scene, and the three arenas get shadows for free.
## Inset by OCCLUDER_INSET: see the constant's note on coplanar self-shadowing.
static func add_box_occluder(parent: Node2D, half_extents: Vector2) -> LightOccluder2D:
	var he := Vector2(
		maxf(half_extents.x - OCCLUDER_INSET, 1.0),
		maxf(half_extents.y - OCCLUDER_INSET, 1.0))
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-he.x, -he.y),
		Vector2(he.x, -he.y),
		Vector2(he.x, he.y),
		Vector2(-he.x, he.y),
	])
	var occluder := LightOccluder2D.new()
	occluder.occluder = poly
	parent.add_child(occluder)
	return occluder


## Give every rectangle-shaped StaticBody2D in `room` a matching occluder, so walls and
## obstacles cast shadows. Returns how many were added (the suite asserts it is not 0:
## a room with no occluders has a light that silently casts nothing).
static func add_room_occluders(room: Node) -> int:
	var added: int = 0
	for body: Node in room.get_children():
		var body_2d := body as StaticBody2D
		if body_2d == null or body_2d.has_node("LitOccluder"):
			continue
		for child: Node in body_2d.get_children():
			var collider := child as CollisionShape2D
			if collider == null:
				continue
			var shape := collider.shape
			if shape is RectangleShape2D:
				var occluder := add_box_occluder(body_2d, (shape as RectangleShape2D).size * 0.5)
				occluder.name = "LitOccluder"
				added += 1
			elif shape is CircleShape2D:
				var radius: float = (shape as CircleShape2D).radius
				var occluder := add_box_occluder(body_2d, Vector2(radius, radius))
				occluder.name = "LitOccluder"
				added += 1
			break
	return added
