extends PanelContainer
signal back_requested
const UISkin = preload("res://scripts/ui/ui_skin.gd")
func _ready() -> void:
	UISkin.panel(self)
	UISkin.button($Margin/Row/Back)
	$Margin/Row/Back.pressed.connect(func(): back_requested.emit())
	UIState.wallet_changed.connect(refresh)
	UIState.profile_changed.connect(refresh)
	refresh()

func refresh() -> void:
	$Margin/Row/Player.text = "%s   Lv.%s" % [UIState.profile.get("name", "Demo"), int(UIState.profile.get("level", 1))]
	$Margin/Row/Gold.text = "Vàng: %d" % int(UIState.profile.get("gold", 0))
	$Margin/Row/Gem.text = "KC: %d" % int(UIState.profile.get("gem", 0))
	var selected = str(UIState.profile.get("selected_character", "mimi"))
	$Margin/Row/Avatar.texture = load("res://assets/characters/portraits/%s.png" % selected)
	$Margin/Row/XP.max_value = maxf(1.0, float(UIState.profile.get("xp_max", 800)))
	$Margin/Row/XP.value = float(UIState.profile.get("xp", 0))
