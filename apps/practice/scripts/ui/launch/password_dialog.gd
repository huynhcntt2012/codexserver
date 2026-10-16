extends "res://scripts/ui/launch/launch_form.gd"
## Change-password popup, opened from the footer: the current password proves
## ownership. Forgotten passwords use forgot_dialog.gd instead.
signal changed(username: String)
var username_field: LineEdit
var current_field: LineEdit
var new_field: LineEdit
var confirm_field: LineEdit

func _ready() -> void:
	name = "PasswordDialog"
	build("ĐỔI MẬT KHẨU", [
		["Username", "Tên tài khoản", false, 24],
		["CurrentPassword", "Mật khẩu hiện tại", true, 128],
		["NewPassword", "Mật khẩu mới (10–128 ký tự)", true, 128],
		["ConfirmNewPassword", "Nhập lại mật khẩu mới", true, 128],
	], "ĐỔI MẬT KHẨU")
	username_field = fields[0]
	current_field = fields[1]
	new_field = fields[2]
	confirm_field = fields[3]

func open(username := "") -> void:
	set_hint("Nhập mật khẩu hiện tại rồi chọn mật khẩu mới.")
	username_field.text = username
	clear_secrets()
	show()
	first_empty().grab_focus()

func submit() -> String:
	if AuthSession.busy:
		return ""
	var error := ""
	if username_field.text.strip_edges().is_empty():
		error = "Bạn chưa nhập tên tài khoản."
	elif current_field.text.is_empty():
		error = "Bạn chưa nhập mật khẩu hiện tại."
	elif new_field.text != confirm_field.text:
		error = "Mật khẩu mới nhập lại chưa khớp."
	if error != "":
		show_error(error)
		return error
	set_busy(true)
	var username := username_field.text.strip_edges()
	var ok: bool = await AuthSession.change_password(username, current_field.text, new_field.text)
	set_busy(false)
	if not ok:
		show_error(AuthSession.last_error)
		current_field.clear()
		return AuthSession.last_error
	close()
	changed.emit(username)
	return ""
