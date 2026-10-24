extends Control
const HeroPortrait := preload("res://scripts/hero_portrait.gd")
signal navigate(destination: String)
const UISkin = preload("res://scripts/ui/ui_skin.gd")
const Card = preload("res://scenes/ui/components/product_card.tscn")
var active_category = "hot"
const CATEGORIES = [
	["hot", "Gói hot"], ["consumable", "Vật phẩm"],
	["outfit", "Trang phục"], ["effect", "Hiệu ứng"],
	["bomb_skin", "Skin bom"], ["pet", "Pet"],
	["accessory", "Phụ kiện"], ["hat", "Mũ"]
]
const CATEGORY_ICONS = {
	"hot": "res://assets/items/flame.png",
	"consumable": "res://assets/bombs/strong_black.png",
	"outfit": "res://assets/characters/portraits/mimi.png",
	"effect": "res://assets/bombs/star.png",
	"bomb_skin": "res://assets/bombs/classic_blue.png",
	"pet": "res://assets/items/heart.png",
	"accessory": "res://assets/items/magnet.png",
	"hat": "res://assets/items/ice.png"
}

func _ready() -> void:
	UISkin.panel($ScreenFrame/VBox/Body/LeftMenu)
	UISkin.panel($ScreenFrame/VBox/Body/RightPanel)
	UISkin.panel($ScreenFrame/VBox/Body/Main/Promo, "gold")
	UISkin.button($ScreenFrame/VBox/Body/Main/Promo/PromoPad/PromoRow/PromoText/PromoCTA, "pink")
	UISkin.heading($ScreenFrame/VBox/Body/Main/Promo/PromoPad/PromoRow/PromoText/PromoTitle, 26, UISkin.NAVY)
	UISkin.heading($ScreenFrame/VBox/Body/Main/ListHeader, 21)
	$ScreenFrame/VBox/Body/Main/Promo/PromoPad/PromoRow/PromoText/PromoSubtitle.add_theme_color_override("font_color", UISkin.NAVY)
	$ScreenFrame/VBox/Body/Main/Promo/PromoPad/PromoRow/PromoArt.texture = HeroPortrait.texture("bombo")
	$ScreenFrame/VBox/Body/RightPanel/MascotVBox/MascotArt.texture = HeroPortrait.texture("mimi")
	$ScreenFrame/VBox/Body/Main/Promo/PromoPad/PromoRow/PromoText/PromoCTA.pressed.connect(_buy_promo)
	$ScreenFrame/VBox/TopBar.back_requested.connect(func(): navigate.emit("home"))
	$ScreenFrame/VBox/BottomNav.navigate.connect(func(page): navigate.emit(page))
	$ScreenFrame/VBox/BottomNav.set_active("shop")
	UIState.inventory_changed.connect(_render_grid)
	_render_categories()
	_render_grid()

func _render_categories() -> void:
	var column = $ScreenFrame/VBox/Body/LeftMenu/SidebarPad/SideBox/CategoryButtons
	for pair in CATEGORIES:
		var b = Button.new()
		b.name = "Category_%s" % pair[0]
		b.text = pair[1]
		b.icon = load(CATEGORY_ICONS.get(str(pair[0]), "res://assets/items/mystery.png"))
		b.expand_icon = true
		b.custom_minimum_size = Vector2(152, 53)
		column.add_child(b)
		b.pressed.connect(_choose_category.bind(str(pair[0])))
	_style_categories()

func _style_categories() -> void:
	for b in $ScreenFrame/VBox/Body/LeftMenu/SidebarPad/SideBox/CategoryButtons.get_children():
		var key = str(b.name).trim_prefix("Category_")
		UISkin.button(b, "gold" if key == active_category else "blue")

func _choose_category(key: String) -> void:
	active_category = key
	_style_categories()
	_render_grid()

func _render_grid() -> void:
	var grid = $ScreenFrame/VBox/Body/Main/Scroll/Products
	for child in grid.get_children():
		child.queue_free()
	for item in UIState.items:
		var cat = str(item.get("category", ""))
		if active_category != "hot" and cat != active_category:
			continue
		var card = Card.instantiate()
		grid.add_child(card)
		card.bind_item(item)
		card.buy_requested.connect(_request_buy)

func _request_buy(id: String) -> void:
	var item = UIState.get_item(id)
	if item.is_empty(): return
	var currency = "kim cương" if str(item.get("currency", "gold")) == "gem" else "vàng"
	var dialog = ConfirmationDialog.new()
	dialog.title = "Xác nhận mua vật phẩm"
	dialog.dialog_text = "Mua %s với giá %s %s?" % [item.get("name", ""), int(item.get("price", 0)), currency]
	add_child(dialog)
	dialog.confirmed.connect(func(): UIState.buy(id))
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.confirmed.connect(func(): dialog.queue_free(), CONNECT_DEFERRED)
	dialog.popup_centered()

func _buy_promo() -> void:
	UIState.toast_requested.emit("Banner combo là minh họa; chưa có SKU bundle")
