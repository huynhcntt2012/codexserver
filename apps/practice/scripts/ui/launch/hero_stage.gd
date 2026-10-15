extends Control
## Gentle, looping idle animation. Sprites and effects are individual TextureRects.
@export var enable_idle_animation := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not enable_idle_animation:
		return
	_float_node($Pip, 8.0, 2.8)
	_float_node($Nop, 11.0, 3.2)
	var i := 0
	for child in get_children():
		if child.name.begins_with("Bubble"):
			_float_node(child, 7.0 + float(i % 3) * 3.0, 2.0 + float(i % 3) * 0.4)
			i += 1

func _float_node(target: Control, distance: float, duration: float) -> void:
	var start_y := target.position.y
	var tween := create_tween().set_loops()
	tween.tween_property(target, "position:y", start_y - distance, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(target, "position:y", start_y, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
