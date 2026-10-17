extends SceneTree
## Exercise the actual asynchronous adapter against the local HTTP fixture.

const Network = preload("res://scripts/network.gd")
var net = Network.new()
var last_status := ""
var failed := false


func _initialize() -> void:
	_start.call_deferred()


func _expect(api: String, username: String, expected: String) -> void:
	await net.join_game(api, OS.get_environment("SUNI_ERROR_TEST_URL"), username, "test-password")
	if expected not in last_status or net.busy or net.connected:
		push_error("Expected '%s', got '%s'; busy=%s" % [expected, last_status, net.busy])
		failed = true


func _start() -> void:
	root.add_child(net)
	net.status_changed.connect(func(message: String): last_status = message)
	var api := OS.get_environment("SUNI_ERROR_TEST_URL")
	for case in [
		["invalid", "Sign-in failed: HTTP 422: Username:"],
		["missing", "Sign-in failed: HTTP 401: Login rejected."],
		["limited", "Sign-in failed: HTTP 429: Too many attempts."],
		["offline", "Sign-in failed: HTTP 503: Server temporarily unavailable."],
		["broken", "Sign-in failed: Invalid server response."],
		["notoken", "Sign-in failed: API response has no access token."],
	]:
		await _expect(api, case[0], case[1])
		if "DO_NOT_DISPLAY_PASSWORD" in last_status:
			failed = true
			push_error("Validation response leaked input data")
	# A transport failure must also release busy, allowing the next guest attempt.
	await _expect(OS.get_environment("SUNI_ERROR_TEST_UNREACHABLE"), "missing", "Cannot reach server.")
	# Whitespace username and endpoint padding still select guest auth.
	# A successful auth must clear the preceding error and preserve matchmaking errors.
	await _expect(" " + api + "/ ", "   ", "Could not join arena: HTTP 429:")
	net.queue_free()
	await process_frame
	if not failed:
		print("GODOT_REQUEST_ERRORS_OK")
	quit(1 if failed else 0)
