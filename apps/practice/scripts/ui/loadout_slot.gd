extends PanelContainer
const UISkin = preload("res://scripts/ui/ui_skin.gd")
func _ready() -> void:
	UISkin.panel(self, "soft")

func bind_slot(slot: String, label_text: String) -> void:
	$Padding/Body/Name.text = label_text
	var equipped_id = str(UIState.profile.get("loadout", {}).get(slot, ""))
	var item = UIState.get_item(equipped_id)
	if item.is_empty():
		$Padding/Body/Art.texture = null
		$Padding/Body/Name.tooltip_text = "Ô trống"
	else:
		$Padding/Body/Art.texture = load(str(item.get("icon", "")))
		$Padding/Body/Name.tooltip_text = str(item.get("name", ""))
