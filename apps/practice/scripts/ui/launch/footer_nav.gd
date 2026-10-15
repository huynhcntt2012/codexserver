extends Control
signal news_requested()
signal guide_requested()
signal register_requested()
signal exit_requested()
const Ui = preload("res://scripts/ui/launch/ui_theme.gd")

func _ready() -> void:
	for button in [$News, $Guide, $Register, $Exit]:
		Ui.apply_button(button, Color("#FFFFFF"), Color("#C3ECED"), 16, 17)
	$News.pressed.connect(func(): news_requested.emit())
	$Guide.pressed.connect(func(): guide_requested.emit())
	$Register.pressed.connect(func(): register_requested.emit())
	$Exit.pressed.connect(func(): exit_requested.emit())
