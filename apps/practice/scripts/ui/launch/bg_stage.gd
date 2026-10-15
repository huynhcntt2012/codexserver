extends Control
## Pure art layer; pointer input must pass through to UI.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
