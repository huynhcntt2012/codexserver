extends PanelContainer
signal equip_requested(item_id: String)
const UISkin = preload("res://scripts/ui/ui_skin.gd")
@onready var rarity: Label = $Padding/Body/Rarity
@onready var art: TextureRect = $Padding/Body/Art
@onready var title: Label = $Padding/Body/Title
@onready var status: Label = $Padding/Body/Status
@onready var action: Button = $Padding/Body/Action
var item_id = ""

func _ready() -> void:
	UISkin.panel(self, "card")
	UISkin.button(action, "gold")
	UISkin.heading(title, 15, UISkin.NAVY)
	UISkin.heading(status, 13, UISkin.NAVY)
	action.pressed.connect(func(): equip_requested.emit(item_id))

func bind_item(item: Dictionary) -> void:
	item_id = str(item.get("id", ""))
	var rarity_id = str(item.get("rarity", "common"))
	rarity.text = rarity_id.to_upper()
	rarity.add_theme_color_override("font_color", UISkin.rarity_color(rarity_id))
	title.text = str(item.get("name", ""))
	title.tooltip_text = str(item.get("description", ""))
	art.texture = load(str(item.get("icon", "")))
	refresh()

func refresh() -> void:
	var owns = UIState.owned(item_id)
	var is_equipped = UIState.equipped(item_id)
	var required_hero = str(UIState.get_item(item_id).get("character_id", ""))
	var wrong_hero = not required_hero.is_empty() and required_hero != str(UIState.profile.get("selected_character", ""))
	status.text = "KHÁC NHÂN VẬT" if wrong_hero else ("ĐANG DÙNG" if is_equipped else ("ĐÃ SỞ HỮU" if owns else "CHƯA MỞ"))
	action.text = "CHỌN NHÂN VẬT" if wrong_hero else ("ĐANG DÙNG" if is_equipped else ("TRANG BỊ" if owns else "ĐẾN SHOP"))
	action.disabled = is_equipped or wrong_hero
