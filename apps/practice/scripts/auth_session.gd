extends Node
## Account credentials are sent only to the configured API. Tokens stay in RAM.
var api_url := "http://127.0.0.1:8000"
var account_name := ""
var account_id := ""
var busy := false
var last_error := ""
var _token := ""
var _deadline := 0
var _http := HTTPRequest.new()

func _ready() -> void:
	var config := ConfigFile.new()
	config.load("user://launch_preferences.cfg")
	api_url = config.get_value("network", "api_url", api_url)
	if not OS.get_environment("SUNI_API_URL").is_empty():
		api_url = OS.get_environment("SUNI_API_URL")
	# The web build's CSP only allows same-origin requests: use the site's /api proxy.
	if OS.has_feature("web"):
		var location := JavaScriptBridge.get_interface("location")
		api_url = str(location.origin) + "/api"
	_http.timeout = 15.0
	_http.body_size_limit = 65536
	_http.max_redirects = 0
	add_child(_http)

## Presence for the admin "online now" count: any signed-in call refreshes it,
## so ping /v1/me while idle (e.g. during an offline match).
const HEARTBEAT_SECONDS := 45.0
var _heartbeat := 0.0

func _process(delta: float) -> void:
	if _token.is_empty():
		return
	_heartbeat += delta
	if _heartbeat >= HEARTBEAT_SECONDS:
		_heartbeat = 0.0
		api(HTTPClient.METHOD_GET, "/v1/me")

func has_session() -> bool:
	if not _token.is_empty() and Time.get_ticks_msec() >= _deadline:
		logout()
	return not _token.is_empty()

## The signed JWT for the arena seat request; empty when signed out or expired.
func access_token() -> String:
	return _token if has_session() else ""

func logout() -> void:
	_token = ""
	account_name = ""
	account_id = ""
	_deadline = 0

