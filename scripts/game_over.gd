extends CanvasLayer
class_name GameOverScreen
## Game-over panel: final score + wave survived + the stored record, and a
## restart via button or the R key (Main handles the R key; this handles the
## button).

signal restart_pressed

@onready var _score_label: Label = $Center/Card/Margin/Column/ScoreLabel
@onready var _wave_label: Label = $Center/Card/Margin/Column/WaveLabel
@onready var _best_label: Label = $Center/Card/Margin/Column/BestLabel
@onready var _restart_button: Button = $Center/Card/Margin/Column/RestartButton


func _ready() -> void:
	visible = false
	_restart_button.pressed.connect(func() -> void: restart_pressed.emit())


## `record` is Storage.record_run()'s reply: best_score/best_wave/new_score/new_wave.
func show_game_over(score: int, wave_reached: int, record: Dictionary) -> void:
	_score_label.text = "SCORE: %d" % score
	_wave_label.text = "SURVIVED TO WAVE %d" % maxi(wave_reached, 1)
	var beat_score: bool = bool(record.get("new_score", false)) and score > 0
	var beat_wave: bool = bool(record.get("new_wave", false)) and wave_reached > 0
	var best_score: int = int(record.get("best_score", score))
	var best_wave: int = int(record.get("best_wave", maxi(wave_reached, 1)))
	if beat_score or beat_wave:
		_best_label.text = "NEW BEST!  %d - WAVE %d" % [best_score, best_wave]
		_best_label.modulate = Color(1.0, 0.82, 0.3)
	else:
		_best_label.text = "BEST: %d - WAVE %d" % [best_score, best_wave]
		_best_label.modulate = Color(1, 1, 1, 0.65)
	visible = true
	_restart_button.grab_focus()
