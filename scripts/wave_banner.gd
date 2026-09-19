extends CanvasLayer
class_name WaveBanner
## Big center-screen banner ("WAVE 3", "WAVE 3 CLEARED", "UNLOCKED: ..."). Fades
## in, holds, fades out -- driven by a tween so overlapping calls restart cleanly.

## Unlockable "streak_banners": streak callouts get their own colour instead of
## the plain white every other callout uses.
const STREAK_COLOR := Color(1.0, 0.55, 0.22)

@export var hold_time: float = 1.2
@export var fade_time: float = 0.4

@onready var _label: Label = $Center/BannerLabel

var _tween: Tween = null


func _ready() -> void:
	visible = false


func show_banner(text: String) -> void:
	_label.text = text
	visible = true
	# RGB is set per call and the tween only animates alpha, so a coloured banner
	# fades exactly like a white one.
	var tint: Color = Color.WHITE
	if text.begins_with("STREAK") and Unlockables.is_unlocked("streak_banners"):
		tint = STREAK_COLOR
	_label.modulate = Color(tint, 0.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, fade_time)
	_tween.tween_interval(hold_time)
	_tween.tween_property(_label, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(hide)