func configure(url: String) -> bool:
	if busy:
		return false
	url = url.strip_edges().trim_suffix("/")
	if not (url.begins_with("https://") or url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")):
		last_error = "Dùng HTTPS cho máy chủ từ xa hoặc HTTP localhost để kiểm thử."
		return false
	if url != api_url:
		logout()
	api_url = url
	var config := ConfigFile.new()
	config.load("user://launch_preferences.cfg")
	config.set_value("network", "api_url", api_url)
	config.save("user://launch_preferences.cfg")
	return true

func authenticate(username: String, password: String, registering := false, email := "") -> bool:
	if busy:
		return false
	last_error = ""
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]{3,24}$")
	if pattern.search(username) == null:
		last_error = "Tên tài khoản cần 3–24 ký tự: a-z, 0-9 hoặc dấu _."
		return false
	if password.length() < 10 or password.length() > 128:
		last_error = "Mật khẩu cần từ 10 đến 128 ký tự."
		return false
	email = email.strip_edges().to_lower()
	if registering and not valid_email(email):
		last_error = "Email chưa hợp lệ (ví dụ ten@gmail.com). Email dùng để lấy lại mật khẩu."
		return false
	if not configure(api_url):
		return false
	busy = true
	logout()
	var endpoint := "/v1/register" if registering else "/v1/login"
	var body := {"username": username, "password": password}
	if registering:
		body["email"] = email
	var error := _http.request(api_url + endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	body.clear()
	password = ""
	if error != OK:
		busy = false
		last_error = "Không thể gửi yêu cầu. Kiểm tra địa chỉ API trong Cài đặt."
		return false
	var response: Array = await _http.request_completed
	busy = false
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		last_error = connection_error(response[0], api_url)
		return false
	if response[1] != 200 and response[1] != 201:
		match response[1]:
			401: last_error = "Tên tài khoản hoặc mật khẩu không đúng."
			409: last_error = "Tên tài khoản hoặc email đã được sử dụng."
			422: last_error = "Thông tin tài khoản không hợp lệ."
			429: last_error = "Bạn thử quá nhiều lần. Vui lòng chờ một phút."
			_: last_error = "Máy chủ chưa sẵn sàng (HTTP %d). Vui lòng thử lại." % response[1]
		return false
	var data = JSON.parse_string(response[3].get_string_from_utf8())
	if not data is Dictionary or not data.get("access_token") is String or data.get("access_token", "").is_empty() or not data.get("expires_in") is float or data.get("expires_in", 0) <= 0 or not data.get("name") is String:
		last_error = "Phản hồi đăng nhập không hợp lệ. Kiểm tra địa chỉ API."
		return false
	_token = data.access_token
	account_name = data.name
	account_id = str(data.get("account_id", ""))
	_deadline = Time.get_ticks_msec() + int(data.expires_in) * 1000
	return true

static func valid_email(email: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[^@\\s]{1,64}@[^@\\s]+\\.[^@\\s]{2,}$")
	return email.length() <= 254 and pattern.search(email) != null

## Unauthenticated POST on the shared request; returns the HTTP status, or 0
## with `last_error` set when the server could not be reached.
func _post(endpoint: String, body: Dictionary) -> int:
	if not configure(api_url):
		return 0
	busy = true
	var error := _http.request(api_url + endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	body.clear()
	if error != OK:
		busy = false
		last_error = "Không thể gửi yêu cầu. Kiểm tra địa chỉ API trong Cài đặt."
		return 0
	var response: Array = await _http.request_completed
	busy = false
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		last_error = connection_error(response[0], api_url)
		return 0
	return response[1]

func _common_error(status: int) -> String:
	match status:
		404, 405: return "Máy chủ này chưa hỗ trợ tính năng này."
		429: return "Bạn thử quá nhiều lần. Vui lòng chờ một phút."
	return "Máy chủ chưa sẵn sàng (HTTP %d). Vui lòng thử lại." % status

## Changes the password from the login screen; the current password proves ownership.
func change_password(username: String, password: String, new_password: String) -> bool:
	if busy:
		return false
	last_error = ""
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]{3,24}$")
	if pattern.search(username) == null:
		last_error = "Tên tài khoản cần 3–24 ký tự: a-z, 0-9 hoặc dấu _."
		return false
	for value in [password, new_password]:
		if value.length() < 10 or value.length() > 128:
			last_error = "Mật khẩu cần từ 10 đến 128 ký tự."
			return false
	if new_password == password:
		last_error = "Mật khẩu mới phải khác mật khẩu hiện tại."
		return false
	var status: int = await _post("/v1/password", {"username": username, "password": password, "new_password": new_password})
	match status:
		0: pass
		200, 204: return true
		401: last_error = "Tên tài khoản hoặc mật khẩu hiện tại không đúng."
		422: last_error = "Mật khẩu mới chưa hợp lệ (10–128 ký tự, khác mật khẩu cũ)."
		_: last_error = _common_error(status)
	return false

## Asks the server to email a six-digit reset code. The answer is the same
## whether or not the address belongs to an account.
func request_reset_code(email: String) -> bool:
	if busy:
		return false
	last_error = ""
	email = email.strip_edges().to_lower()
	if not valid_email(email):
		last_error = "Email chưa hợp lệ (ví dụ ten@gmail.com)."
		return false
	var status: int = await _post("/v1/password/forgot", {"email": email})
	match status:
		0: pass
		200, 202: return true
		422: last_error = "Email chưa hợp lệ (ví dụ ten@gmail.com)."
		503: last_error = "Máy chủ chưa gửi được email. Vui lòng thử lại sau."
		_: last_error = _common_error(status)
	return false

func reset_password(email: String, code: String, new_password: String) -> bool:
	if busy:
		return false
	last_error = ""
	email = email.strip_edges().to_lower()
	code = code.strip_edges()
	if not code.is_valid_int() or code.length() != 6:
		last_error = "Mã xác nhận gồm đúng 6 chữ số."
		return false
	if new_password.length() < 10 or new_password.length() > 128:
		last_error = "Mật khẩu mới cần từ 10 đến 128 ký tự."
		return false
	var status: int = await _post("/v1/password/reset", {"email": email, "code": code, "new_password": new_password})
	match status:
		0: pass
		200, 204: return true
		400: last_error = "Mã không đúng hoặc đã hết hạn. Kiểm tra email hoặc gửi lại mã."
		422: last_error = "Thông tin chưa hợp lệ."
		_: last_error = _common_error(status)
	return false

## Signed-in JSON call. Returns {"status", "data", "error"}; status 0 means no answer.
## Each call gets its own HTTPRequest so polling never blocks a send.
func api(method: int, path: String, body: Variant = null) -> Dictionary:
	if not has_session():
		return {"status": 0, "data": null, "error": "Đăng nhập tài khoản để dùng tính năng này."}
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.max_redirects = 0
	request.body_size_limit = 262144
	add_child(request)
	var headers := PackedStringArray(["Authorization: Bearer " + _token])
	var payload := ""
	if body != null:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	if request.request(api_url + path, headers, method, payload) != OK:
		request.queue_free()
		return {"status": 0, "data": null, "error": "Không gửi được yêu cầu."}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "data": null, "error": connection_error(response[0], api_url)}
	var raw: String = response[3].get_string_from_utf8()
	var data: Variant = JSON.parse_string(raw) if not raw.is_empty() else null
	var status: int = response[1]
	var error := ""
	match status:
		200, 201, 204: pass
		401:
			logout()
			error = "Phiên đăng nhập đã hết hạn."
		403: error = "Bạn chưa có quyền làm việc này."
		404: error = "Không tìm thấy người chơi hoặc dữ liệu."
		409: error = "Yêu cầu đã tồn tại hoặc chưa đủ điều kiện."
		422: error = "Thông tin chưa hợp lệ."
		429: error = "Bạn thao tác quá nhanh, chờ vài giây nhé."
		_: error = "Máy chủ chưa sẵn sàng (HTTP %d)." % status
	return {"status": status, "data": data, "error": error}

func connection_error(result: int, url: String) -> String:
	var reason := "Không kết nối được"
	match result:
		HTTPRequest.RESULT_TIMEOUT: reason = "Hết thời gian kết nối"
		HTTPRequest.RESULT_CANT_RESOLVE: reason = "Không tìm thấy địa chỉ máy chủ"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: reason = "Lỗi kết nối bảo mật TLS"
	var hint := "Vào Cài đặt → Máy chủ tài khoản → Kiểm tra."
	if "127.0.0.1" in url or "localhost" in url:
		hint = "Đây là máy PC của bạn. Trong Cài đặt, chọn Máy chủ Bụp Bụp rồi Áp dụng."
	return "%s: %s. %s" % [reason, url, hint]

func check_connection(url: String) -> String:
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.max_redirects = 0
	request.body_size_limit = 65536
	add_child(request)
	url = url.strip_edges().trim_suffix("/")
	if not (url.begins_with("https://") or url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")):
		request.queue_free()
		return "URL không hợp lệ: dùng HTTPS hoặc localhost."
	var error := request.request(url + "/health")
	if error != OK:
		request.queue_free()
		return "Không gửi được yêu cầu. Kiểm tra URL."
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return connection_error(response[0], url)
	var data = JSON.parse_string(response[3].get_string_from_utf8())
	if response[1] == 200 and data is Dictionary and data.get("status") == "ok":
		return "Kết nối thành công. Nhấn ÁP DỤNG để dùng máy chủ này."
	return "Máy chủ chưa sẵn sàng hoặc URL không phải API (HTTP %d)." % response[1]
