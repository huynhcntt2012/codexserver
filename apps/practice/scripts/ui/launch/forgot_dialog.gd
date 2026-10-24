extends "res://scripts/ui/launch/launch_form.gd"
## Forgotten password in two steps: enter the account email to receive a
## six-digit code, then enter the code with a new password.
signal reset_done()
var step := "email"
var email_field: LineEdit
var code_field: LineEdit
var new_field: LineEdit
var confirm_field: LineEdit

func _ready() -> void:
	name = "ForgotDialog"
	build("QUÊN MẬT KHẨU", [
		["Email", "Email đã đăng ký (ví dụ ten@gmail.com)", false, 254],
		["Code", "Mã xác nhận 6 số", false, 6],
		["NewPassword", "Mật khẩu mới (10–128 ký tự)", true, 128],
		["ConfirmNewPassword", "Nhập lại mật khẩu mới", true, 128],
	], "GỬI MÃ")
	email_field = fields[0]
	code_field = fields[1]
	new_field = fields[2]
	confirm_field = fields[3]
	code_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_field.text_changed.connect(_digits_only)
	link.text = "Chưa nhận được mã? Gửi lại"
	link.pressed.connect(resend)

func _digits_only(value: String) -> void:
	var digits := ""
	for ch in value:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits != value:
		code_field.text = digits
		code_field.caret_column = digits.length()

func open() -> void:
	set_step("email")
	show()
	email_field.grab_focus()

func set_step(value: String) -> void:
	step = value
	var on_code := value == "code"
	email_field.visible = not on_code
	for field in [code_field, new_field, confirm_field]:
		field.visible = on_code
	link.visible = on_code
	submit_text = "ĐẶT LẠI MẬT KHẨU" if on_code else "GỬI MÃ"
	submit_button.text = submit_text
	cancel_button.text = "ĐỔI EMAIL" if on_code else "HỦY"
	if cancel_button.pressed.is_connected(close):
		cancel_button.pressed.disconnect(close)
	if cancel_button.pressed.is_connected(back):
		cancel_button.pressed.disconnect(back)
	cancel_button.pressed.connect(back if on_code else close)
	if on_code:
		set_hint("Đã gửi mã 6 số tới %s nếu email này có tài khoản. Mã có hiệu lực 15 phút." % email_field.text.strip_edges().to_lower())
	else:
		set_hint("Nhập email đã đăng ký, chúng tôi sẽ gửi mã xác nhận 6 số.")
		code_field.clear()
		clear_secrets()
	layout()

func back() -> void:
	set_step("email")
	email_field.grab_focus()

func close() -> void:
	code_field.clear()
	super.close()

func submit() -> String:
	if AuthSession.busy:
		return ""
	if step == "email":
		return await send_code()
	return await finish()

func send_code() -> String:
	set_busy(true)
	var ok: bool = await AuthSession.request_reset_code(email_field.text)
	set_busy(false)
	if not ok:
		show_error(AuthSession.last_error)
		return AuthSession.last_error
	set_step("code")
	code_field.grab_focus()
	return ""

func resend() -> void:
	set_busy(true)
	var ok: bool = await AuthSession.request_reset_code(email_field.text)
	set_busy(false)
	if ok:
		set_hint("Đã gửi lại mã (mỗi phút gửi được một lần). Kiểm tra cả thư mục Spam.")
	else:
		show_error(AuthSession.last_error)

func finish() -> String:
	var error := ""
	if code_field.text.length() != 6:
		error = "Mã xác nhận gồm đúng 6 chữ số."
	elif new_field.text != confirm_field.text:
		error = "Mật khẩu mới nhập lại chưa khớp."
	if error != "":
		show_error(error)
		return error
	set_busy(true)
	var ok: bool = await AuthSession.reset_password(email_field.text, code_field.text, new_field.text)
	set_busy(false)
	if not ok:
		show_error(AuthSession.last_error)
		return AuthSession.last_error
	close()
	reset_done.emit()
	return ""
