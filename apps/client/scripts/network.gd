extends Node
## Minimal Colyseus protocol adapter, tested against the pinned server.
## Supports joinOrCreate, JOIN_ROOM ack, string input and JSON byte snapshots.
## No schema decoder, third-party SDK, or reconnection protocol is required.

signal snapshot_received(snapshot: Dictionary)
signal status_changed(message: String)
signal account_changed
signal rooms_opened
signal rooms_received(rooms: Array)

var session_id := ""
var room_id := ""
var connected := false
var busy := false
var socket := WebSocketPeer.new()
var _http := HTTPRequest.new()
var _was_open := false
var _opening := false
var _connect_deadline := 0
var _request_error := ""
var account_name := ""
var _access_token := ""
var _token_deadline := 0
var _account_api := ""


func _ready() -> void:
	add_child(_http)
	_http.timeout = 10.0


func _post(url: String, body: Dictionary) -> Dictionary:
	_request_error = ""
	var error := _http.request(
		url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)
	)
	if error != OK:
		_request_error = "Cannot send request. Check the URL (http:// or https://)."
		return {}
	var response: Array = await _http.request_completed
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		_request_error = "Cannot reach server. Check URL, LAN/VPN and firewall."
		if response[0] == HTTPRequest.RESULT_TIMEOUT:
			_request_error = "Request timed out. Check URL and LAN/VPN, then retry."
		return {}
	if response[1] < 200 or response[1] >= 300:
		match int(response[1]):
			401, 403:
				_request_error = "HTTP %s: Login rejected. Use a registered account or clear Username for guest." % response[1]
			409:
				_request_error = "HTTP 409: Tên tài khoản đã được dùng. Chọn tên khác hoặc Đăng nhập."
			422:
				_request_error = "HTTP 422: Username: 3-24 lowercase letters/digits/_. Password: 10-128 characters."
			429:
				_request_error = "HTTP 429: Too many attempts. Wait one minute, then retry."
			503:
				_request_error = "HTTP 503: Server temporarily unavailable. Retry shortly."
			_:
				_request_error = "HTTP %s: Request failed. Check server URL or contact the host." % response[1]
		return {}
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not parsed is Dictionary:
		_request_error = "Invalid server response. Check that the URL points to the game server."
		return {}
	return parsed


func has_account_session(api_url: String, username: String) -> bool:
	return not _access_token.is_empty() and Time.get_ticks_msec() < _token_deadline and _account_api == api_url.strip_edges().trim_suffix("/") and account_name == username.strip_edges()


func logout() -> void:
	disconnect_game()
	_access_token = ""
	_token_deadline = 0
	_account_api = ""
	account_name = ""
	account_changed.emit()


func join_game(api_url: String, arena_url: String, username := "", password := "", register := false, browse_only := false) -> void:
	if busy or connected:
		return
	username = username.strip_edges()
	if register and username.is_empty():
		status_changed.emit("Nhập tên tài khoản để đăng ký.")
		return
	busy = true
	var token := _access_token
	if register or not password.is_empty() or not has_account_session(api_url, username):
		# Only registered sessions are kept, in memory; never persist credentials.
		_access_token = ""
		account_name = ""
		account_changed.emit()
		status_changed.emit("Đang tạo tài khoản…" if register else "Signing in...")
		var auth_path := "/v1/register" if register else ("/v1/guests" if username.is_empty() else "/v1/login")
		var body := {} if username.is_empty() else {"username": username, "password": password}
		var auth := await _post(api_url.strip_edges().trim_suffix("/") + auth_path, body)
		if not auth.get("access_token") is String or str(auth.get("access_token", "")).is_empty():
			busy = false
			var reason := _request_error if not _request_error.is_empty() else "API response has no access token. Check API URL."
			status_changed.emit(("Đăng ký thất bại: " if register else "Sign-in failed: ") + reason)
			return
		token = auth.access_token
		_token_deadline = Time.get_ticks_msec() + maxi(0, int(auth.get("expires_in", 0)) - 10) * 1000
		if not username.is_empty():
			_access_token = token
			account_name = username
			_account_api = api_url.strip_edges().trim_suffix("/")
			_token_deadline = Time.get_ticks_msec() + maxi(0, int(auth.get("expires_in", 0)) - 10) * 1000
			account_changed.emit()
	if browse_only:
		_access_token = token
		_account_api = api_url.strip_edges().trim_suffix("/")
		busy = false
		rooms_opened.emit()
		await list_rooms(arena_url)
		return
	await _reserve(arena_url, token, "joinOrCreate/arena")


