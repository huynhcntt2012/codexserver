extends SceneTree
const View = preload("res://scripts/arena_view.gd")
func _initialize() -> void:
	var view = View.new()
	var s := {"round": 1, "phase": "playing", "players": [{"id": "a", "x": 1, "y": 1, "slot": 0, "alive": true}], "grid": [[1, 1, 1, 1], [1, 0, 0, 1], [1, 1, 1, 1]], "bombs": [], "flames": []}
	view.set_snapshot(s, "a")
	view.movement_intent("right")
	view._process(0.016)
	assert(view.positions.a.x > 1.0 and view.positions.a.x <= 1.25)
	assert(s.players[0].x == 1)
	view.movement_intent("right")
	view._process(0.3)
	assert(view.positions.a.x == 1.0)
	view.clear()
	s.bombs = [{"x": 2, "y": 1}]
	view.set_snapshot(s, "a")
	view.movement_intent("right")
	assert(view.movement_cue.is_empty())
	view.free()
	print("GODOT_MOVEMENT_OK: immediate bounded cue, timeout, no snapshot mutation, bomb collision")
	quit()
