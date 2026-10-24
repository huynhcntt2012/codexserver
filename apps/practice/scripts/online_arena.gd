extends Node
## Online rooms through the Colyseus arena, protocol v2 (see docs/ARCHITECTURE.md).
## Same wire format as apps/client/scripts/network.gd: seat reservation over HTTP,
## WebSocket JOIN_ROOM ack, MsgPack fixstr intents, JSON byte snapshots (type 1).
## The client only sends intents (move/bomb/ready); positions, timers, blasts and
## winners always come from the server snapshot.

signal snapshot_received(snapshot: Dictionary)
## A teammate's voice frame relayed by the arena (VoiceChat plays it).
signal voice_received(speaker: String, channel: int, audio: PackedByteArray)
## Emitted once when the room connection ends (left, kicked, or network lost).
signal closed(reason: String)
## Boss raids: the connection dropped mid-raid and the adapter is getting the seat back.
signal reconnecting(active: bool)

const MAPS := ["park", "frost", "coast"]
const ACTIONS := [
	"up", "down", "left", "right", "bomb", "ready", "mount",
	"use_throw_bomb", "use_dart", "use_blue_shield", "use_speed_shoes", "use_freeze_bomb", "use_push_glove",
]
const CONNECT_MS := 12000
## The arena keeps a dropped raider's seat for 30 s (BossRoom.RECONNECT_SECONDS).
const RECONNECT_MS := 25000

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
var _ws_base := ""
var _process_id := ""
## From JOIN_ROOM: lets this client take its seat back after a drop.
var _reconnect_token := ""
var _rejoining := false

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
## Boss raid rooms (docs/BOSS.md). quick = team up with a public room of the
## event (or open one); otherwise a new room, private = invite only (no economy
## rewards unless the event allows them). The server reads the rules itself.
func boss_room(event_id: String, hero: String, quick := true, private := false) -> bool:
	var options := {"event": event_id, "hero": hero}
	if private:
		options["private"] = true
	return await _join(("joinOrCreate/boss" if quick and not private else "create/boss"), options)

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
	# The equipped pet skin; the arena shows it only if this account owns it.
	var pet := UIState.round_pet()
	if pet != "":
		body["pet"] = pet
	var base := arena_url()
	var reply := await _request(base + "/matchmake/" + route, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	var seat: Variant = reply.data
	if reply.status != 200 or not seat is Dictionary or not seat.has("roomId") or not seat.has("sessionId") or not seat.has("processId"):
		busy = false
		last_error = _seat_error(reply)
		return false
	room_id = str(seat.roomId)
	session_id = str(seat.sessionId)
	_process_id = str(seat.processId)
	_ws_base = base.replace("https://", "wss://").replace("http://", "ws://")
	_reconnect_token = ""
	var ws_url := _ws_url()
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

func _ws_url() -> String:
	return _ws_base + "/%s/%s?sessionId=%s" % [_process_id.uri_encode(), room_id.uri_encode(), session_id.uri_encode()]

## A drop during a boss raid is retried with the reconnection token.
func _resumable() -> bool:
	return _reconnect_token != "" and str(snapshot.get("mode", "")) == "boss" and str(snapshot.get("phase", "")) == "playing"

func _rejoin() -> void:
	_rejoining = true
	reconnecting.emit(true)
	var room := room_id
	var until := Time.get_ticks_msec() + RECONNECT_MS
	while Time.get_ticks_msec() < until and _rejoining:
		room_id = room
		socket = WebSocketPeer.new()
		socket.inbound_buffer_size = 1024 * 1024
		if socket.connect_to_url(_ws_url() + "&reconnectionToken=" + _reconnect_token.uri_encode()) == OK:
			last_error = ""
			_opening = true
			_deadline = Time.get_ticks_msec() + 5000
			while _opening:
				await get_tree().process_frame
			if connected:
				_rejoining = false
				reconnecting.emit(false)
				return
		await get_tree().create_timer(1.5).timeout
	var gave_up := _rejoining
	_rejoining = false
	reconnecting.emit(false)
	_reset()
	if gave_up:
		closed.emit("Mất kết nối với phòng.")

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

## One voice frame: ROOM_DATA_BYTES (17), type 2, [channel, ...mu-law audio].
func send_voice(channel: int, audio: PackedByteArray) -> void:
	if not connected or audio.is_empty():
		return
	var packet := PackedByteArray([17, 2, channel])
	packet.append_array(audio)
	socket.send(packet)

func send_action(action: String) -> void:
	if not connected or action not in ACTIONS:
		return
	# ROOM_DATA (13), numeric type 0, MsgPack fixstr of a short ASCII enum.
	var bytes := action.to_utf8_buffer()
	var packet := PackedByteArray([13, 0, 0xa0 + bytes.size()])
	packet.append_array(bytes)
	socket.send(packet)

func leave() -> void:
	var was_in_room := connected or _opening or _rejoining
	_rejoining = false
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
		if was_connected and _resumable():
			connected = false
			_rejoin()
			return
		_reset()
		if was_connected:
			closed.emit("Mất kết nối với phòng.")

func _handle(packet: PackedByteArray) -> void:
	if packet.is_empty():
		return
	match packet[0]:
		10:  # JOIN_ROOM [10, len, reconnection token, ...]: ack ('none' serializer).
			if packet.size() > 1 and packet.size() >= 2 + packet[1]:
				_reconnect_token = packet.slice(2, 2 + packet[1]).get_string_from_utf8()
			socket.send(PackedByteArray([10]))
			connected = true
		17:  # ROOM_DATA_BYTES: type 1 snapshot JSON, type 2 voice frame.
			if packet.size() >= 5 and packet[1] == 2:
				var id_end := 4 + packet[3]
				if packet.size() > id_end:
					voice_received.emit(packet.slice(4, id_end).get_string_from_utf8(), packet[2], packet.slice(id_end))
				return
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
