extends Node
## Online rooms through the Colyseus arena, protocol v2 (see docs/ARCHITECTURE.md).
## Same wire format as apps/client/scripts/network.gd: seat reservation over HTTP,
## WebSocket JOIN_ROOM ack, MsgPack fixstr intents, JSON byte snapshots (type 1).
## The client only sends intents (move/bomb/ready); positions, timers, blasts and
## winners always come from the server snapshot.

signal snapshot_received(snapshot: Dictionary)
## Emitted once when the room connection ends (left, kicked, or network lost).
signal closed(reason: String)

const MAPS := ["park", "frost", "coast"]
const ACTIONS := ["up", "down", "left", "right", "bomb", "ready"]
const CONNECT_MS := 12000

var room_id := ""
var session_id := ""
var connected := false
var busy := false
var last_error := ""
var snapshot: Dictionary = {}
var socket := WebSocketPeer.new()
## Seat token override (a second local player in tests); empty uses AuthSession.
var token_override := ""
var _opening := false
var _deadline := 0

## Arena base URL. SUNI_ARENA_URL wins; otherwise the API URL's sibling: the
## public host ("https://api.x" -> "https://arena.x"), the web proxy
## (".../api" -> ".../arena") or the local dev arena port next to :8000.
func arena_url() -> String:
	var override := OS.get_environment("SUNI_ARENA_URL")
	if not override.is_empty():
		return override.strip_edges().trim_suffix("/")
	return arena_for(AuthSession.api_url)

static func arena_for(api_url: String) -> String:
	var api := api_url.strip_edges().trim_suffix("/")
	for scheme in ["https://", "http://"]:
		if api.begins_with(scheme + "api."):
			return scheme + "arena." + api.trim_prefix(scheme + "api.")
	if api.ends_with("/api"):
		return api.trim_suffix("/api") + "/arena"
	if api.ends_with(":8000"):
		return api.trim_suffix(":8000") + ":2567"
	return api + "/arena"

## Open rooms (waiting and playing) with live counts. {ok, rooms, error}.
func list_rooms() -> Dictionary:
	var token := _token()
	if token.is_empty():
		return {"ok": false, "rooms": [], "error": "Đăng nhập để xem phòng online."}
	var reply := await _request(arena_url() + "/rooms/v2", ["Authorization: Bearer " + token])
	if reply.status == 200 and reply.data is Dictionary and reply.data.get("rooms") is Array:
		return {"ok": true, "rooms": reply.data.rooms, "error": ""}
	if reply.status == 401:
		return {"ok": false, "rooms": [], "error": "Phiên đăng nhập đã hết hạn."}
	if reply.status == 429:
		return {"ok": false, "rooms": [], "error": "Làm mới quá nhanh, chờ một chút nhé."}
	return {"ok": false, "rooms": [], "error": "Chưa kết nối được máy chủ phòng."}

## Account ids of accepted friends; empty for guests or when the API is down.
func friend_ids() -> Array:
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/friends")
	var ids := []
	if reply.status == 200 and reply.data is Dictionary:
		for friend in reply.data.get("friends", []):
			ids.append(str(friend.get("id", "")))
	return ids

## practice = a private room where server bots fill the empty seats (up to 4).
func create_room(map_id: String, hero: String, practice := false) -> bool:
	var options := {"map": map_id, "hero": hero}
	if practice:
		options["practice"] = true
	return await _join("create/arena2", options)

func quick_join(map_id: String, hero: String) -> bool:
	return await _join("joinOrCreate/arena2", {"map": map_id, "hero": hero})

func join_room(target: String, hero: String) -> bool:
	return await _join("joinById/" + target.uri_encode(), {"hero": hero})

