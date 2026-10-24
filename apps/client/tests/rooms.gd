extends SceneTree
const Network = preload("res://scripts/network.gd")
var scene = preload("res://main.tscn").instantiate()
var host = Network.new()
var failed := false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func settle(client: Node) -> void:
	while client.busy:
		await process_frame
	await process_frame

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Room test timeout"); quit(1))
	root.add_child(host)
	root.add_child(scene)
	var api := OS.get_environment("SUNI_API_URL")
	var arena := OS.get_environment("SUNI_ARENA_URL")
	scene.api_input.text = api
	scene.arena_input.text = arena
	await host.join_game(api, arena, "", "", false, true)
	host.join_selected(arena, "", true)
	await settle(host)
	check(host.connected, "Host creates a room")
	scene._set_login_mode(false)
	scene._join()
	await settle(scene.net)
	check(scene.room_browser.visible and not scene.form.visible, "Guest opens picker instead of auto joining")
	var target = scene.room_browser.grid.get_node_or_null("Room_" + host.room_id)
	check(target != null, "Room appears as tile")
	if target != null:
		target.pressed.emit()
		await settle(scene.net)
	check(scene.net.connected and scene.net.room_id == host.room_id, "Tile joins exact room ID")
	scene._leave()
	await settle(scene.net)
	check(scene.room_browser.visible, "Leave returns to grid")
	scene._enter_room("", true)
	await settle(scene.net)
	check(scene.net.connected and scene.net.room_id != host.room_id, "Create makes a separate room")
	scene._leave()
	await settle(scene.net)
	scene._enter_room("missing-room")
	await settle(scene.net)
	check(not scene.net.connected and scene.room_browser.visible and not scene.net.busy, "Stale room fails safely")
	scene.room_browser.render_rooms([{"roomId": "full", "players": 8, "maxPlayers": 8, "joinable": false}])
	check(scene.room_browser.grid.get_child(0).disabled, "Full room cannot be clicked")
	scene.net._token_deadline = 0
	await scene.net.list_rooms(arena)
	check(not scene.room_browser.visible and scene.form.visible, "Expired session returns to login")
	host.logout()
	scene.net.logout()
	scene.queue_free()
	host.queue_free()
	await process_frame
	print("GODOT_ROOMS_OK" if not failed else "GODOT_ROOMS_FAILED")
	quit(1 if failed else 0)
