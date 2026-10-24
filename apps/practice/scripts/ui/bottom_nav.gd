extends PanelContainer
signal navigate(destination: String)
const UISkin = preload("res://scripts/ui/ui_skin.gd")
func _ready() -> void:
	UISkin.panel(self, "soft")
	for button in $Margin/Buttons.get_children():
		if button is Button:
			UISkin.button(button, "gold" if button.name == "Shop" else "blue")
	$Margin/Buttons/Shop.pressed.connect(func(): navigate.emit("shop"))
	$Margin/Buttons/Equipment.pressed.connect(func(): navigate.emit("equipment"))
	$Margin/Buttons/Battle.pressed.connect(func(): navigate.emit("battle"))
	$Margin/Buttons/Home.pressed.connect(func(): navigate.emit("home"))

func set_active(page: String) -> void:
	for button in $Margin/Buttons.get_children():
		if button is Button:
			var dest = button.name.to_lower()
			UISkin.button(button, "gold" if dest == page else "blue")
