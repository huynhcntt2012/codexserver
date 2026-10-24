extends Node
## Friends, guild and chat state for the PC lobby. Polls the API while the
## lobby is visible and an account is signed in; the server decides visibility.
signal friends_changed()
signal guild_changed()
signal messages_changed()
signal friend_request_arrived(name: String)

const POLL_SECONDS := 3.0
const KEEP_MESSAGES := 200
var friends: Array = []
var incoming: Array = []
var outgoing: Array = []
var guild: Variant = null
var messages: Array = []
var last_id := 0
var clock := 0.0
var polling := false
var fetching := false
var _seen: Dictionary = {}
var _known_requests: Dictionary = {}
var _first_poll := true

func online() -> bool:
	return AuthSession.has_session()

func _process(delta: float) -> void:
	var host := get_parent() as CanvasItem
	if not online() or (host and not host.is_visible_in_tree()):
		return
	clock -= delta
	if clock <= 0.0 and not polling:
		poll()

func poll() -> void:
	while polling:
		await get_tree().process_frame
	polling = true
	clock = POLL_SECONDS
	await refresh_friends()
	await refresh_guild()
	await refresh_messages()
	polling = false

func refresh_friends() -> void:
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/friends")
	if reply.status != 200 or not reply.data is Dictionary:
		return
	friends = reply.data.get("friends", [])
	incoming = reply.data.get("incoming", [])
	outgoing = reply.data.get("outgoing", [])
	for entry in incoming:
		var id := str(entry.request_id)
		if not _known_requests.has(id) and not _first_poll:
			friend_request_arrived.emit(str(entry.user.name))
		_known_requests[id] = true
	_first_poll = false
	friends_changed.emit()

func refresh_guild() -> void:
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/guild")
	if reply.status == 200 and reply.data is Dictionary:
		var before = guild
		guild = reply.data.get("guild")
		if str(before) != str(guild):
			guild_changed.emit()

## Fetches only messages newer than the last one; duplicates are dropped by id.
func refresh_messages() -> void:
	if fetching:
		return
	fetching = true
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_GET, "/v1/chat?after=%d" % last_id)
	fetching = false
	if reply.status != 200 or not reply.data is Dictionary:
		return
	var added := false
	for message in reply.data.get("messages", []):
		var id := int(message.id)
		last_id = maxi(last_id, id)
		if _seen.has(id):
			continue
		_seen[id] = true
		messages.append(message)
		added = true
	if messages.size() > KEEP_MESSAGES:
		for old in messages.slice(0, messages.size() - KEEP_MESSAGES):
			_seen.erase(int(old.id))
		messages = messages.slice(messages.size() - KEEP_MESSAGES)
	if added:
		messages_changed.emit()

func search(query: String) -> Dictionary:
	return await AuthSession.api(HTTPClient.METHOD_GET, "/v1/users?q=" + query.strip_edges().uri_encode())

func add_friend(account_id: String) -> Dictionary:
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/friends/requests", {"account_id": account_id})
	if reply.status == 409:
		reply.error = "Đã là bạn bè hoặc lời mời đang chờ xác nhận."
	await refresh_friends()
	return reply

func respond(request_id: String, accept: bool) -> Dictionary:
	var path := "/v1/friends/requests/%s/%s" % [request_id.uri_encode(), "accept" if accept else "decline"]
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, path)
	await refresh_friends()
	return reply

func join_guild(guild_name: String) -> Dictionary:
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/guild", {"name": guild_name})
	if reply.status == 422:
		reply.error = "Tên bang cần 3–24 ký tự: chữ, số, khoảng trắng hoặc _."
	await refresh_guild()
	return reply

func leave_guild() -> Dictionary:
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_DELETE, "/v1/guild")
	await refresh_guild()
	return reply

func send(channel: String, body: String, to := "") -> Dictionary:
	var payload := {"channel": channel, "body": body}
	if channel == "private":
		payload["to"] = to
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/chat", payload)
	match reply.status:
		409: reply.error = "Bạn cần tham gia bang hội trước."
		403: reply.error = "Chỉ nhắn riêng được cho bạn bè."
		422: reply.error = "Tin nhắn cần 1–200 ký tự."
	await refresh_messages()
	return reply

func friend_name(account_id: String) -> String:
	for friend in friends:
		if str(friend.id) == account_id:
			return str(friend.name)
	return ""