func list_rooms(arena_url: String) -> void:
	if busy or connected:
		return
	if _access_token.is_empty() or Time.get_ticks_msec() >= _token_deadline:
		logout()
		status_changed.emit("Phiên đã hết hạn. Hãy đăng nhập lại.")
		return
	busy = true
	var error := _http.request(arena_url.strip_edges().trim_suffix("/") + "/rooms", ["Authorization: Bearer " + _access_token])
	if error != OK:
		busy = false
		rooms_received.emit([])
		status_changed.emit("Không tải được phòng. Kiểm tra URL và thử Làm mới.")
		return
	var response: Array = await _http.request_completed
	busy = false
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		rooms_received.emit([])
		if response[1] == 401:
			logout()
		status_changed.emit("Không tải được phòng (HTTP %s). Thử Làm mới hoặc đăng nhập lại." % response[1])
		return
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not data is Dictionary or not data.get("rooms") is Array:
		rooms_received.emit([])
		status_changed.emit("Danh sách phòng không hợp lệ.")
		return
	rooms_received.emit(data.rooms)
	status_changed.emit("Chọn phòng hoặc tạo phòng mới.")


func join_selected(arena_url: String, selected_room := "", create := false) -> void:
	if busy or connected:
		return
	if _access_token.is_empty() or Time.get_ticks_msec() >= _token_deadline:
		logout()
		status_changed.emit("Phiên đã hết hạn. Hãy đăng nhập lại.")
		return
	if not create and selected_room.is_empty():
		return
	busy = true
	await _reserve(arena_url, _access_token, "create/arena" if create else "joinById/" + selected_room.uri_encode())


func _reserve(arena_url: String, token: String, route: String) -> void:
	status_changed.emit("Đang vào phòng…")
	var endpoint := arena_url.strip_edges().trim_suffix("/")
	var seat := await _post(endpoint + "/matchmake/" + route, {"token": token})
	if not seat.has("roomId") or not seat.has("sessionId") or not seat.has("processId"):
		busy = false
		var reason := _request_error if not _request_error.is_empty() else "Invalid room response. Check Arena URL."
		status_changed.emit("Could not join arena: " + reason)
		return
	session_id = str(seat.sessionId)
	room_id = str(seat.roomId)
	var websocket_url := endpoint.replace("https://", "wss://").replace("http://", "ws://")
	websocket_url += "/%s/%s?sessionId=%s" % [
		seat.processId, room_id, session_id.uri_encode()
	]
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1024 * 1024
	var error := socket.connect_to_url(websocket_url)
	if error != OK:
		busy = false
		status_changed.emit("WebSocket connection failed. Retry Join arena.")
		return
	_opening = true
	_connect_deadline = Time.get_ticks_msec() + 12000


func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if _opening and Time.get_ticks_msec() > _connect_deadline:
		disconnect_game()
		status_changed.emit("Connection timed out. Retry Join arena.")
		return
	if state == WebSocketPeer.STATE_OPEN:
		_was_open = true
		while socket.get_available_packet_count() > 0:
			_handle_packet(socket.get_packet())
	elif state == WebSocketPeer.STATE_CLOSED and (_was_open or _opening):
		connected = false
		busy = false
		_was_open = false
		_opening = false
		status_changed.emit("Disconnected. Join again for a new seat.")


func _handle_packet(packet: PackedByteArray) -> void:
	if packet.is_empty():
		return
	match packet[0]:
		10:  # JOIN_ROOM. Server uses the 'none' serializer; no schema handshake.
			socket.send(PackedByteArray([10]))
			connected = true
			busy = false
			_opening = false
			status_changed.emit("Connected to arena " + room_id)
		17:  # ROOM_DATA_BYTES + positive fixint message type 1 + UTF-8 JSON.
			if packet.size() < 3 or packet[1] != 1:
				return
			var parsed: Variant = JSON.parse_string(packet.slice(2).get_string_from_utf8())
			if parsed is Dictionary and parsed.get("version") == 1:
				snapshot_received.emit(parsed)
		11, 12:  # ERROR / LEAVE_ROOM
			disconnect_game()
			status_changed.emit("Server rejected or closed the room. Join again.")


func send_action(action: String) -> void:
	if not connected or action not in ["up", "down", "left", "right", "bomb", "ready"]:
		return
	# ROOM_DATA (13), numeric type 0, MsgPack fixstr. Only our short ASCII enums.
	var bytes := action.to_utf8_buffer()
	var packet := PackedByteArray([13, 0, 0xa0 + bytes.size()])
	packet.append_array(bytes)
	socket.send(packet)


func disconnect_game() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send(PackedByteArray([12]))
	socket.close()
	connected = false
	busy = false
	_opening = false
	_was_open = false
