extends Control
signal dismissed()
const Ui = preload("res://scripts/ui/launch/ui_theme.gd")

func _ready() -> void:
	$Card.add_theme_stylebox_override("panel", Ui.box(Ui.CREAM, Ui.WHITE, 30, 14, 5))
	Ui.apply_label($Title, 27, Ui.INK)
	Ui.apply_label($Message, 17, Ui.INK)
	$Message.position.y = 285
	$Message.size.y = 135
	Ui.apply_button($Close, Ui.PEACH, Ui.CORAL, 21, 20)
	$Close.pressed.connect(hide_dialog)

func show_info(title_text: String, message_text: String) -> void:
	$Title.text = title_text
	$Message.text = message_text
	show()
	$Close.grab_focus()

func hide_dialog() -> void:
	hide()
	dismissed.emit()
