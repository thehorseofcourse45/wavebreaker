extends Control
class_name ShopIcon
## One 20x20 line icon per shop row, drawn from a tiny shape set -- no art
## files (house rule: all art is _draw()). The shape + colour come from the
## row's DEFS "icon" entry; an unknown shape falls back to a hollow square.

const SIZE := 20.0

var _shape: String = "default"
var _color: Color = Color.WHITE


func setup(shape: String, color_hex: String) -> void:
	_shape = shape
	_color = Color.from_string(color_hex, Color.WHITE)
	custom_minimum_size = Vector2(SIZE, SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	queue_redraw()


func _draw() -> void:
	var c := Color(_color, 0.95)
	var mid := Vector2(SIZE * 0.5, SIZE * 0.5)
	match _shape:
		"chevron":
			draw_polyline(PackedVector2Array([Vector2(5, 4), Vector2(14, 10), Vector2(5, 16)]), c, 2.0, true)
		"bolt":
			draw_polyline(PackedVector2Array([Vector2(12, 2), Vector2(7, 10), Vector2(13, 10), Vector2(8, 18)]), c, 2.0, true)
		"ring":
			draw_arc(mid, 7.0, 0.0, TAU, 24, c, 2.0, true)
		"hex":
			var pts := PackedVector2Array()
			for i: int in 6:
				pts.append(mid + Vector2.RIGHT.rotated(TAU * float(i) / 6.0 - PI / 6.0) * 8.0)
			pts.append(pts[0])
			draw_polyline(pts, c, 2.0, true)
		"cross":
			draw_line(Vector2(10, 4), Vector2(10, 16), c, 2.5, true)
			draw_line(Vector2(4, 10), Vector2(16, 10), c, 2.5, true)
		"drop":
			draw_colored_polygon(PackedVector2Array([Vector2(10, 3), Vector2(15, 11), Vector2(10, 17), Vector2(5, 11)]), c)
		"wing":
			draw_polyline(PackedVector2Array([Vector2(3, 15), Vector2(8, 8), Vector2(12, 12), Vector2(17, 5)]), c, 2.0, true)
		"spark":
			draw_line(Vector2(10, 3), Vector2(10, 17), c, 2.0, true)
			draw_line(Vector2(4, 7), Vector2(16, 13), c, 2.0, true)
			draw_line(Vector2(4, 13), Vector2(16, 7), c, 2.0, true)
		"skull":
			draw_arc(mid + Vector2(0, -1), 6.0, 0.0, TAU, 20, c, 2.0, true)
			draw_circle(Vector2(7.5, 9), 1.6, c)
			draw_circle(Vector2(12.5, 9), 1.6, c)
		_:
			draw_rect(Rect2(5, 5, 10, 10), c, false, 2.0)
