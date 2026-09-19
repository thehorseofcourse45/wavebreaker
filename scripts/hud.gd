extends CanvasLayer
class_name Hud
## In-game HUD. Pure view: Main pushes values in via setters; it never pulls
## node references from gameplay systems.

## Health ratio at or below which the bar starts pulsing, so the player notices
## they are about to die without reading a number.
const LOW_HEALTH_RATIO := 0.25
## Dash pip colours: bright teal = panic button live, dark violet = recharging.
const DASH_READY_COLOR := Color("#46e6de")
const DASH_COOLING_COLOR := Color(0.32, 0.27, 0.42)

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _wave_label: Label = %WaveLabel
@onready var _enemies_label: Label = %EnemiesLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _credits_label: Label = %CreditsLabel
## Screen-edge warning for low health, sharing the arena backdrop shader with
## `overlay = 1` (only the edges tint). The bar alone is easy to miss while the
## player is looking at the middle of the arena.
@onready var _low_health: ColorRect = $LowHealth
## Dash readiness pip, built in _ready beside the health bar.
var _dash_pip: ColorRect = null

var _pulse_phase: float = 0.0
## Heartbeat timing: a short beat that re-fires sooner as more health is missing.
var _heartbeat_timer: float = 0.0
const HEARTBEAT_INTERVAL := 0.8
## The fastest the beat gets (at near-zero health); never zero, or it would fire
## every frame.
const HEARTBEAT_MIN_INTERVAL := 0.22


func _process(delta: float) -> void:
	_pulse_phase += delta * 7.0
	var ratio: float = 1.0
	if _health_bar.max_value > 0.0:
		ratio = _health_bar.value / _health_bar.max_value
	if ratio > LOW_HEALTH_RATIO:
		_health_bar.modulate = Color.WHITE
		_low_health.visible = false
		_heartbeat_timer = 0.0   # full: the next low-health stretch starts fresh
		return
	var k: float = 0.5 + 0.5 * absf(sin(_pulse_phase))
	_health_bar.modulate = Color(1.0, 0.25 + 0.35 * k, 0.25 + 0.35 * k)
	_low_health.visible = true
	_low_health.modulate.a = 0.45 + 0.45 * k
	# Heartbeat: only while low. The interval shrinks with the missing fraction,
	# so a nearly-dead player hears it faster.
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		var missing: float = clampf(1.0 - ratio, 0.0, 1.0)
		AudioManager.play_heartbeat(missing)
		_heartbeat_timer = maxf(HEARTBEAT_MIN_INTERVAL, HEARTBEAT_INTERVAL * (1.0 - 0.65 * missing))


func reset(max_hp: int, score: int) -> void:
	_health_bar.max_value = max_hp
	_health_bar.value = max_hp
	_health_bar.modulate = Color.WHITE
	_low_health.visible = false
	set_health(max_hp, max_hp)
	set_score(score)
	set_credits(0)
	set_wave(0)
	set_remaining(0)


func set_health(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "%d / %d" % [current, maximum]


func set_wave(wave_number: int) -> void:
	_wave_label.text = "WAVE %d" % wave_number if wave_number > 0 else "WAVE --"


func set_remaining(remaining: int) -> void:
	_enemies_label.text = "ENEMIES: %d" % remaining


func set_score(score: int) -> void:
	_score_label.text = "SCORE: %d" % score


func set_credits(credits: int) -> void:
	_credits_label.text = "CREDITS: %d" % credits

## Dash readiness, 0 = just spent, 1 = ready again. Main pushes this every
## frame while the run is live.
func set_dash_ratio(ready: float) -> void:
	if _dash_pip != null:
		_dash_pip.modulate = DASH_COOLING_COLOR.lerp(DASH_READY_COLOR, clampf(ready, 0.0, 1.0))

func _ready() -> void:
	var left: PanelContainer = $PanelRoot
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dash pip: one thin bar under the health bar, tinted by set_dash_ratio.
	var dash_pip := ColorRect.new()
	dash_pip.name = "DashPip"
	dash_pip.custom_minimum_size = Vector2(240, 5)
	dash_pip.color = Color.WHITE
	dash_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dash_pip.modulate = DASH_READY_COLOR
	($PanelRoot/Panel as Control).add_child(dash_pip)
	($PanelRoot/Panel as Control).move_child(dash_pip, 1)
	_dash_pip = dash_pip
	var center := PanelContainer.new()
	center.name = "WaveReadout"
	add_child(center)
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.offset_left = -100
	center.offset_right = 100
	center.offset_top = 16
	var right := PanelContainer.new()
	right.name = "ScoreReadout"
	add_child(right)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -246
	right.offset_right = -18
	right.offset_top = 16
	var wave_column := VBoxContainer.new()
	center.add_child(wave_column)
	var score_column := VBoxContainer.new()
	right.add_child(score_column)
	_wave_label.reparent(wave_column)
	_enemies_label.reparent(wave_column)
	_score_label.reparent(score_column)
	_credits_label.reparent(score_column)
	for panel: PanelContainer in [left, center, right]:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.045, 0.03, 0.08, 0.92)
		style.border_color = Color("#68517f")
		style.border_width_bottom = 2
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", style)
	for label: Label in [_health_label, _wave_label, _enemies_label, _score_label, _credits_label]:
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color("#e7def4"))
	_wave_label.add_theme_font_size_override("font_size", 24)
	_wave_label.add_theme_color_override("font_color", Color("#ff71bb"))
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemies_label.add_theme_font_size_override("font_size", 12)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credits_label.add_theme_color_override("font_color", Color("#ffcc81"))
	_health_bar.custom_minimum_size = Vector2(200, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#46e6de")
	_health_bar.add_theme_stylebox_override("fill", fill)
