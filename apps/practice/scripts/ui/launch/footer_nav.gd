extends Control
signal news_requested()
signal guide_requested()
signal register_requested()
signal exit_requested()
signal change_password_requested()
const Ui = preload("res://scripts/ui/launch/ui_theme.gd")

func _ready() -> void:
	var change := Button.new()
	change.name = "ChangePassword"
	change.text = "ĐỔI MẬT KHẨU"
	add_child(change)
	move_child(change, $Exit.get_index())
	# Five buttons now: re-space them and stay centred on the 1280-wide canvas.
	var buttons := [$News, $Guide, $Register, change, $Exit]
	var width := 150.0
	var gap := 10.0
	var total := buttons.size() * width + (buttons.size() - 1) * gap
	position.x = (1280.0 - total) / 2.0
	size.x = total
	for i in buttons.size():
		buttons[i].position = Vector2(i * (width + gap), 0)
		buttons[i].size = Vector2(width, 44)
	change.pressed.connect(func(): change_password_requested.emit())
	for button in buttons:
		Ui.apply_button(button, Color("#FFFFFF"), Color("#C3ECED"), 16, 17)
	$News.pressed.connect(func(): news_requested.emit())
	$Guide.pressed.connect(func(): guide_requested.emit())
	$Register.pressed.connect(func(): register_requested.emit())
	$Exit.pressed.connect(func(): exit_requested.emit())
