extends Control
class_name RetroMenuArt
## Resolution-independent vector poster behind the existing menu controls.
## CARD_TITLE is what the menu card actually shows: the game's name is drawn into the
## poster above it (see _draw), so the card is a call to action, not the title.
const CARD_TITLE := "ENTER THE ARENA"
## Poster title: one big line when the name fits the 570 px column, wrapped when it does
## not. The name itself has one source -- project.godot's config/name (which also sets the
## window title).
const TITLE_SIZE := 56
const TITLE_MAX_CHARS := 12
var _font: Font = ThemeDB.fallback_font


## The game's name laid out for the poster, upper-cased and wrapped at spaces so no line
## runs past TITLE_MAX_CHARS. Extracted from _draw so it can be asserted.
static func title_lines(raw: String) -> PackedStringArray:
	var title := raw.strip_edges().to_upper()
	if title.length() <= TITLE_MAX_CHARS:
		return PackedStringArray([title])
	var lines := PackedStringArray()
	var current := ""
	for word: String in title.split(" ", false):
		if current == "":
			current = word
		elif (current + " " + word).length() <= TITLE_MAX_CHARS:
			current += " " + word
		else:
			lines.append(current)
			current = word
	if current != "":
		lines.append(current)
	return lines

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	call_deferred("_style_console")

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(1280, 720))
	draw_rect(Rect2(0, 0, 1280, 720), Color("#0b0919"))
	# Broad, soft sunset atmosphere.
	for i in range(32, 0, -1):
		draw_circle(Vector2(318, 342), 150 + i * 5, Color(0.5, 0.05, 0.35, 0.006))
	# Striped sunset, gold at the crown through electric pink at the horizon.
	for y in range(-126, 127, 2):
		if y > 4 and posmod(y, 18) > 10:
			continue
		var half_width := sqrt(maxf(0, 126.0 * 126.0 - float(y * y)))
		var tint := Color("#ffc16b").lerp(Color("#ff369c"), float(y + 126) / 252.0)
		draw_line(Vector2(318 - half_width, 332 + y), Vector2(318 + half_width, 332 + y), tint, 2.0)
	var mountains := PackedVector2Array([Vector2(0, 470), Vector2(0, 387), Vector2(70, 425), Vector2(142, 360), Vector2(212, 414), Vector2(280, 395), Vector2(345, 430), Vector2(448, 369), Vector2(524, 420), Vector2(650, 383), Vector2(650, 470)])
	draw_colored_polygon(mountains, Color("#100d24"))
	draw_polyline(PackedVector2Array([Vector2(0, 387), Vector2(70, 425), Vector2(142, 360), Vector2(212, 414), Vector2(280, 395), Vector2(345, 430), Vector2(448, 369), Vector2(524, 420), Vector2(650, 383)]), Color("#784b93"), 1.0, true)
	for i in range(-10, 11):
		draw_line(Vector2(318 + i * 24, 470), Vector2(318 + i * 140, 720), Color(0.22, 0.66, 0.83, 0.3), 1.0, true)
	for y in [470, 482, 499, 523, 557, 604, 668]:
		draw_line(Vector2(0, y), Vector2(650, y), Color(0.4, 0.25, 0.75, 0.45), 1.0, true)
	draw_line(Vector2(0, 469), Vector2(650, 469), Color("#ec409a"), 2.0)
	# Right-hand console sits on clean negative space.
	draw_rect(Rect2(660, 0, 620, 720), Color("#0b0a18"))
	draw_line(Vector2(660, 44), Vector2(660, 676), Color("#35233f"), 1.0)
	draw_line(Vector2(660, 44), Vector2(660, 130), Color("#ff4ca5"), 3.0)
	draw_string(_font, Vector2(58, 65), "N E O N   /   S U R V I V A L", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#55e5eb"))
	var title := String(ProjectSettings.get_setting("application/config/name", "WAVEBREAKER"))
	var baseline := 137.0
	for line: String in title_lines(title):
		draw_string(_font, Vector2(54, baseline), line, HORIZONTAL_ALIGNMENT_LEFT, 570, TITLE_SIZE, Color("#f3eaff"))
		baseline += TITLE_SIZE * 1.05
	draw_string(_font, Vector2(58, 641), "OUTLAST THE NIGHT.", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#f3eaff"))
	draw_string(_font, Vector2(58, 670), "ONE ARENA. ENDLESS WAVES.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9f91b8"))
	draw_string(_font, Vector2(720, 57), "A R C A D E   S Y S T E M   /   0 1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#827794"))

func _style_console() -> void:
	var menu: CanvasLayer = get_parent()
	menu.move_child(self, 1)
	menu.get_node("Dim").color = Color("#0b0919")
	var center: CenterContainer = menu.get_node("Center")
	center.anchor_left = 0.54
	center.anchor_right = 0.99
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#110d1b")
	panel.border_color = Color("#513451")
	panel.set_border_width_all(1)
	panel.border_width_top = 3
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		panel.set_content_margin(side, 22)
	menu.get_node("Center/Card").add_theme_stylebox_override("panel", panel)
	for side in ["left", "right", "top", "bottom"]:
		menu.get_node("Center/Card/Margin").add_theme_constant_override("margin_" + side, 8)
	var column: VBoxContainer = menu.get_node("Center/Card/Margin/Column")
	column.add_theme_constant_override("separation", 10)
	var title: Label = column.get_node("Title")
	title.text = CARD_TITLE
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#f4eaff"))
	var subtitle: Label = column.get_node("Subtitle")
	subtitle.text = "SURVIVE  /  UPGRADE  /  REPEAT"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.modulate = Color("#a59ab8")
	var start: Button = column.get_node("StartButton")
	start.text = "DEPLOY   /   ENTER"
	start.add_theme_font_size_override("font_size", 21)
	var primary := StyleBoxFlat.new()
	primary.bg_color = Color("#86295f")
	primary.border_color = Color("#ff63ba")
	primary.set_border_width_all(1)
	primary.content_margin_top = 12
	primary.content_margin_bottom = 12
	start.add_theme_stylebox_override("normal", primary)
	var hover := primary.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#b3357e")
	start.add_theme_stylebox_override("hover", hover)
	start.add_theme_stylebox_override("pressed", hover)
	column.get_node("EndlessCheck").add_theme_font_size_override("font_size", 14)
	for row in ["Music", "Sfx"]:
		column.get_node("Audio/" + row + "Row/" + row + "Slider").custom_minimum_size.x = 240
		var label: Label = column.get_node("Audio/" + row + "Row/" + row + "Label")
		label.custom_minimum_size.x = 80
		label.add_theme_font_size_override("font_size", 13)
	var controls: Label = column.get_node("Controls")
	controls.text = "WASD  MOVE    /    MOUSE  AIM\nLMB  FIRE    /    RMB  CHARGE    /    ESC  PAUSE"
	controls.add_theme_font_size_override("font_size", 11)
	controls.modulate = Color("#a59ab8")
	column.get_node("ResetButton").add_theme_font_size_override("font_size", 13)
	column.get_node("ResetButton").custom_minimum_size.y = 30
	column.get_node("ResetHint").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.get_node("BestLabel").add_theme_font_size_override("font_size", 15)
	column.get_node("KillsLabel").add_theme_font_size_override("font_size", 13)
