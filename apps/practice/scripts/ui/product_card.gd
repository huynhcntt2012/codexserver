extends PanelContainer
signal buy_requested(item_id: String)
const UISkin = preload("res://scripts/ui/ui_skin.gd")
@onready var rarity: Label = $Padding/Body/Rarity
@onready var art: TextureRect = $Padding/Body/Art
@onready var title: Label = $Padding/Body/Title
@onready var price: Label = $Padding/Body/PriceRow/Price
@onready var action: Button = $Padding/Body/Action
var item_id = ""

func _ready() -> void:
	UISkin.panel(self, "card")
	UISkin.button(action, "gold")
	UISkin.heading(title, 16, UISkin.NAVY)
	UISkin.heading(price, 18, UISkin.NAVY)
	action.pressed.connect(func(): buy_requested.emit(item_id))

func bind_item(item: Dictionary) -> void:
	item_id = str(item.get("id", ""))
	var rarity_id = str(item.get("rarity", "common"))
	rarity.text = rarity_id.to_upper()
	rarity.add_theme_color_override("font_color", UISkin.rarity_color(rarity_id))
	title.text = str(item.get("name", ""))
	title.tooltip_text = str(item.get("description", ""))
	art.texture = load(str(item.get("icon", "")))
	price.text = ("%d KC" if str(item.get("currency", "gold")) == "gem" else "%d vàng") % int(item.get("price", 0))
	refresh()

func refresh() -> void:
	var item = UIState.get_item(item_id)
	var has_item = str(item.get("category", "")) != "consumable" and UIState.owned(item_id)
	action.text = "SỞ HỮU" if has_item else "MUA"
	action.disabled = has_item
