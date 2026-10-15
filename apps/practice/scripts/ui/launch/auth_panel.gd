extends Control
## Native account form. AuthSession handles API requests and in-memory sessions.
signal login_requested(username: String, password: String)
signal guest_requested()
signal forgot_password_requested()
signal validation_failed(message: String)

const Ui = preload("res://scripts/ui/launch/ui_theme.gd")
var registering := false
var confirm_field := LineEdit.new()
var preferences := ConfigFile.new()
@onready var username_field: LineEdit = $Username
@onready var password_field: LineEdit = $Password

func _ready() -> void:
	confirm_field.name = "ConfirmPassword"
	confirm_field.position = Vector2(34, 198)
	confirm_field.size = Vector2(416, 36)
	confirm_field.secret = true
	confirm_field.max_length = 128
	confirm_field.placeholder_text = "Nhập lại mật khẩu"
	add_child(confirm_field)
	_style_input(confirm_field)
	confirm_field.hide()
	confirm_field.text_submitted.connect(func(_text): _submit())
	username_field.max_length = 24
	preferences.load("user://launch_preferences.cfg")
	$Remember.button_pressed = preferences.get_value("login", "remember", false)
	if $Remember.button_pressed:
		username_field.text = preferences.get_value("login", "username", "")
	$Remember.toggled.connect(func(_enabled): _save_username())
	username_field.text_changed.connect(func(_text): _save_username())
	$Frame.add_theme_stylebox_override("panel", Ui.box(Ui.CREAM, Color("#FFFFFF"), 30, 10, 5))
	Ui.apply_label($Title, 28, Ui.INK)
	Ui.apply_label($SubTitle, 15, Color("#8B83A4"))
	_style_input(username_field)
	_style_input(password_field)
	$Remember.add_theme_color_override("font_color", Ui.INK)
	$Remember.add_theme_font_size_override("font_size", 14)
	Ui.apply_link($Forgot, Ui.AQUA_DARK, 15)
	Ui.apply_button($Login, Color("#FFC868"), Color("#F28B76"), 24, 24)
	Ui.apply_button($Guest, Color("#99E9DF"), Color("#36BAC5"), 17, 24)
	$Login.pressed.connect(_submit)
	$Guest.pressed.connect(func(): guest_requested.emit())
	$Forgot.pressed.connect(func(): forgot_password_requested.emit())
	username_field.text_submitted.connect(func(_txt: String): password_field.grab_focus())
	password_field.text_submitted.connect(func(_txt: String): _submit())

func _style_input(field: LineEdit) -> void:
	field.add_theme_stylebox_override("normal", Ui.box(Color("#FFFFFF"), Color("#E0DDF1"), 15, 0, 2))
	field.add_theme_stylebox_override("focus", Ui.box(Color("#FFFFFF"), Ui.AQUA, 15, 0, 3))
	field.add_theme_color_override("font_color", Ui.INK)
	field.add_theme_color_override("font_placeholder_color", Color("#9B96B4"))
	field.add_theme_color_override("caret_color", Ui.AQUA_DARK)
	field.add_theme_font_size_override("font_size", 17)

func _submit() -> void:
	if AuthSession.busy:
		return
	if registering and password_field.text != confirm_field.text:
		validation_failed.emit("Mật khẩu nhập lại chưa khớp.")
		confirm_field.grab_focus()
		return
	var username := username_field.text.strip_edges()
	if username.is_empty():
		validation_failed.emit("Bạn chưa nhập tên tài khoản.")
		username_field.grab_focus()
		return
	if password_field.text.is_empty():
		validation_failed.emit("Bạn chưa nhập mật khẩu.")
		password_field.grab_focus()
		return
	login_requested.emit(username, password_field.text)

func should_remember_username() -> bool:
	return $Remember.button_pressed

func reset_password_field() -> void:
	password_field.clear()
	confirm_field.clear()

func _save_username() -> void:
	preferences.load("user://launch_preferences.cfg")
	preferences.set_value("login", "remember", $Remember.button_pressed)
	preferences.set_value("login", "username", username_field.text if $Remember.button_pressed else "")
	preferences.save("user://launch_preferences.cfg")

func set_registration(enabled: bool) -> void:
	registering = enabled
	reset_password_field()
	confirm_field.visible = enabled
	$Remember.visible = not enabled
	$Forgot.visible = not enabled
	$Title.text = "ĐĂNG KÝ" if enabled else "ĐĂNG NHẬP"
	$Login.text = "TẠO TÀI KHOẢN" if enabled else "VÀO TRẬN"

func set_busy(value: bool) -> void:
	for node in [$Login, $Guest, $Forgot, $Remember]:
		node.disabled = value
	for field in [username_field, password_field, confirm_field]:
		field.editable = not value
	$Login.text = "ĐANG KẾT NỐI…" if value else ("TẠO TÀI KHOẢN" if registering else "VÀO TRẬN")