## Reserves a seat and opens the WebSocket; true once the server sent JOIN_ROOM
## and the first snapshot. On failure `last_error` says why.
func _join(route: String, options: Dictionary) -> bool:
	if busy or connected:
		last_error = "Đang ở trong một phòng khác."
		return false
	var token := _token()
	if token.is_empty():
		last_error = "Đăng nhập để chơi online."
		return false
	busy = true
	last_error = ""
	snapshot = {}
	var body := options.duplicate()
	body["token"] = token
	var base := arena_url()
	var reply := await _request(base + "/matchmake/" + route, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	var seat: Variant = reply.data
	if reply.status != 200 or not seat is Dictionary or not seat.has("roomId") or not seat.has("sessionId") or not seat.has("processId"):
		busy = false
		last_error = _seat_error(reply)
		return false
	room_id = str(seat.roomId)
	session_id = str(seat.sessionId)
	var ws_url := base.replace("https://", "wss://").replace("http://", "ws://")
	ws_url += "/%s/%s?sessionId=%s" % [str(seat.processId).uri_encode(), room_id.uri_encode(), session_id.uri_encode()]
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1024 * 1024
	if socket.connect_to_url(ws_url) != OK:
		busy = false
		last_error = "Không mở được kết nối phòng."
		return false
	_opening = true
	_deadline = Time.get_ticks_msec() + CONNECT_MS
	while _opening:
		await get_tree().process_frame
	busy = false
	return connected and not snapshot.is_empty()

func _token() -> String:
	return token_override if token_override != "" else AuthSession.access_token()

func _seat_error(reply: Dictionary) -> String:
	var message := ""
	if reply.data is Dictionary:
		message = str(reply.data.get("error", ""))
	match int(reply.status):
		0: return "Chưa kết nối được máy chủ phòng."
		401: return "Phiên đăng nhập đã hết hạn."
		404: return "Không tìm thấy máy chủ phòng hoặc phòng đã đóng."
		429: return "Thao tác quá nhanh, chờ một phút rồi thử lại."
	if message.contains("locked") or message.contains("full") or message.contains("not found"):
		return "Phòng đã đầy hoặc đã bắt đầu."
	return "Không vào được phòng (HTTP %d)." % int(reply.status)

func send_action(action: String) -> void:
	if not connected or action not in ACTIONS:
		return
	# ROOM_DATA (13), numeric type 0, MsgPack fixstr of a short ASCII enum.
	var bytes := action.to_utf8_buffer()
	var packet := PackedByteArray([13, 0, 0xa0 + bytes.size()])
	packet.append_array(bytes)
	socket.send(packet)

func leave() -> void:
	var was_in_room := connected or _opening
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send(PackedByteArray([12]))
	socket.close()
	_reset()
	if was_in_room:
		closed.emit("")

func me() -> Dictionary:
	for player in snapshot.get("players", []):
		if str(player.get("id", "")) == session_id:
			return player
	return {}

func _reset() -> void:
	connected = false
	_opening = false
	room_id = ""

func _process(_delta: float) -> void:
	if not (connected or _opening):
		return
	socket.poll()
	var state := socket.get_ready_state()
	if _opening and Time.get_ticks_msec() > _deadline:
		last_error = "Kết nối phòng quá lâu, thử lại nhé."
		socket.close()
		_reset()
		return
	if state == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count() > 0:
			_handle(socket.get_packet())
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_connected := connected
		if _opening and last_error.is_empty():
			last_error = "Máy chủ từ chối vào phòng."
		_reset()
		if was_connected:
			closed.emit("Mất kết nối với phòng.")

func _handle(packet: PackedByteArray) -> void:
	if packet.is_empty():
		return
	match packet[0]:
		10:  # JOIN_ROOM: ack; the server uses the 'none' serializer.
			socket.send(PackedByteArray([10]))
			connected = true
		17:  # ROOM_DATA_BYTES, type 1, UTF-8 JSON snapshot (version 2 only).
			if packet.size() < 3 or packet[1] != 1:
				return
			var parsed: Variant = JSON.parse_string(packet.slice(2).get_string_from_utf8())
			if parsed is Dictionary and int(parsed.get("version", 0)) == 2 and parsed.get("grid") is Array and parsed.get("players") is Array:
				snapshot = parsed
				_opening = false
				snapshot_received.emit(snapshot)
		11, 12:  # ERROR / LEAVE_ROOM
			var was_connected := connected
			last_error = "Máy chủ từ chối vào phòng." if _opening else ""
			socket.close()
			_reset()
			if was_connected:
				closed.emit("Phòng đã đóng.")

func _request(url: String, headers: Array, method := HTTPClient.METHOD_GET, body := "") -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.max_redirects = 0
	request.body_size_limit = 262144
	add_child(request)
	if request.request(url, PackedStringArray(headers), method, body) != OK:
		request.queue_free()
		return {"status": 0, "data": null}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "data": null}
	return {"status": int(response[1]), "data": JSON.parse_string(response[3].get_string_from_utf8())}
