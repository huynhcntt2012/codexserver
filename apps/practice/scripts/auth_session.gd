extends Node
## Account credentials are sent only to the configured API. Tokens stay in RAM.
var api_url := "http://127.0.0.1:8000"
var account_name := ""
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
	_http.timeout = 15.0
	_http.body_size_limit = 65536
	_http.max_redirects = 0
	add_child(_http)

func has_session() -> bool:
	if not _token.is_empty() and Time.get_ticks_msec() >= _deadline:
		logout()
	return not _token.is_empty()

func logout() -> void:
	_token = ""
	account_name = ""
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

func authenticate(username: String, password: String, registering := false) -> bool:
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
	if not configure(api_url):
		return false
	busy = true
	logout()
	var endpoint := "/v1/register" if registering else "/v1/login"
	var error := _http.request(api_url + endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"username": username, "password": password}))
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
			409: last_error = "Tên tài khoản đã được sử dụng."
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
	_deadline = Time.get_ticks_msec() + int(data.expires_in) * 1000
	return true

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
