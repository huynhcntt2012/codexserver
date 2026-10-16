extends Control
## Shared popup for the login screen's password forms: cream card, hint line,
## stacked fields, an optional link row, then submit and cancel buttons.
const Ui = preload("res://scripts/ui/launch/ui_theme.gd")
const HINT := Color("#8B83A4")
var card := Panel.new()
var title := Label.new()
var message := Label.new()
var fields: Array[LineEdit] = []
var link := Button.new()
var submit_button := Button.new()
var cancel_button := Button.new()
var hint := ""
var submit_text := ""

## specs: [[name, placeholder, secret, max_length], ...]
func build(title_text: String, specs: Array, submit_label: String) -> void:
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.2, 0.36, 0.55)
	dim.size = size
	add_child(dim)
	card.add_theme_stylebox_override("panel", Ui.box(Ui.CREAM, Ui.WHITE, 30, 14, 5))
	add_child(card)
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(30, 22)
	title.size = Vector2(440, 40)
	Ui.apply_label(title, 27, Ui.INK)
	card.add_child(title)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.position = Vector2(34, 64)
	message.size = Vector2(432, 56)
	Ui.apply_label(message, 15, HINT)
	card.add_child(message)
	for i in specs.size():
		var field := LineEdit.new()
		field.name = specs[i][0]
		field.placeholder_text = specs[i][1]
		field.secret = specs[i][2]
		field.max_length = specs[i][3]
		field.size = Vector2(416, 46)
		Ui.apply_input(field, Color("#E0DDF1"), Ui.AQUA)
		field.text_submitted.connect(_advance.bind(field))
		card.add_child(field)
		fields.append(field)
	link.name = "Link"
	Ui.apply_link(link, Ui.AQUA_DARK, 15)
	link.hide()
	card.add_child(link)
	submit_text = submit_label
	submit_button.name = "Submit"
	submit_button.text = submit_label
	submit_button.size = Vector2(250, 58)
	Ui.apply_button(submit_button, Color("#FFC868"), Color("#F28B76"), 21, 24)
	submit_button.pressed.connect(submit)
	card.add_child(submit_button)
	cancel_button.name = "Cancel"
	cancel_button.text = "HỦY"
	cancel_button.size = Vector2(152, 58)
	Ui.apply_button(cancel_button, Color("#99E9DF"), Color("#36BAC5"), 19, 24)
	cancel_button.pressed.connect(close)
	card.add_child(cancel_button)
	layout()
	hide()

## Stacks the visible fields, the link if shown, then the buttons; the card
## grows to fit and stays centred.
func layout() -> void:
	var y := 128.0
	for field in fields:
		if field.visible:
			field.position = Vector2(42, y)
			y += 58
	if link.visible:
		link.position = Vector2(42, y - 6)
		link.size = Vector2(416, 30)
		y += 28
	y += 12
	submit_button.position = Vector2(42, y)
	cancel_button.position = Vector2(306, y)
	card.size = Vector2(500, y + 58 + 30)
	card.position = Vector2(390, (720 - card.size.y) / 2)

func set_hint(text: String) -> void:
	hint = text
	message.text = text
	message.add_theme_color_override("font_color", HINT)

func show_error(error: String) -> void:
	message.text = error
	message.add_theme_color_override("font_color", Ui.CORAL)

func _advance(_value: String, from: LineEdit) -> void:
	var after := false
	for field in fields:
		if after and field.visible and field.editable:
			field.grab_focus()
			return
		after = after or field == from
	submit()

func first_empty() -> LineEdit:
	for field in fields:
		if field.visible and field.text.is_empty():
			return field
	return fields[0]

func clear_secrets() -> void:
	for field in fields:
		if field.secret:
			field.clear()

func close() -> void:
	clear_secrets()
	hide()

func set_busy(value: bool) -> void:
	for field in fields:
		field.editable = not value
	submit_button.disabled = value
	cancel_button.disabled = value
	link.disabled = value
	submit_button.text = "ĐANG GỬI…" if value else submit_text

## Overridden by each form; returns the error shown, or "" on success.
func submit() -> String:
	return ""
