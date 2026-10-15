extends SceneTree
var scene = preload("res://main.tscn").instantiate()
var failed := false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	root.add_child(scene)
	var browser = scene.room_browser
	browser.show()
	scene._refresh_lobby()
	var rooms: Array = []
	for i in 13:
		rooms.append({"roomId": "test-%02d" % i, "players": 8 if i == 0 else 2, "maxPlayers": 8, "joinable": i != 0})
	browser.render_rooms(rooms)
	check(browser.grid.get_child_count() == 6, "Six rooms per page")
	check(browser.grid.get_child(0).disabled, "Full room disabled")
	browser.next.pressed.emit()
	check(browser.page == 1 and browser.grid.get_child_count() == 6, "Second page")
	browser.next.pressed.emit()
	check(browser.grid.get_child_count() == 1, "Last page")
	browser.render_rooms(rooms.slice(0, 2))
	check(browser.page == 0, "Page clamps after room removal")
	browser.slots.button_pressed = true
	check(browser.grid.get_child_count() == 1, "Available slots filter")
	browser.search.text = "missing"
	browser.search.text_changed.emit(browser.search.text)
	check(browser.grid.get_child_count() == 0, "Search empty state")
	browser.search.clear()
	browser.search.text_changed.emit("")
	check(browser.grid.get_child_count() == 1, "Empty query restores rooms")
	browser.set_busy(true)
	check(browser.quick_button.disabled and browser.grid.get_child(0).disabled, "Busy prevents duplicate joins")
	browser.set_busy(false)
	check(not browser.grid.get_child(0).disabled, "Busy reset restores joining")
	if not OS.get_environment("SUNI_LOBBY_SCREENSHOT").is_empty():
		browser.render_rooms(rooms)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("SUNI_LOBBY_SCREENSHOT"))
	print("GODOT_MAIN_LOBBY_OK" if not failed else "GODOT_MAIN_LOBBY_FAILED")
	quit(1 if failed else 0)
