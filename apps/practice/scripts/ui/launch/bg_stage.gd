extends Control
## Pure art layer; pointer input must pass through to UI.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Cover the whole window so wide PC screens show no bare bands.
	$SkyArt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
