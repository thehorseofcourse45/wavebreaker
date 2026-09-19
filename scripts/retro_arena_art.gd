extends Node2D
## Static vector detailing, rebuilt with each arena. No collision or gameplay state.
const CYAN := Color("#39e8ef")
const PINK := Color("#ff4ca5")

func _ready() -> void:
	z_index = 1

func _draw() -> void:
	# Quiet central launch pad and inset perimeter.
	draw_arc(Vector2.ZERO, 108, 0, TAU, 96, Color(0.22, 0.7, 0.8, 0.18), 1.0, true)
	draw_arc(Vector2.ZERO, 116, 0, TAU, 96, Color(0.5, 0.2, 0.7, 0.16), 2.0, true)
	for i in range(12):
		var a := float(i) * TAU / 12.0
		draw_line(Vector2.from_angle(a) * 124, Vector2.from_angle(a) * 134, Color(0.3, 0.8, 0.9, 0.25), 2.0, true)
	draw_rect(Rect2(-780, -580, 1560, 1160), Color(0.6, 0.13, 0.48, 0.35), false, 2.0)
	for body: Node in get_parent().get_children():
		if not body is StaticBody2D:
			continue
		for child: Node in body.get_children():
			if not child is CollisionShape2D or not child.shape is RectangleShape2D:
				continue
			var extent: Vector2 = child.shape.size * 0.5
			var accent: Color = CYAN if body.position.y < 0 else PINK
			draw_set_transform(body.position, body.rotation)
			var box := Rect2(-extent, extent * 2.0)
			draw_rect(box.grow(4), Color(accent, 0.055), false, 10.0)
			draw_rect(box, Color("#181329"), true)
			draw_rect(box, Color(accent, 0.7), false, 1.4, true)
			draw_rect(box.grow(-4), Color("#322743"), false, 1.0)
			var horizontal: bool = extent.x > extent.y
			var length_axis: float = extent.x if horizontal else extent.y
			for sign_value in [-1.0, 1.0]:
				var point := Vector2(sign_value * (length_axis - 12), 0) if horizontal else Vector2(0, sign_value * (length_axis - 12))
				var across := Vector2(0, extent.y - 3) if horizontal else Vector2(extent.x - 3, 0)
				draw_line(point - across, point + across, accent, 3.0, true)
			# Machined vent marks, kept inside the solid silhouette.
			for index in range(-2, 3):
				var p := Vector2(float(index) * 10, 0) if horizontal else Vector2(0, float(index) * 10)
				var v := Vector2(3, 5) if horizontal else Vector2(5, 3)
				draw_line(p - v, p + v, Color(accent, 0.23), 1.0, true)
			break
	draw_set_transform(Vector2.ZERO)
	for marker: Node in get_parent().get_children():
		if marker is Marker2D and marker.is_in_group("spawn_points"):
			draw_arc(marker.position, 27, 0, TAU, 32, Color(PINK, 0.25), 1.0, true)
			draw_arc(marker.position, 32, 0.2, 1.2, 16, Color(PINK, 0.5), 2.0, true)
